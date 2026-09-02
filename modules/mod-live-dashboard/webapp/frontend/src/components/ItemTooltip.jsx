import { useLayoutEffect, useRef, useState } from 'react'

const QUALITY_COLORS = ['#9d9d9d', '#ffffff', '#1eff00', '#0070dd', '#a335ee', '#ff8000', '#e6cc80', '#e6cc80']

function Money({ copper }) {
  const g = Math.floor(copper / 10000)
  const s = Math.floor((copper % 10000) / 100)
  const c = copper % 100
  return (
    <span className="money">
      {g > 0 && <><b>{g.toLocaleString()}</b><i className="coin g" /></>}
      {(g > 0 || s > 0) && <><b>{s}</b><i className="coin s" /></>}
      <b>{c}</b><i className="coin c" />
    </span>
  )
}

// The game's item tooltip, line for line: name in its quality colour, the
// binding, slot and type on one row, damage or armour, the white stats, the
// green Equip/Use lines, durability, level requirement, flavour text, sell
// price. Positioned beside the anchor and kept inside the viewport.
export default function ItemTooltip({ item, anchor, onClose }) {
  const ref = useRef(null)
  const [pos, setPos] = useState({ left: -9999, top: -9999 })

  useLayoutEffect(() => {
    if (!anchor || !ref.current) return
    const a = anchor.getBoundingClientRect()
    const t = ref.current.getBoundingClientRect()
    const margin = 8
    // To the right of the anchor when there is room, else to the left.
    let left = a.right + margin
    if (left + t.width > window.innerWidth - margin) left = a.left - t.width - margin
    if (left < margin) left = margin
    let top = a.top
    if (top + t.height > window.innerHeight - margin) top = window.innerHeight - t.height - margin
    if (top < margin) top = margin
    setPos({ left, top })
  }, [anchor, item])

  if (!item) return null
  const tip = item.tooltip || {}
  const color = QUALITY_COLORS[item.quality] || '#fff'

  return (
    <div ref={ref} className="tip" style={pos} onClick={onClose}>
      <div className="tip-name" style={{ color }}>{item.name}</div>
      <div className="tip-line muted">Item Level {item.ilvl}</div>
      {tip.binding && <div className="tip-line">{tip.binding}</div>}
      {(tip.slot || tip.type) && (
        <div className="tip-line tip-row"><span>{tip.slot}</span><span>{tip.type}</span></div>
      )}
      {tip.damage && (
        <>
          <div className="tip-line tip-row">
            <span>{tip.damage.min} - {tip.damage.max} Damage</span>
            <span>Speed {tip.damage.speed.toFixed(2)}</span>
          </div>
          <div className="tip-line">({tip.damage.dps.toFixed(1)} damage per second)</div>
        </>
      )}
      {tip.armor > 0 && <div className="tip-line">{tip.armor} Armor</div>}
      {tip.stats?.map((s, i) => (
        <div key={i} className="tip-line">{s.value > 0 ? '+' : ''}{s.value} {s.name}</div>
      ))}
      {tip.durability && (
        <div className="tip-line">Durability {tip.durability[0]} / {tip.durability[1]}</div>
      )}
      {tip.reqLevel > 1 && <div className="tip-line">Requires Level {tip.reqLevel}</div>}
      {tip.equip?.map((line, i) => <div key={i} className="tip-line green">Equip: {line}</div>)}
      {tip.use?.map((line, i) => <div key={i} className="tip-line green">Use: {line}</div>)}
      {tip.flavor && <div className="tip-line flavor">"{tip.flavor}"</div>}
      {tip.sell > 0 && <div className="tip-line tip-row"><span>Sell Price:</span><Money copper={tip.sell} /></div>}
    </div>
  )
}
