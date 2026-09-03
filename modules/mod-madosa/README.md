# mod-madosa

A grab-bag module for madosa's own small, ongoing server customizations -
tweaks that are worth keeping in the fork but don't each need their own
dedicated module (unlike e.g. `mod-xpboost` or `mod-live-dashboard`, which
are substantial enough to stand on their own).

## What goes here

- Small SQL content tweaks: drop them in `data/sql/db-world/base/` (or
  `db-characters/`, `db-auth/`), one `.sql` file per tweak, applied
  automatically by the DB updater/`dbimport` like any other module SQL.
  Keep each file idempotent (`DELETE ... WHERE` before `INSERT`, `UPDATE`
  instead of blind inserts) so re-running it is always safe.
- Small C++ tweaks (a command, a script hook): add a new `.cpp`/`.h` pair
  under `src/`, declare and call its `AddSC_*()` from
  `src/mod_madosa_loader.cpp`.
- Lua (ALE) scripts: put them in `lua/` - see [`lua/README.md`](lua/README.md).
  Prefer Lua over C++ for anything you expect to iterate on, since a Lua
  change needs neither a rebuild nor a restart. Note that `mod-ale` is a
  diverged Eluna fork with its own API, and that this realm's ~3000
  playerbots make every player-scoped hook bot-heavy - both are covered
  there.

## Current content

- **`free_starter_mounts.sql`**: lowers Apprentice Riding's trainable level
  (spell 33388) and the ten starter mount items' required level to 7, and
  adds a "Riding Instructor" NPC (race-gated gossip menu, one free mount per
  race) spawned in each starting zone.
- **`src/mod_madosa_profession_tools.cpp`**: hands a player the matching
  gathering tool (Mining Pick, Skinning Knife, Fishing Pole) the moment they
  know that profession - on training it (`OnPlayerLearnSpell`) and, to catch
  characters/bots that already knew it beforehand, on every login too. Keyed
  off the skill itself rather than a specific trainer spell id, since a
  trainer "buy" spell is often just a wrapper around the spell that actually
  sets the skill. See `Madosa.ProfessionTools.Enable`.
- **`auto_loot_pet.sql`** + `src/mod_madosa_autoloot_pet.cpp`: "Lootbot", a
  companion pet (1000g, sold by a "Special Vendor" NPC in every capital city)
  that auto-loots the owner's kills while summoned. See
  `Madosa.AutoLootPet.Enable` under "Live-tunable settings" below.

  **Kills made at range count too**, which took a core hook to arrange. Looting
  is gated on `INTERACTION_DISTANCE` (5.5 yards) in four places -
  `Player::SendLoot()`, both loot opcode handlers and `DoLootRelease()` - so the
  pet used to work only for things killed in melee, and a hunter or a caster
  watched it do nothing. `PlayerScript::OnPlayerCanLootOutOfRange()` lets a
  script say "this one, now"; the pet answers true for exactly the corpse it is
  looting and everything else - permission, group rolls, master loot, the gold
  split - runs the code it always did. `DoLootRelease()` is the gate worth
  naming: it is where an emptied corpse loses `UNIT_DYNFLAG_LOOTABLE`, so
  lifting the other three and not that one would leave empty corpses still
  advertising loot.
- **`class_trainer_pet.sql`**: "Classtrainer", a companion pet (2000g, sold by
  the same Special Vendor NPCs as Lootbot) that opens a real class-trainer
  window when talked to. There is only one pet/creature for every class - the
  trainer it points at (`trainer.Id = 90001`) has the union of every class's
  own trainer spells, and the core's existing per-spell class/race filtering
  (`Player::IsSpellFitByClassAndRace`, used by `Trainer::SendSpells`/
  `GetSpellState`) already hides and blocks anything that isn't the viewing
  player's own class - no per-class creature or custom C++ needed. Startup
  logs a one-line `invalid class requirement` warning for trainer 90001; that's
  expected (`Requirement = 0` is what makes the window open for every class)
  and harmless.
- **`profession_trainer_pet.sql`**: "Craftbot", a companion pet (2000g, sold
  by the same Special Vendor NPCs) that opens one trainer window teaching
  every profession at once - not a "pick a profession" menu, one flat list
  with everything in it (all crafting/gathering professions plus cooking,
  first aid and fishing). Unlike Classtrainer, profession trainers don't need
  the `Requirement = 0` workaround - real ones already ship that way - so
  every player genuinely sees every profession together; the normal
  2-primary-profession limit still applies via the core's own
  `Trainer::CanTeachSpell()`.
- **`bank_pet.sql`**: "Bankbot", a companion pet (2000g) that opens your bank
  window from anywhere - the core's normal `GOSSIP_OPTION_BANKER` ->
  `SendShowBank()` path, just wired to a companion instead of a stationary
  NPC. Inspired by Ascension WoW's "Personal Bank" convenience item.
- **`auction_pet.sql`**: "Auctionbot", a companion pet (2000g) that opens the
  (neutral - the pet's faction template carries no Alliance/Horde mask, so
  `AuctionHouseMgr::GetAuctionHouseEntryFromFactionTemplate()` always falls
  back to the neutral house) auction house from anywhere, same
  `GOSSIP_OPTION_AUCTIONEER` trick as Bankbot.
- **`instance_quest_pet.sql`** + `src/mod_madosa_instance_quest_pet.cpp`:
  "Questbot", a companion pet (2000g) that, while summoned inside a dungeon
  or raid, offers every quest that instance has - not the usual one-at-a-time
  chain order, all of it at once - and from anywhere takes back any instance
  quest currently in the log. The only companion that needed real C++: which
  quests belong to which instance is computed once at startup from
  `creature_queststarter`/`gameobject_queststarter` cross-referenced with
  where those NPCs/objects are actually spawned, checked against the live
  Map.dbc data (`sMapStore`) since this database's `map_dbc` mirror table
  isn't populated. The accept list deliberately skips the level and
  prerequisite-chain checks (`Player::SatisfyQuestLevel`/
  `SatisfyQuestPreviousQuest`/etc.) but keeps every other real one (class,
  race, reputation, exclusivity, disables) - the actual accept opcode still
  runs the full `CanTakeQuest()`, so something that truly isn't takeable yet
  still gets the normal rejection instead of silently breaking. See
  `Madosa.InstanceQuestPet.Enable`.
- **Vanity quality (`item_template.Quality = 6`)**: WotLK 3.3.5a never assigns
  quality 6 ("Artifact") to any obtainable item, so mod-madosa repurposes it
  as a "Vanity" quality for account-wide companions/toys instead of inventing
  an out-of-range value the client has never seen. All six companion pets are
  Vanity items. The `addon/VanityQuality` addon recolors it client-side
  (magenta by default - see the comment at the top of `VanityQuality.lua` for
  how, and its documented limits: the tooltip name/border and the in-world
  loot glow are rendered natively and stay the default Artifact gold, since
  that path never calls back into Lua).
- **`addon/AdiBags_RecipeHint`**: an AdiBags plugin that marks every recipe
  in the bags with the one thing you want to know about it - a green tick if
  this character can learn it now, the skill number if a profession they have
  is not high enough yet, a faint cross if it is already known, nothing if it
  is another profession's or another class's. There is no API for
  "learnable"; the game only says it the way it says it to the player, in the
  tooltip, so the plugin reads a hidden tooltip and looks for the red
  "Requires Tailoring (150)" and "Already known" lines - only above the "Use:"
  line, because what follows is the crafted item's tooltip and its own red
  level requirement is about the product. Client-side only; drop the folder
  into `Interface/AddOns` next to AdiBags, and it appears in AdiBags' module
  options.
- **`src/mod_madosa_account_companions.cpp`**: makes every Vanity item's
  learn-spell account-wide - once any character on the account has learned
  one (used the item), every other character on that account knows it too
  from their next login on, no extra purchase and no client changes needed.
  Not specific to the six pets: any future item with `Quality = 6` that
  teaches a spell via the standard `spellid_N`/`spelltrigger_N =
  ITEM_SPELLTRIGGER_LEARN_SPELL_ID` convention is picked up automatically -
  the spell list is loaded from `item_template` once at startup (a restart is
  needed to pick up a newly added Vanity item, same as trainer/quest data).
  The WotLK client's own Pets/Companions tab already lists whatever the
  character currently knows, so this doesn't need a custom browser window -
  granting the spell server-side on login gets the same result. Tracked in
  the `account_companion_pets` characters-DB table, keyed by spell id. See
  `Madosa.AccountCompanions.Enable`.
- **`profession_slot_scroll.sql`** + `src/mod_madosa_profession_slots.cpp`:
  "Scroll of Professions" (item 90001, 5000g, sold at the same 8 Special
  Vendor NPCs as the companion pets), consumed to grant a character one
  further primary profession slot past the server's usual limit, up to
  `Madosa.ProfessionSlots.Max`. Also a Vanity item, but deliberately not
  account-wide: it doesn't teach a spell via the learn-spell convention (a
  profession slot is per-character by nature), so
  `mod_madosa_account_companions.cpp` never picks it up. See
  `Madosa.ProfessionSlots.Enable`.
- **`src/mod_madosa_passerby_buff.cpp`**: idle/random playerbots that are NOT
  in your group give you their signature buff when standing nearby, the way a
  friendly player might in trade chat - checked every 5 seconds via a periodic
  scan from each real player's side (using mod-playerbots' `GET_PLAYERBOT_AI`
  purely to tell a bot from a real player, no other coupling to its internals,
  so this survives `mod-playerbots` upstream merges untouched). Only Priest
  (Fortitude/Divine Spirit), Mage (Arcane Intellect), Druid (Mark of the Wild)
  and Paladin (a Blessing) have anything to offer this way: every other
  class's group buffs (Battle Shout, Aspects, Auras, totems) only ever affect
  the caster's own party/raid in WotLK, so a bystander can't receive them. A
  bot only ever offers the highest rank it currently knows (resolved by spell
  name against its own spellbook, mirroring how mod-playerbots itself picks a
  bot's spell rank) and never re-casts a buff already present on the target.
  See `Madosa.PasserbyBuff.Enable` and friends.

- **`service_pets.sql`** + `src/mod_madosa_service_pets.cpp`: "Repairbot" and
  "Mailbot", two more 2000g companions from the same Special Vendors.
  Repairbot repairs everything you carry (normal durability cost still
  applies - it removes the walk to town, not the gold sink); Mailbot opens
  your mailbox anywhere. Unlike Bankbot/Auctionbot neither could be pure
  data: there is no `GOSSIP_OPTION_MAILBOX` at all, and
  `GOSSIP_OPTION_ARMORER` is never rendered as a menu entry
  (`PlayerGossip.cpp` sets `canTalk = false` for it) because repairing
  normally goes through the *merchant* frame - which would mean giving the
  pet a vendor inventory it has no business having, and an empty one makes
  `SendListInventory` answer "Vendor has no inventory" instead of opening.
  Both repurpose a genuinely unobtainable companion (picked by elimination:
  no vendor, no loot table, no quest reward, not craftable, no existing
  `ScriptName`, spawned nowhere). See `Madosa.RepairPet.Enable` and
  `Madosa.MailPet.Enable`.

- **`omni_pet.sql`** + the `npc_madosa_omnibot` script in
  `src/mod_madosa_service_pets.cpp`: "Omnibot", one 10000g companion offering
  every service the individual ones do - bank, auction house, mail, repair and
  training - and auto-looting kills like Lootbot (that part lives in
  `mod_madosa_autoloot_pet.cpp`, which now matches either companion's entry).
  It exists because of a hard client limit rather than for convenience: WotLK
  allows exactly **one** summoned companion, so owning eight service pets means
  constantly swapping them, and each companion added makes that worse. The core
  has the same idea in the Argent Pony (`scripts/Pet/pet_generic.cpp`).
  Training was the one service that could not simply be forwarded: both
  `WorldSession::SendTrainerList()` and the buy handler resolve the trainer from
  `npc->GetEntry()`, so showing another creature's list would display spells
  that then fail to purchase. Omnibot therefore has its own trainer (90003),
  built in SQL as a `SELECT` union of Classtrainer's (90001) and Craftbot's
  (90002) lists so it cannot drift out of sync. Merging is safe because neither
  the class/race filtering (`Trainer::GetSpellState` ->
  `Player::IsSpellFitByClassAndRace`) nor the two-primary-profession limit
  (`Trainer::CanTeachSpell` -> `GetFreePrimaryProfessionPoints`) depends on the
  trainer's `Type`. Like trainer 90001 it logs one harmless `invalid class
  requirement` warning at startup, for the same `Requirement = 0` reason. See
  `Madosa.OmniPet.Enable`.

- **`worldforged.sql` + `worldforged_spawns.sql` + `src/mod_madosa_worldforged.cpp`**:
  **Worldforged**, a recurring world event, inspired by Ascension WoW's
  Worldforged drops and the community `LootCollector` addon that shares their
  locations. Every `Madosa.Worldforged.IntervalMinutes` the server forges a
  "Worldforged Cache" somewhere in the open world, announces its **zone** (never
  its exact spot - the searching is the feature) to everyone online, and whoever
  gets there first opens it for a randomly enchanted piece of gear scaled to
  their own level, plus some gold. Unclaimed caches crumble away after
  `LifetimeMinutes`. Three things are worth knowing:
  - **Only real players can open one.** With ~3000 playerbots roaming, a bot
    would otherwise claim nearly every cache and the event would exist only in
    its own announcements. Same `GET_PLAYERBOT_AI` bot check the passerby buff
    uses, and no other coupling to mod-playerbots.
  - **The reward scales to the finder, not to the spawn point**, which is what
    lets one world-wide spawn table serve every level. The spawn point's level
    band only decides *where* a cache lands: the forge picks a spot that suits
    the level of one of the real players currently online, and forges nothing at
    all while nobody is.
  - **No new items, spells or DBC rows** - the "forging" is the core's own
    `Item::GenerateItemRandomPropertyId()` over the 3400-odd shipped
    weapon/armor templates that carry a `RandomProperty`/`RandomSuffix` group,
    so a find is a real *"of the Eagle"* roll and needs no client patch.

  The cache object (`gameobject_template` 900400) is a **GOOBER, not a CHEST**,
  despite looking like one: a chest is looted through `CMSG_LOOT` ->
  `Player::SendLoot()`, a path with no script hook at all, while a goober goes
  through `CMSG_GAMEOBJ_USE` -> `GameObject::Use()`, whose first statement is
  `sScriptMgr->OnGossipHello()`. Returning `true` there hands the whole
  interaction to the script, which is what makes a per-finder reward possible.

  The 192 spawn points are generated by `tools/worldforged/build_spawns.py` from
  the positions of real world creature spawns - which gives reachable ground in
  a populated place *and* an exact level for free, where the `gameobject` and
  `creature` tables' own `zoneId` columns are populated for too few rows to use.
  Re-run it (`--write`) to regenerate; ids from 10000 up are left alone for
  hand-picked spots of your own. Known trade-off: each forge can leave one more
  map grid resident for the rest of the uptime, since this core never unloads
  grids at runtime - which is why the interval is in minutes and `MaxActive`
  defaults to 1.

  GM commands: `.madosa worldforged status` / `spawn` / `clear`.

- **`worldforged_ascension_items.sql` + `worldforged_ascension_spawns.sql` +
  `src/mod_madosa_worldforged_ascension.cpp`**: **Ascension's Worldforged, for
  real.** Not an homage this time - the actual items, with Ascension's own names,
  qualities, item levels, slots, armour, damage and stats, standing at the actual
  3608 places Ascension players found them. A separate system from the timed
  event above: nothing is announced and nothing moves; a spot always holds what
  it holds.

  Where the data comes from, since both Ascension item databases are gone
  (`db.ascension.gg` no longer resolves, `db.exil.es` does not answer, and the
  Wayback captures are empty SPA shells):
  - **The items** come out of the Ascension *client's own cache*
    (`Cache/WDB/.../itemcache.wdb`), which stores the raw
    `SMSG_ITEM_QUERY_SINGLE_RESPONSE` the server sent for every item the client
    was ever shown. Ascension left that packet at the stock 3.3.5a layout, so it
    parses exactly - and the parser proves it by checking that every one of the
    17391 records is consumed to precisely its declared length. Worldforged items
    identify themselves: Ascension tags each one `@Worldforged@` in the
    description. 2615 of them.
  - **The locations** come from the `LootCollector` addon's community starter
    database, decoded back through its
    `!LC1!` + LibDeflate + AceSerializer pipeline, then converted from zone
    percentages to world coordinates exactly as the core's own
    `Zone2MapCoordinates()` does it. That conversion is checked rather than
    trusted: the median converted point lands **16 yards** from the nearest
    creature spawn in this world database, 87% within 50. 351 finds are dropped -
    caves, mines and starting sub-zones have no `WorldMapArea` row to convert
    against.

  Two things deliberately do not come across, because a dangling reference is
  worse than an absent one: the **item effects** (586 distinct Ascension spells -
  recreating them would be a project the size of everything else here) and
  `ItemLimitCategory` above 85, the highest WotLK ships.

  **The display ids had to be re-numbered.** Ascension did not only add
  ItemDisplayInfo rows, it reused existing ones for other things: of the 1424
  displays these items use, 918 exist in WotLK too and mean something entirely
  different. Display 15113 is a mage cape here and a flint axe on Ascension -
  leave it alone and the axe renders wearing the cape's texture, which is what a
  checkerboard model is. So every Worldforged display is copied in under a fresh
  id from 200000 up (this client's highest real one is 69006) and the items point
  at those. Both the SQL and the client patch derive the mapping from the same
  `selected_items()`, so they cannot disagree.

  **Delete the client's item cache after regenerating the items.** WoW writes
  every item the server ever sent it to `Cache/WDB/<locale>/itemcache.wdb` and
  never asks again, so a character who already saw an item keeps its old
  appearance no matter what the server now says - which looks exactly like a
  broken patch. Removing that file (the client rebuilds it on next login) is part
  of the workflow, not troubleshooting.

  **One find per item, per character.** A character may claim each distinct
  Worldforged item once, tracked in `character_worldforged_ascension_loot`. That
  table is keyed by *item*, not by spot, because the 1509 items are spread over
  3599 places - claiming a Silverbound Dagger at one of them finishes every other
  spot holding one, instead of letting you farm duplicates a few hills apart.
  A cache is never consumed and never removed: it stands where it stands, for
  everyone, and claiming its item only records that this character has had it.
  Clicking one you have finished says so rather than handing out a second copy.
  What empties out as a collection fills is the *map*, not the world - see
  `addon/WorldforgedAtlas` below.

  **Two things about the placement**, both found by walking to a spot in-game.
  LootCollector records one find *per player*, so a single Ascension chest
  arrives as several entries a few yards apart - three "Claw of Vagash"
  recordings within ten yards are one chest seen by three people. Entries of the
  same item within 40 yards are merged, which takes 3608 raw locations down to
  1633 real ones. And the ground search does **not** start from MAX_HEIGHT, the
  obvious choice: several finds are inside caves, and the first surface below the
  sky is the mountain sitting on top of one - which put three chests on a Dun
  Morogh mountainside instead of in the cave below it. It starts just above the
  player who pulled the cache in instead; they are within 300 yards and, if the
  find is in a cave, they are in it too. Ascension's data cannot settle this on
  its own: LootCollector stores map percentages and zone ids, never a height, and
  the client's gameobject cache holds names and models but no positions.

  **Streamed, not spawned.** 3608 permanent objects would mean 3608 map grids
  resident for the rest of the uptime, since this core never unloads one. So a
  scan spawns the caches near a real player and drops them again once nobody is
  close. You cannot tell the difference - a cache is always there when you get
  there - but only a handful exist at a time, in grids a player is standing in
  anyway. It also solves ground height for free: the spawn table carries no Z,
  and `Map::GetHeight()` answers exactly once the grid is loaded. Only real
  players stream caches in and only real players can open one, for the same
  reason as everywhere else in this module.

  **The effects come across too.** `build_ascension_spells.py` imports the 896
  spells behind them - the 594 named on items, plus the 307 those cast in turn,
  because "Fiery Attack" does its damage through a second spell and importing
  only the first leaves the proc firing into nothing. They come from Ascension's
  own Spell.dbc (in `patch-T.MPQ`, not a locale archive): 209 MB and 209294
  spells against this client's 49 MB and 49840, but the layout is untouched, so a
  spell carries over as a straight row copy. They go into **`spell_dbc`** rather
  than a patched server-side file, because DBCStores overlays that table on the
  file and grows its index table past the file's maximum - so a row there is all
  the server needs to know a new spell.

  **PvE and PvP Power do something now.** Both are stats Ascension invented, and
  the spells carrying them are `SPELL_EFFECT_DUMMY` - a placeholder that does
  nothing at all without server code behind it, which meant 1926 of the items
  promised something in their tooltip and delivered nothing. Each is rewritten
  into the nearest real WotLK aura, description included so the tooltip stops
  lying. PvP Power becomes resilience, which is the same idea under another name
  and carries over one for one. PvE Power has no equivalent at all, so it becomes
  a flat damage bonus - and its scale (`PVE_POWER_PER_PERCENT`) is the one number
  in this whole import that is invented rather than Ascension's. At 24 the +48
  items give 2% and the +96 ones 4%, keeping their relative worth intact.

  Effect ids above 164 and aura ids above 316 are zeroed on the way in, and not
  for tidiness: `AuraEffect::HandleEffect` indexes a fixed
  `AuraEffectHandler[TOTAL_AURAS]` array with the aura id and bounds-checks
  nothing (`SpellAuraEffects.cpp:793`), so one of Ascension's 354s would call
  past the end of it. That costs 22 spells their custom behaviour; the other 559
  use nothing but stock WotLK effects and auras and work here as they did there.

  **`tools/worldforged/build_client_patch.py`** supplies everything client-side.
  Neither item templates nor spell behaviour need a client patch - the client
  asks the server for the first and the server performs the second - but the
  *look and the tooltip text* are client-side:
  - **ItemDisplayInfo**: 914 of the 1415 displays already exist here; it adds the
    other 501. 66 of those name a 3D model this client lacks, affecting 116 of
    2625 items; they keep their correct Ascension icon and borrow the model of a
    WotLK item of the same class and slot, so nothing renders broken.
  - **Spell.dbc**: +896 rows, or an item's effect line would be blank even though
    the effect fires. Built from the same `select_spells()` the SQL import uses,
    clamped identically - a tooltip must not describe behaviour the server does
    not perform.
  - **SpellIcon.dbc**: +198 rows, plus the `.blp` icon files that WotLK never
    shipped.
  - **DisenchantID**: not client-side at all, but the same class of omission -
    it was missing from the item INSERT, and an item with 0 there cannot be
    disenchanted. The id is not derivable from the item; WotLK assigns it per
    class, quality and item level band, weapons on one series and armour on
    another. Each import takes the id of the closest real WotLK item of the same
    shape, so a level 12 one-handed axe gets 21 - what "Stonesplinter Axe" has.
  - **Item.dbc**: a row per imported item. Easy to miss, because leaving it out
    fails in a way that looks like something else entirely: the item shows its
    correct 3D model and a question mark for an icon. The model comes from the
    displayid the *server* sends with the item, but the inventory icon is looked
    up through Item.dbc, and an item the client has no row for there falls back
    to the question mark however good its ItemDisplayInfo row is. Its field order
    is `ID, Class, Subclass, SoundOverrideSubclass, Material, DisplayInfoID,
    InventoryType, SheatheType` - verified against this client's own row for item
    25, "Worn Shortsword": `(25, 2, 7, -1, 1, 1542, 21, 3)`.

  It writes `patch-y.mpq` and `patch-enus-z.mpq` - letters checked against this
  client rather than assumed free, since `patch-w` is already taken there by 27 MB
  of other content. Its DBCs are built on top of whatever the client reads today,
  so `clientpatch`'s own rows survive (its XP Boost spell is still there
  afterwards, which is the check worth repeating) - and that also means **run it
  after `clientpatch/build_patches.py`, never before**.

  **`addon/WorldforgedAtlas` + `tools/worldforged/build_atlas_addon.py`**: the
  map. Ascension had the `LootCollector` addon for exactly this, and without
  something like it the only way to find a cache is to walk over it - nothing is
  announced and nothing sparkles from a distance. The addon draws a pin for every
  find location on the world map, the continent map and the minimap, wearing the
  icon of the item lying there inside a quality-coloured ring. It works alongside
  Mapster without knowing about it: pins are children of `WorldMapDetailFrame`,
  so Mapster's rescaling carries them along.

  - **The pins come from the server's own table**, not from LootCollector again.
    `build_atlas_addon.py` reads `mod_madosa_worldforged_ascension_spawns` and
    `item_template` out of the live world database and inverts
    `build_ascension_spawns.py`'s `zone_to_map()` back to the zone fractions the
    map wants. The conversion is linear, so the inverse is exact - checked, not
    assumed: all 1633 points round-trip to 0.000000 yards, and a point that would
    not land inside its own zone's box is dropped rather than pinned to the wrong
    hill. 1628 of 1633 survive; the other five name an item that is not in
    `item_template`. Regenerating from the raw discoveries instead would put pins
    where no cache stands, which is worse than no pin at all.
  - **Claimed finds come over the wire.** Which items this character has already
    had lives in `character_worldforged_ascension_loot`, and it is the difference
    between a map of the world and a map of what is *left*. The addon asks for
    the list on login over the same self-whisper + `LANG_ADDON` transport
    MadosaControl uses, on its own `WFATLAS` prefix and deliberately **without**
    that bridge's RBAC gate - the bridge writes server settings and is rightly
    GM-only, this hands a player their own collection. A claim made in play is
    pushed as it happens, so the pin disappears as the item goes in the bag. The
    list is cached per character, so the map is already right on the next login
    before the sync arrives.
  - **Placement is Astrolabe's**, which is already installed here. It translates
    a zone fraction onto whatever map is open and keeps minimap pins positioned
    as the player moves. Two things worth knowing: its `RemoveAllMinimapIcons()`
    drops every icon the *library* is tracking - Questie's included - so pins are
    only ever handed back one at a time through `RemoveIconFromMinimap()`. And on
    a continent map, only that continent's zones are walked: Astrolabe would
    reject the rest anyway, but not before each had taken a frame and a slot off
    the pin cap, and since the zone list is alphabetical the two continents
    interleave, so the cap would have eaten into the pins being looked at.
  - **A zone map and a continent map want different markers.** On a zone map
    every find gets its own pin, bucketed into a grid one pin wide so two spots
    a few yards apart become one marker with a count rather than two icons drawn
    on top of each other. A continent gets **one marker per zone**, at the middle
    of that zone's finds - drawing them individually there was what made the
    first version unusable (753 icons stacked over Kalimdor), and grid clustering
    does not save it, because the points are genuinely spread out. It is also the
    question actually being asked at that zoom: not "where exactly" but "which
    zone is worth going to". Continent markers are off by default.
  - **Counted in distinct items, not in spots.** Claiming is per item, so
    several places in a zone holding the same one are one thing to collect;
    a marker that would list it twice lists it once, and "N of M left here"
    means how many things there are still to take.
  - **Pins are children of `WorldMapButton`, not `WorldMapDetailFrame`.** The
    latter is the obvious parent and holds the map art, but `WorldMapButton`
    covers the whole map on top of it and takes every mouse event - pins under
    the detail frame draw perfectly and never show a tooltip, which looks like a
    broken tooltip and is not. Blizzard's own POIs parent to `WorldMapButton` for
    the same reason. The *anchor* stays the detail frame, whose size the
    fractions are relative to.
  - Options live in a right-click menu on one small button in the map's header
    bar next to Zoom Out - a panel floating over the map hides the part of the
    map it sits on, which for a map addon is a poor trade. Right-clicking any
    pin opens the same menu. `/wfa` toggles the pins, `/wfa sync` re-asks the
    server.

- **`hardcore_pvp.sql` + `src/mod_madosa_hardcore_pvp.cpp` +
  `src/mod_madosa_hardcore_pvp_loot.cpp`**: **Hardcore PvP**, after Ascension
  WoW's mode of the same name. Opt in and you earn 10% more experience, ordinary
  world mobs start dropping dungeon and raid gear, and being killed by another
  Hardcore player leaves a chest holding part of what your bags held. Switched
  on and off at a **Hardcore Herald** - one in every capital and every neutral
  town - or with `.hardcore on|off`, in any inn or city, out of combat, on a
  30-minute cooldown so it cannot be dropped the moment it stops being
  convenient.

  **The chest needs both sides.** It only ever drops when killer *and* victim
  are in Hardcore PvP - never off a bystander, never onto one. That is why each
  mode wears a visible aura: the mark is not decoration, it is how a killer can
  tell beforehand whether a target is carrying anything, and how a Hardcore
  player knows they are fair game. Everything in the bags can drop, soulbound
  included; worn equipment, quest items, the bags themselves, keys, the
  Hearthstone, conjured items and heirlooms never do. The killer, their
  group and the victim may open the chest at once - the victim's own things are
  theirs to race for - and anyone else only if they are in High-Risk
  themselves. It is gone after five minutes. The chest sparkles - the same
  glitter a quest object has - for exactly the people who may open it, and
  for nobody else. That is the one core change this feature carries:
  `GameObjectScript::OnActivateToQuest` (`src/server/game/Scripting/`), a
  hook that lets a gameobject's script answer the "show this as activatable"
  question the core otherwise asks the quest log.

  **Nothing is lost to a chest nobody opened.** Every dropped stack - and the
  gold of an insurance chest - is written to `character_hardcore_pvp_chest`
  *before* it leaves the victim's bags, removed again as it is looted, and
  whatever is left when the chest crumbles is mailed back to the victim. If
  the map refuses the chest, the same rows are mailed back on the spot.
  Leftover rows are mailed back at the next startup, which covers a crash as
  well as a clean restart. Bots are the one exception: their belongings are
  never recorded, because mod-playerbots re-rolls them anyway and a mailbox no
  bot ever opens would only grow.

  This was found the hard way and is worth stating plainly: the first version
  kept a chest's contents in memory only and gave the killer two minutes of
  exclusivity. On a realm where the killer is almost always a bot that walks
  away without looting, the outcome was that the victim's belongings were
  destroyed, the victim was locked out of them, and then they ceased to exist
  when the chest expired. The victim lost and nobody won - the worst outcome the
  design allowed, and it happened on the first real death.

  **Who may open it**: the killer, the killer's group and the victim, all at
  once - your own things are yours to race for. Everyone else must be in
  High-Risk themselves, because a chest is what High-Risk players stake against
  each other and someone risking nothing does not get to collect from it.

  **The chest is a chest with no loot table.** `Player::SendLoot()` only calls
  `loot->clear()` and `FillLoot()` inside `if (lootid)` (`Player.cpp:8029`), so
  a `gameobject_template` without one keeps whatever the server put in it by
  hand - which is how the victim's own belongings, with their own random
  properties, arrive in an ordinary loot window. Enchantments cannot be
  expressed as loot at all, so they are recorded when the item is taken and put
  back in `OnPlayerLootItem`, which hands us the freshly created `Item`.
  Durability and charges are not preserved; loot has no way to say them.

  **Three risk modes, Ascension's own three.** A character is in exactly one,
  chosen at the Herald or with `.hardcore pve|war|high`:

  | Mode | Ascension | Flagged | Bonus XP | World dungeon drops | Bags at stake |
  |---|---|---|---|---|---|
  | PvE | `PvE Mode` (84422) | no | - | no | no |
  | War Mode | `War Mode` (84420) | permanently | yes, the smaller rate | no | no |
  | High-Risk | `High-Risk (PvP)` (84421) | permanently | yes, the larger rate | yes | yes |

  PvE is not merely "not opted in", it carries Ascension's own rule: *"You
  cannot heal or buff players in War Mode or High-Risk while in the open
  world."* Without it a PvE character is a pocket healer who can never be
  punished for it - all of the support, none of the exposure. This core has no
  hook that can refuse a helpful cast before it happens, and patching
  `Unit::_IsValidAssistTarget` would mean core code to re-merge forever - the
  same trade refused for the traitor rule - so the cast goes off and then does
  nothing: the heal is zeroed (`UnitScript::ModifyHealReceived`) and the buff is
  expired on its next tick (`OnAuraApply` + `SetDuration(0)`). The caster still
  pays the mana and the global cooldown, which is the feedback. One acknowledged
  gap: an aura with no duration cannot be expired that way, though every class
  buff in 3.3.5a has one.

  Watch the parameter names on that heal hook. `Unit.cpp:8409` calls it as
  `ModifyHealReceived(this, healInfo.GetTarget(), ...)` from
  `Unit::HealBySpell`, which callers invoke as `caster->HealBySpell(...)` - so
  the argument the hook *declares* as "target" is the healer. Taking the names
  at face value points the rule the wrong way round.

  Treason needs War Mode or High-Risk: it opens same-faction fighting, and a
  PvE character cannot fight at all. Dropping back to PvE renounces it in the
  same breath.

  **The realm is PvE; the mode is how you opt out of that.** `GameType = 0`,
  so nobody is flagged against their will and PvP is something a player asks
  for - the same shape as Ascension, which is PvE by default with War Mode and
  High-Risk as opt-ins. A hardcore character is permanently flagged and can be
  fought by anyone else who is flagged, however they got that way (`/pvp`
  included); the chest is the part reserved for two hardcore players.

  That permanence needs `PLAYER_FLAGS_IN_PVP`, not just `UpdatePvP(true, true)`.
  `Player::UpdatePvPState()` starts the five-minute unflag timer for any flagged
  player in friendly territory that lacks it (`PlayerUpdates.cpp:1459`) - it is
  what the `/pvp` toggle sets to mean "leave me flagged". Without it a hardcore
  character quietly stops being attackable a few minutes after walking into
  their own capital, keeping every cost of the mode and none of its risk. On a
  PvP realm that is easy to miss, because contested territory keeps re-flagging
  them; on a PvE realm it would be true everywhere.

  **Treason is a second, separate switch.** "Traitor to the Alliance" / "Traitor
  to the Horde" is what enables same-faction PvP; Hardcore on its own never
  does. It is the core's own FFA flag, what Gurubashi Arena uses:
  `Unit::GetReactionTo()` returns `REP_HOSTILE` when **both** sides carry it
  (`Unit.cpp:7174`), so traitors are hostile to each other and to nobody else -
  a loyal player still cannot swing at one. That symmetry is deliberate, and it
  is also why no core file is touched: making it one-sided would mean patching
  `Unit::_IsValidAttackTarget()`, since this core has no attack-target hook.

  Two things about that flag are worth knowing, because both look like bugs:
  - **The core clears it on every area change.** `UpdateFFAPvPState()`
    (`PlayerUpdates.cpp:1465`) removes it from anyone not standing in an
    `AREA_FLAG_ARENA` area, and `UpdateArea()` calls that *after* the
    `OnPlayerUpdateArea` hook, so a script cannot get its answer in first.
    Rather than fight it, a traitor is marked as being in an FFA area
    (`pvpInfo.IsInFFAPvPArea`) and that is re-asserted from the world tick,
    letting the core's own code set the flag. Sanctuaries keep their protection
    for free, because `UpdateFFAPvPState()` checks `IsInNoPvPArea` first.
  - **Treason costs you the city, not just its guards.** The price is
    `ReputationMgr::ApplyForceReaction(cityFaction, REP_HOSTILE, true)` - the
    core's own temporary-reaction mechanism, read back in the very same
    `GetReactionTo()` path (`Unit.cpp:7147`), leaving real reputation values
    untouched so switching off restores the character exactly. But a
    forced-hostile city faction is the whole faction: its vendors, flight
    masters and quest givers refuse you too. Which is why the Herald is
    faction-neutral (faction 35) and also stands in Booty Bay, Gadgetzan,
    Everlook, Ratchet, Shattrath and Dalaran - the NPC that takes the flag back
    off must not be behind the guards that flag just turned on you.

  **You can see which tier you are pulling from.** While the mode is on the
  player wears a second aura naming their current level band and the dungeons
  it covers - "Dungeon Spoils: Levels 40-49 ... Zul'Farrak, Maraudon and the
  Sunken Temple" - and it moves on as they level. The band is not a label
  painted over the drop logic: `LOOT_BANDS` in
  `mod_madosa_hardcore_pvp_loot.cpp` *is* the selection rule (items whose
  required level falls in the band, capped at what the player can equip today),
  and `tools/clientpatch/build_patches.py` builds spells 900010-900017 from the
  same boundaries. A tooltip here cannot drift away from what the roll does.
  Crossing into a new band narrows the pool to its first level for a while -
  that is the band change being felt, and even the thinnest band opens with
  around 64 items in this database.

  **Two more things carried over from Ascension's High-Risk**, both read out of
  its own client rather than guessed at:

  - **Gear insurance.** 84421 promises *"you drop equipped gear, **or Fel Com
    gold if your gear is insured**"*. Here a High-Risk character buys cover at
    the Herald (or with `.hardcore insure`) for
    `Madosa.HardcorePvP.InsuranceCostGold`; the next High-Risk player to kill
    them finds that gold in the chest instead of their bags, and the cover is
    spent. Nothing is minted: the payout is the premium the victim already
    handed over, changing hands. Dropping out of High-Risk drops the cover
    rather than banking it, or it could be bought cheaply now and cashed in
    much later.
  - **Bounty.** Ascension's perk (83284-83286), *"You have a X% chance to double
    a creature's gold."* Both flagged modes get it, hooked on
    `OnPlayerBeforeLootMoney` and limited to creature purses -
    `loot.sourceWorldObjectGUID` is a creature guid for a corpse
    (`Creature.cpp:331`), so a chest or a fishing pool cannot pay a bounty. It
    is the one reward War Mode has of its own, standing in for the extra
    crafting materials Ascension gives it that this realm has no equivalent for.

  **The world drops are not a hand-picked list.** At startup
  `creature_loot_template` (and the reference table it points at) is joined
  against where those creatures are actually spawned and checked against
  Map.dbc through `sMapStore` - the same instance-resolution
  `mod_madosa_instance_quest_pet.cpp` does for quests - so the pool is every
  weapon and armour piece that drops inside a dungeon or raid, bucketed by
  required level. Add a dungeon to the database and its loot is in the pool
  after the next restart. The item is then chosen for the **looter's** level,
  not the mob's, exactly like Worldforged: a level 24 character gets level 24
  dungeon gear off a boar, and a find is always something they can equip. The
  hook is `OnPlayerBeforeSendLoot` (`Player.cpp:8369`), the one place that runs
  after the creature's own loot has been rolled and before the packet is built.

  **Grey mobs are a setting, and the default is to allow them.** This started
  out gated on `Player::isHonorOrXPTarget()`, which reads well - "a grey mob is
  not a world worth finding things in" - and is far sharper than it sounds:
  `GetGrayLevel(80)` is 71, so for a max-level character *every mob up to level
  71* is worthless, which is most of the world outside Northrend. The drop
  simply never happened, at any percentage. `hardcorepvp.dungeondrop.greymobs`
  now decides it. The cost of leaving it on is real and worth stating: since the
  reward is picked for the looter's level, mass-killing trivial mobs farms
  current-tier gear, and the drop chance is the only throttle. Critters, totems,
  pets and no-experience creatures never drop either way - those are scenery.

  **Playerbots take part, deliberately and partially.**
  `Madosa.HardcorePvP.BotParticipation` percent of them (10 by default, so ~300
  of this realm's ~3000) run the mode, keyed off the bot's guid so a given bot
  is consistently in or out rather than re-rolling every login. They wear the
  same mark and drop from their bags like anyone else - without that, a realm
  this thinly populated by real players would have nothing to hunt. Bots are
  never traitors: treason changes who may attack whom, and 3000 bots deciding
  that among themselves is a different realm from the one this is for.

  **The marks are three new spells** (900002-900004), built by
  `tools/clientpatch/build_patches.py` like the XP Boost aura, reusing icons
  this client already has - `Spell_Shadow_Skull` and the two PvP banners. They
  carry `NO_AURA_CANCEL`, because a player being able to right-click their own
  status off would break the one rule the chest depends on. Until that patch is
  rebuilt the mode works exactly as it does after; only the buff icon is
  missing.

  **What Ascension actually calls this**, since the point was to reproduce it:
  its client's own Spell.dbc has **`High-Risk (PvP)` (84421)** - *"Any death
  while in the open world with High-Risk Mode active will cause you to drop
  equipped gear ... and items from your bag ... grants 15% increased experience
  ... Can only be cast while in a rested area!"* - and the milder
  **`War Mode (PvP)` (84420)**, open-world PvP and +10% experience with no gear
  at stake. Ascension is PvE by default and you opt into one of the two. So this
  module's Hardcore PvP is Ascension's High-Risk, the Traitor switch is the FFA
  half of it, and the inn-or-city rule turns out to be Ascension's own wording.
  War Mode has no counterpart here yet.

  Two things looked for and *not* found in that client, so nobody hunts for them
  again: there is no player-side aura naming a dungeon tier (the level bands
  above are this module's own answer to the same idea), and Ascension's
  open-world tier system is instead expressed on the *mob* - auras like
  `Blood Bringer` (969036), *"This creature has a chance to drop Heroic Karazhan
  Bloodforged Gear. Requires 111 item level"* - gated on item level rather than
  character level.

  GM command: `.madosa hardcore`. Player commands: `.hardcore`,
  `.hardcore pve|war|high` (`on`/`off` kept as the names players already learned,
  meaning the two ends of the ladder), `.hardcore insure`,
  `.hardcore traitor on|off` (permission
  1002, granted to the player role by
  `data/sql/db-auth/base/hardcore_pvp_rbac.sql`).

- **`tools/launcher/`**: a launcher, so the client patch can reach someone
  else's machine. `serve_patches.py` publishes a folder of patches over HTTP with
  a generated `manifest.json` (a path, size and SHA-256 per file);
  `madosa_launcher.py` is the single file a player gets - it asks once for their
  WoW folder, then on every start compares their patches against the manifest,
  downloads only what differs, writes the realmlist and starts the game.

  There is no alternative to a launcher here: 3.3.5a has no patch download of its
  own and the game protocol cannot carry files, which is why Ascension ships one
  too. Two details it has to get right:
  - **Folder spelling.** A WoW folder copied between Windows, Wine and Linux ends
    up with any mixture of `Data`/`data` and `enUS`/`enus`, and on a
    case-sensitive filesystem writing the wrong one creates a second directory
    the client never reads. Manifest paths are resolved against the directories
    that actually exist, one component at a time.
  - **No half-written archives.** Downloads land in a `.part` file and are only
    renamed once the hash matches, or an interrupted download would look complete
    on the next start and break the client.

  `build_exe.sh` turns it into `MadosaLauncher.exe`, so a player needs nothing
  installed at all. PyInstaller cannot cross-compile - a Windows executable has
  to be built by a Windows Python - so the script puts one in its own Wine prefix
  under `~/.cache/madosa-launcher-build` and builds there. Deliberately not
  `~/.wine`: a build tool has no business installing into the prefix the games
  use, and deleting that one directory undoes everything the script did.

  It is standard library only, and the window is optional: tkinter ships with
  Python on Windows but is a separate package on many Linux distributions, so
  without it the launcher runs the same routine on the terminal rather than
  refusing to start.

## Live-tunable settings (`MadosaSettings`)

Every knob a GM might want to tweak while the server is running is **not**
read straight from the config file:

| Runtime key | Config key | Type |
|---|---|---|
| `professionxp.enable` | `Madosa.ProfessionXP.Enable` | on/off |
| `professionxp.percent` | `Madosa.ProfessionXP.PercentOfLevelXP` | number, 0-100 |
| `professionxp.skillmultiplier` | `Madosa.ProfessionXP.SkillGainMultiplier` | number, 1-100 |
| `autolootpet.enable` | `Madosa.AutoLootPet.Enable` | on/off |
| `professiontools.enable` | `Madosa.ProfessionTools.Enable` | on/off |
| `accountcompanions.enable` | `Madosa.AccountCompanions.Enable` | on/off |
| `instancequestpet.enable` | `Madosa.InstanceQuestPet.Enable` | on/off |
| `professionslots.enable` | `Madosa.ProfessionSlots.Enable` | on/off |
| `professionslots.max` | `Madosa.ProfessionSlots.Max` | number, 1-20 |
| `passerbybuff.enable` | `Madosa.PasserbyBuff.Enable` | on/off |
| `passerbybuff.radius` | `Madosa.PasserbyBuff.Radius` | number, 5-60 |
| `passerbybuff.priest.fortitude.enable` | `Madosa.PasserbyBuff.Priest.Fortitude.Enable` | on/off |
| `passerbybuff.priest.spirit.enable` | `Madosa.PasserbyBuff.Priest.Spirit.Enable` | on/off |
| `passerbybuff.mage.intellect.enable` | `Madosa.PasserbyBuff.Mage.Intellect.Enable` | on/off |
| `passerbybuff.druid.markofthewild.enable` | `Madosa.PasserbyBuff.Druid.MarkOfTheWild.Enable` | on/off |
| `passerbybuff.paladin.kings.enable` | `Madosa.PasserbyBuff.Paladin.Kings.Enable` | on/off |
| `passerbybuff.paladin.wisdom.enable` | `Madosa.PasserbyBuff.Paladin.Wisdom.Enable` | on/off |
| `worldforged.enable` | `Madosa.Worldforged.Enable` | on/off |
| `worldforged.announce` | `Madosa.Worldforged.Announce` | on/off |
| `worldforged.interval` | `Madosa.Worldforged.IntervalMinutes` | number, 1-1440 |
| `worldforged.lifetime` | `Madosa.Worldforged.LifetimeMinutes` | number, 1-1440 |
| `worldforged.maxactive` | `Madosa.Worldforged.MaxActive` | number, 1-10 |
| `worldforged.rarechance` | `Madosa.Worldforged.RareChance` | number, 0-100 |
| `worldforged.goldperlevel` | `Madosa.Worldforged.GoldPerLevel` | number, 0-100000 |
| `worldforged.ascension.enable` | `Madosa.Worldforged.Ascension.Enable` | on/off |
| `passerbybuff.paladin.might.enable` | `Madosa.PasserbyBuff.Paladin.Might.Enable` | on/off |
| `hardcorepvp.enable` | `Madosa.HardcorePvP.Enable` | on/off |
| `hardcorepvp.xppercent` | `Madosa.HardcorePvP.XPPercent` | number, 0-100 |
| `hardcorepvp.warmode.enable` | `Madosa.HardcorePvP.WarModeEnable` | on/off |
| `hardcorepvp.warmode.xppercent` | `Madosa.HardcorePvP.WarModeXPPercent` | number, 0-100 |
| `hardcorepvp.insurance.enable` | `Madosa.HardcorePvP.InsuranceEnable` | on/off |
| `hardcorepvp.insurance.cost` | `Madosa.HardcorePvP.InsuranceCostGold` | number, 1-100000 |
| `hardcorepvp.bountychance` | `Madosa.HardcorePvP.BountyChance` | number, 0-100 |
| `hardcorepvp.minlevel` | `Madosa.HardcorePvP.MinLevel` | number, 1-80 |
| `hardcorepvp.togglecooldown` | `Madosa.HardcorePvP.ToggleCooldownMinutes` | number, 0-1440 |
| `hardcorepvp.traitor.enable` | `Madosa.HardcorePvP.TraitorEnable` | on/off |
| `hardcorepvp.traitor.guardshostile` | `Madosa.HardcorePvP.TraitorGuardsHostile` | on/off |
| `hardcorepvp.droppercent` | `Madosa.HardcorePvP.DropPercent` | number, 0-100 |
| `hardcorepvp.dropmaxitems` | `Madosa.HardcorePvP.DropMaxItems` | number, 1-18 |
| `hardcorepvp.chestlifetime` | `Madosa.HardcorePvP.ChestLifetimeMinutes` | number, 1-60 |
| `hardcorepvp.repeatkillcooldown` | `Madosa.HardcorePvP.RepeatKillCooldownMinutes` | number, 0-1440 |
| `hardcorepvp.dungeondropchance` | `Madosa.HardcorePvP.DungeonDropChance` | number, 0-100 |
| `hardcorepvp.dungeondrop.greymobs` | `Madosa.HardcorePvP.DungeonDropGreyMobs` | on/off |
| `hardcorepvp.botparticipation` | `Madosa.HardcorePvP.BotParticipation` | number, 0-100 |

`Madosa.Addon.Enable` is deliberately absent: it gates the bridge MadosaControl
talks through, so exposing it there would let the panel lock itself out. Change
it in the conf file and restart, or use the `.madosa` chat commands.

These all go through `MadosaSettings`. They go through `MadosaSettings` (`src/mod_madosa_settings.h`), a small
runtime store that is:

- seeded from `mod_madosa.conf.dist` on startup (`WorldScript::OnStartup`),
- changeable at any time, with no server restart, via:
  - the `.madosa status` / `.madosa set <key> <value>` / `.madosa reset <key>`
    GM chat commands (`src/mod_madosa_command.cpp`), or
  - the **MadosaControl** client addon (`addon/MadosaControl`) over a small
    addon-message bridge (`src/mod_madosa_addon_bridge.cpp`),
- persisted in the `mod_madosa_settings` world DB table, so changes survive a
  restart too - `.madosa reset <key>` clears the DB override and reverts to
  the conf file value.

Both the chat command and the addon require the `Command: madosa` RBAC
permission (id 1001, granted to the "Gamemaster Commands" role by
`data/sql/db-auth/base/madosa_settings_rbac.sql`).

When adding a new tunable, wire it into `MadosaSettings` instead of reading
`sConfigMgr` directly from the feature script, so it picks up the same
live-control path automatically. **Every setting is one line in one of three
tables** in `src/mod_madosa_settings.cpp` - `boolSettings`, `uintSettings` or
`floatSettings` - giving its config key, storage slot, default and (for the
numeric ones) the interval it may be set to. Startup seeding, DB overrides,
`Set`, `Reset` and `List` all follow from that line; there is no per-setting
code left anywhere.

A second line in `settingTexts` gives it a panel, a label and a sentence of
explanation. That is what MadosaControl draws - so a new setting appears in
the addon, in the right group, with the right widget and the right slider
bounds, **with no client change at all**. Leave it out and the setting still
works; it just turns up under "Other", labelled with its own key.

**Name on/off keys `<feature>.enable`.** The list is sorted so a feature's
settings arrive together with its master switch first, and that suffix is how
the switch is recognised.

### MadosaControl addon

`addon/MadosaControl` is a small, standalone WotLK 3.3.5a addon (`/madosa` or
`/mc` to toggle): categories down the left, the settings of the selected one on
the right, Apply/Revert/Refresh along the bottom. Checkboxes for the toggles,
a slider with an editable number for everything else.

**It knows nothing about any individual setting.** Protocol 2 of the bridge
sends each one fully described - widget type, bounds, group, label and help
text - so the panel builds its category list and its rows out of whatever
arrives. A setting added on the server shows up here correctly grouped,
correctly bounded and correctly labelled without this addon being touched;
one the server has never heard of cannot show up at all. The labels and the
help text live in `settingTexts` in `src/mod_madosa_settings.cpp`, next to the
settings they describe, rather than in a second list in Lua that could drift
out of step with the first.

The look is ElvUI's, without ElvUI: flat near-black panels, a hard one-pixel
border with a one-pixel shadow frame behind it, one accent colour for anything
carrying a value and greyscale for everything else. `Widgets.lua` is that whole
idea - a `Panel` primitive plus the handful of controls built out of it -
and `Core.lua` is the comms and the layout. No libraries and no media files:
the only texture used is `WHITE8X8`, which the client already ships, so the
addon stays three Lua files and a `.toc`. Changed-but-unapplied rows are marked
in the accent colour and counted on the Apply button; Revert throws them away,
and each row's "Default" button drops the DB override and returns that one
setting to the conf file value.

**The minimap button** (`Minimap.lua`) is hand-rolled rather than LibDBIcon.
Four addons on this client ship that library and any of them would hand it over
through LibStub - but only while that addon is enabled, and a button that
disappears because someone turned off Questie is a worse bug than the sixty
lines it takes to draw one. It follows the same rule as the rest of the addon:
no libraries, no media. So no artwork either - Blizzard's round
`MiniMap-TrackingBorder` would be the only thing here that is not flat, and the
button is a `MadosaUI.Panel` with an **M** in it instead, which is both the
addon's own look and what every minimap button ends up as once ElvUI has skinned
it. The M turns the accent colour while the panel is open.

It is a `MadosaUI.Button`, and that part is load-bearing. The first version was
a `MadosaUI.Panel` - a `Frame` - which draws identically and cannot be clicked
in practice: a Frame with `EnableMouse` does receive `OnMouseUp`, but with
`RegisterForDrag` on it the couple of pixels a hand moves during a press is
enough for the client to call it a drag, and telling a drag from a click by hand
needs a timing guard that then eats real clicks. A Button has the distinction
built in - the client does not fire `OnClick` when a drag happened - which is
why every minimap button is one.

**The ring is measured, and it follows the minimap's shape.** The usual constant
for this is 80, which is the ring of a stock 140px minimap - and this install's
is 220px, because ElvUI is configured that way. 80px from the centre of a 220px
minimap is *inside* the map, sitting on the minimap's own surface, where the
button draws perfectly and never sees a mouse event: the icon is there and
nothing happens when you click it, tooltip included.

The size comes from `Minimap:GetWidth()`, and the shape from the global
`GetMinimapShape()` - the convention an addon that reshapes the minimap
announces itself through, which is how a button follows a square edge while
knowing nothing about the addon that made it square. ElvUI returns `SQUARE` or
`ROUND` from its own setting (`ElvUI/Core/Modules/Maps/Minimap.lua:576`), and
the fourteen corner and side shapes other addons declare cost one table.

On a round quadrant the angle goes straight out onto the ellipse. On a square
one the point is pushed out along its own direction until it is past the corner
and then clamped back into the box - the clamp is what makes the button slide
along a flat side instead of cutting across it, and it is why an angle is still
the right thing to store for a minimap that is not round. The corners come out
pulled in by the ring margin, deliberately: a button at the corner of a square
would otherwise stand 170px off the centre where the flanks put it at 120.
LibDBIcon does exactly this, which is why Questie's button behaves the same.

**None of that is stated once and trusted.** Setting a frame's strata takes its
children with it, and ElvUI configures the minimap at `PLAYER_LOGIN` - long
after this addon builds its button at `ADDON_LOADED`. Whatever the button was
put above at build time, ElvUI's `Minimap:SetFrameStrata('LOW')` afterwards puts
it back underneath, which is how it kept sliding under things. The size is the
same story: at `ADDON_LOADED` the minimap is still Blizzard's 140px, so a ring
measured then belongs to a map that no longer exists a second later.

So the strata (`HIGH`, level 100) and the position are re-stated whenever the
minimap's own layer or size moves - `hooksecurefunc` on its `SetFrameStrata`,
`SetFrameLevel`, `SetWidth` and `SetHeight` - with `PLAYER_ENTERING_WORLD` as a
backstop for anything that changed the minimap without going through those. A
profile switch or a resize mid-session is then handled by the same code. `HIGH`
rather than the `MEDIUM` a minimap button conventionally uses, because what it
was sliding under is on `MEDIUM`; not `DIALOG`, where menus and popups live and
a decoration has no business being.

`/madosa minimap debug` prints the size, the shape, the angle and where it
lands, plus `GetMouseFocus()` - the frame actually taking the mouse. On someone
else's UI that is worth more than any amount of reasoning about frame strata.

Its position is stored as an **angle on the minimap's ring**, not as a point:
dragging it is dragging it around the circle, and one number survives a UI scale
change that a saved x/y offset would not. Left-click opens the panel,
right-click hides the button, `/madosa minimap` brings it back.

It talks to the server the same way every other WotLK GM-addon bridge does: a
self-whisper (`SendAddonMessage(prefix, msg, "WHISPER", UnitName("player"))`)
tagged `LANG_ADDON`, intercepted server-side in
`PlayerScript::OnPlayerCanUseChat` before it would otherwise bounce back as a
normal whisper. It is intentionally independent from the third-party
`mod-homebrew-gm`/`HomebrewGM` addon already in this repo - separate prefix
(`MADOSA` vs `HGM`), separate protocol, no shared code.

To install: copy `addon/MadosaControl` into the client's
`Interface/AddOns/MadosaControl` folder (already done for the WotLK client at
`~/Games/world-of-warcraft-wrath-of-the-lich-king/...` in this dev setup).

**An update that adds a file needs the client restarted, not `/reload`.** The
client reads an addon's file list from its `.toc` when it starts; `/reload`
re-runs the files it already knows about. Copying in a version with a new file
therefore reloads the old ones and leaves the new one absent - which is how
`Minimap.lua` first arrived as an error in `Core.lua` rather than as a button.
Core.lua guards its calls into it for that reason, so a half-updated install
costs the button and not the panel.
