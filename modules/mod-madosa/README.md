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
