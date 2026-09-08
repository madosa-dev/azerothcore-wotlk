-- The harness, in one dofile.
--
--   dofile("/path/to/wowsim/init.lua")
--   Sim.LoadAddon("/path/to/MyAddon")
--   Sim.Enter()
--
-- After that the addon is running inside a stand-in WoW 3.3.5: frames are
-- laid out for real against the client's own fonts, the game APIs answer out
-- of the World table, and Sim.Dump writes the resolved layout for render.py.
--
-- See README.md for what is and is not simulated.

WowSim = { dir = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]") or ".") }

for _, file in ipairs({
    "data/fontmetrics.lua",   -- glyph advances, from the client's own TTFs
    "data/fonts.lua",         -- the 149 GameFont* objects, from FontStyles.xml
    "data/talents.lua",       -- every class's talent tree, from Talent.dbc
    "layout.lua",             -- anchors and text measurement
    "client.lua",             -- widgets, the game API, and the World behind it
    "compat.lua",             -- the globals WoW adds on top of Lua 5.1
    "xml.lua",                -- frames declared in XML
    "toc.lua",                -- loading an addon from its .toc
    "apitrace.lua",           -- what the harness does not implement yet
}) do
    local path = WowSim.dir .. "/" .. file
    local chunk, err = loadfile(path)
    if not chunk then error("wowsim: " .. tostring(err), 0) end
    chunk()
end

function WowSim.ArtDir() return WowSim.dir .. "/art" end
