-- The geometry half of the stand-in client: WoW's anchor rules and text
-- measurement, for real.
--
-- A frame in WoW has no position of its own. It has anchors - "my TOPLEFT sits
-- at my parent's TOPLEFT plus (16, -40)" - and its rectangle falls out of them
-- together with whatever width and height were set. Two anchors on opposite
-- sides give a size; one anchor and a size give a position. A FontString with
-- a left and a right anchor wraps its text at that width, and how many lines
-- that takes is its height, which then decides where everything anchored below
-- it lands.
--
-- That last chain is the reason this exists. Guessing string heights, which is
-- what an inert stub has to do, means the layout arithmetic in the addon is
-- never actually checked: a panel can be too short for its own contents and
-- nothing says so. Here the rectangles are resolved the way the client
-- resolves them, off the client's own font metrics (fontmetrics.lua), so the
-- test can ask whether the last row still fits inside the panel.
--
-- Coordinates are WoW's: origin bottom left of UIParent, y upwards.
--
-- What this is not: a renderer. Glyph shaping, kerning, Blizzard's backdrop
-- art and the exact insets of a template are not here. Widths are plain glyph
-- advances, which is what a proportional font without kerning comes to, and
-- close enough that "does this text fit in this box" is a real answer.

Layout = {}

local GEN = 0
function Layout.Invalidate() GEN = GEN + 1 end
function Layout.Generation() return GEN end

-- The GameFont* objects the addon asks for, at the pixel sizes Fonts.xml gives
-- them in 3.3.5.
Layout.FONT_SIZE = {
    GameFontNormal = 12, GameFontNormalSmall = 10, GameFontNormalLarge = 16,
    GameFontNormalHuge = 20, GameFontHighlight = 12, GameFontHighlightSmall = 10,
    GameFontHighlightLarge = 16, GameFontDisable = 12, GameFontDisableSmall = 10,
    GameFontGreen = 12, GameFontRed = 12, NumberFontNormal = 14,
}
Layout.DEFAULT_FONT_SIZE = 12

function Layout.FontSize(widget)
    return Layout.FONT_SIZE[widget._font or ""] or Layout.DEFAULT_FONT_SIZE
end

----------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------

-- WoW's escape codes: |cAARRGGBB starts a colour and |r ends it, |Hlink|htext|h
-- is a hyperlink whose visible part is between the |h's, |T...|t is an inline
-- texture and || is a literal pipe. Text is turned into a list of coloured
-- characters once, and everything else - measuring, wrapping, drawing - works
-- off that, so a colour in the middle of a line cannot shift the layout.
function Layout.Runs(text)
    local out = {}
    if not text then return out end
    local s, i, n = tostring(text), 1, #tostring(text)
    local stack = {}
    while i <= n do
        local c = s:sub(i, i)
        if c == "|" then
            local code = s:sub(i + 1, i + 1)
            if code == "|" then
                out[#out + 1] = { ch = "|", color = stack[#stack] }
                i = i + 2
            elseif code == "c" or code == "C" then
                local hex = s:sub(i + 2, i + 9)
                if hex:match("^%x%x%x%x%x%x%x%x$") then
                    stack[#stack + 1] = {
                        tonumber(hex:sub(3, 4), 16) / 255,
                        tonumber(hex:sub(5, 6), 16) / 255,
                        tonumber(hex:sub(7, 8), 16) / 255,
                    }
                    i = i + 10
                else
                    i = i + 2
                end
            elseif code == "r" then
                stack[#stack] = nil
                i = i + 2
            elseif code == "H" then
                local close = s:find("|h", i + 2, true)
                i = close and (close + 2) or (i + 2)
            elseif code == "h" then
                i = i + 2
            elseif code == "T" then
                local close = s:find("|t", i + 2, true)
                i = close and (close + 2) or (i + 2)
            elseif code == "n" then
                out[#out + 1] = { ch = "\n", color = stack[#stack] }
                i = i + 2
            else
                i = i + 2
            end
        else
            out[#out + 1] = { ch = c, color = stack[#stack] }
            i = i + 1
        end
    end
    return out
end

-- What a player actually sees, as a plain string.
function Layout.Visible(text)
    local out = {}
    for _, c in ipairs(Layout.Runs(text)) do out[#out + 1] = c.ch end
    return table.concat(out)
end

local function metrics(size)
    local m = FontMetrics[size]
    if m then return m end
    -- nearest size we measured, scaled
    local best, bestDiff
    for s in pairs(FontMetrics) do
        local d = math.abs(s - size)
        if not bestDiff or d < bestDiff then best, bestDiff = s, d end
    end
    local base = FontMetrics[best]
    local scale = size / best
    local out = { lineHeight = base.lineHeight * scale, default = base.default * scale }
    for k, v in pairs(base) do
        if type(k) == "number" then out[k] = v * scale end
    end
    FontMetrics[size] = out
    return out
end

function Layout.LineHeight(size) return metrics(size).lineHeight end

-- Width of one line, in pixels, with no markup in it.
function Layout.Width(line, size)
    local m = metrics(size)
    local w = 0
    for i = 1, #line do
        w = w + (m[line:byte(i)] or m.default)
    end
    return w
end

-- A hair of slack: a FontString sized to its own text ends up comparing a
-- width against right-minus-left, which is the same number give or take a
-- float, and without this every such string would wrap onto a second line.
local SLACK = 0.05

-- Word wrap over coloured characters. Returns a list of lines, each a list of
-- { text, color } runs - adjacent characters of the same colour merged, which
-- is what a renderer wants and what Layout.Wrap flattens back to strings.
function Layout.WrapRuns(text, size, maxWidth)
    local m = metrics(size)
    local chars = Layout.Runs(text)
    local lines, line, word, lineW, wordW = {}, {}, {}, 0, 0

    local function flushWord()
        for _, c in ipairs(word) do line[#line + 1] = c end
        lineW = lineW + wordW
        word, wordW = {}, 0
    end
    local function flushLine()
        flushWord()
        lines[#lines + 1] = line
        line, lineW = {}, 0
    end

    for _, c in ipairs(chars) do
        if c.ch == "\n" then
            flushLine()
        else
            local w = m[c.ch:byte()] or m.default
            if c.ch == " " then
                flushWord()
                line[#line + 1] = c
                lineW = lineW + w
            else
                word[#word + 1] = c
                wordW = wordW + w
                if maxWidth and maxWidth > 0 and lineW + wordW > maxWidth + SLACK and #line > 0 then
                    -- drop the trailing spaces the break sits on
                    while #line > 0 and line[#line].ch == " " do
                        lineW = lineW - (m[32] or m.default)
                        line[#line] = nil
                    end
                    lines[#lines + 1] = line
                    line, lineW = {}, 0
                end
            end
        end
    end
    flushLine()
    if #lines == 0 then lines[1] = {} end

    -- merge runs
    local out = {}
    for _, chs in ipairs(lines) do
        local runs, cur = {}, nil
        for _, c in ipairs(chs) do
            local key = c.color and table.concat(c.color, ",") or ""
            if cur and cur.key == key then
                cur.parts[#cur.parts + 1] = c.ch
            else
                cur = { key = key, color = c.color, parts = { c.ch } }
                runs[#runs + 1] = cur
            end
        end
        local merged = {}
        for _, run in ipairs(runs) do
            merged[#merged + 1] = { text = table.concat(run.parts), color = run.color }
        end
        out[#out + 1] = merged
    end
    return out
end

-- The same wrap, as plain strings.
function Layout.Wrap(text, size, maxWidth)
    local out = {}
    for _, runs in ipairs(Layout.WrapRuns(text, size, maxWidth)) do
        local parts = {}
        for _, run in ipairs(runs) do parts[#parts + 1] = run.text end
        out[#out + 1] = table.concat(parts)
    end
    return out
end

----------------------------------------------------------------------------
-- Anchors
----------------------------------------------------------------------------

local XKIND = {
    TOPLEFT = "left", LEFT = "left", BOTTOMLEFT = "left",
    TOPRIGHT = "right", RIGHT = "right", BOTTOMRIGHT = "right",
    TOP = "center", CENTER = "center", BOTTOM = "center",
}
local YKIND = {
    TOPLEFT = "top", TOP = "top", TOPRIGHT = "top",
    BOTTOMLEFT = "bottom", BOTTOM = "bottom", BOTTOMRIGHT = "bottom",
    LEFT = "center", CENTER = "center", RIGHT = "center",
}

local function anchorX(l, r, point)
    local k = XKIND[point or "CENTER"] or "center"
    if k == "left" then return l elseif k == "right" then return r end
    return (l + r) / 2
end

local function anchorY(b, t, point)
    local k = YKIND[point or "CENTER"] or "center"
    if k == "bottom" then return b elseif k == "top" then return t end
    return (b + t) / 2
end

local RectX, RectY

-- Screen: UIParent is the whole of it and anchors nothing.
local function isScreen(w) return w._name == "UIParent" end

RectX = function(w)
    if not w then return 0, 0 end
    if isScreen(w) then return 0, w._width end
    if w._genX == GEN then return w._left, w._right end
    if w._busyX then error("circular horizontal anchor at " .. tostring(w._name or w._kind), 0) end
    w._busyX = true

    local left, right, center
    for _, p in ipairs(w._points) do
        local rel = p.rel or w._parent or UIParent
        local rl, rr = RectX(rel)
        if p.point == "ALL" then
            left, right, center = rl, rr, nil
            break
        end
        local target = anchorX(rl, rr, p.relPoint) + (p.x or 0)
        local kind = XKIND[p.point]
        if kind == "left" then left = target
        elseif kind == "right" then right = target
        else center = target end
    end

    local width = (w._width and w._width > 0) and w._width or nil
    if not width and w._kind == "FontString" and not (left and right) then
        local size = Layout.FontSize(w)
        local widest = 0
        for _, line in ipairs(Layout.Wrap(w._text, size, nil)) do
            widest = math.max(widest, Layout.Width(line, size))
        end
        width = widest
    end

    if left and right then                       -- both sides pinned
    elseif left and width then right = left + width
    elseif right and width then left = right - width
    elseif center and width then left, right = center - width / 2, center + width / 2
    elseif left then right = left
    elseif right then left = right
    elseif center then left, right = center, center
    else
        local pl = RectX(w._parent or UIParent)
        left = pl
        right = pl + (width or 0)
    end

    w._busyX, w._genX, w._left, w._right = nil, GEN, left, right
    return left, right
end

-- Height of a FontString's wrapped text; needs its width, never its height.
function Layout.TextHeight(w)
    if w._kind ~= "FontString" then return 0 end
    local visible = Layout.Visible(w._text)
    if visible == "" then return 0 end
    local size = Layout.FontSize(w)
    local l, r = RectX(w)
    local lines = Layout.Wrap(w._text, size, r - l)
    return #lines * Layout.LineHeight(size)
end

RectY = function(w)
    if not w then return 0, 0 end
    if isScreen(w) then return 0, w._height end
    if w._genY == GEN then return w._bottom, w._top end
    if w._busyY then error("circular vertical anchor at " .. tostring(w._name or w._kind), 0) end
    w._busyY = true

    local bottom, top, center
    for _, p in ipairs(w._points) do
        local rel = p.rel or w._parent or UIParent
        local rb, rt = RectY(rel)
        if p.point == "ALL" then
            bottom, top, center = rb, rt, nil
            break
        end
        local target = anchorY(rb, rt, p.relPoint) + (p.y or 0)
        local kind = YKIND[p.point]
        if kind == "bottom" then bottom = target
        elseif kind == "top" then top = target
        else center = target end
    end

    local height = (w._height and w._height > 0) and w._height or nil
    if not height and w._kind == "FontString" and not (bottom and top) then
        height = Layout.TextHeight(w)
    end

    if bottom and top then
    elseif top and height then bottom = top - height
    elseif bottom and height then top = bottom + height
    elseif center and height then bottom, top = center - height / 2, center + height / 2
    elseif top then bottom = top
    elseif bottom then top = bottom
    elseif center then bottom, top = center, center
    else
        local _, pt = RectY(w._parent or UIParent)
        top = pt
        bottom = pt - (height or 0)
    end

    w._busyY, w._genY, w._bottom, w._top = nil, GEN, bottom, top
    return bottom, top
end

Layout.RectX, Layout.RectY = RectX, RectY

-- left, bottom, right, top
function Layout.Rect(w)
    local l, r = RectX(w)
    local b, t = RectY(w)
    return l, b, r, t
end

-- Is every part of `inner` inside `outer`? Returns false plus the side that
-- sticks out, which is the message a failing layout test wants to print.
function Layout.Contains(outer, inner, slack)
    slack = slack or 0
    local ol, ob, or_, ot = Layout.Rect(outer)
    local il, ib, ir, it = Layout.Rect(inner)
    if il < ol - slack then return false, "left" end
    if ir > or_ + slack then return false, "right" end
    if ib < ob - slack then return false, "bottom" end
    if it > ot + slack then return false, "top" end
    return true
end

function Layout.Overlaps(a, b)
    local al, ab, ar, at = Layout.Rect(a)
    local bl, bb, br, bt = Layout.Rect(b)
    return al < br and bl < ar and ab < bt and bb < at
end
