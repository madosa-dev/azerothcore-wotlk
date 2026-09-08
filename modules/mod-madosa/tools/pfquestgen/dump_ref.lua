-- Print a sample of pfQuest's own TBC unit coordinates, so the generator's
-- world-to-zone conversion can be checked against numbers the addon shipped.
local PF = arg[1]
pfDB = { units = {}, objects = {}, quests = {}, items = {}, zones = {} }
dofile(PF .. "/db/units-tbc.lua")
local data = pfDB.units["data-tbc"]
local n = 0
for id, entry in pairs(data) do
  if type(entry) == "table" and entry.coords and #entry.coords > 0 and #entry.coords <= 3 then
    for _, c in ipairs(entry.coords) do
      if c[3] and c[3] > 3400 then          -- a TBC zone
        print(string.format("%d\t%.1f\t%.1f\t%d\t%d", id, c[1], c[2], c[3], c[4] or 0))
        n = n + 1
      end
    end
  end
  if n > 40 then break end
end
