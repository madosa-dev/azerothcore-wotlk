import { useEffect, useState } from 'react'

// The tile pyramid's index (webapp/tiles/index.json), or null while it loads
// or when no pyramid has been built - in which case the map falls back to the
// single low-resolution picture per continent.
export function useTileIndex() {
  const [index, setIndex] = useState(null)
  const [ready, setReady] = useState(false)

  useEffect(() => {
    let cancelled = false
    fetch('/tiles/index.json')
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null)
      .then((json) => { if (!cancelled) { setIndex(json); setReady(true) } })
    return () => { cancelled = true }
  }, [])

  return { index, ready }
}
