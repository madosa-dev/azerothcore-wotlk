import { useMemo } from 'react'
import { MAP_IMAGES, OTHER_TAB_ID, worldToContinentPct } from '../constants'

function Dot({ player, pctX, pctY }) {
  const title = `${player.name} — Lvl ${player.level} ${player.race} ${player.class}` +
    (player.guild ? ` <${player.guild}>` : '') +
    ` — ${player.areaName} — ${player.hpPct}% HP`

  return (
    <div
      className={`dot ${player.isBot ? 'bot' : 'player'}`}
      style={{ left: `${pctX}%`, top: `${pctY}%` }}
      title={title}
    />
  )
}

function ContinentMap({ mapId, positions }) {
  const image = MAP_IMAGES[mapId]

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
      <div className="world-map" style={{ aspectRatio: `${image.width} / ${image.height}` }}>
        <img src={image.src} alt="" draggable={false} />
        {dots.map(({ player, pctX, pctY }) => (
          <Dot key={player.guid} player={player} pctX={pctX} pctY={pctY} />
        ))}
      </div>
    </div>
  )
}

function OtherList({ positions }) {
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
                <tr key={p.guid}>
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

export default function WorldMap({ positions, activeTab }) {
  const inTab = useMemo(
    () => positions.filter((p) => (activeTab === OTHER_TAB_ID ? !MAP_IMAGES[p.mapId] : p.mapId === activeTab)),
    [positions, activeTab],
  )

  if (activeTab === OTHER_TAB_ID) {
    return <OtherList positions={inTab} />
  }

  return <ContinentMap mapId={activeTab} positions={inTab} />
}
