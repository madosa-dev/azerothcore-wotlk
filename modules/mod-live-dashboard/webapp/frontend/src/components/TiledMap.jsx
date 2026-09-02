import { useEffect, useRef } from 'react'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { TILE_SIZE, tileColRow } from '../constants'

// A transparent pixel for the tiles that do not exist: the pyramid only holds
// land, and Leaflet would otherwise draw a broken-image icon over the sea.
const EMPTY_TILE = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'

const COLORS = {
  player: getComputedStyle(document.documentElement).getPropertyValue('--player').trim() || '#6ea8fe',
  bot: getComputedStyle(document.documentElement).getPropertyValue('--bot').trim() || '#ffb454',
}

function styleFor(player, selected) {
  return {
    radius: selected ? 7 : 4,
    color: selected ? '#ffffff' : 'rgba(0,0,0,0.6)',
    weight: selected ? 2 : 1,
    fillColor: player.isBot ? COLORS.bot : COLORS.player,
    fillOpacity: 0.95,
  }
}

function tooltipFor(p) {
  return `<b>${p.name}</b> — Lvl ${p.level} ${p.race} ${p.class}` +
    (p.guild ? ` &lt;${p.guild}&gt;` : '') + `<br>${p.areaName} — ${p.hpPct}% HP`
}

// The web map proper: Leaflet over the tile pyramid tools/build_map_tiles.py
// builds from the client's minimap. CRS.Simple, with the unit chosen so that
// at the pyramid's native zoom one unit is one pixel of the stitched
// continent - which makes a position's tile column and row (the same numbers
// MAP_TILES uses for the single-picture fallback) its coordinates directly.
export default function TiledMap({ mapId, extent, positions, selected, onSelect }) {
  const elRef = useRef(null)
  const mapRef = useRef(null)
  const markersRef = useRef(new Map())
  const onSelectRef = useRef(onSelect)
  onSelectRef.current = onSelect

  const unitsPerTile = TILE_SIZE / 2 ** extent.maxZoom
  const toLatLng = (posX, posY) => {
    const { col, row } = tileColRow(posX, posY)
    return L.latLng(-(row - extent.rowMin) * unitsPerTile, (col - extent.colMin) * unitsPerTile)
  }

  useEffect(() => {
    const bounds = L.latLngBounds([-extent.rows * unitsPerTile, 0], [0, extent.cols * unitsPerTile])
    const map = L.map(elRef.current, {
      crs: L.CRS.Simple,
      minZoom: 0,
      maxZoom: extent.maxZoom + 1,   // one level of plain upscaling past native
      zoomSnap: 0.5,
      preferCanvas: true,            // three thousand markers on one canvas, not three thousand nodes
      attributionControl: false,
      maxBounds: bounds.pad(0.25),
      maxBoundsViscosity: 0.8,
    })
    L.tileLayer(`/tiles/${mapId}/{z}/{x}/{y}.webp`, {
      tileSize: TILE_SIZE,
      minNativeZoom: 0,
      maxNativeZoom: extent.maxZoom,
      bounds,
      noWrap: true,
      errorTileUrl: EMPTY_TILE,
      keepBuffer: 4,
    }).addTo(map)
    map.fitBounds(bounds)
    mapRef.current = map
    return () => {
      map.remove()
      mapRef.current = null
      markersRef.current = new Map()
    }
    // The map is created once per continent; the parent keys this component on mapId.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mapId])

  // Reconcile markers with the latest positions: move the ones still here,
  // add the new, drop the departed. No layer is rebuilt for a poll.
  useEffect(() => {
    const map = mapRef.current
    if (!map) return
    const markers = markersRef.current
    const seen = new Set()

    for (const p of positions) {
      seen.add(p.guid)
      const latlng = toLatLng(p.posX, p.posY)
      const isSelected = p.guid === selected
      let m = markers.get(p.guid)
      if (!m) {
        m = L.circleMarker(latlng, styleFor(p, isSelected))
          .bindTooltip(tooltipFor(p), { direction: 'top', offset: [0, -6], opacity: 0.95 })
          .on('click', () => onSelectRef.current(p.guid))
          .addTo(map)
        m._dash = { isBot: p.isBot, selected: isSelected, tip: '' }
        markers.set(p.guid, m)
      } else {
        m.setLatLng(latlng)
        if (m._dash.isBot !== p.isBot || m._dash.selected !== isSelected) {
          m.setStyle(styleFor(p, isSelected))
          m._dash.isBot = p.isBot
          m._dash.selected = isSelected
        }
      }
      const tip = tooltipFor(p)
      if (m._dash.tip !== tip) { m.setTooltipContent(tip); m._dash.tip = tip }
      if (isSelected) m.bringToFront()
    }

    for (const [guid, m] of markers) {
      if (!seen.has(guid)) { m.remove(); markers.delete(guid) }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [positions, selected])

  // A newly selected character is brought into view once, at a zoom where
  // the neighbourhood is readable; after that the view is the user's.
  useEffect(() => {
    const map = mapRef.current
    if (!map || selected == null) return
    const m = markersRef.current.get(selected)
    if (m) map.setView(m.getLatLng(), Math.max(map.getZoom(), extent.maxZoom - 1))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selected])

  return <div ref={elRef} className="tiled-map" />
}
