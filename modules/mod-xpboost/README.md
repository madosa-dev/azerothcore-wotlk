# mod-xpboost

Adds a `.xpboost set/remove/info` GM command that grants a persistent, per-character
percentage XP boost.

The boost is stored in the `character_xp_boost` table and applied via the
`OnPlayerGiveXP` hook, not a spell aura, so it survives death, logout and server
restarts. An optional cosmetic aura can be shown while a boost is active by setting
`XP_BOOST_VISUAL_SPELL_ID` in `src/cs_xpboost.cpp`.

## Commands

- `.xpboost set <pct> [player]` - grant `<pct>`% bonus XP (1-2000) to `[player]` or self/target.
- `.xpboost remove [player]` - remove the boost.
- `.xpboost info [player]` - show the current boost, if any.

Requires RBAC permission `Command: xpboost` (id 1000, linked to GM level by default).
