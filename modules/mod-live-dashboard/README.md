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

## The map

The continent pictures are the client's own minimap tiles, stitched into one
image per continent (`webapp/frontend/public/maps/`), one 32 px square per
533.33-yard ADT tile and cropped to the tiles that exist. That crop is the
whole projection: a dot's position is its ADT tile column and row relative to
the image's first tile (`MAP_TILES` in `constants.js`), nothing more. The first
version plotted against the WorldMapArea.dbc continent rectangle instead, which
is a different and much larger box - for the Eastern Kingdoms it spans tile
columns -2 to 74 while the picture holds 24 to 44 - so every dot was squeezed
toward the centre and the ones near the coast landed in the sea.

**Build the tile pyramid** and the map becomes a real web map: Leaflet over
tiles at the minimap's full 256 px per ADT tile, loaded on demand, from a
whole continent down to a single tile, with pinch-zoom on a phone.

```bash
cd modules/mod-live-dashboard/webapp
python3 tools/build_map_tiles.py /path/to/your/3.3.5a/client
```

That reads the minimap straight out of the client's MPQ archives (about a
minute, ~22 MB into `webapp/tiles/`, gitignored) and `server.py` serves it
under `/tiles/`. Without it the dashboard falls back to the single
low-resolution picture per continent with CSS zoom (scroll, double-click, or
the buttons; drag to pan) - usable, but blocky when zoomed in. Clicking a dot - or a row
in the "Other" list - opens a character card beside the map: level, class,
guild, gold, played time, honour, every equipped item in its quality colour
with the average item level, and professions. It is read from the tables the
game persists, so it works for someone who is offline too, and follows the
live row for HP and area while they are on. `?guid=N` in the URL opens a card
straight away, and switches to that character's continent.

The card is laid out like the game's own character frame - slots down both
sides, weapons underneath - with each item's icon in a frame of its quality
colour, the way the game draws it. The icons come from the client too:

```bash
python3 tools/build_item_icons.py /path/to/your/3.3.5a/client
```

reads ItemDisplayInfo.dbc and the ~5000 icon textures it names out of the
archives (they live in the locale archives; custom ones such as mod-madosa's
Ascension items in the data patches) into `webapp/icons/` (~20 MB,
gitignored). Without it the sheet still works, showing a quality-coloured
placeholder where the icon would be.

The same run writes what a tooltip needs beyond `item_template`: Spell.dbc's
descriptions for the Equip/Use lines, and SpellItemEnchantment, ItemRandomSuffix,
ItemRandomProperties and RandPropPoints for what a worn item's enchantments and
random suffix actually give. That last part matters more than it sounds - the
gear on a playerbot realm carries most of its stats as random suffixes
("of Stamina") and enchants, none of which is in `item_template`, so without
this data the sheet would show a helm with no stats at all.

For a playerbot the card also offers actions - revive, level up, refresh,
send it grinding, teleport it to a city, log it out - which go through the
admin command queue below and therefore need the admin token, unlocked once in
the Admin view. They are mod-playerbots' own `.playerbots rndbot <verb> <name>`
console commands plus `.tele name` and `.kick`; the rndbot ones answer in the
server log rather than to the caller, so "done" means the world tick ran it.

## Worldforged finds on the map

The **Worldforged** button beside the continent tabs draws mod-madosa's 1628
Ascension Worldforged find locations onto the same map the players are on, with
a search-and-filter panel beside it.

The spawn table stores world coordinates - the same thing a player position is -
so a find needs no conversion the map does not already do for a character. That
is the whole reason this is a few dozen lines rather than a coordinate project:
`/api/worldforged` reads `mod_madosa_worldforged_ascension_spawns` joined to
`item_template` and hands over points and items as they are.

- **Two payloads, on purpose.** The point list and the item table are sent
  separately and keyed by item entry, because 1628 finds name only 1506 distinct
  items - several places hold the same one - and the search wants that table
  anyway. It is 355 KB, fetched once when the layer is first switched on and
  kept for the session: unlike positions this is not live data, so polling it
  would be the same answer every two seconds.
- **Tooltips are fetched per item, on hover.** `/api/worldforged/item?entry=N`
  returns the full game tooltip through the same `item_tooltip()` the character
  sheet uses, so a find describes itself exactly the way the gear on a character
  card does - stats, Equip/Use lines, durability, sell price. Sending all 1506
  up front would be megabytes for the handful anyone looks at. The one
  adjustment: that function reads a row whose first columns come from
  `item_instance` - one physical copy's enchantments and random-property roll -
  and a find has no copy yet, so those are sent as "none rolled" and durability
  as full. What is shown is the item as it will be handed over.
- **The map draws exactly what the filters left.** The panel owns the filtering
  and reports its result up, rather than the map filtering again - two
  implementations of "what is being looked at" is one too many. Markers carry
  the item's quality colour, which is also what the search list and the tooltip
  use, all three from one table in `constants.js`.
- Picking a row centres the map on that find, switching continent if it is on
  the other one.

The single-picture fallback map (`ContinentMap`, for a continent whose tile
pyramid has not been built) carries no find layer. Every continent this server
serves has tiles, so that path is a safety net rather than a second UI to keep
in step.

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
- The read-only endpoints (`/api/positions`, `/api/stats`, `/api/chronicle`,
  `/api/character?guid=N`, `/api/worldforged`, `/api/worldforged/item?entry=N`)
  are unauthenticated, exactly as before.
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
(do this only on a trusted network - the read-only endpoints are
unauthenticated, and the admin ones are one shared token away from console
rights). If the machine runs a firewall, the port has to be opened as well,
e.g. `sudo ufw allow 8787/tcp`.

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
