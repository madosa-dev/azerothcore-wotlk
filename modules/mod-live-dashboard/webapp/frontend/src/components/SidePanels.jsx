function GuildTable({ guilds }) {
  if (!guilds?.length) {
    return <tbody><tr><td className="empty">No guilds online</td></tr></tbody>
  }
  return (
    <tbody>
      {guilds.map((g) => (
        <tr key={g.name}>
          <td>{g.name}</td>
          <td>{g.online}</td>
        </tr>
      ))}
    </tbody>
  )
}

function AuctionTable({ auctions }) {
  if (!auctions?.length) {
    return <tbody><tr><td className="empty">No active auctions</td></tr></tbody>
  }
  return (
    <tbody>
      {auctions.map((a, i) => (
        <tr key={i}>
          <td>{a.item}</td>
          <td>{a.buyoutGold.toLocaleString()}g</td>
        </tr>
      ))}
    </tbody>
  )
}

export default function SidePanels({ stats }) {
  return (
    <div className="side">
      <div className="panel">
        <h2>Top Guilds Online</h2>
        <table>
          <GuildTable guilds={stats?.topGuilds} />
        </table>
      </div>
      <div className="panel">
        <h2>Top Auctions (buyout)</h2>
        <table>
          <AuctionTable auctions={stats?.topAuctions} />
        </table>
      </div>
    </div>
  )
}
