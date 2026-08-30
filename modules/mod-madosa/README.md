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
slot and default - and everything else (startup seeding, DB overrides, set,
reset, list) follows from it.

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
