import { useEffect, useState } from 'react'

// Polls `path` every `intervalMs` and returns the latest parsed JSON response
// (or `null` until the first successful fetch). Errors are logged and simply
// keep the previous value on screen rather than tearing down the UI.
export function usePolling(path, intervalMs = 2000) {
  const [data, setData] = useState(null)

  useEffect(() => {
    let cancelled = false

    async function tick() {
      try {
        const res = await fetch(path)
        if (!res.ok) throw new Error(`${path} -> HTTP ${res.status}`)
        const json = await res.json()
        if (!cancelled) setData(json)
      } catch (err) {
        console.error(err)
      }
    }

    tick()
    const id = setInterval(tick, intervalMs)
    return () => {
      cancelled = true
      clearInterval(id)
    }
  }, [path, intervalMs])

  return data
}
