# wowsim — a stand-in WoW 3.3.5 client for testing addons

Runs a WoW addon with no game, no server and no Wine: frames are laid out for
real, the game APIs answer out of a table the test sets up, and the resolved
layout can be drawn to a PNG with the client's own fonts and art.

It exists because the interesting half of an addon only happens inside the
client. Pure functions are easy to test; what breaks in practice is the frame
that is too short for its own contents, the string that wraps and pushes
everything below it down, the event that never fires, the item the client had
not cached yet. None of that is reachable from a plain `lua5.1` script, and all
of it is reachable here.

## Using it

```lua
dofile("/path/to/tools/wowsim/init.lua")
assert(Sim.LoadAddon("/path/to/MyAddon"))   -- reads MyAddon.toc, runs its files

World.Reset("SHAMAN", 40)                   -- class and level
World.AddItem("axe", { id = 1, name = "Axe", equipLoc = "INVTYPE_WEAPON",
                       stats = { DPS = 30 }, speed = 2.6 })
World.PutInBag(0, 1, "axe")
Sim.Enter()                                 -- ADDON_LOADED .. PLAYER_ENTERING_WORLD

assert(MyAddonFrame:IsShown())
print(MyAddonFrame.title:GetText())
Sim.ReportMissing()                         -- what the harness has not got
```

Then look at it:

```sh
lua5.1 my_scenarios.lua          # ends with Sim.Dump("snapshots/thing.json")
python3 render.py --client ~/path/to/wow
```

## What is real

**Layout.** `layout.lua` resolves anchors the way the client does: two anchors
on opposite sides give a size, one anchor and a size give a position, and a
FontString pinned left and right wraps at that width — which then decides where
everything anchored below it lands. `GetStringHeight`, `GetWidth`, `GetRect`
and friends answer off that, and `Layout.Contains` / `Layout.Overlaps` turn it
into assertions: *is this panel tall enough for its own contents*, *do these
two lines collide*, *does this text fit its row*.

**Fonts.** `extract.py` reads `Fonts.xml` and `FontStyles.xml` out of the
client and writes all 149 `GameFont*` objects — face, pixel height, colour,
outline — then measures the glyph advances of every TTF they name, at every
size they use, straight out of the archives. So a string is as wide here as it
is in the game. This is not a detail: the difference between the client's
`FRIZQT__.TTF` and a replaced one was enough to push three lines of a real
addon out of their boxes.

**Game data.** Every class's talent tree comes from `Talent.dbc`, icons and all
(`tools/talentadvisor/dump_trees.py`), so `GetTalentInfo` answers with the real
thing.

**Art.** Backdrops are drawn as the game draws them — the `bgFile` tiled inside
the insets, the `edgeFile`'s eight tiles laid round the outside, the top and
bottom ones rotated because that is how they are stored. Textures the art
folder does not have are pulled from the client on demand when `render.py` is
given `--client`.

**The rest of the client's Lua.** `compat.lua` carries the globals WoW adds on
top of Lua 5.1 — `strmatch`, `strsplit`, `tinsert`, `wipe`, `bit`,
`hooksecurefunc`, `GetTime` and the rest. LibStub calls `strmatch` on its
second line, so without these nothing third-party loads at all.

**XML.** `xml.lua` reads the second language addons are written in: `Ui`,
`Include`, `Script`, virtual templates and `inherits`, `Size` and `Anchors`,
`Layers` of `Texture` and `FontString`, nested `Frames`, `Backdrop`, and
`Scripts` compiled with the names the client gives them (`self`, `this`,
`event`, `arg1..arg9`). Files are run in `.toc` order, Lua and XML alike, each
handed the addon name and its private table the way the client hands them
over.

## What is not

- **A partial API.** What is implemented is what addons have needed so far, not
  the whole client. This is not hidden: every read of an undefined global that
  looks like a game function is counted, and `Sim.ReportMissing()` lists them
  after a run, so bringing up a new addon is a loop — run it, read the list,
  add what it wants to `client.lua` or `compat.lua`. `Sim.Strict(true)` turns
  the next such read into an error with a traceback. Expect a large addon with
  its own library stack to want a dozen rounds of this.
- **XML, but not all of it.** TexCoords, gradients, animations and the more
  exotic widget types are parsed and ignored rather than refused.
- **No pixels of its own.** The renderer approximates: no glyph kerning, no
  button states, no strata, no animation. It answers "does this fit, does it
  overlap, what does it say, roughly what does it look like" — not "is this
  pixel-identical to the game".

## Files

| | |
|---|---|
| `init.lua` | loads the harness; the only thing a consumer needs to `dofile` |
| `layout.lua` | anchors, text measurement, wrapping over coloured runs |
| `client.lua` | widgets, the game API, and the `World` behind it |
| `compat.lua` | the globals WoW adds on top of Lua 5.1 |
| `xml.lua` | frames declared in XML |
| `toc.lua` | `.toc` parsing and addon loading |
| `apitrace.lua` | what the harness does not implement yet |
| `data/` | generated: font objects, font metrics, talent trees |
| `mpq.py` | reads the client's MPQ archives, honouring the patch order |
| `blp.py` | decodes BLP2 textures (palette, DXT1/3/5, BGRA) |
| `extract.py` | pulls fonts, metrics and art out of a client install |
| `fontmetrics.py` | measures the TTFs `extract.py` finds |
| `render.py` | draws a layout snapshot as a PNG |

`data/` is committed, so the harness runs without a client. `art/` is not:
that is Blizzard's artwork, and `extract.py --client <dir> art` puts it back.

## Setting it up against a client

```sh
python3 extract.py --client ~/Games/.../world_of_warcraft_wrath_of_the_lich_king all
```

Reads the archives in the game's own load order, so a client with custom UI
patches yields what that client actually shows.

## Bringing up an addon that has never run here

```lua
dofile("tools/wowsim/init.lua")
local toc, why = Sim.LoadAddon("/path/to/Whatever")
if not toc then print(why) end        -- a named file and line, every time
Sim.ReportMissing()                   -- then add what it asked for
```

Paths are matched case-insensitively, a UTF-8 byte order mark is stripped, and
a folder whose `.toc` is named for something else (`Foo.repo/` holding
`Foo.toc`) still loads — all of which the real client does for free on Windows
and none of which Lua does on Linux.

## A worked example

`tools/talentadvisor/run_ui_tests.lua` drives mod-madosa's TalentAdvisor
through it in 35 scenarios — the picker, learning talents, bag scans, the
tooltip fallback, and seven layout checks. Between them the harness turned up
a heading indented differently from its neighbours, a panel with under a pixel
of clearance above its footer, a title that wrapped onto the icon below it,
and three descriptions that ran out of their rows once the font was the
client's own.
