import { useCallback, useState } from 'react'

const TOKEN_KEY = 'madosa.dashboard.adminToken'

// The admin token, remembered per browser. Shared by the admin console and
// the bot actions on a character card, so unlocking one unlocks the other.
export function useAdminToken() {
  const [token, setToken] = useState(() => {
    try { return localStorage.getItem(TOKEN_KEY) ?? '' } catch { return '' }
  })
  const save = useCallback(value => {
    setToken(value)
    try { localStorage.setItem(TOKEN_KEY, value) } catch { /* private mode */ }
  }, [])
  return [token, save]
}

// Queues a console command and waits for the world tick to answer it.
// Resolves to { status, output }; status is 'done', 'failed' or 'timeout'.
export async function runAdminCommand(token, cmd, { timeoutMs = 20000 } = {}) {
  const headers = { 'X-Admin-Token': token, 'Content-Type': 'application/json' }
  const res = await fetch('/api/admin/command', { method: 'POST', headers, body: JSON.stringify({ command: cmd }) })
  const { id, error } = await res.json()
  if (!id) throw new Error(error || 'the server refused the command')

  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    await new Promise(r => setTimeout(r, 500))
    const r2 = await fetch(`/api/admin/result?id=${id}`, { headers })
    const result = await r2.json()
    if (result.status === 'done' || result.status === 'failed') return result
  }
  return { status: 'timeout', output: 'No answer in 20s. Is the worldserver running?' }
}
