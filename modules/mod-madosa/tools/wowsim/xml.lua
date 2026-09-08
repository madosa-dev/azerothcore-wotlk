-- Frames defined in XML.
--
-- An addon's interface is written in two languages: Lua, and an XML dialect
-- that declares frames, their regions, their anchors and their script bodies.
-- Nearly every real addon uses both - Ace3 alone pulls in three XML files -
-- so a harness that only speaks Lua can load almost nothing.
--
-- This covers the dialect as 3.3.5 addons actually use it: Ui, Include and
-- Script, virtual templates and inherits, Size and Anchors, Layers of Textures
-- and FontStrings, nested Frames, Backdrop, and Scripts. What it does not do
-- is the parts that only mean something to a renderer - TexCoords, gradients,
-- animations, layout of the more exotic widget types - which are parsed and
-- ignored rather than refused.
--
-- Script bodies are compiled with the names the client gives them: self and
-- this always, event and arg1..arg9 on OnEvent, arg1 as the elapsed time on
-- OnUpdate.

XmlTemplates = {}

----------------------------------------------------------------------------
-- A small XML reader
----------------------------------------------------------------------------

local function unescape(s)
    return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"')
             :gsub("&apos;", "'"):gsub("&amp;", "&"))
end

-- { tag = , attr = {}, kids = {}, text = }
local function parse(text)
    local pos, root, stack = 1, { tag = "#root", attr = {}, kids = {} }, {}
    local top = root
    while true do
        local open = text:find("<", pos, true)
        if not open then break end
        if open > pos then
            local chunk = text:sub(pos, open - 1)
            if chunk:match("%S") then top.text = (top.text or "") .. chunk end
        end
        if text:sub(open, open + 3) == "<!--" then
            local close = text:find("-->", open, true)
            pos = close and close + 3 or #text + 1
        elseif text:sub(open, open + 8) == "<![CDATA[" then
            local close = text:find("]]>", open, true) or #text
            top.text = (top.text or "") .. text:sub(open + 9, close - 1)
            pos = close + 3
        elseif text:sub(open + 1, open + 1) == "?" or text:sub(open + 1, open + 1) == "!" then
            pos = (text:find(">", open, true) or #text) + 1
        elseif text:sub(open + 1, open + 1) == "/" then
            local close = text:find(">", open, true) or #text
            top = table.remove(stack) or root
            pos = close + 1
        else
            local close = text:find(">", open, true)
            if not close then break end
            local body = text:sub(open + 1, close - 1)
            local selfClosing = body:sub(-1) == "/"
            if selfClosing then body = body:sub(1, -2) end
            local tag = body:match("^([%w_:%-]+)")
            local node = { tag = tag, attr = {}, kids = {} }
            for key, value in body:gmatch('([%w_:%-]+)%s*=%s*"([^"]*)"') do
                node.attr[key] = unescape(value)
            end
            top.kids[#top.kids + 1] = node
            if not selfClosing then
                stack[#stack + 1] = top
                top = node
            end
            pos = close + 1
        end
    end
    return root
end
Sim.ParseXml = parse

local function kidsNamed(node, tag)
    local out = {}
    for _, kid in ipairs(node.kids) do
        if kid.tag:lower() == tag:lower() then out[#out + 1] = kid end
    end
    return out
end

local function firstNamed(node, tag) return kidsNamed(node, tag)[1] end

local function truthy(v) return v == "true" or v == "1" end

----------------------------------------------------------------------------
-- Turning nodes into widgets
----------------------------------------------------------------------------

local WIDGETS = {
    frame = "Frame", button = "Button", checkbutton = "CheckButton",
    editbox = "EditBox", slider = "Slider", statusbar = "StatusBar",
    scrollframe = "ScrollFrame", scrollingmessageframe = "ScrollingMessageFrame",
    messageframe = "MessageFrame", simplehtml = "SimpleHTML", colorselect = "ColorSelect",
    model = "Model", playermodel = "PlayerModel", dressupmodel = "DressUpModel",
    tabardmodel = "TabardModel", movieframe = "MovieFrame", gametooltip = "GameTooltip",
    cooldown = "Cooldown", minimap = "Minimap",
}

local function resolveName(name, parent)
    if not name then return nil end
    if name:find("$parent", 1, true) then
        local parentName = parent and parent._name or ""
        return (name:gsub("%$parent", parentName))
    end
    return name
end

local function absDimension(node)
    if not node then return nil, nil end
    local abs = firstNamed(node, "AbsDimension")
    if abs then return tonumber(abs.attr.x), tonumber(abs.attr.y) end
    return tonumber(node.attr.x), tonumber(node.attr.y)
end

local function absValue(node)
    if not node then return nil end
    local abs = firstNamed(node, "AbsValue")
    if abs then return tonumber(abs.attr.val) end
    return tonumber(node.attr.val)
end

local applyNode, applyTo          -- forward

local function applyAnchors(widget, node)
    local anchors = firstNamed(node, "Anchors")
    if not anchors then return end
    for _, anchor in ipairs(kidsNamed(anchors, "Anchor")) do
        local point = anchor.attr.point or "TOPLEFT"
        local relTo = anchor.attr.relativeTo
        local rel = relTo and _G[resolveName(relTo, widget._parent)] or widget._parent
        local relPoint = anchor.attr.relativePoint or point
        local x, y = absDimension(firstNamed(anchor, "Offset"))
        widget:SetPoint(point, rel, relPoint, tonumber(anchor.attr.x) or x or 0,
                        tonumber(anchor.attr.y) or y or 0)
    end
end

local function applyScripts(widget, node, name)
    local scripts = firstNamed(node, "Scripts")
    if not scripts then return end
    for _, script in ipairs(scripts.kids) do
        local handler = script.tag
        local body = script.text
        if body and body:match("%S") then
            local head
            if handler:lower() == "onevent" then
                head = "local self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9 = ...\n"
                    .. "local this = self\n"
            elseif handler:lower() == "onupdate" then
                head = "local self, arg1 = ...\nlocal this, elapsed = self, arg1\n"
            else
                head = "local self, arg1, arg2, arg3, arg4 = ...\nlocal this = self\n"
            end
            local chunk, err = loadstring(head .. body, (name or "xml") .. ":" .. handler)
            if not chunk then
                error(string.format("%s <%s>: %s", name or "xml", handler, err), 0)
            end
            widget:SetScript(handler, chunk)
        elseif script.attr["function"] then
            local fname = script.attr["function"]
            widget:SetScript(handler, function(...) return _G[fname](...) end)
        end
    end
end

local function applyBackdrop(widget, node)
    local backdrop = firstNamed(node, "Backdrop")
    if not backdrop then return end
    local insets = firstNamed(backdrop, "BackgroundInsets")
    local left, right, top, bottom = 0, 0, 0, 0
    if insets then
        local abs = firstNamed(insets, "AbsInset")
        if abs then
            left = tonumber(abs.attr.left) or 0; right = tonumber(abs.attr.right) or 0
            top = tonumber(abs.attr.top) or 0; bottom = tonumber(abs.attr.bottom) or 0
        end
    end
    widget:SetBackdrop({
        bgFile = backdrop.attr.bgFile, edgeFile = backdrop.attr.edgeFile,
        tile = truthy(backdrop.attr.tile),
        tileSize = absValue(firstNamed(backdrop, "TileSize")) or 16,
        edgeSize = absValue(firstNamed(backdrop, "EdgeSize")) or 16,
        insets = { left = left, right = right, top = top, bottom = bottom },
    })
end

local function applyRegions(widget, node, name)
    local layers = firstNamed(node, "Layers")
    if not layers then return end
    for _, layer in ipairs(kidsNamed(layers, "Layer")) do
        local level = layer.attr.level or "ARTWORK"
        for _, region in ipairs(layer.kids) do
            local tag = region.tag:lower()
            local regionName = resolveName(region.attr.name, widget)
            local child
            if tag == "texture" then
                child = widget:CreateTexture(regionName, level)
                if region.attr.file then child:SetTexture(region.attr.file) end
                local colour = firstNamed(region, "Color")
                if colour then
                    child:SetTexture(tonumber(colour.attr.r) or 1, tonumber(colour.attr.g) or 1,
                                     tonumber(colour.attr.b) or 1, tonumber(colour.attr.a) or 1)
                end
            elseif tag == "fontstring" then
                child = widget:CreateFontString(regionName, level, region.attr.inherits)
                if region.attr.text then child:SetText(region.attr.text) end
                if region.attr.justifyH then child:SetJustifyH(region.attr.justifyH) end
            end
            if child then
                if truthy(region.attr.setAllPoints) then child:SetAllPoints(widget) end
                local w, h = absDimension(firstNamed(region, "Size"))
                if w then child:SetWidth(w) end
                if h then child:SetHeight(h) end
                child._parent = widget
                applyAnchors(child, region)
                if regionName then _G[regionName] = child end
            end
        end
    end
end

-- Build (or, for a template, remember) one widget node.
applyNode = function(node, parent, nameOverride)
    local kind = WIDGETS[node.tag:lower()]
    if not kind then return nil end

    if truthy(node.attr.virtual) then
        XmlTemplates[node.attr.name] = node
        return nil
    end

    local name = nameOverride or resolveName(node.attr.name, parent)
    -- parent="SomeFrame" names a global; without it a top-level node hangs off
    -- UIParent, the way the client does it.
    if node.attr.parent then parent = _G[node.attr.parent] or parent end
    local widget = CreateFrame(kind, name, parent, node.attr.inherits)

    -- a template is applied first, then this node's own settings on top
    for template in (node.attr.inherits or ""):gmatch("[^,%s]+") do
        local base = XmlTemplates[template]
        if base then
            applyTo(base, widget, name)
        end
    end
    applyTo(node, widget, name)

    if widget:GetScript("OnLoad") then widget:Fire("OnLoad") end
    return widget
end

-- everything a node says about an existing widget
applyTo = function(node, widget, name)
    local w, h = absDimension(firstNamed(node, "Size"))
    if w then widget:SetWidth(w) end
    if h then widget:SetHeight(h) end
    if truthy(node.attr.setAllPoints) then widget:SetAllPoints(widget._parent) end
    if truthy(node.attr.hidden) then widget:Hide() end
    if node.attr.text then widget:SetText(node.attr.text) end
    if node.attr.id then widget._id = tonumber(node.attr.id) end
    applyAnchors(widget, node)
    applyBackdrop(widget, node)
    applyRegions(widget, node, name)
    applyScripts(widget, node, name)

    local frames = firstNamed(node, "Frames")
    if frames then
        for _, kid in ipairs(frames.kids) do applyNode(kid, widget) end
    end
    -- a Button's own label regions sit outside <Layers>
    for _, tag in ipairs({ "NormalText", "ButtonText" }) do
        local fs = firstNamed(node, tag)
        if fs then
            local child = widget:CreateFontString(resolveName(fs.attr.name, widget),
                                                  "OVERLAY", fs.attr.inherits)
            child._parent = widget
            applyAnchors(child, fs)
            if fs.attr.text then child:SetText(fs.attr.text) end
        end
    end
end

----------------------------------------------------------------------------
-- Loading a file
----------------------------------------------------------------------------

-- Windows does not care about the case of a path and the client is a Windows
-- program, so .toc and XML files habitually name "Libs/..." for a folder on
-- disk called "libs". On a case-sensitive filesystem that is a missing file
-- unless the lookup is forgiving, segment by segment, the way it effectively
-- is in the game.
local function resolvePath(path)
    local fh = io.open(path, "rb")
    if fh then fh:close(); return path end
    local parts, rebuilt = {}, path:sub(1, 1) == "/" and "" or "."
    for part in path:gmatch("[^/\\]+") do parts[#parts + 1] = part end
    for i, part in ipairs(parts) do
        local candidate = rebuilt .. "/" .. part
        local probe = io.open(candidate, "rb")
        if probe then
            probe:close()
            rebuilt = candidate
        elseif i < #parts or true then
            local found
            local pipe = io.popen('ls -1 "' .. rebuilt .. '" 2>/dev/null')
            if pipe then
                for line in pipe:lines() do
                    if line:lower() == part:lower() then found = line; break end
                end
                pipe:close()
            end
            if not found then return path end
            rebuilt = rebuilt .. "/" .. found
        end
    end
    return rebuilt
end
Sim.ResolvePath = resolvePath

local function readFile(path)
    local fh = io.open(resolvePath(path), "rb")
    if not fh then return nil end
    local text = fh:read("*a")
    fh:close()
    return (text:gsub("^\239\187\191", ""))          -- a UTF-8 BOM the client tolerates
end
Sim.ReadFile = readFile

-- dir is where $parent-relative includes are resolved from.
function Sim.LoadXml(path, dir)
    dir = dir or path:match("^(.*)[/\\]") or "."
    local text = readFile(path)
    if not text then return nil, "no such file: " .. path end
    local root = parse(text)
    local ui = firstNamed(root, "Ui") or root
    for _, node in ipairs(ui.kids) do
        local tag = node.tag:lower()
        if tag == "include" then
            -- an included file's own includes are relative to where that file
            -- lives, not to where the chain started
            local ok, err = Sim.LoadXml(dir .. "/" .. node.attr.file:gsub("\\", "/"))
            if not ok then return nil, err end
        elseif tag == "script" and node.attr.file then
            local file = dir .. "/" .. node.attr.file:gsub("\\", "/")
            local body = readFile(file)
            if not body then return nil, "no such file: " .. file end
            local chunk, err = loadstring(body, "@" .. file)
            if not chunk then return nil, err end
            local loading = Sim.loading
            local ok, runErr = pcall(chunk, loading and loading.name or "",
                                     loading and loading.private or {})
            if not ok then return nil, tostring(runErr) end
        elseif tag == "script" and node.text then
            local chunk, err = loadstring(node.text, "@" .. path)
            if not chunk then return nil, err end
            local ok, runErr = pcall(chunk)
            if not ok then return nil, tostring(runErr) end
        elseif tag == "font" then
            if node.attr.name then
                FontObjects[node.attr.name] = {
                    font = node.attr.font or "Fonts\\FRIZQT__.TTF",
                    size = absValue(firstNamed(node, "FontHeight")) or 12,
                    color = { 1, 1, 1 }, outline = node.attr.outline,
                }
            end
        else
            applyNode(node, UIParent)
        end
    end
    return true
end
