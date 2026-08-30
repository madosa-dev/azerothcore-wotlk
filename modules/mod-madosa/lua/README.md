# ALE (Lua) scripts

Server-side Lua for this realm, run by [`mod-ale`](../../mod-ale). Scripts live here,
under version control, and are reached by the server through a symlink (see
[Setup](#setup)) - never author them directly in `env/dist/bin/lua_scripts/`, where
nothing is tracked and `make install` is free to interfere.

## Why bother, when we already have C++ modules

A change here needs **no rebuild and no restart**: save the file and the running
worldserver picks it up. Compare that with a C++ tweak, which costs a multi-minute
`make` plus a `make install` plus a restart. So the rule of thumb is:

- **Lua** for content and rules that will be iterated on: NPCs, events, rewards,
  announcements, one-off queries, anything you expect to tune by feel.
- **C++** (mod-madosa) for things Lua cannot reach, anything on a hot path, and
  anything that must survive with the Lua engine disabled.

## ⚠ ALE is not Eluna

`mod-ale` is a **diverged fork** of Eluna with its own API. Scripts written for the
original Eluna project do not run here, and tutorials found online are frequently
wrong for this engine. Before using any function, check it actually exists:

```bash
# every global function, Player method, etc. the engine really exposes
grep -oE '\{ "[A-Za-z0-9]+", &LuaGlobalFunctions::' modules/mod-ale/src/LuaEngine/LuaFunctions.cpp
grep -oE '\{ "[A-Za-z0-9]+", &LuaPlayer::'          modules/mod-ale/src/LuaEngine/LuaFunctions.cpp

# event ids (PLAYER_EVENT_ON_LOGIN = 3, WORLD_EVENT_ON_STARTUP = 14, ...)
modules/mod-ale/src/LuaEngine/Hooks.h
```

## ⚠ This realm runs ~3000 playerbots

Every player-scoped hook - login, XP gain, level up, kill - fires overwhelmingly for
**bots**, not humans. A script that does real work per player (a DB query above all)
will run thousands of times during a bot ramp-up and can stall the world thread.

Always guard:

```lua
if not Madosa.IsRealPlayer(player) then return end
```

`00_madosa_common.lua` provides that, detecting bots by mod-playerbots' own account
prefix (`AiPlayerbot.RandomBotAccountPrefix`, currently `rndbot`). ALE itself has no
bot awareness.

## Conventions

- **Load order is alphabetical by path** (ALE sorts with `ScriptPathComparator`), and
  all scripts share one Lua state. Hence the numeric prefixes: `00_` holds shared
  globals that everything else depends on, feature scripts start at `10_`.
- One feature per file, named after what it does, so it can be deleted on its own.
- Log through `Madosa.Log` / `Madosa.LogError` so this realm's output stays greppable
  in `ALE.log`.

## Current scripts

| File | What it does |
|---|---|
| `00_madosa_common.lua` | Shared globals: `Madosa.IsRealPlayer` / `IsPlayerbot`, tagged logging. Must load first. |
| `10_smoketest.lua` | Logs one line at startup proving the engine and this directory are live. Safe to delete. |
| `20_xpboost_login_notice.lua` | Tells a player on login how large their mod-xpboost boost is (the buff icon alone does not say). |

## Setup

The server reads `ALE.ScriptPath` (`lua_scripts`, relative to `env/dist/bin`). This
directory is linked in rather than configured directly, so the engine's own
`extensions/` folder keeps working and `make install` stays harmless:

```bash
ln -s ~/azerothcore/modules/mod-madosa/lua ~/azerothcore/env/dist/bin/lua_scripts/madosa
```

ALE recurses into subdirectories and follows the symlink, so everything here loads.

For development, `env/dist/etc/modules/mod_ale.conf` sets:

```ini
ALE.AutoReload = true      # save a .lua -> reloaded within a second, no restart
ALE.TraceBack  = true      # full Lua stack trace on error instead of one line
```

Turn `AutoReload` off if this realm ever stops being a personal server - it polls the
filesystem every `ALE.AutoReloadInterval` seconds.

## Reloading by hand

```
.reload ALE
```

in-game or on the console, if `AutoReload` is off or you want to force it.
