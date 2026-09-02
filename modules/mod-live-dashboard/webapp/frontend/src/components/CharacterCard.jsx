import { useEffect, useState } from 'react'
import { useAdminToken, runAdminCommand } from '../hooks/useAdminToken'
import { CLASS_COLORS } from '../chronicle'
import ItemTooltip from './ItemTooltip'

const QUALITY_COLORS = ['#9d9d9d', '#ffffff', '#1eff00', '#0070dd', '#a335ee', '#ff8000', '#e6cc80', '#e6cc80']

// The character frame's own arrangement: eight slots down the left, eight
// down the right, the weapons underneath. Same order as the game draws them.
const LEFT = [[0, 'Head'], [1, 'Neck'], [2, 'Shoulder'], [14, 'Back'], [4, 'Chest'], [3, 'Shirt'], [18, 'Tabard'], [8, 'Wrist']]
const RIGHT = [[9, 'Hands'], [5, 'Waist'], [6, 'Legs'], [7, 'Feet'], [10, 'Finger'], [11, 'Finger'], [12, 'Trinket'], [13, 'Trinket']]
const WEAPONS = [[15, 'Main Hand'], [16, 'Off Hand'], [17, 'Ranged']]

const CITIES = ['Stormwind', 'Ironforge', 'Darnassus', 'Orgrimmar', 'ThunderBluff', 'Undercity',
  'Shattrath', 'Dalaran', 'BootyBay', 'Gadgetzan']

function played(seconds) {
  const d = Math.floor(seconds / 86400)
  const h = Math.floor((seconds % 86400) / 3600)
  return d ? `${d}d ${h}h` : `${h}h ${Math.floor((seconds % 3600) / 60)}m`
}

function Money({ copper }) {
  const g = Math.floor(copper / 10000)
  const s = Math.floor((copper % 10000) / 100)
  const c = copper % 100
  return (
    <span className="money">
      {g > 0 && <><b>{g.toLocaleString()}</b><i className="coin g" /></>}
      <b>{s}</b><i className="coin s" />
      <b>{c}</b><i className="coin c" />
    </span>
  )
}

// One slot of the paper doll: the icon in a quality-coloured frame, or the
// empty socket the game shows when nothing is worn. Everything else is the
// tooltip, as in the game - on hover with a mouse, on tap on a phone.
function Slot({ label, item, side, onHover }) {
  const color = item ? QUALITY_COLORS[item.quality] || '#fff' : null
  const show = (e) => item && onHover(item, e.currentTarget)
  return (
    <div className={`pd-slot ${side}`} title={item ? undefined : label}
      onMouseEnter={show} onMouseLeave={() => onHover(null)}
      onClick={(e) => { if (item) { e.stopPropagation(); onHover(item, e.currentTarget, true) } }}>
      <div className="pd-socket" style={color ? { borderColor: color, boxShadow: `0 0 6px ${color}55` } : undefined}>
        {item?.icon
          ? <img src={`/icons/${item.icon}.webp`} alt="" loading="lazy" />
          : item
            ? <span className="pd-noicon" style={{ color }}>{item.name.slice(0, 2)}</span>
            : <span className="pd-empty" />}
        {item && <span className="pd-ilvl">{item.ilvl}</span>}
      </div>
      <span className="pd-label" style={color ? { color } : undefined}>
        {item ? `${item.name}${item.tooltip?.suffix ? ` ${item.tooltip.suffix}` : ''}` : label}
      </span>
    </div>
  )
}

function BotActions({ name }) {
  const [token] = useAdminToken()
  const [city, setCity] = useState(CITIES[0])
  const [state, setState] = useState(null)

  if (!token) {
    return (
      <p className="cc-note">
        Bot actions need the admin token — unlock it once in the Admin view.
      </p>
    )
  }

  const run = async (label, cmd) => {
    setState({ label, status: 'queued' })
    try {
      const r = await runAdminCommand(token, cmd)
      setState({ label, status: r.status, output: r.output })
    } catch (err) {
      setState({ label, status: 'failed', output: String(err.message || err) })
    }
  }

  // .playerbots rndbot <verb> <name> is mod-playerbots' own console interface
  // to one bot; it answers in the server log rather than to the caller, so
  // "done" here means "the world tick ran it", not that it printed anything.
  const busy = state?.status === 'queued'
  return (
    <div className="cc-actions">
      <h4>Bot actions</h4>
      <div className="cc-buttons">
        <button disabled={busy} onClick={() => run('Revive', `.playerbots rndbot revive ${name}`)}>Revive</button>
        <button disabled={busy} onClick={() => run('Level up', `.playerbots rndbot levelup ${name}`)}>Level up</button>
        <button disabled={busy} onClick={() => run('Refresh', `.playerbots rndbot refresh ${name}`)}
          title="Re-roll the bot's gear and state for its level">Refresh</button>
        <button disabled={busy} onClick={() => run('Send grinding', `.playerbots rndbot teleport ${name}`)}
          title="Teleport to a zone that fits its level">Send grinding</button>
        <button disabled={busy} className="danger" onClick={() => run('Log out', `.kick ${name}`)}>Log out</button>
      </div>
      <div className="cc-buttons">
        <select value={city} onChange={(e) => setCity(e.target.value)} disabled={busy}>
          {CITIES.map((c) => <option key={c} value={c}>{c}</option>)}
        </select>
        <button disabled={busy} onClick={() => run(`Teleport to ${city}`, `.tele name ${name} ${city}`)}>Teleport</button>
      </div>
      {state && (
        <div className={`cc-result ${state.status}`}>
          {state.label}: {state.status}
          {state.output && state.status !== 'done' ? ` — ${state.output}` : ''}
        </div>
      )}
    </div>
  )
}

export default function CharacterCard({ guid, live, onClose }) {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)

  useEffect(() => {
    let cancelled = false
    setData(null)
    setError(null)
    fetch(`/api/character?guid=${guid}`)
      .then((r) => r.ok ? r.json() : r.json().then((e) => { throw new Error(e.error || `HTTP ${r.status}`) }))
      .then((json) => { if (!cancelled) setData(json) })
      .catch((err) => { if (!cancelled) setError(String(err.message || err)) })
    return () => { cancelled = true }
  }, [guid])

  const name = data?.name ?? live?.name ?? '…'
  const isBot = live?.isBot ?? data?.isBot ?? false
  const classColor = CLASS_COLORS[data?.classId] || 'var(--text)'
  const bySlot = new Map((data?.equipment ?? []).map((i) => [i.slot, i]))
  const level = data?.level ?? live?.level
  const raceClass = data ? `${data.race} ${data.class}` : (live ? `${live.race} ${live.class}` : '')

  // Hover shows the tooltip and leaving hides it; a tap (no hover on a
  // phone) pins it until the next tap anywhere.
  const [tip, setTip] = useState(null)
  const onHover = (item, anchor, pin = false) => {
    if (!item) { if (!tip?.pinned) setTip(null); return }
    if (pin && tip?.pinned && tip.item === item) { setTip(null); return }
    setTip({ item, anchor, pinned: pin })
  }
  useEffect(() => {
    if (!tip?.pinned) return
    const off = () => setTip(null)
    document.addEventListener('click', off)
    return () => document.removeEventListener('click', off)
  }, [tip])

  return (
    <aside className={`cc pd ${isBot ? 'bot' : 'player'}`}>
      <div className="pd-head">
        <div>
          <h3 style={{ color: classColor }}>{name}</h3>
          <p className="pd-sub">
            {level != null && <>Level {level} {raceClass}</>}
            {data?.guild ? <span className="pd-guild"> &lt;{data.guild}&gt;</span> : null}
            <span className="cc-kind">{isBot ? 'playerbot' : 'player'}</span>
          </p>
        </div>
        <button className="cc-close" onClick={onClose} aria-label="Close">×</button>
      </div>

      {live && (
        <div className="pd-live">
          <div className="pd-hp" title={`${live.hpPct}% health`}><i style={{ width: `${live.hpPct}%` }} /></div>
          <span>{live.areaName}</span>
        </div>
      )}

      {error && <p className="cc-note">Could not load the character: {error}</p>}

      {data && (
        <>
          <div className="pd-doll">
            <div className="pd-col">
              {LEFT.map(([slot, label]) => <Slot key={slot} label={label} item={bySlot.get(slot)} side="left" onHover={onHover} />)}
            </div>
            <div className="pd-centre">
              <div className="pd-stat big"><b>{data.avgItemLevel || '—'}</b><span>item level</span></div>
              <div className="pd-stat"><b><Money copper={data.money} /></b><span>gold</span></div>
              <div className="pd-stat"><b>{played(data.totaltime)}</b><span>played</span></div>
              <div className="pd-stat"><b>{data.totalKills.toLocaleString()}</b><span>honorable kills</span></div>
              <div className="pd-stat"><b>{data.totalHonorPoints.toLocaleString()}</b><span>honor</span></div>
              <div className="pd-stat"><b>{data.arenaPoints.toLocaleString()}</b><span>arena points</span></div>
            </div>
            <div className="pd-col">
              {RIGHT.map(([slot, label]) => <Slot key={slot} label={label} item={bySlot.get(slot)} side="right" onHover={onHover} />)}
            </div>
          </div>
          <div className="pd-weapons">
            {WEAPONS.map(([slot, label]) => <Slot key={slot} label={label} item={bySlot.get(slot)} side="bottom" onHover={onHover} />)}
          </div>

          {data.professions.length > 0 && (
            <div className="pd-profs">
              {data.professions.map((p) => (
                <div key={p.name} className="pd-prof" title={`${p.name} ${p.value} / ${p.max}`}>
                  <span>{p.name}</span>
                  <i><b style={{ width: `${(p.value / Math.max(1, p.max)) * 100}%` }} /></i>
                  <em>{p.value}/{p.max}</em>
                </div>
              ))}
            </div>
          )}
        </>
      )}

      {isBot && live && <BotActions name={name} />}

      {tip && <ItemTooltip item={tip.item} anchor={tip.anchor} onClose={() => setTip(null)} />}
    </aside>
  )
}
