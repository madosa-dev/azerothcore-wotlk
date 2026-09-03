import { useEffect, useRef, useState } from 'react'

// The Worldforged find locations, fetched once and kept. Unlike positions this
// is not live data: the spawn table is generated offline and read by the server
// at startup, so polling it would be 350 KB of the same answer every two
// seconds. Module scope rather than component state, so switching away from the
// map view and back does not fetch it again.
let cache = null
let inFlight = null

export function useWorldforged(enabled) {
  const [data, setData] = useState(cache)

  useEffect(() => {
    if (!enabled || cache) return
    let cancelled = false

    inFlight = inFlight || fetch('/api/worldforged').then((res) => {
      if (!res.ok) throw new Error(`/api/worldforged -> HTTP ${res.status}`)
      return res.json()
    })

    inFlight
      .then((json) => {
        cache = json
        if (!cancelled) setData(json)
      })
      .catch((err) => {
        // Let a later mount try again rather than leaving the panel empty
        // forever because one request happened to fail.
        inFlight = null
        console.error(err)
      })

    return () => { cancelled = true }
  }, [enabled])

  return data
}

// One item's full tooltip, fetched when it is first hovered and kept for the
// session. 1500 tooltips up front would be several megabytes for the handful
// anyone actually looks at.
export function useItemTooltips() {
  const cacheRef = useRef(new Map())
  const [, bump] = useState(0)

  const get = (entry) => cacheRef.current.get(entry) ?? null

  const load = (entry) => {
    if (!entry || cacheRef.current.has(entry)) return
    cacheRef.current.set(entry, null)  // in flight; keeps a hover from asking twice
    fetch(`/api/worldforged/item?entry=${entry}`)
      .then((res) => (res.ok ? res.json() : null))
      .then((item) => {
        if (item) {
          cacheRef.current.set(entry, item)
          bump((n) => n + 1)
        }
      })
      .catch((err) => {
        cacheRef.current.delete(entry)
        console.error(err)
      })
  }

  return { get, load }
}
