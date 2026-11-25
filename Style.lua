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

local WHITE = "Interface\\Buttons\\WHITE8x8"
local LOGO = "Interface\\AddOns\\CysGuildHall\\Media\\Logo"
S.LOGO = LOGO

-- 1.2.0 palette: near-black panels, a muted gold edge, bright gold only where it matters
local OWN = {
    bg = Hex("0E0D0C", 0.97), header = Hex("161411"), field = Hex("0A0A09", 0.92), card = Hex("0C0B0A", 0.92),
    cardHover = Hex("D9A421", 0.07), button = Hex("1A1815"), selected = Hex("D9A421", 0.13), line = Hex("2A2621"),
    border = Hex("D9A421", 0.42), brand = Hex("E0AE2C"), glow = Hex("F5CB55"), accent = Hex("F0C24A"),
    text = Hex("EDEAE4"), dim = Hex("8C8882"), green = Hex("58D873"), danger = Hex("FF5A4E"), edge = Hex("000000"),
}

-- Fully standalone. If Cys's UI is loaded, only its theme color is borrowed so the gold matches.
local themed
function S.T()
    if themed then return OWN end
    themed = true
    local W = CysUI and CysUI.W
    local b = W and W.T and W.T.brand
    if b and b[1] then
        OWN.brand = { b[1], b[2], b[3], 1 }
        OWN.border = { b[1], b[2], b[3], 0.42 }
        OWN.cardHover = { b[1], b[2], b[3], 0.07 }
        OWN.selected = { b[1], b[2], b[3], 0.13 }
    end
    return OWN
end

--------------------------------------------------------------------------------
-- Fonts: Clean (Arial Narrow, sharp at small sizes) or Classic (Friz Quadrata).
-- Titles (14+) always use Friz for the Guild Hall character. Options > Text font.
--------------------------------------------------------------------------------
local CLEAN = "Fonts\\ARIALN.TTF"
function S.Clean()
    local db = GH.db
    return not (db and db.settings and db.settings.font == "classic")
end
function S.F() return S.Clean() and CLEAN or STANDARD_TEXT_FONT end
function S.SetFont(fs, size, flags)
    size = size or 12
    if size >= 14 then
        fs:SetFont(STANDARD_TEXT_FONT, size, flags or "")
    elseif S.Clean() then
        fs:SetFont(CLEAN, size + 1, flags or "")
    else
        fs:SetFont(STANDARD_TEXT_FONT, size, flags or "")
    end
end

function S.Tex(parent, layer, color, sublevel)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return t
end

-- Vertical gradient on a texture (top -> bottom); quietly skipped on clients without it
local function Grad(t, top, bottom)
    if not (t.SetGradient and CreateColor) then return end
    pcall(t.SetGradient, t, "VERTICAL", CreateColor(bottom[1], bottom[2], bottom[3], bottom[4] or 1),
        CreateColor(top[1], top[2], top[3], top[4] or 1))
end
local function HGrad(t, left, right)
    if not (t.SetGradient and CreateColor) then return end
    pcall(t.SetGradient, t, "HORIZONTAL", CreateColor(left[1], left[2], left[3], left[4] or 1),
        CreateColor(right[1], right[2], right[3], right[4] or 1))
end
S.Grad, S.HGrad = Grad, HGrad

-- 1px edge, inset px inside the parent (default 0)
function S.Border(parent, color, layer, inset)
    local e = {}
    local i = inset or 0
    for k = 1, 4 do e[k] = S.Tex(parent, layer or "BORDER", color) end
    e[1]:SetPoint("TOPLEFT", i, -i);    e[1]:SetPoint("TOPRIGHT", -i, -i);    e[1]:SetHeight(1)
    e[2]:SetPoint("BOTTOMLEFT", i, i);  e[2]:SetPoint("BOTTOMRIGHT", -i, i);  e[2]:SetHeight(1)
    e[3]:SetPoint("TOPLEFT", i, -i);    e[3]:SetPoint("BOTTOMLEFT", i, i);    e[3]:SetWidth(1)
    e[4]:SetPoint("TOPRIGHT", -i, -i);  e[4]:SetPoint("BOTTOMRIGHT", -i, i);  e[4]:SetWidth(1)
    return e
end

function S.SetBorder(edges, color)
    for i = 1, #edges do edges[i]:SetColorTexture(color[1], color[2], color[3], color[4] or 1) end
end

-- Soft drop shadow just outside a frame
function S.Shadow(f, size)
    for i = 1, (size or 5) do
        local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetColorTexture(0, 0, 0, 0.13)
        t:SetPoint("TOPLEFT", -i, i)
        t:SetPoint("BOTTOMRIGHT", i, -i)
    end
end

-- Window chrome: shadow, dark fill with a faint top sheen, black outer line, muted gold inner line
function S.Chrome(f, color)
    local T = S.T()
    S.Shadow(f)
    local bg = S.Tex(f, "BACKGROUND", color or T.bg, -7)
    bg:SetAllPoints()
    local sheen = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    sheen:SetTexture(WHITE)
    sheen:SetPoint("TOPLEFT", 2, -2)
    sheen:SetPoint("TOPRIGHT", -2, -2)
    sheen:SetHeight(90)
    Grad(sheen, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0 })
    f.edgeOuter = S.Border(f, T.edge, "BORDER")
    f.edgeInner = S.Border(f, T.border, "BORDER", 1)
    return bg
end

-- Header strip: slightly lifted fill and a gold hairline underneath that fades at both ends
function S.HeaderBg(h)
    local T = S.T()
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 0)
    Grad(bg, { T.header[1] * 1.25, T.header[2] * 1.25, T.header[3] * 1.25, 1 }, T.header)
    local b = T.brand
    local l = h:CreateTexture(nil, "ARTWORK")
    l:SetTexture(WHITE)
    l:SetHeight(1)
    l:SetPoint("BOTTOMLEFT", 1, 0)
    l:SetPoint("BOTTOMRIGHT", h, "BOTTOM", 0, 0)
    HGrad(l, { b[1], b[2], b[3], 0.05 }, { b[1], b[2], b[3], 0.6 })
    local r = h:CreateTexture(nil, "ARTWORK")
    r:SetTexture(WHITE)
    r:SetHeight(1)
    r:SetPoint("BOTTOMLEFT", h, "BOTTOM", 0, 0)
    r:SetPoint("BOTTOMRIGHT", -1, 0)
    HGrad(r, { b[1], b[2], b[3], 0.6 }, { b[1], b[2], b[3], 0.05 })
    return bg
end

-- The Guild Hall seal, for headers
function S.Emblem(parent, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(LOGO)
    t:SetSize(size or 22, size or 22)
    return t
end

-- Big faint seal behind an empty detail panel
function S.Watermark(panel, size)
    local t = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
    t:SetTexture(LOGO)
    t:SetSize(size or 150, size or 150)
    t:SetPoint("CENTER")
    t:SetAlpha(0.035)
    t:SetDesaturated(true)
    return t
end

function S.Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    S.SetFont(fs, size or 12)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    if color then fs:SetTextColor(color[1], color[2], color[3], color[4] or 1) end
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- Section heading: gold label with a short gold tick to its left
function S.Heading(parent, text)
    local T = S.T()
    local fs = S.Text(parent, 12, T.accent)
    fs:SetText(text or "")
    local bar = parent:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(T.brand[1], T.brand[2], T.brand[3], 0.9)
    bar:SetSize(2, 11)
    bar:SetPoint("RIGHT", fs, "LEFT", -5, 0)
    fs.bar = bar
    local set = fs.SetText
    fs.SetText = function(self, t) set(self, t); bar:SetShown(t ~= nil and t ~= "") end
    fs:SetText(text or "")
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

-- Selected-row fill with a gold bar on the left edge; shows and hides as one texture
function S.Selection(row)
    local T = S.T()
    local t = S.Tex(row, "BACKGROUND", T.selected, 1)
    t:SetAllPoints()
    local bar = S.Tex(row, "ARTWORK", T.brand, 2)
    bar:SetWidth(2)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:Hide()
    local show, hide, shown = t.Show, t.Hide, t.SetShown
    t.Show = function(s) show(s); bar:Show() end
    t.Hide = function(s) hide(s); bar:Hide() end
    t.SetShown = function(s, v) shown(s, v); bar:SetShown(v and true or false) end
    return t
end

function S.Button(parent, w, h, label)
    local T = S.T()
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = S.Tex(b, "BACKGROUND", T.button)
    b.bg:SetAllPoints()
    local sheen = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    sheen:SetTexture(WHITE)
    sheen:SetPoint("TOPLEFT", 1, -1)
    sheen:SetPoint("BOTTOMRIGHT", -1, 1)
    Grad(sheen, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0 })
    b.hover = S.Tex(b, "BACKGROUND", { T.brand[1], T.brand[2], T.brand[3], 0.09 }, 2)
    b.hover:SetAllPoints()
    b.hover:Hide()
    b.edges = S.Border(b, T.line)
    b.label = S.Text(b, 11, T.accent, "CENTER")
    b.label:SetPoint("CENTER")
    b.label:SetText(label or "")
    local edgeOn = { T.brand[1], T.brand[2], T.brand[3], 0.75 }
    b:SetScript("OnEnter", function(s) if s:IsEnabled() then S.SetBorder(s.edges, edgeOn); s.hover:Show() end end)
    b:SetScript("OnLeave", function(s) S.SetBorder(s.edges, T.line); s.hover:Hide() end)
    -- pressed: nudge a centered label (left-aligned labels, like dropdowns, stay put)
    b:SetScript("OnMouseDown", function(s)
        if s:IsEnabled() and s.label:GetNumPoints() == 1 and select(3, s.label:GetPoint(1)) == "CENTER" then s.label:SetPoint("CENTER", 1, -1) end
    end)
    b:SetScript("OnMouseUp", function(s)
        if s.label:GetNumPoints() == 1 and select(3, s.label:GetPoint(1)) == "CENTER" then s.label:SetPoint("CENTER", 0, 0) end
    end)
    function b:SetActive(on)
        if on then self:Enable(); self:SetAlpha(1) else self:Disable(); self:SetAlpha(0.4); S.SetBorder(self.edges, T.line); self.hover:Hide() end
    end
    function b:SetLabel(text) self.label:SetText(text or "") end
    return b
end

-- Close button: a thin drawn X, red on hover
function S.Close(parent, size)
    local T = S.T()
    local b = CreateFrame("Button", nil, parent)
    size = size or 22
    b:SetSize(size, size)
    b.edges = {}
    b.lines = {}
    for i, rot in ipairs({ math.pi / 4, -math.pi / 4 }) do
        local l = b:CreateTexture(nil, "ARTWORK")
        l:SetTexture(WHITE)
        l:SetSize(math.floor(size * 0.55), 1.5)
        l:SetPoint("CENTER")
        l:SetRotation(rot)
        l:SetVertexColor(T.dim[1], T.dim[2], T.dim[3])
        b.lines[i] = l
    end
    b.hover = S.Tex(b, "BACKGROUND", { T.danger[1], T.danger[2], T.danger[3], 0.12 })
    b.hover:SetAllPoints()
    b.hover:Hide()
    local function Paint(c) for _, l in ipairs(b.lines) do l:SetVertexColor(c[1], c[2], c[3]) end end
    b:SetScript("OnEnter", function(s) if s:IsEnabled() then Paint(T.danger); s.hover:Show() end end)
    b:SetScript("OnLeave", function(s) Paint(T.dim); s.hover:Hide() end)
    b.label = S.Text(b, 11, T.text, "CENTER") -- unused, kept so :SetLabel callers don't break
    function b:SetActive(on)
        if on then self:Enable(); self:SetAlpha(1) else self:Disable(); self:SetAlpha(0.4) end
    end
    function b:SetLabel() end
    return b
end

-- Header tab: text with a gold underline when selected. Sizes itself to its text.
function S.Tab(parent, label)
    local T = S.T()
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(parent:GetHeight() > 0 and parent:GetHeight() or 30)
    b.label = S.Text(b, 12, T.dim, "CENTER")
    b.label:SetPoint("CENTER", 0, 0)
    b.hover = S.Tex(b, "BACKGROUND", { 1, 1, 1, 0.03 })
    b.hover:SetPoint("TOPLEFT", 0, -1)
    b.hover:SetPoint("BOTTOMRIGHT", 0, 1)
    b.hover:Hide()
    b.under = S.Tex(b, "OVERLAY", T.glow)
    b.under:SetHeight(2)
    b.under:SetPoint("BOTTOMLEFT", 6, 0)
    b.under:SetPoint("BOTTOMRIGHT", -6, 0)
    b.under:Hide()
    b.bg = b.hover -- older callers recolor .bg; harmless
    local function Color(s)
        local c = s.on and T.glow or (s:IsMouseOver() and T.text or T.dim)
        s.label:SetTextColor(c[1], c[2], c[3])
    end
    b:SetScript("OnEnter", function(s) s.hover:Show(); Color(s) end)
    b:SetScript("OnLeave", function(s) s.hover:Hide(); Color(s) end)
    function b:SetLabel(text)
        self.label:SetText(text or "")
        self:SetWidth(math.ceil(self.label:GetStringWidth()) + 22)
    end
    function b:SetSelected(on)
        self.on = on and true or false
        self.under:SetShown(self.on)
        Color(self)
    end
    function b:SetActive(on)
        if on then self:Enable(); self:SetAlpha(1) else self:Disable(); self:SetAlpha(0.4) end
    end
    b:SetLabel(label)
    b:SetSelected(false)
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
    c.edges = S.Border(box, T.line)
    c.fill = S.Tex(box, "BACKGROUND", { T.brand[1], T.brand[2], T.brand[3], 0.16 }, 1)
    c.fill:SetPoint("TOPLEFT", 1, -1)
    c.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    c.mark = box:CreateTexture(nil, "ARTWORK")
    c.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    c.mark:SetSize(20, 20)
    c.mark:SetPoint("CENTER", 1, 1)
    c.mark:SetVertexColor(T.glow[1], T.glow[2], T.glow[3])
    c.label = S.Text(c, 11, T.text)
    c.label:SetPoint("LEFT", box, "RIGHT", 6, 0)
    c.label:SetText(label)
    c:SetWidth(22 + c.label:GetStringWidth())
    function c:Refresh()
        local on = get() and true or false
        self.mark:SetShown(on)
        self.fill:SetShown(on)
    end
    c:SetScript("OnClick", function(s) set(not get()); s:Refresh() end)
    c:SetScript("OnEnter", function(s) S.SetBorder(s.edges, { T.brand[1], T.brand[2], T.brand[3], 0.8 }); s.label:SetTextColor(1, 1, 1) end)
    c:SetScript("OnLeave", function(s) S.SetBorder(s.edges, T.line); s.label:SetTextColor(T.text[1], T.text[2], T.text[3]) end)
    c:Refresh()
    return c
end

-- Search box with a dark field and gold edge on focus
function S.EditBox(parent, w, h)
    local T = S.T()
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, h)
    e:SetAutoFocus(false)
    S.SetFont(e, 12)
    e:SetTextColor(T.text[1], T.text[2], T.text[3])
    e:SetTextInsets(6, 6, 0, 0)
    S.Tex(e, "BACKGROUND", T.field):SetAllPoints()
    e.edges = S.Border(e, T.line)
    e:SetScript("OnEditFocusGained", function(s) S.SetBorder(s.edges, { T.brand[1], T.brand[2], T.brand[3], 0.8 }) end)
    e:SetScript("OnEditFocusLost", function(s) S.SetBorder(s.edges, T.line) end)
    e:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    e.hint = S.Text(e, 11, T.dim)
    e.hint:SetPoint("LEFT", 7, 0)
    -- search boxes: a magnifier on the left, text and hint moved past it
    function e:SetSearch()
        local icon = self:CreateTexture(nil, "OVERLAY")
        icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
        icon:SetSize(13, 13)
        icon:SetPoint("LEFT", 6, -1)
        icon:SetVertexColor(T.dim[1], T.dim[2], T.dim[3])
        self:SetTextInsets(22, 6, 0, 0)
        self.hint:SetPoint("LEFT", 23, 0)
        self:HookScript("OnEditFocusGained", function() icon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3]) end)
        self:HookScript("OnEditFocusLost", function() icon:SetVertexColor(T.dim[1], T.dim[2], T.dim[3]) end)
        return self
    end
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
        S.Chrome(menu, { 0.07, 0.065, 0.06, 0.98 })
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
            r.mark = S.Tex(r, "ARTWORK", T.brand)
            r.mark:SetWidth(2)
            r.mark:SetPoint("TOPLEFT", 1, -3)
            r.mark:SetPoint("BOTTOMLEFT", 1, 3)
            r.text = S.Text(r, 11, T.text)
            r.text:SetPoint("LEFT", 12, 0)
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
        r:SetPoint("TOPLEFT", 2, -3 - (i - 1) * MENU_ROW)
        r:SetPoint("TOPRIGHT", -2, -3 - (i - 1) * MENU_ROW)
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
    menu:SetSize(math.max(owner:GetWidth(), widest + 28), #items * MENU_ROW + 6)
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
    b.label:SetTextColor(T.text[1], T.text[2], T.text[3])
    for _, side in ipairs({ -1, 1 }) do
        local l = b:CreateTexture(nil, "ARTWORK")
        l:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
        l:SetSize(6, 1.5)
        l:SetPoint("CENTER", b, "RIGHT", -10 + side * 2, -1)
        l:SetRotation(side * math.pi / 4)
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
    local track = S.Tex(sb, "BACKGROUND", { 1, 1, 1, 0.04 })
    track:SetPoint("TOP")
    track:SetPoint("BOTTOM")
    track:SetWidth(2)
    local thumb = CreateFrame("Frame", nil, sb)
    thumb:SetWidth(8)
    thumb:EnableMouse(true)
    thumb.tex = S.Tex(thumb, "ARTWORK", { T.brand[1], T.brand[2], T.brand[3], 0.55 })
    thumb.tex:SetPoint("TOP")
    thumb.tex:SetPoint("BOTTOM")
    thumb.tex:SetWidth(4)
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
