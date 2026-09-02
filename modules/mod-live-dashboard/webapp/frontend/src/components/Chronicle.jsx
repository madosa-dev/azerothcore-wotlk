import { useMemo, useState } from 'react'
import { usePolling } from '../hooks/usePolling'
import { CLASS_COLORS, CLASS_NAMES, kindMeta, describe, timeAgo } from '../chronicle'

function Name({ part }) {
  const color = part.bot ? 'var(--bot)' : (CLASS_COLORS[part.cls] || 'var(--player)')
  const title = [CLASS_NAMES[part.cls], part.bot ? 'playerbot' : 'player']
    .filter(Boolean).join(' · ')
  return <strong className="chr-name" style={{ color }} title={title}>{part.name}</strong>
}

function Line({ e }) {
  const meta = kindMeta(e.kind)
  return (
    <li className="chr-row" style={{ '--kind': meta.color }}>
      <span className="chr-icon" aria-hidden="true">{meta.icon}</span>
      <span className="chr-text">
        {describe(e).map((part, i) => {
          if (typeof part === 'string') return <span key={i}>{part}</span>
          if (part.em) return <em key={i} className="chr-em">{part.text}</em>
          if (!part.name) return null
          return <Name key={i} part={part} />
        })}
      </span>
      <span className="chr-where">{e.zone}</span>
      <time className="chr-when" dateTime={new Date(e.at * 1000).toISOString()}>
        {timeAgo(e.at)}
      </time>
    </li>
  )
}

function Leaderboard({ title, rows, unit }) {
  if (!rows?.length) return null
  const max = Math.max(...rows.map(r => r.count)) || 1
  return (
    <section className="chr-board">
      <h3>{title}</h3>
      <ol>
        {rows.map(r => (
          <li key={r.name}>
            <span className="chr-board-name" style={{ color: r.bot ? 'var(--bot)' : 'var(--player)' }}>
              {r.name}
            </span>
            <span className="chr-bar"><i style={{ width: `${(r.count / max) * 100}%` }} /></span>
            <span className="chr-board-n">{r.count}{unit ? ` ${unit}` : ''}</span>
          </li>
        ))}
      </ol>
    </section>
  )
}

export default function Chronicle() {
  const [filter, setFilter] = useState('')
  const path = filter ? `/api/chronicle?limit=300&kind=${filter}` : '/api/chronicle?limit=300'
  const events = usePolling(path, 4000) ?? []
  const summary = usePolling('/api/chronicle/summary', 15000)

  // Only offer chips for kinds the realm has actually produced - an empty
  // filter is a dead end and this realm's mix changes as features are added.
  const chips = useMemo(() => summary?.kinds?.map(k => k.kind) ?? [], [summary])

  const today = summary?.kinds?.reduce((n, k) => n + k.today, 0) ?? 0

  return (
    <div className="chr">
      <div className="chr-main">
        <div className="chr-head">
          <h2>The Chronicle</h2>
          <p className="chr-sub">
            {summary
              ? `${summary.total.toLocaleString()} recorded moments · ${today.toLocaleString()} in the last day`
              : 'reading the record…'}
          </p>
        </div>

        <div className="chr-chips">
          <button className={filter === '' ? 'on' : ''} onClick={() => setFilter('')}>
            Everything
          </button>
          {chips.map(k => (
            <button key={k} className={filter === k ? 'on' : ''} onClick={() => setFilter(k)}
              style={{ '--kind': kindMeta(k).color }}>
              <span aria-hidden="true">{kindMeta(k).icon}</span> {kindMeta(k).label}
            </button>
          ))}
        </div>

        {events.length === 0 ? (
          <p className="chr-empty">
            Nothing here yet. The chronicle fills itself as the realm plays —
            kills, Worldforged claims, bosses, risk-mode changes.
          </p>
        ) : (
          <ul className="chr-list">
            {events.map(e => <Line key={e.id} e={e} />)}
          </ul>
        )}
      </div>

      <aside className="chr-side">
        <Leaderboard title="Deadliest" rows={summary?.top_killers} unit="kills" />
        <Leaderboard title="Best finders" rows={summary?.top_finders} unit="finds" />
        {summary?.kinds?.length > 0 && (
          <section className="chr-board">
            <h3>By kind</h3>
            <ol className="chr-kinds">
              {summary.kinds.map(k => (
                <li key={k.kind}>
                  <span style={{ color: kindMeta(k.kind).color }} aria-hidden="true">
                    {kindMeta(k.kind).icon}
                  </span>
                  <span className="chr-board-name">{kindMeta(k.kind).label}</span>
                  <span className="chr-board-n">{k.total.toLocaleString()}</span>
                </li>
              ))}
            </ol>
          </section>
        )}
      </aside>
    </div>
  )
}
