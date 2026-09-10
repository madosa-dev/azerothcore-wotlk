# craftbotgen

Generates `data/sql/db-world/base/profession_trainer_pet_recipes.sql`: every
recipe a profession can learn, as a row on Craftbot's trainer (90002).

Craftbot itself (`profession_trainer_pet.sql`) is a union of the profession
trainers' lists, so it only knows trainer recipes. Vendor, drop, reputation
and book recipes - including Expert/Artisan/Master First Aid, Cooking and
Fishing, which the game hands out via books and quests - only exist as
recipe items (`item_template.class = 9`). This script resolves what each of
those teaches (via `spelltrigger 6`, or the learn spell's
`EffectTriggerSpell` from `Spell.dbc`), checks it against
`SkillLineAbility.dbc`, and writes one free trainer row per spell with the
item's skill, rank and specialisation requirement.

Weapon skills are a plain SQL union and live next door in
`profession_trainer_pet_weapons.sql`.

## Run

```bash
./gen.py --password '<world db password>'
```

Needs `mysql` on PATH and the extracted DBCs (`--dbc`, default
`~/azerothcore/env/dist/data/dbc`). Prints per-skill counts and what was
skipped (class spellbooks, "Deprecated"/"[PH]" names, items that teach
nothing, spells not on their skill line, Alliance/Horde twins).

## Ordering caveat

`profession_trainer_pet.sql` opens with `DELETE FROM trainer_spell WHERE
TrainerId = 90002`. The generated file and the weapons file sort after it,
so a fresh database ends up right. But the updater only re-applies a file
whose hash changed: if `profession_trainer_pet.sql` is edited later, its
re-application wipes these rows and nothing puts them back until the two
add-on files change too. Re-run this script (or touch a comment in both
files) after any edit to the base file.
