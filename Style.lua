--------------------------------------------------------------------------------
-- Cys's Guild Hall - look
-- The Cys palette: dark flat panels, soft antique gold edges, white text with gold labels.
-- When Cys's UI is loaded its colors are used (so its Border color setting is followed).
--------------------------------------------------------------------------------
local GH = CysGuildHall
local S = {}
GH.Style = S

local function Hex(hex, a)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, a or 1 }
end

local OWN = {
    bg = Hex("16130F", 0.97), header = Hex("1B1713"), field = Hex("0E0C0A"), card = Hex("1C1814"),
    cardHover = Hex("231E19"), button = Hex("201B16"), selected = Hex("27211B"), line = Hex("332C24"),
    border = Hex("D9A421", 0.7), brand = Hex("D9A421"), glow = Hex("FFD100"), accent = Hex("FFD100"),
    text = Hex("E0E0E0"), dim = Hex("8A8A8A"), green = Hex("4FD66B"), danger = Hex("FF4040"),
}

-- Colors: Cys's UI's table when present (read when the panel is built), else our own
function S.T()
    local W = CysUI and CysUI.W
    if W and W.T and W.T.border then
        local T = W.T
        -- fill gaps so every key we use exists
        for k, v in pairs(OWN) do if T[k] == nil then T[k] = v end end
        return T
    end
    return OWN
end

local function CUIW() return CysUI and CysUI.W end

function S.Tex(parent, layer, color, sublevel)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    local W = CUIW()
    if W and W.TrackEdge then
        local T = S.T()
        if color == T.border then W.TrackEdge(t) end
    end
    return t
end

function S.Border(parent, color, layer)
    local e = {}
    for i = 1, 4 do e[i] = S.Tex(parent, layer or "BORDER", color) end
    e[1]:SetPoint("TOPLEFT");    e[1]:SetPoint("TOPRIGHT");    e[1]:SetHeight(1)
    e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(1)
    e[3]:SetPoint("TOPLEFT");    e[3]:SetPoint("BOTTOMLEFT");  e[3]:SetWidth(1)
    e[4]:SetPoint("TOPRIGHT");   e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(1)
    return e
end

function S.SetBorder(edges, color)
    for i = 1, #edges do edges[i]:SetColorTexture(color[1], color[2], color[3], color[4] or 1) end
end

function S.Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size or 12, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
    if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- Flat panel with a 1px edge
function S.Panel(parent, color, edge)
    local T = S.T()
    local f = CreateFrame("Frame", nil, parent)
    f.bg = S.Tex(f, "BACKGROUND", color or T.card)
    f.bg:SetAllPoints()
    f.edges = S.Border(f, edge or T.line)
    return f
end

function S.Button(parent, w, h, label)
    local T = S.T()
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = S.Tex(b, "BACKGROUND", T.button)
    b.bg:SetAllPoints()
    b.edges = S.Border(b, T.line)
    b.label = S.Text(b, 11, T.accent, "CENTER")
    b.label:SetPoint("CENTER")
    b.label:SetText(label or "")
    b:SetScript("OnEnter", function(s) if s:IsEnabled() then S.SetBorder(s.edges, T.glow) end end)
    b:SetScript("OnLeave", function(s) S.SetBorder(s.edges, T.line) end)
    function b:SetActive(on)
        if on then self:Enable(); self:SetAlpha(1) else self:Disable(); self:SetAlpha(0.45); S.SetBorder(self.edges, T.line) end
    end
    function b:SetLabel(text) self.label:SetText(text or "") end
    return b
end

-- Checkbox: get() -> bool, set(bool)
function S.Check(parent, label, get, set)
    local T = S.T()
    local c = CreateFrame("Button", nil, parent)
    c:SetHeight(18)
    local box = CreateFrame("Frame", nil, c)
    box:SetSize(14, 14)
    box:SetPoint("LEFT")
    S.Tex(box, "BACKGROUND", T.field):SetAllPoints()
    c.edges = S.Border(box, T.border)
    c.mark = S.Tex(box, "ARTWORK", T.glow)
    c.mark:SetPoint("TOPLEFT", 3, -3)
    c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    c.label = S.Text(c, 11, T.text)
    c.label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    c.label:SetText(label)
    c:SetWidth(22 + c.label:GetStringWidth())
    function c:Refresh() self.mark:SetShown(get() and true or false) end
    c:SetScript("OnClick", function(s) set(not get()); s:Refresh() end)
    c:Refresh()
    return c
end

-- Search box with a dark field and gold edge on focus
function S.EditBox(parent, w, h)
    local T = S.T()
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, h)
    e:SetAutoFocus(false)
    e:SetFont(STANDARD_TEXT_FONT, 12, "")
    e:SetTextColor(T.text[1], T.text[2], T.text[3])
    e:SetTextInsets(6, 6, 0, 0)
    S.Tex(e, "BACKGROUND", T.field):SetAllPoints()
    e.edges = S.Border(e, T.line)
    e:SetScript("OnEditFocusGained", function(s) S.SetBorder(s.edges, T.border) end)
    e:SetScript("OnEditFocusLost", function(s) S.SetBorder(s.edges, T.line) end)
    e:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    e.hint = S.Text(e, 11, T.dim)
    e.hint:SetPoint("LEFT", 7, 0)
    return e
end

-- Stepper: label, then [-] value [+]. values = list; get() -> current value; set(v); fmt(v) -> text
function S.Stepper(parent, label, values, get, set, fmt)
    local T = S.T()
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(208, 20)
    s.label = S.Text(s, 11, T.text)
    s.label:SetPoint("LEFT")
    s.label:SetText(label)
    s.plus = S.Button(s, 18, 18, "+")
    s.plus:SetPoint("RIGHT")
    s.value = S.Text(s, 11, T.accent, "CENTER")
    s.value:SetWidth(58)
    s.value:SetPoint("RIGHT", s.plus, "LEFT", -2, 0)
    s.minus = S.Button(s, 18, 18, "-")
    s.minus:SetPoint("RIGHT", s.value, "LEFT", -2, 0)
    local function Index()
        local cur = get()
        for i, v in ipairs(values) do if v == cur then return i end end
        for i, v in ipairs(values) do if v >= cur then return i end end
        return #values
    end
    function s:Refresh() self.value:SetText(fmt(get())) end
    s.minus:SetScript("OnClick", function() local i = Index(); if i > 1 then set(values[i - 1]) end; s:Refresh() end)
    s.plus:SetScript("OnClick", function() local i = Index(); if i < #values then set(values[i + 1]) end; s:Refresh() end)
    s:Refresh()
    return s
end

-- Money input: gold / silver / copper boxes. :GetAmount() -> copper, :SetAmount(copper), .OnChange()
function S.MoneyInput(parent)
    local T = S.T()
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(208, 22)
    local boxes = {}
    local defs = { { "g", 58, "Interface\\MoneyFrame\\UI-GoldIcon" }, { "s", 34, "Interface\\MoneyFrame\\UI-SilverIcon" },
                   { "c", 34, "Interface\\MoneyFrame\\UI-CopperIcon" } }
    local prev
    for i, d in ipairs(defs) do
        local e = S.EditBox(m, d[2], 22)
        e:SetNumeric(true)
        e:SetMaxLetters(i == 1 and 6 or 2)
        e:SetJustifyH("RIGHT")
        e:SetTextInsets(4, 4, 0, 0)
        if prev then e:SetPoint("LEFT", prev, "RIGHT", 18, 0) else e:SetPoint("LEFT") end
        local icon = m:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetTexture(d[3])
        icon:SetPoint("LEFT", e, "RIGHT", 3, 0)
        e:SetScript("OnTextChanged", function(_, user) if user and m.OnChange then m.OnChange() end end)
        e:SetScript("OnTabPressed", function() local n = boxes[i % 3 + 1]; n:SetFocus(); n:HighlightText() end)
        boxes[i] = e
        prev = e
    end
    m.boxes = boxes
    function m:GetAmount()
        local g, s, c = tonumber(boxes[1]:GetText()) or 0, tonumber(boxes[2]:GetText()) or 0, tonumber(boxes[3]:GetText()) or 0
        return g * 10000 + s * 100 + c
    end
    function m:SetAmount(copper)
        copper = math.max(0, math.floor((copper or 0) + 0.5))
        boxes[1]:SetText(tostring(math.floor(copper / 10000)))
        boxes[2]:SetText(tostring(math.floor(copper / 100) % 100))
        boxes[3]:SetText(tostring(copper % 100))
    end
    function m:ClearFocus() for _, e in ipairs(boxes) do e:ClearFocus() end end
    return m
end

--------------------------------------------------------------------------------
-- Dropdown: items() -> { { value, text }, ... }; get() -> value; set(value).
-- Click opens the list under the button; picking, clicking elsewhere or hiding
-- the button closes it. b:Refresh() repaints the label. b.placeholder = text when
-- the current value is not in the list.
--------------------------------------------------------------------------------
local menu, catcher
local MENU_ROW = 20

local function CloseMenu()
    if menu then menu:Hide(); menu.owner = nil end
    if catcher then catcher:Hide() end
end
S.CloseMenu = CloseMenu

local function OpenMenu(owner)
    local T = S.T()
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", CloseMenu)
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
        menu:SetClampedToScreen(true)
        S.Tex(menu, "BACKGROUND", T.bg):SetAllPoints()
        S.Border(menu, T.border)
        menu.rows = {}
    end
    local items = owner.items() or {}
    local cur = owner.get()
    local widest = 0
    for i, it in ipairs(items) do
        local r = menu.rows[i]
        if not r then
            r = CreateFrame("Button", nil, menu)
            r:SetHeight(MENU_ROW)
            r.hl = S.Tex(r, "BACKGROUND", T.cardHover)
            r.hl:SetAllPoints()
            r.hl:Hide()
            r.mark = S.Tex(r, "ARTWORK", T.accent)
            r.mark:SetSize(5, 5)
            r.mark:SetPoint("LEFT", 8, 0)
            r.text = S.Text(r, 11, T.text)
            r.text:SetPoint("LEFT", 20, 0)
            r.text:SetWordWrap(false)
            r:SetScript("OnEnter", function(s) s.hl:Show() end)
            r:SetScript("OnLeave", function(s) s.hl:Hide() end)
            r:SetScript("OnClick", function(s)
                local o = menu.owner
                CloseMenu()
                if o then
                    o.set(s.value)
                    o:Refresh()
                end
            end)
            menu.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 1, -1 - (i - 1) * MENU_ROW)
        r:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * MENU_ROW)
        r.value = it[1]
        r.text:SetText(it[2])
        local on = it[1] == cur
        r.mark:SetShown(on)
        local c = on and T.accent or T.text
        r.text:SetTextColor(c[1], c[2], c[3])
        widest = math.max(widest, r.text:GetStringWidth())
        r:Show()
    end
    for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:SetSize(math.max(owner:GetWidth(), widest + 30), #items * MENU_ROW + 2)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    menu.owner = owner
    catcher:Show()
    menu:Show()
end

function S.Dropdown(parent, w, h, items, get, set)
    local T = S.T()
    local b = S.Button(parent, w, h, "")
    b.items, b.get, b.set = items, get, set
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 7, 0)
    b.label:SetPoint("RIGHT", -18, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    -- small gold chevron, drawn from two lines
    for i, side in ipairs({ -1, 1 }) do
        local l = b:CreateTexture(nil, "ARTWORK")
        l:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
        l:SetSize(5, 1.5)
        l:SetPoint("CENTER", b, "RIGHT", -10 + side * 1.6, 0)
        l:SetRotation(side * -math.pi / 4)
    end
    function b:Refresh()
        local cur = self.get()
        for _, it in ipairs(self.items() or {}) do
            if it[1] == cur then self:SetLabel(it[2]); return end
        end
        self:SetLabel(self.placeholder or "")
    end
    b:SetScript("OnClick", function(s)
        if menu and menu:IsShown() and menu.owner == s then CloseMenu() else OpenMenu(s) end
    end)
    b:HookScript("OnHide", function(s) if menu and menu.owner == s then CloseMenu() end end)
    b:Refresh()
    return b
end

-- Thin scroll bar: drag the thumb, or click the track to page. onScroll(offset).
-- sb:Update(offset, maxOffset, visibleRows, totalRows); hides itself when nothing scrolls.
function S.ScrollBar(parent, onScroll)
    local T = S.T()
    local sb = CreateFrame("Frame", nil, parent)
    sb:SetWidth(8)
    sb:EnableMouse(true)
    local track = S.Tex(sb, "BACKGROUND", T.line)
    track:SetAllPoints()
    local thumb = CreateFrame("Frame", nil, sb)
    thumb:SetWidth(8)
    thumb:EnableMouse(true)
    thumb.tex = S.Tex(thumb, "ARTWORK", { T.brand[1], T.brand[2], T.brand[3], 0.55 })
    thumb.tex:SetAllPoints()
    thumb:SetScript("OnEnter", function(t) t.tex:SetAlpha(1) end)
    thumb:SetScript("OnLeave", function(t) if not t.drag then t.tex:SetAlpha(0.55) end end)
    sb.off, sb.maxOff, sb.page = 0, 0, 1
    local function CursorY() local _, y = GetCursorPosition(); return y / sb:GetEffectiveScale() end
    function sb:Update(off, maxOff, visible, total)
        self.off, self.maxOff, self.page = off, maxOff, visible
        if maxOff <= 0 then self:Hide(); return end
        self:Show()
        local h = self:GetHeight()
        local th = math.max(24, math.floor(h * visible / total))
        self.th = th
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", self, "TOP", 0, -math.floor((h - th) * off / maxOff + 0.5))
    end
    thumb:SetScript("OnMouseDown", function(t)
        t.drag, t.y0, t.off0 = true, CursorY(), sb.off
        t:SetScript("OnUpdate", function()
            local room = sb:GetHeight() - (sb.th or 24)
            if room <= 0 then return end
            local off = math.floor(t.off0 + (t.y0 - CursorY()) / room * sb.maxOff + 0.5)
            off = math.max(0, math.min(sb.maxOff, off))
            if off ~= sb.off then onScroll(off) end
        end)
    end)
    thumb:SetScript("OnMouseUp", function(t)
        t.drag = nil
        t:SetScript("OnUpdate", nil)
        t.tex:SetAlpha(t:IsMouseOver() and 1 or 0.55)
    end)
    sb:SetScript("OnMouseDown", function()
        -- page toward where the track was clicked
        local top = thumb:GetTop() or 0
        local dir = CursorY() > top and -1 or 1
        onScroll(math.max(0, math.min(sb.maxOff, sb.off + dir * sb.page)))
    end)
    return sb
end
