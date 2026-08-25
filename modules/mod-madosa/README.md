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
