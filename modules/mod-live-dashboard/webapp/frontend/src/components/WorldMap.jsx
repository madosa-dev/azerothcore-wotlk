import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { MAP_IMAGES, OTHER_TAB_ID, worldToContinentPct } from '../constants'
import { useTileIndex } from '../hooks/useTileIndex'
import TiledMap from './TiledMap'

const MIN_ZOOM = 1
const MAX_ZOOM = 14

function Dot({ player, pctX, pctY, selected, onSelect }) {
  const title = `${player.name} — Lvl ${player.level} ${player.race} ${player.class}` +
    (player.guild ? ` <${player.guild}>` : '') +
    ` — ${player.areaName} — ${player.hpPct}% HP`

  return (
    <button
      type="button"
      className={`dot ${player.isBot ? 'bot' : 'player'}${selected ? ' selected' : ''}`}
      style={{ left: `${pctX}%`, top: `${pctY}%` }}
      title={title}
      aria-label={title}
      onClick={(e) => { e.stopPropagation(); onSelect(player.guid) }}
    />
  )
}

// Google-Maps-style viewport: the picture and its dots live on one layer that
// is translated and scaled as a unit, so a dot's percentage position never
// has to be recomputed on zoom. The dots counter-scale (see .dot in App.css)
// so they stay the same size on screen at every zoom level.
function useViewport(containerRef) {
  const [view, setView] = useState({ scale: 1, tx: 0, ty: 0 })
  const drag = useRef(null)

  const clamp = useCallback((v) => {
    const el = containerRef.current
    if (!el) return v
    const { clientWidth: w, clientHeight: h } = el
    const scale = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, v.scale))
    // The picture must always cover the frame: no dragging the map off into
    // the void, and zooming out past 1:1 is zooming into nothing.
    const tx = Math.min(0, Math.max(w - w * scale, v.tx))
    const ty = Math.min(0, Math.max(h - h * scale, v.ty))
    return { scale, tx, ty }
  }, [containerRef])

  // Zoom keeping the point under the cursor (or the centre) where it is.
  const zoomAt = useCallback((factor, cx, cy) => {
    setView((v) => {
      const el = containerRef.current
      if (!el) return v
      if (cx == null) { cx = el.clientWidth / 2; cy = el.clientHeight / 2 }
      const scale = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, v.scale * factor))
      const k = scale / v.scale
      return clamp({ scale, tx: cx - (cx - v.tx) * k, ty: cy - (cy - v.ty) * k })
    })
  }, [clamp, containerRef])

  const reset = useCallback(() => setView({ scale: 1, tx: 0, ty: 0 }), [])

  // Wheel needs a non-passive listener to stop the page scrolling under it,
  // which React's synthetic onWheel cannot promise.
  useEffect(() => {
    const el = containerRef.current
    if (!el) return
    const onWheel = (e) => {
      e.preventDefault()
      const rect = el.getBoundingClientRect()
      zoomAt(e.deltaY < 0 ? 1.25 : 0.8, e.clientX - rect.left, e.clientY - rect.top)
    }
    el.addEventListener('wheel', onWheel, { passive: false })
    return () => el.removeEventListener('wheel', onWheel)
  }, [containerRef, zoomAt])

  // Pointer capture only once the pointer has actually moved: capturing on
  // pointerdown redirects the pointerup - and with it the click - to the
  // frame, so no dot could ever be clicked. A press that never moves stays
  // an ordinary click on whatever is under it.
  const onPointerDown = useCallback((e) => {
    if (e.button !== 0) return
    drag.current = { x: e.clientX, y: e.clientY, moved: false, target: e.currentTarget, id: e.pointerId }
  }, [])

  const onPointerMove = useCallback((e) => {
    const d = drag.current
    if (!d) return
    const dx = e.clientX - d.x
    const dy = e.clientY - d.y
    if (!d.moved && Math.hypot(dx, dy) < 3) return
    if (!d.moved) d.target.setPointerCapture(d.id)
    d.moved = true
    d.x = e.clientX
    d.y = e.clientY
    setView((v) => clamp({ ...v, tx: v.tx + dx, ty: v.ty + dy }))
  }, [clamp])

  const onPointerUp = useCallback(() => { drag.current = null }, [])

  // A window resize changes the frame the clamp is measured against.
  useEffect(() => {
    const onResize = () => setView((v) => clamp(v))
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [clamp])

  return { view, zoomAt, reset, handlers: { onPointerDown, onPointerMove, onPointerUp, onPointerCancel: onPointerUp } }
}

function ContinentMap({ mapId, positions, selected, onSelect }) {
  const image = MAP_IMAGES[mapId]
  const frameRef = useRef(null)
  const { view, zoomAt, reset, handlers } = useViewport(frameRef)

  // A new continent starts at 1:1; the old translation means nothing there.
  useEffect(() => { reset() }, [mapId, reset])

  const dots = useMemo(() => {
    return positions
      .map((p) => {
        const pct = worldToContinentPct(mapId, p.posX, p.posY)
        if (!pct || pct.pctX < 0 || pct.pctX > 100 || pct.pctY < 0 || pct.pctY > 100) return null
        return { player: p, ...pct }
      })
      .filter(Boolean)
  }, [positions, mapId])

  return (
    <div className="world-map-wrap">
      <div
        ref={frameRef}
        className={`world-map${view.scale > 1 ? ' zoomed' : ''}`}
        style={{ aspectRatio: `${image.width} / ${image.height}`, '--ratio': image.width / image.height }}
        onDoubleClick={(e) => {
          const rect = e.currentTarget.getBoundingClientRect()
          zoomAt(2, e.clientX - rect.left, e.clientY - rect.top)
        }}
        {...handlers}
      >
        <div
          className="map-layer"
          style={{
            transform: `translate(${view.tx}px, ${view.ty}px) scale(${view.scale})`,
            '--inv': 1 / view.scale,
          }}
        >
          <img src={image.src} alt="" draggable={false} />
          {dots.map(({ player, pctX, pctY }) => (
            <Dot key={player.guid} player={player} pctX={pctX} pctY={pctY}
              selected={player.guid === selected} onSelect={onSelect} />
          ))}
        </div>

        <div className="map-zoom" onPointerDown={(e) => e.stopPropagation()}>
          <button type="button" onClick={() => zoomAt(1.5)} title="Zoom in">+</button>
          <button type="button" onClick={() => zoomAt(1 / 1.5)} title="Zoom out">−</button>
          <button type="button" onClick={reset} title="Reset view" disabled={view.scale === 1}>⌂</button>
        </div>
        <div className="map-hint">scroll to zoom · drag to pan · click a dot</div>
      </div>
    </div>
  )
}

function OtherList({ positions, onSelect }) {
  const areas = useMemo(() => {
    const byArea = new Map()
    for (const p of positions) {
      if (!byArea.has(p.areaId)) byArea.set(p.areaId, { name: p.areaName, players: [] })
      byArea.get(p.areaId).players.push(p)
    }
    return [...byArea.values()].sort((a, b) => b.players.length - a.players.length)
  }, [positions])

  if (!areas.length) {
    return <div className="empty">Nobody here right now.</div>
  }

  return (
    <div className="other-list">
      {areas.map((area) => (
        <div className="panel" key={area.name}>
          <h2>
            {area.name} <span className="count">{area.players.length}</span>
          </h2>
          <table>
            <tbody>
              {area.players.map((p) => (
                <tr key={p.guid} className="clickable" onClick={() => onSelect(p.guid)}>
                  <td className={p.isBot ? 'bot' : 'player'}>{p.name}</td>
                  <td>
                    Lvl {p.level} {p.race} {p.class}
                  </td>
                  <td>{p.hpPct}% HP</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ))}
    </div>
  )
}

export default function WorldMap({ positions, activeTab, selected, onSelect }) {
  const { index, ready } = useTileIndex()
  const inTab = useMemo(
    () => positions.filter((p) => (activeTab === OTHER_TAB_ID ? !MAP_IMAGES[p.mapId] : p.mapId === activeTab)),
    [positions, activeTab],
  )

  if (activeTab === OTHER_TAB_ID) {
    return <OtherList positions={inTab} onSelect={onSelect} />
  }

  // Nothing until the index has answered, so the page does not flash the
  // low-resolution picture before the real map takes over.
  if (!ready) return <div className="world-map-wrap"><div className="tiled-map" /></div>

  // The tile pyramid when it has been built (tools/build_map_tiles.py), the
  // single picture with CSS zoom when it has not.
  const extent = index?.[activeTab]
  if (extent) {
    return (
      <div className="world-map-wrap">
        <TiledMap key={activeTab} mapId={activeTab} extent={extent} positions={inTab}
          selected={selected} onSelect={onSelect} />
      </div>
    )
  }

  return <ContinentMap mapId={activeTab} positions={inTab} selected={selected} onSelect={onSelect} />
}
