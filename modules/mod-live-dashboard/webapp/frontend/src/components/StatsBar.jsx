function Stat({ value, label, className }) {
  return (
    <div className="stat">
      <span className={`n ${className ?? ''}`}>{value ?? '-'}</span>
      <span className="l">{label}</span>
    </div>
  )
}

export default function StatsBar({ stats }) {
  return (
    <header>
      <h1>AzerothCore Live Dashboard</h1>
      <Stat value={stats?.playersOnline} label="Players" className="player" />
      <Stat value={stats?.botsOnline} label="Bots" className="bot" />
      <Stat value={stats?.auctionCount} label="Auctions" />
      <Stat value={stats?.auctionGoldTotal?.toLocaleString()} label="AH Gold" />
    </header>
  )
}
