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
  spot holding one, instead of letting you farm duplicates a few hills apart. The
  streaming scan knows about it, so a cache you have finished simply stops
  appearing rather than standing there to refuse you, and the world visibly
  empties out as your collection fills up. The per-spot respawn timer stays
  A cache is never consumed - it stands where it stands for anyone who has not
  claimed its item, and simply stops appearing for whoever has.

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
| `worldforged.ascension.respawn` | `Madosa.Worldforged.Ascension.RespawnMinutes` | number, 1-10080 |
| `passerbybuff.paladin.might.enable` | `Madosa.PasserbyBuff.Paladin.Might.Enable` | on/off |

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
live-control path automatically. A plain on/off toggle is one line in the
`boolSettings` table in `src/mod_madosa_settings.cpp` - config key, storage
slot and default - and a whole number whose only rule is a range is one line in
the `uintSettings` table next to it, which adds the valid range and the wording
of the error a GM sees. Everything else (startup seeding, DB overrides, set,
reset, list) follows from either. Only a setting needing a check that is not a
plain interval still deserves hand-written handling in `Set()`.

**Name on/off keys `<feature>.enable`.** MadosaControl picks its control type
from that suffix, because guessing from the value would misread a numeric
setting that happens to sit at 0 or 1 - `professionxp.percent` defaults to
exactly `1`.

### MadosaControl addon

`addon/MadosaControl` is a small, standalone WotLK 3.3.5a addon (`/madosa` or
`/mc` to toggle) with checkboxes/edit boxes for each `MadosaSettings` value
and an Apply/Refresh button. It **builds its rows from whatever the server
sends**, so a setting added to `MadosaSettings` shows up without touching the
addon. The only local knowledge is a label lookup, and an unknown key falls
back to a label derived from the key itself. It talks to the server the same way every other
WotLK GM-addon bridge does: a self-whisper (`SendAddonMessage(prefix, msg,
"WHISPER", UnitName("player"))`) tagged `LANG_ADDON`, intercepted server-side
in `PlayerScript::OnPlayerCanUseChat` before it would otherwise bounce back as
a normal whisper. It is intentionally independent from the third-party
`mod-homebrew-gm`/`HomebrewGM` addon already in this repo - separate prefix
(`MADOSA` vs `HGM`), separate protocol, no shared code.

To install: copy `addon/MadosaControl` into the client's
`Interface/AddOns/MadosaControl` folder (already done for the WotLK client at
`~/Games/world-of-warcraft-wrath-of-the-lich-king/...` in this dev setup).
