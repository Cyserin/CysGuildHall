--------------------------------------------------------------------------------
-- Cys's Guild Hall - search index + main window
--------------------------------------------------------------------------------
local GH = CysGuildHall
local S = GH.Style

--------------------------------------------------------------------------------
-- Index: recipe -> crafters, item -> recipes, profession summaries
--------------------------------------------------------------------------------
local I = {}
GH.Index = I

local dirty = true
local byRecipe, byItem, profs = {}, {}, {}
local unresolved, tried = {}, {}
local working = false

GH.Listen("DATA", function() dirty = true end)
GH.Listen("GUILD", function() dirty = true end)

local Work
function Work()
    if #unresolved == 0 then working = false; return end
    working = true
    local stop = debugprofilestop() + 3
    local got = false
    while #unresolved > 0 do
        local id = table.remove(unresolved)
        local c = GH.Prof.Resolve(id)
        if c and (c.o or c.n) then got = true end
        if debugprofilestop() > stop then break end
    end
    if got then dirty = true end
    if #unresolved > 0 then
        C_Timer.After(0, Work)
    else
        working = false
        GH.Fire("INDEX")
    end
end

function I.Build()
    if not dirty then return end
    dirty = false
    wipe(byRecipe); wipe(byItem); wipe(profs)
    local g = GH.Guild()
    if not g or not GH.db then return end
    for name, m in pairs(g.members) do
        for pid, p in pairs(m.profs or {}) do
            local pr = profs[pid]
            if not pr then
                pr = { pid = pid, crafters = 0, best = 0, max = 0, recipes = {} }
                profs[pid] = pr
            end
            pr.crafters = pr.crafters + 1
            if (p.s or 0) > pr.best then pr.best, pr.max = p.s or 0, p.m or 0 end
            for _, id in ipairs(p.r or {}) do
                pr.recipes[id] = true
                local list = byRecipe[id]
                if not list then list = {}; byRecipe[id] = list end
                list[#list + 1] = { name = name, s = p.s or 0, m = p.m or 0, pid = pid }
            end
        end
    end
    for id in pairs(byRecipe) do
        local c = GH.db.recipes[id]
        if c and c.o then
            local l = byItem[c.o]
            if not l then l = {}; byItem[c.o] = l end
            l[#l + 1] = id
        elseif not c and not tried[id] then
            tried[id] = true
            unresolved[#unresolved + 1] = id
        end
    end
    if #unresolved > 0 and not working then C_Timer.After(0, Work) end
end

local function SortCrafters(list)
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.s ~= b.s then return a.s > b.s end
        return a.name < b.name
    end)
    return list
end

-- crafters of a recipe, online first
function I.Crafters(recipeID)
    I.Build()
    local out = {}
    for _, c in ipairs(byRecipe[recipeID] or {}) do
        out[#out + 1] = { name = c.name, s = c.s, m = c.m, pid = c.pid, online = GH.IsOnline(c.name) or false }
    end
    return SortCrafters(out)
end

-- crafters of an item (any recipe that makes it), one line per person
function I.CraftersOfItem(itemID)
    I.Build()
    local recipes = byItem[itemID]
    if not recipes then return nil end
    local seen, out = {}, {}
    for _, rid in ipairs(recipes) do
        for _, c in ipairs(byRecipe[rid] or {}) do
            if not seen[c.name] then
                seen[c.name] = true
                out[#out + 1] = { name = c.name, s = c.s, m = c.m, pid = c.pid, online = GH.IsOnline(c.name) or false }
            end
        end
    end
    return SortCrafters(out)
end

function I.RecipeName(id)
    local c = GH.db.recipes[id]
    if c and c.o then
        local n = GH.Prof.ItemName(c.o)
        if n then return n end
    end
    return (c and c.n) or ("Recipe " .. id)
end

local function OnlineCount(list)
    local n = 0
    for _, c in ipairs(list) do if GH.IsOnline(c.name) then n = n + 1 end end
    return n
end

-- Search results: { kind = "recipe", id, name, crafters, online } sorted by name
function I.Search(query, pid)
    I.Build()
    local q = query and query:lower() or ""
    local out = {}
    for id, list in pairs(byRecipe) do
        local inProf = not pid
        if pid then
            for _, c in ipairs(list) do if c.pid == pid then inProf = true; break end end
        end
        if inProf then
            local name = I.RecipeName(id)
            local c = GH.db.recipes[id]
            local alt = c and c.n
            if q == "" or name:lower():find(q, 1, true) or (alt and alt:lower():find(q, 1, true)) then
                out[#out + 1] = { kind = "recipe", id = id, name = name, crafters = #list, online = OnlineCount(list) }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

function I.Professions()
    I.Build()
    local out = {}
    for pid, p in pairs(profs) do
        local n = 0
        for _ in pairs(p.recipes) do n = n + 1 end
        out[#out + 1] = { kind = "prof", pid = pid, name = GH.ProfName(pid), crafters = p.crafters, best = p.best, max = p.max, recipes = n }
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.pid < b.pid
    end)
    return out
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local W = {}
GH.Window = W

local WIDTH, HEIGHT = 700, 470
local LIST_W = 300
local ROW_H = 22
local ROWS = 16
local CRAFTER_ROWS = 6
local REAGENT_ROWS = 8

local frame
local state = { query = "", prof = nil, results = {}, offset = 0, selected = nil, make = 1 }

local function ItemTip(owner, itemID)
    if not itemID then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    GameTooltip:Show()
end

local function QualityColor(itemID)
    local q = itemID and C_Item.GetItemQualityByID(itemID)
    if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        local c = ITEM_QUALITY_COLORS[q]
        return c.r, c.g, c.b
    end
    return 0.88, 0.88, 0.88
end

local function Icon(itemID, recipeID)
    if itemID then
        local tex = C_Item.GetItemIconByID(itemID)
        if tex then return tex end
    end
    if recipeID and C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(recipeID)
        if tex then return tex end
    end
    return 134400 -- question mark
end

--------------------------------------------------------------------------------
-- List (left)
--------------------------------------------------------------------------------
local Paint, PaintDetail

local function Rebuild()
    if not frame then return end
    local list = {}
    if state.query == "" and not state.prof then
        list = I.Professions()
    else
        if state.prof then list[1] = { kind = "back" } end
        for _, r in ipairs(I.Search(state.query, state.prof)) do list[#list + 1] = r end
    end
    state.results = list
    local maxOff = math.max(0, #list - ROWS)
    if state.offset > maxOff then state.offset = maxOff end
    Paint()
end

local function SetQuery(text)
    state.query = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    state.offset = 0
    Rebuild()
end

local function ClickRow(row)
    local d = row.data
    if not d then return end
    if d.kind == "prof" then
        state.prof = d.pid
        state.offset = 0
        frame.search.hint:SetText("Search " .. d.name .. "...")
        Rebuild()
    elseif d.kind == "back" then
        state.prof = nil
        state.offset = 0
        frame.search.hint:SetText("Search items or recipes...")
        Rebuild()
    else
        state.selected = d.id
        state.make = 1
        Paint()
    end
end

function Paint()
    if not frame or not frame:IsShown() then return end
    local T = S.T()
    local list = state.results
    for i = 1, ROWS do
        local row = frame.rows[i]
        local d = list[state.offset + i]
        row.data = d
        if d then
            row:Show()
            row.sel:SetShown(d.kind == "recipe" and d.id == state.selected)
            if d.kind == "prof" then
                row.icon:Hide()
                row.text:SetPoint("LEFT", 8, 0)
                row.text:SetText(d.name)
                row.text:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
                row.right:SetText(("%d %s, best %d"):format(d.crafters, d.crafters == 1 and "crafter" or "crafters", d.best))
            elseif d.kind == "back" then
                row.icon:Hide()
                row.text:SetPoint("LEFT", 8, 0)
                row.text:SetText("< All professions")
                row.text:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
                row.right:SetText(GH.ProfName(state.prof))
            else
                local c = GH.db.recipes[d.id]
                row.icon:Show()
                row.icon:SetTexture(Icon(c and c.o, d.id))
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetText(d.name)
                row.text:SetTextColor(QualityColor(c and c.o))
                if d.online > 0 then
                    row.right:SetText(("|cff4fd66b%d on|r / %d"):format(d.online, d.crafters))
                else
                    row.right:SetText(("|cff8a8a8a%d|r"):format(d.crafters))
                end
            end
        else
            row:Hide()
        end
    end
    -- scroll thumb
    local n = #list
    if n > ROWS then
        local track = frame.track
        local h = track:GetHeight()
        local th = math.max(20, h * ROWS / n)
        frame.thumb:SetHeight(th)
        frame.thumb:ClearAllPoints()
        frame.thumb:SetPoint("TOP", track, "TOP", 0, -((h - th) * state.offset / (n - ROWS)))
        frame.thumb:Show()
    else
        frame.thumb:Hide()
    end
    -- empty states
    local g = GH.Guild()
    if not g then
        frame.empty:SetText("You are not in a guild.")
    elseif n == 0 and state.query == "" then
        frame.empty:SetText("No crafters yet.\n\nOpen each of your profession windows once so the addon can read your recipes. Guildmates who run Cys's Guild Hall show up here as they log in.")
    elseif n == 0 then
        frame.empty:SetText("Nobody in the guild can make that yet.")
    else
        frame.empty:SetText("")
    end
    frame.count:SetText(n > 0 and state.query ~= "" and ("%d found"):format(n - (state.prof and 1 or 0)) or "")
    PaintDetail()
end

--------------------------------------------------------------------------------
-- Detail (right)
--------------------------------------------------------------------------------
function PaintDetail()
    local T = S.T()
    local d = frame.detail
    local id = state.selected
    if not id then
        d.box:Hide()
        d.hint:Show()
        return
    end
    d.hint:Hide()
    d.box:Show()
    local c = GH.Prof.Resolve(id) or {}
    d.icon:SetTexture(Icon(c.o, id))
    d.icon.itemID = c.o
    d.name:SetText(I.RecipeName(id))
    d.name:SetTextColor(QualityColor(c.o))
    local crafters = I.Crafters(id)
    local pid = c.p or (crafters[1] and crafters[1].pid)
    local sub = pid and GH.ProfName(pid) or ""
    if (c.q or 1) > 1 then sub = sub .. ("  -  makes %d"):format(c.q) end
    d.sub:SetText(sub)

    -- crafters
    for i = 1, CRAFTER_ROWS do
        local r = d.crafters[i]
        local cr = crafters[i]
        if cr then
            r:Show()
            r.dot:SetColorTexture(cr.online and T.green[1] or 0.35, cr.online and T.green[2] or 0.35, cr.online and T.green[3] or 0.35)
            local cr_r, cr_g, cr_b = GH.ClassColor(cr.name)
            if not cr.online then cr_r, cr_g, cr_b = 0.55, 0.55, 0.55 end
            r.text:SetText(GH.Short(cr.name))
            r.text:SetTextColor(cr_r, cr_g, cr_b)
            r.right:SetText(cr.m > 0 and ("%d / %d"):format(cr.s, cr.m) or tostring(cr.s))
        else
            r:Hide()
        end
    end
    if #crafters > CRAFTER_ROWS then
        d.more:SetText(("+%d more"):format(#crafters - CRAFTER_ROWS))
    else
        d.more:SetText("")
    end

    -- reagents: have (bags + bank) / need
    local make = state.make
    d.makeValue:SetText(tostring(make))
    local reagents = c.r or {}
    local missing = 0
    for i = 1, REAGENT_ROWS do
        local r = d.reagents[i]
        local rg = reagents[i]
        if rg then
            r:Show()
            local rid, per = rg[1], rg[2]
            local need = per * make
            local have = C_Item.GetItemCount(rid, true) or 0
            r.icon:SetTexture(Icon(rid))
            r.itemID = rid
            r.text:SetText(GH.Prof.ItemName(rid) or ("Item " .. rid))
            r.text:SetTextColor(QualityColor(rid))
            if have >= need then
                r.right:SetText(("|cff4fd66b%d|r / %d"):format(have, need))
            else
                r.right:SetText(("|cffff4040%d|r / %d"):format(have, need))
                missing = missing + 1
            end
        else
            r:Hide()
        end
    end
    if #reagents == 0 then
        d.status:SetText((c.o or c.n) and "No reagents known for this recipe." or "Recipe details not available yet.")
        d.status:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
    elseif missing == 0 then
        d.status:SetText("You have everything for this (bags + bank).")
        d.status:SetTextColor(T.green[1], T.green[2], T.green[3])
    else
        d.status:SetText(("Missing %d of %d reagents."):format(missing, #reagents))
        d.status:SetTextColor(T.danger[1], T.danger[2], T.danger[3])
    end
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------
local function Label(parent, text)
    local T = S.T()
    local fs = S.Text(parent, 11, T.accent)
    fs:SetText(text)
    return fs
end

local function Build()
    local T = S.T()
    frame = CreateFrame("Frame", "CysGuildHallFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local p, _, _, x, y = f:GetPoint()
        GH.db.settings.pos = { p, x, y }
    end)
    local pos = GH.db.settings.pos
    if pos then frame:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else frame:SetPoint("CENTER", 0, 40) end

    S.Tex(frame, "BACKGROUND", T.bg):SetAllPoints()
    S.Border(frame, T.border)

    -- header
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(30)
    S.Tex(header, "BACKGROUND", T.header):SetAllPoints()
    local title = S.Text(header, 14, T.brand)
    title:SetPoint("LEFT", 10, 0)
    title:SetText("Cys's Guild Hall")
    frame.guild = S.Text(header, 11, T.dim)
    frame.guild:SetPoint("LEFT", title, "RIGHT", 10, -1)
    local close = S.Button(header, 22, 22, "x")
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- search
    local search = S.EditBox(frame, LIST_W, 24)
    search:SetPoint("TOPLEFT", 10, -40)
    search.hint:SetText("Search items or recipes...")
    search:SetScript("OnTextChanged", function(e)
        e.hint:SetShown(e:GetText() == "")
        SetQuery(e:GetText())
    end)
    search:SetScript("OnEscapePressed", function(e)
        if e:GetText() ~= "" then e:SetText("") else e:ClearFocus(); frame:Hide() end
    end)
    frame.search = search
    frame.count = S.Text(frame, 10, T.dim, "RIGHT")
    frame.count:SetPoint("RIGHT", search, "RIGHT", -6, 0)

    -- list
    local listBox = S.Panel(frame, T.field)
    listBox:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
    listBox:SetSize(LIST_W, ROWS * ROW_H + 4)
    listBox:EnableMouseWheel(true)
    listBox:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #state.results - ROWS)
        state.offset = math.min(maxOff, math.max(0, state.offset - delta * 3))
        Paint()
    end)
    frame.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, listBox)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", -8, -2 - (i - 1) * ROW_H)
        row.hl = S.Tex(row, "BACKGROUND", T.cardHover)
        row.hl:SetAllPoints()
        row.hl:Hide()
        row.sel = S.Tex(row, "BACKGROUND", T.selected, 1)
        row.sel:SetAllPoints()
        row.sel:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.right = S.Text(row, 10, T.dim, "RIGHT")
        row.right:SetPoint("RIGHT", -4, 0)
        row.text = S.Text(row, 12, T.text)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", ClickRow)
        row:SetScript("OnEnter", function(r)
            r.hl:Show()
            local dd = r.data
            if dd and dd.kind == "recipe" then
                local c = GH.db.recipes[dd.id]
                if c and c.o then ItemTip(r, c.o) end
            end
        end)
        row:SetScript("OnLeave", function(r) r.hl:Hide(); GameTooltip:Hide() end)
        frame.rows[i] = row
    end
    frame.track = CreateFrame("Frame", nil, listBox)
    frame.track:SetPoint("TOPRIGHT", -2, -2)
    frame.track:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.track:SetWidth(4)
    frame.thumb = S.Tex(frame.track, "ARTWORK", T.line)
    frame.thumb:SetWidth(4)
    frame.empty = S.Text(listBox, 11, T.dim, "CENTER")
    frame.empty:SetPoint("CENTER")
    frame.empty:SetWidth(LIST_W - 20)

    -- detail
    local d = {}
    frame.detail = d
    local box = S.Panel(frame, T.card)
    box:SetPoint("TOPLEFT", search, "TOPRIGHT", 10, 0)
    box:SetPoint("BOTTOMRIGHT", -10, 10)
    d.hint = S.Text(frame, 12, T.dim, "CENTER")
    d.hint:SetPoint("CENTER", box, "CENTER")
    d.hint:SetWidth(320)
    d.hint:SetText("Search for an item, or pick a profession,\nto see who in the guild can make it.")
    local inner = CreateFrame("Frame", nil, box)
    inner:SetAllPoints()
    d.box = inner

    local icon = CreateFrame("Button", nil, inner)
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", 12, -12)
    d.icon = icon:CreateTexture(nil, "ARTWORK")
    d.icon:SetAllPoints()
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    S.Border(icon, T.line)
    icon:SetScript("OnEnter", function(b) ItemTip(b, d.icon.itemID) end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.name = S.Text(inner, 14, T.text)
    d.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    d.name:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
    d.name:SetWordWrap(false)
    d.sub = S.Text(inner, 11, T.dim)
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)

    local cLabel = Label(inner, "Can make it")
    cLabel:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -14)
    d.crafters = {}
    for i = 1, CRAFTER_ROWS do
        local r = CreateFrame("Frame", nil, inner)
        r:SetHeight(18)
        r:SetPoint("TOPLEFT", cLabel, "BOTTOMLEFT", 0, -4 - (i - 1) * 18)
        r:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(7, 7)
        r.dot:SetPoint("LEFT", 2, 0)
        r.text = S.Text(r, 12, T.text)
        r.text:SetPoint("LEFT", r.dot, "RIGHT", 8, 0)
        r.right = S.Text(r, 11, T.dim, "RIGHT")
        r.right:SetPoint("RIGHT")
        d.crafters[i] = r
    end
    d.more = S.Text(inner, 10, T.dim)
    d.more:SetPoint("TOPLEFT", cLabel, "BOTTOMLEFT", 17, -6 - CRAFTER_ROWS * 18)

    local rLabel = Label(inner, "Reagents")
    rLabel:SetPoint("TOPLEFT", cLabel, "BOTTOMLEFT", 0, -22 - CRAFTER_ROWS * 18)
    -- how many to make
    local plus = S.Button(inner, 18, 18, "+")
    plus:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
    plus:SetPoint("TOP", rLabel, "TOP", 0, 3)
    d.makeValue = S.Text(inner, 11, T.accent, "CENTER")
    d.makeValue:SetWidth(28)
    d.makeValue:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    local minus = S.Button(inner, 18, 18, "-")
    minus:SetPoint("RIGHT", d.makeValue, "LEFT", -2, 0)
    local makeLabel = S.Text(inner, 11, T.dim, "RIGHT")
    makeLabel:SetPoint("RIGHT", minus, "LEFT", -6, 0)
    makeLabel:SetText("Make")
    plus:SetScript("OnClick", function() state.make = math.min(99, state.make + 1); PaintDetail() end)
    minus:SetScript("OnClick", function() state.make = math.max(1, state.make - 1); PaintDetail() end)

    local field = S.Panel(inner, T.field)
    field:SetPoint("TOPLEFT", rLabel, "BOTTOMLEFT", 0, -6)
    field:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
    field:SetHeight(REAGENT_ROWS * 20 + 8)
    d.reagents = {}
    for i = 1, REAGENT_ROWS do
        local r = CreateFrame("Button", nil, field)
        r:SetHeight(20)
        r:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 20)
        r:SetPoint("RIGHT", field, "RIGHT", -8, 0)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT")
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.right = S.Text(r, 11, T.text, "RIGHT")
        r.right:SetPoint("RIGHT")
        r.text = S.Text(r, 12, T.text)
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
        r.text:SetWordWrap(false)
        r:SetScript("OnEnter", function(b) ItemTip(b, b.itemID) end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d.reagents[i] = r
    end
    d.status = S.Text(inner, 11, T.text)
    d.status:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -6)
    d.status:SetPoint("RIGHT", field, "RIGHT", 0, 0)

    frame:SetScript("OnShow", function()
        local key = GH.GuildKey()
        frame.guild:SetText(key and (GetGuildInfo("player") or "") or "")
        if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        Rebuild()
    end)
    frame:SetScript("OnHide", function() GameTooltip:Hide() end)
    frame:Hide()
end

--------------------------------------------------------------------------------
-- Refresh when data changes (batched)
--------------------------------------------------------------------------------
local refreshTimer
local function RefreshSoon()
    if not frame or not frame:IsShown() or refreshTimer then return end
    refreshTimer = C_Timer.NewTimer(0.3, function()
        refreshTimer = nil
        Rebuild()
    end)
end
GH.Listen("DATA", RefreshSoon)
GH.Listen("INDEX", RefreshSoon)
GH.Listen("NAMES", RefreshSoon)
GH.Listen("ROSTER", RefreshSoon)
GH.On("BAG_UPDATE_DELAYED", function()
    if frame and frame:IsShown() and state.selected then PaintDetail() end
end)

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------
function W.Toggle()
    if not GH.db then return end
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end

function W.Open(query)
    if not GH.db then return end
    if not frame then Build() end
    frame:Show()
    if query then
        state.prof = nil
        frame.search.hint:SetText("Search items or recipes...")
        frame.search:SetText(query)   -- fires OnTextChanged -> search
        -- one result: show it right away
        local only
        for _, r in ipairs(state.results) do
            if r.kind == "recipe" then
                if only then only = nil; break end
                only = r
            end
        end
        if only then state.selected = only.id; Paint() end
    end
end
