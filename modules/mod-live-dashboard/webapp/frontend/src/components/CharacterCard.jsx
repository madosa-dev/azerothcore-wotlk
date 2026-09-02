import { useEffect, useState } from 'react'
import { useAdminToken, runAdminCommand } from '../hooks/useAdminToken'

const QUALITY_COLORS = ['#9d9d9d', '#ffffff', '#1eff00', '#0070dd', '#a335ee', '#ff8000', '#e6cc80', '#e6cc80']

// Equipment slots as the character sheet lays them out: a left column, a
// right column, and the weapons underneath.
const LEFT = [[0, 'Head'], [1, 'Neck'], [2, 'Shoulder'], [14, 'Back'], [4, 'Chest'], [3, 'Shirt'], [18, 'Tabard'], [8, 'Wrist']]
const RIGHT = [[9, 'Hands'], [5, 'Waist'], [6, 'Legs'], [7, 'Feet'], [10, 'Ring'], [11, 'Ring'], [12, 'Trinket'], [13, 'Trinket']]
const WEAPONS = [[15, 'Main hand'], [16, 'Off hand'], [17, 'Ranged']]

const CITIES = ['Stormwind', 'Ironforge', 'Darnassus', 'Orgrimmar', 'ThunderBluff', 'Undercity',
  'Shattrath', 'Dalaran', 'BootyBay', 'Gadgetzan']

function played(seconds) {
  const d = Math.floor(seconds / 86400)
  const h = Math.floor((seconds % 86400) / 3600)
  return d ? `${d}d ${h}h` : `${h}h ${Math.floor((seconds % 3600) / 60)}m`
}

function money(copper) {
  const g = Math.floor(copper / 10000)
  const s = Math.floor((copper % 10000) / 100)
  return g >= 1000 ? `${g.toLocaleString()}g` : `${g}g ${s}s`
}

function Slot({ label, item }) {
  return (
    <li className="cc-slot">
      <span className="cc-slot-label">{label}</span>
      {item ? (
        <span className="cc-item" style={{ color: QUALITY_COLORS[item.quality] || '#fff' }} title={`Item level ${item.ilvl}`}>
          {item.name}
          <small>{item.ilvl}</small>
        </span>
      ) : <span className="cc-item empty">—</span>}
    </li>
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
  const bySlot = new Map((data?.equipment ?? []).map((i) => [i.slot, i]))

  return (
    <aside className={`cc ${isBot ? 'bot' : 'player'}`}>
      <div className="cc-head">
        <div>
          <h3>{name} <span className="cc-kind">{isBot ? 'playerbot' : 'player'}</span></h3>
          <p className="cc-sub">
            {data ? `Level ${data.level} ${data.race} ${data.class}` : (live ? `Level ${live.level} ${live.race} ${live.class}` : '')}
            {data?.guild ? <> · &lt;{data.guild}&gt;</> : null}
          </p>
        </div>
        <button className="cc-close" onClick={onClose} aria-label="Close">×</button>
      </div>

      {live && (
        <div className="cc-live">
          <div className="cc-hp"><i style={{ width: `${live.hpPct}%` }} /></div>
          <span>{live.hpPct}% HP · {live.areaName}</span>
        </div>
      )}

      {error && <p className="cc-note">Could not load the character: {error}</p>}

      {data && (
        <>
          <dl className="cc-facts">
            <div><dt>Item level</dt><dd>{data.avgItemLevel || '—'}</dd></div>
            <div><dt>Gold</dt><dd>{money(data.money)}</dd></div>
            <div><dt>Played</dt><dd>{played(data.totaltime)}</dd></div>
            <div><dt>Honor kills</dt><dd>{data.totalKills.toLocaleString()}</dd></div>
            <div><dt>Honor</dt><dd>{data.totalHonorPoints.toLocaleString()}</dd></div>
            <div><dt>Arena points</dt><dd>{data.arenaPoints.toLocaleString()}</dd></div>
          </dl>

          <div className="cc-gear">
            <ul>{LEFT.map(([slot, label]) => <Slot key={slot} label={label} item={bySlot.get(slot)} />)}</ul>
            <ul>{RIGHT.map(([slot, label]) => <Slot key={slot} label={label} item={bySlot.get(slot)} />)}</ul>
          </div>
          <ul className="cc-weapons">
            {WEAPONS.map(([slot, label]) => <Slot key={slot} label={label} item={bySlot.get(slot)} />)}
          </ul>

          {data.professions.length > 0 && (
            <div className="cc-profs">
              <h4>Professions</h4>
              <ul>
                {data.professions.map((p) => (
                  <li key={p.name}><span>{p.name}</span><span>{p.value} / {p.max}</span></li>
                ))}
              </ul>
            </div>
          )}
        </>
      )}

      {isBot && live && <BotActions name={name} />}
    </aside>
  )
}
