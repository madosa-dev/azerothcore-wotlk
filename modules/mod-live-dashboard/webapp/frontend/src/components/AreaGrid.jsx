import { useMemo } from 'react'
import { KNOWN_MAP_IDS, OTHER_TAB_ID } from '../constants'

function Dot({ player }) {
  const title = `${player.name} — Lvl ${player.level} ${player.race} ${player.class}` +
    (player.guild ? ` <${player.guild}>` : '') +
    ` — ${player.hpPct}% HP`

  return (
    <div
      className={`dot ${player.isBot ? 'bot' : 'player'}`}
      style={{ left: `${player.pctX}%`, top: `${player.pctY}%` }}
      title={title}
    />
  )
}

function AreaCard({ area }) {
  return (
    <div className="area-card">
      <h3>
        {area.name} <span className="count">{area.players.length}</span>
      </h3>
      <div className="area-map">
        {area.players.map((p) => (
          <Dot key={p.guid} player={p} />
        ))}
      </div>
    </div>
  )
}

export default function AreaGrid({ positions, activeTab }) {
  const areas = useMemo(() => {
    const inTab = positions.filter((p) =>
      activeTab === OTHER_TAB_ID ? !KNOWN_MAP_IDS.has(p.mapId) : p.mapId === activeTab,
    )

    const byArea = new Map()
    for (const p of inTab) {
      if (!byArea.has(p.areaId)) byArea.set(p.areaId, { id: p.areaId, name: p.areaName, players: [] })
      byArea.get(p.areaId).players.push(p)
    }

    return [...byArea.values()].sort((a, b) => b.players.length - a.players.length)
  }, [positions, activeTab])

  if (!areas.length) {
    return <div className="empty">Nobody here right now.</div>
  }

  return (
    <div className="grid">
      {areas.map((area) => (
        <AreaCard key={area.id} area={area} />
      ))}
    </div>
  )
}
