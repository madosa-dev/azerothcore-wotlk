import { useCallback, useEffect, useRef, useState } from 'react'
import { useAdminToken } from '../hooks/useAdminToken'

// Curated actions, grouped. Only commands the server console can actually run
// are offered as buttons: anything declared Console::No in its command table
// needs a player behind it and would simply fail here. `.playerbots bot ...` is
// the notable one that cannot be driven from a dashboard for that reason.
const ACTIONS = [
  {
    group: 'Server',
    items: [
      { label: 'Status', cmd: '.server info' },
      { label: 'Save everyone', cmd: '.save all' },
      { label: 'Motd', cmd: '.server motd' },
      { label: 'Shutdown in 60s', cmd: '.server shutdown 60', danger: true },
      { label: 'Cancel shutdown', cmd: '.server shutdown cancel' },
      { label: 'Restart in 300s', cmd: '.server restart 300', danger: true },
    ],
  },
  {
    group: 'Playerbots',
    items: [
      { label: 'Bot stats', cmd: '.playerbots rndbot stats' },
      { label: 'Reload config', cmd: '.playerbots rndbot reload' },
      { label: 'Force update', cmd: '.playerbots rndbot update' },
      { label: 'Performance monitor', cmd: '.playerbots pmon' },
      { label: 'Reset all bots', cmd: '.playerbots rndbot reset', danger: true },
    ],
  },
  {
    group: 'World',
    items: [
      { label: 'Who is online', cmd: '.account onlinelist' },
      { label: 'Reload creature templates', cmd: '.reload creature_template' },
      { label: 'Reload all gossip', cmd: '.reload gossip_menu' },
      { label: 'Reload config', cmd: '.reload config' },
    ],
  },
  {
    group: 'Madosa',
    items: [
      { label: 'Module settings', cmd: '.madosa status' },
      { label: 'Hardcore PvP status', cmd: '.madosa hardcore' },
      { label: 'Worldforged status', cmd: '.madosa worldforged status' },
    ],
  },
]

export default function Admin() {
  const [token, setToken] = useAdminToken()
  const [draft, setDraft] = useState('')
  const [log, setLog] = useState([])
  const [history, setHistory] = useState([])
  const [busy, setBusy] = useState(false)
  const logRef = useRef(null)

  const headers = token ? { 'X-Admin-Token': token } : {}

  const refreshHistory = useCallback(async () => {
    if (!token) return
    try {
      const res = await fetch('/api/admin/history', { headers })
      if (res.ok) setHistory(await res.json())
    } catch { /* the panel keeps whatever it had */ }
  }, [token])

  useEffect(() => {
    refreshHistory()
    const id = setInterval(refreshHistory, 5000)
    return () => clearInterval(id)
  }, [refreshHistory])

  useEffect(() => {
    if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight
  }, [log])

  // Queue, then poll for the result. The command runs inside the world tick, so
  // "queued" and "finished" are genuinely different moments and the panel says
  // which one it is rather than pretending the button was the action.
  const run = useCallback(async cmd => {
    if (!token) return
    setBusy(true)
    setLog(l => [...l, { cmd, status: 'queued', output: '' }])
    try {
      const res = await fetch('/api/admin/command', {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({ command: cmd }),
      })
      const { id, error } = await res.json()
      if (!id) throw new Error(error || 'the server refused the command')

      for (let i = 0; i < 40; i++) {
        await new Promise(r => setTimeout(r, 500))
        const r2 = await fetch(`/api/admin/result?id=${id}`, { headers })
        const result = await r2.json()
        if (result.status === 'done' || result.status === 'failed') {
          setLog(l => l.map((entry, idx) =>
            idx === l.length - 1 ? { ...entry, status: result.status, output: result.output } : entry))
          refreshHistory()
          return
        }
      }
      setLog(l => l.map((entry, idx) =>
        idx === l.length - 1
          ? { ...entry, status: 'timeout', output: 'No answer in 20s. Is the worldserver running?' }
          : entry))
    } catch (err) {
      setLog(l => l.map((entry, idx) =>
        idx === l.length - 1 ? { ...entry, status: 'failed', output: String(err.message || err) } : entry))
    } finally {
      setBusy(false)
    }
  }, [token, refreshHistory])

  if (!token) {
    return (
      <div className="adm-gate">
        <h2>Admin console</h2>
        <p>
          Commands here run with the same rights as the server console. The token
          is printed by <code>server.py</code> when it starts, and kept in
          <code> webapp/.admin-token</code>.
        </p>
        <form onSubmit={e => { e.preventDefault(); setToken(draft.trim()) }}>
          <input type="password" value={draft} placeholder="Admin token"
            onChange={e => setDraft(e.target.value)} autoFocus />
          <button type="submit">Unlock</button>
        </form>
      </div>
    )
  }

  return (
    <div className="adm">
      <div className="adm-main">
        <div className="adm-head">
          <h2>Admin console</h2>
          <button className="adm-lock" onClick={() => setToken('')}>Lock</button>
        </div>

        {ACTIONS.map(({ group, items }) => (
          <section key={group} className="adm-group">
            <h3>{group}</h3>
            <div className="adm-buttons">
              {items.map(a => (
                <button key={a.cmd} disabled={busy}
                  className={a.danger ? 'danger' : ''}
                  title={a.cmd}
                  onClick={() => run(a.cmd)}>
                  {a.label}
                </button>
              ))}
            </div>
          </section>
        ))}

        <section className="adm-group">
          <h3>Anything else</h3>
          <form className="adm-console" onSubmit={e => {
            e.preventDefault()
            const cmd = draft.trim()
            if (cmd) { run(cmd); setDraft('') }
          }}>
            <input value={draft} placeholder=".server info"
              onChange={e => setDraft(e.target.value)} disabled={busy} />
            <button type="submit" disabled={busy || !draft.trim()}>Run</button>
          </form>
        </section>

        <div className="adm-log" ref={logRef}>
          {log.length === 0
            ? <p className="adm-empty">Output appears here.</p>
            : log.map((entry, i) => (
              <div key={i} className={`adm-entry ${entry.status}`}>
                <div className="adm-cmd">{entry.cmd} <span>{entry.status}</span></div>
                {entry.output && <pre>{entry.output}</pre>}
              </div>
            ))}
        </div>
      </div>

      <aside className="adm-side">
        <h3>Recently run</h3>
        {history.length === 0 ? <p className="adm-empty">Nothing yet.</p> : (
          <ol className="adm-history">
            {history.map(h => (
              <li key={h.id} className={h.status}>
                <code>{h.command}</code>
                <span>{h.status}</span>
              </li>
            ))}
          </ol>
        )}
      </aside>
    </div>
  )
}
