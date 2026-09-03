import { useEffect, useMemo, useState } from 'react'
import { KNOWN_MAP_IDS, QUALITY_COLORS } from '../constants'

// Every slot the Worldforged items actually occupy, in the order a character
// sheet reads. Built from the data rather than hard-coded so a regenerated
// spawn table cannot leave a filter option pointing at nothing.
const SLOT_ORDER = [
  'Head', 'Neck', 'Shoulder', 'Back', 'Chest', 'Shirt', 'Tabard', 'Wrist',
  'Hands', 'Waist', 'Legs', 'Feet', 'Finger', 'Trinket',
  'One-Hand', 'Main Hand', 'Off Hand', 'Two-Hand', 'Held In Off-hand',
  'Ranged', 'Thrown', 'Relic', 'Shield',
]

const QUALITIES = [
  [0, 'Any quality'],
  [2, 'Uncommon and better'],
  [3, 'Rare and better'],
  [4, 'Epic only'],
]

// A find matches the search when the typed words all appear somewhere in its
// item name, its zone or its slot - so "epic dagger stranglethorn" narrows the
// way someone would expect without a query language.
function matches(find, item, words) {
  if (!words.length) return true
  const haystack = `${item.name} ${find.zone} ${item.slot} ${item.type}`.toLowerCase()
  return words.every((w) => haystack.includes(w))
}

export default function WorldforgedPanel({
  data, mapId, onPick, onHover, onLeave, onResults, picked, onClose,
}) {
  const [search, setSearch] = useState('')
  const [minQuality, setMinQuality] = useState(0)
  const [slot, setSlot] = useState('')
  const [zone, setZone] = useState('')
  const [thisContinent, setThisContinent] = useState(true)

  const items = data?.items ?? {}

  // The "Other" tab is a list of stragglers on maps with no picture, not a
  // continent, so there is nothing there to scope to - the filter falls back to
  // everything rather than to an empty list.
  const onAContinent = KNOWN_MAP_IDS.has(mapId)

  const scoped = useMemo(
    () => (data?.points ?? []).filter((p) => !thisContinent || !onAContinent || p.mapId === mapId),
    [data, mapId, thisContinent, onAContinent],
  )

  const zones = useMemo(
    () => [...new Set(scoped.map((p) => p.zone))].sort(),
    [scoped],
  )

  const slots = useMemo(() => {
    const present = new Set(scoped.map((p) => items[p.entry]?.slot).filter(Boolean))
    return SLOT_ORDER.filter((s) => present.has(s))
  }, [scoped, items])

  const results = useMemo(() => {
    const words = search.toLowerCase().split(/\s+/).filter(Boolean)
    return scoped.filter((p) => {
      const item = items[p.entry]
      if (!item) return false
      if (minQuality && item.quality < minQuality) return false
      if (slot && item.slot !== slot) return false
      if (zone && p.zone !== zone) return false
      return matches(p, item, words)
    })
  }, [scoped, items, search, minQuality, slot, zone])

  // The map draws exactly what the filters left, so the two can never disagree
  // about what is being looked at. Reported up rather than computed twice.
  useEffect(() => { onResults(results) }, [results, onResults])

  // The list is what a person reads; the map already carries every match. A few
  // hundred rows is plenty to scroll and keeps the panel from rendering two
  // thousand nodes on every keystroke.
  const shown = results.slice(0, 300)

  if (!data) {
    return (
      <aside className="panel wf-panel">
        <h2>Worldforged</h2>
        <div className="empty">Loading find locations…</div>
      </aside>
    )
  }

  return (
    <aside className="panel wf-panel">
      <h2>
        Worldforged <span className="count">{results.length}</span>
        <button type="button" className="wf-close" onClick={onClose} title="Close">×</button>
      </h2>

      <input
        className="wf-search"
        type="search"
        value={search}
        placeholder="Search item, zone or slot…"
        onChange={(e) => setSearch(e.target.value)}
      />

      <div className="wf-filters">
        <select value={minQuality} onChange={(e) => setMinQuality(Number(e.target.value))}>
          {QUALITIES.map(([v, label]) => <option key={v} value={v}>{label}</option>)}
        </select>
        <select value={slot} onChange={(e) => setSlot(e.target.value)}>
          <option value="">Any slot</option>
          {slots.map((s) => <option key={s} value={s}>{s}</option>)}
        </select>
        <select value={zone} onChange={(e) => setZone(e.target.value)}>
          <option value="">Any zone</option>
          {zones.map((z) => <option key={z} value={z}>{z}</option>)}
        </select>
        <label className="wf-check">
          <input
            type="checkbox"
            checked={thisContinent}
            disabled={!onAContinent}
            onChange={(e) => { setThisContinent(e.target.checked); setZone('') }}
          />
          This continent only
        </label>
      </div>

      {results.length === 0 ? (
        <div className="empty">Nothing matches.</div>
      ) : (
        <div className="wf-list">
          {shown.map((p) => {
            const item = items[p.entry]
            return (
              <button
                type="button"
                key={p.id}
                className={`wf-row${picked === p.id ? ' on' : ''}`}
                onClick={() => onPick(p)}
                onMouseEnter={(e) => onHover(p, e.currentTarget)}
                onMouseLeave={onLeave}
              >
                {item.icon
                  ? <img src={`/icons/${item.icon}.webp`} alt="" loading="lazy" />
                  : <span className="wf-noicon" />}
                <span className="wf-text">
                  <span className="wf-name" style={{ color: QUALITY_COLORS[item.quality] }}>{item.name}</span>
                  <span className="wf-meta">{p.zone} · {item.slot || item.type || '—'} · ilvl {item.ilvl}</span>
                </span>
              </button>
            )
          })}
          {results.length > shown.length && (
            <div className="wf-more">{results.length - shown.length} more — narrow the search</div>
          )}
        </div>
      )}
    </aside>
  )
}
