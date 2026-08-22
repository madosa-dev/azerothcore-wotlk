# mod-live-dashboard

A live, self-refreshing web dashboard showing every online player and bot on a
per-area minimap, plus a few server stats (online counts, top guilds, top
auction house listings).

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
  TypeScript) that polls those `/api/*` endpoints every 2 seconds and renders
  the continent tabs / area cards / dots / stat panels.

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
