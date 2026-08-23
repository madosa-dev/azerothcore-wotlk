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

## Live-tunable settings (`MadosaSettings`)

The knobs a GM might want to tweak while the server is running - currently
profession XP (enable, `%` of level XP per attempt, skill-up multiplier) and
the Lootbot auto-loot pet toggle - are **not** read straight from the config
file. They go through `MadosaSettings` (`src/mod_madosa_settings.h`), a small
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

When adding a new tunable, wire it into `MadosaSettings` (get/set/reset/list)
instead of reading `sConfigMgr` directly from the feature script, so it picks
up the same live-control path automatically.

### MadosaControl addon

`addon/MadosaControl` is a small, standalone WotLK 3.3.5a addon (`/madosa` or
`/mc` to toggle) with checkboxes/edit boxes for each `MadosaSettings` value
and an Apply/Refresh button. It talks to the server the same way every other
WotLK GM-addon bridge does: a self-whisper (`SendAddonMessage(prefix, msg,
"WHISPER", UnitName("player"))`) tagged `LANG_ADDON`, intercepted server-side
in `PlayerScript::OnPlayerCanUseChat` before it would otherwise bounce back as
a normal whisper. It is intentionally independent from the third-party
`mod-homebrew-gm`/`HomebrewGM` addon already in this repo - separate prefix
(`MADOSA` vs `HGM`), separate protocol, no shared code.

To install: copy `addon/MadosaControl` into the client's
`Interface/AddOns/MadosaControl` folder (already done for the WotLK client at
`~/Games/world-of-warcraft-wrath-of-the-lich-king/...` in this dev setup).
