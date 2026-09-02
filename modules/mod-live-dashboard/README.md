# mod-live-dashboard

A live, self-refreshing web dashboard with three views:

- **Live map** - every online player and bot on a per-continent map, plus server
  stats (online counts, top guilds, top auction house listings).
- **Chronicle** - what actually *happened*: kills, Worldforged claims, raid
  bosses, epic loot, risk-mode changes, treason. Three thousand playerbots
  generate stories without pause and nobody ever sees one; the map shows where
  they are, the chronicle shows what they did.
- **Admin** - a console that drives the running server and its bots, gated by a
  token.

## How it works

- The C++ module (`src/live_dashboard.cpp`) is a `WorldScript` that snapshots
  every online player's position into the `live_player_positions` table every
  ~2 seconds. No core files are touched, no sockets are opened from inside the
  game process. Positions are converted to the same 0-100 zone-relative
  percentage used by in-game coordinate addons via the core's
  `Map2ZoneCoordinates()` helper, so the dashboard doesn't need to guess at
  continent art/bounding boxes - it draws one small grid per currently
  populated area instead of a full world map.
- Bot vs. real-player detection uses mod-playerbots' `sPlayerbotsMgr.GetPlayerbotAI()`.
- `webapp/server.py` is a separate, standalone Python process (not part of
  worldserver) that reads DB credentials straight out of your
  `env/dist/etc/worldserver.conf`, polls `live_player_positions` (and the
  `auctionhouse`/`item_template` tables for the AH stats) via the `mysql` CLI
  (no extra pip packages required), and exposes it as JSON under `/api/*`.
- `webapp/frontend/` is the actual UI: a Vite + React app (plain JS, no
  TypeScript) that polls those `/api/*` endpoints and renders the three views.

## The Chronicle

`src/live_chronicle.cpp` writes one row per notable event into
`live_chronicle`. On a realm this size the hard part is deciding what *not* to
record - a line nobody reads is worse than no line - so each kind has a
threshold: levels only at the round milestones, loot only at epic and above,
deaths only for real players. PvP kills and raid bosses always count, being rare
enough to matter on their own.

**The table is the whole contract between modules.** mod-madosa writes its own
events (Worldforged claims, risk-mode changes, death chests, insurance payouts)
into the same table without including a single header from here, and asks the
database once at startup whether the table exists - so neither module needs the
other installed. See `mod-madosa/src/mod_madosa_chronicle.cpp`.

All of the wording lives client-side in `frontend/src/chronicle.js`: the server
stores facts, the browser turns them into sentences. A new event kind added on
the server still appears (under its raw name) and can be given a voice later
without touching the server.

## The admin console

The dashboard still never opens a socket into the game process - that was this
module's founding promise. Instead `server.py` writes a row into
`live_dashboard_commands`, and `src/live_admin.cpp` picks it up on its next tick,
runs it through the same `CliHandler` the server console uses, and writes the
output back. Two things fall out of that for free: an admin action survives the
web server restarting mid-command, and there is a permanent record of every
command anyone ran.

**Commands run with console rights.** There is no curated whitelist on the
server side, because an admin console that can only do a fixed list of things is
not an admin console. The gate is at the other end:

- `server.py` requires an `X-Admin-Token` header on every `/api/admin/*`
  endpoint. The token is generated on first run, kept in `webapp/.admin-token`
  (mode 0600) and printed at startup. Delete that file to roll it.
- The read-only endpoints (`/api/positions`, `/api/stats`, `/api/chronicle`) are
  unauthenticated, exactly as before.
- Binding stays localhost-only unless you pass `--host`, and passing it prints a
  warning. **Do not expose this to an untrusted network.**

The panel's buttons only offer commands the console can actually run: anything
declared `Console::No` in its command table needs a player behind it and would
fail here. `.playerbots bot ...` is the notable one that cannot be driven from a
dashboard for that reason.

## Running the dashboard

**Production** (built once, then just run the Python server):

```bash
cd modules/mod-live-dashboard/webapp/frontend
npm install      # first time only
npm run build    # outputs to ../dist

cd ..
python3 server.py
```

Open http://127.0.0.1:8787 . By default the server only binds to localhost;
pass `--host 0.0.0.0` to make it reachable from other devices on your network
(do this only on a trusted network - the endpoints are unauthenticated).

**Development** (hot reload while editing the React app):

```bash
# terminal 1
python3 modules/mod-live-dashboard/webapp/server.py

# terminal 2
cd modules/mod-live-dashboard/webapp/frontend
npm install
npm run dev
```

Open the Vite dev URL it prints (default http://localhost:5173) - `/api/*`
calls are proxied to the Python server on :8787 (see `vite.config.js`).

Rebuild (`npm run build`) whenever you're done editing so the production path
above picks up the changes - the Python server always serves whatever is in
`webapp/dist/`.
