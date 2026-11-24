--------------------------------------------------------------------------------
-- Cys's Guild Hall - Roster tab
-- Left: every member (alts folded under their main when alt grouping is on) with
-- class, level, rank, professions and when they were last on. Members who run
-- Cys's Guild Hall carry its seal. Right: the picked member in full: notes, alts,
-- every character's professions and skill, addon version.
--------------------------------------------------------------------------------
local GH = CysGuildHall
local S = GH.Style
local UI = {}
GH.RosterPanel = UI

local SOFT = { 0.84, 0.77, 0.62, 1 }
local ROWS, ROW_H = 16, 22
-- small gold "GH" coin: the full seal is too detailed to read at row size
local LOGO = "Interface\\AddOns\\CysGuildHall\\Media\\Mark"
local CLASS_TEX = "Interface\\TargetingFrame\\UI-Classes-Circles"
local PROF_ICON = {
    [164] = 136241, [165] = 133611, [171] = 136240, [182] = 136246, [186] = 136248, [197] = 136249,
    [202] = 136243, [333] = 136244, [393] = 134366, [185] = 133971, [129] = 135966, [356] = 136245,
}

local panel
local state = { sel = nil, offset = 0, query = "", online = false, sort = "online", list = {} }

local Paint, PaintList

local ScrollBar = function(parent, onScroll) return S.ScrollBar(parent, onScroll) end

local function Hex(r, g, b) return ("%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)) end

local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and Hex(c.r, c.g, c.b) or "e0e0e0"
end

local function SetClassIcon(tex, class)
    local c = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if c then
        tex:SetTexture(CLASS_TEX)
        tex:SetTexCoord(unpack(c))
        tex:Show()
    else
        tex:Hide()
    end
end

local function ProfIcon(pid)
    return PROF_ICON[pid] or 134400
end

local function LastText(e)
    if e.online then return "|cff4fd66bOnline|r" end
    local h = e.lastH
    if not h then return "" end
    if h < 1 then return "<1 h" end
    if h < 24 then return h .. " h" end
    local d = math.floor(h / 24)
    if d < 60 then return d .. " d" end
    return math.floor(d / 30) .. " mo"
end

local function Version(full)
    -- you and your own characters run this copy
    if full == GH.Me() or (GH.db and GH.db.mine and GH.db.mine[full]) then return GH.version end
    local C = GH.Comm
    local live = C and C.live and C.live[full]
    if live then return live == true and "?" or live end
    local g = GH.Guild()
    local v = g and g.vers and g.vers[full]
    return v and v.v
end

-- every profession of a character from the guild's shared data
local function Profs(full)
    local g = GH.Guild()
    local m = g and g.members and g.members[full]
    return m and m.profs
end

--------------------------------------------------------------------------------
-- Building the list: one line per player (main + alts) when alt grouping is on
--------------------------------------------------------------------------------
local function Build()
    local players, byMain = {}, {}
    local group = GH.db.settings.altGroup
    for full, e in pairs(GH.roster) do
        local main = group and GH.MainOf(full)
        if main and GH.roster[main] and main ~= full then
            local p = byMain[main]
            if not p then p = { alts = {} }; byMain[main] = p end
            p.alts[#p.alts + 1] = full
        else
            local p = byMain[full]
            if not p then p = { alts = {} }; byMain[full] = p end
            p.full, p.e = full, e
        end
    end
    for _, p in pairs(byMain) do
        if p.full then
            table.sort(p.alts)
            p.online = p.e.online
            p.onChar = p.e.online and p.full or nil
            p.lastH = p.e.lastH
            local pids = {}
            for _, c in ipairs({ p.full, unpack(p.alts) }) do
                local ce = GH.roster[c]
                if ce and ce.online and not p.online then p.online, p.onChar = true, c end
                if ce and ce.lastH and (not p.lastH or ce.lastH < p.lastH) then p.lastH = ce.lastH end
                for pid, pr in pairs(Profs(c) or {}) do
                    if not pids[pid] or (pr.s or 0) > pids[pid] then pids[pid] = pr.s or 0 end
                end
            end
            p.pids = {}
            for pid in pairs(pids) do p.pids[#p.pids + 1] = pid end
            table.sort(p.pids, function(a, b)
                if pids[a] ~= pids[b] then return pids[a] > pids[b] end
                return a < b
            end)
            p.ver = Version(p.full)
            if not p.ver then for _, a in ipairs(p.alts) do p.ver = p.ver or Version(a) end end
            players[#players + 1] = p
        end
    end
    return players
end

local function Matches(p, q)
    if q == "" then return true end
    if GH.Short(p.full):lower():find(q, 1, true) then return true end
    for _, a in ipairs(p.alts) do if GH.Short(a):lower():find(q, 1, true) then return true end end
    if p.e.rankName and p.e.rankName:lower():find(q, 1, true) then return true end
    for _, pid in ipairs(p.pids) do
        if GH.ProfName(pid):lower():find(q, 1, true) then return true end
    end
    return false
end

local SORTS = {
    online = function(a, b)
        if a.online ~= b.online then return a.online end
        local la, lb = a.lastH or 1e9, b.lastH or 1e9
        if la ~= lb then return la < lb end
        return a.full < b.full
    end,
    name = function(a, b) return a.full < b.full end,
    level = function(a, b)
        if (a.e.level or 0) ~= (b.e.level or 0) then return (a.e.level or 0) > (b.e.level or 0) end
        return a.full < b.full
    end,
    rank = function(a, b)
        if (a.e.rank or 99) ~= (b.e.rank or 99) then return (a.e.rank or 99) < (b.e.rank or 99) end
        return a.full < b.full
    end,
}

local function List()
    local out, total, on, users = {}, 0, 0, 0
    local q = state.query:lower()
    for _, p in ipairs(Build()) do
        total = total + 1
        if p.online then on = on + 1 end
        if p.ver then users = users + 1 end
        if (not state.online or p.online) and Matches(p, q) then out[#out + 1] = p end
    end
    table.sort(out, SORTS[state.sort] or SORTS.online)
    return out, total, on, users
end

--------------------------------------------------------------------------------
-- Paint
--------------------------------------------------------------------------------
local function PaintDetail(p)
    local d = panel.detail
    d.body:SetShown(p and true or false)
    d.none:SetShown(not p)
    if not p then
        d.none:SetText(GH.rosterCount == 0 and "Reading the guild roster..." or "Pick a member.")
        return
    end
    local e = p.e
    SetClassIcon(d.cls, e.class)
    d.name:SetText("|cff" .. ClassHex(e.class) .. GH.Short(p.full) .. "|r")
    d.logo:SetShown(p.ver and true or false)
    local line = ("Level %d"):format(e.level or 0)
    if e.rankName then line = line .. "  -  " .. e.rankName end
    d.sub:SetText(line)
    if p.online then
        local where = GH.roster[p.onChar] and GH.roster[p.onChar].zone
        local who = p.onChar ~= p.full and (" on " .. GH.Short(p.onChar)) or ""
        d.where:SetText("|cff4fd66bOnline|r" .. who .. (where and where ~= "" and ("  |cffd6c49e" .. where .. "|r") or ""))
    else
        local t = LastText({ lastH = p.lastH })
        d.where:SetText(t ~= "" and ("Last on " .. t .. " ago") or "Offline")
    end

    local lines = {}
    local function Add(s) lines[#lines + 1] = s end
    if e.note and e.note ~= "" then Add("|cffd9a421Note:|r " .. e.note) end
    if e.onote and e.onote ~= "" then Add("|cffd9a421Officer note:|r " .. e.onote) end
    Add(p.ver and ("|cffd9a421Cys's Guild Hall|r " .. (p.ver == "?" and "" or p.ver)) or "|cff8a8a8aDoesn't run Cys's Guild Hall|r")
    Add(" ")
    -- professions per character (main first, then alts)
    local any = false
    for _, c in ipairs({ p.full, unpack(p.alts) }) do
        local pr = Profs(c)
        if pr and next(pr) then
            any = true
            local ce = GH.roster[c] or {}
            Add("|cff" .. ClassHex(ce.class) .. GH.Short(c) .. "|r" .. (ce.level and ("  |cff8a8a8a" .. ce.level .. "|r") or ""))
            local pids = {}
            for pid in pairs(pr) do pids[#pids + 1] = pid end
            table.sort(pids, function(a, b) return (pr[a].s or 0) > (pr[b].s or 0) or ((pr[a].s or 0) == (pr[b].s or 0) and a < b) end)
            for _, pid in ipairs(pids) do
                local x = pr[pid]
                local skill = (x.m and x.m > 0) and ("%d / %d"):format(x.s or 0, x.m) or tostring(x.s or 0)
                local n = x.r and #x.r or 0
                Add(("   |T%d:14:14|t %s  |cffd6c49e%s%s|r"):format(ProfIcon(pid), GH.ProfName(pid), skill, n > 0 and ("  -  " .. n .. (n == 1 and " recipe" or " recipes")) or ""))
            end
        end
    end
    if not any then
        Add(p.ver and "|cff8a8a8aNo professions shared yet.|r" or "|cff8a8a8aProfessions show for members who run Cys's Guild Hall.|r")
    end
    -- alts without professions still listed
    local bare = {}
    for _, a in ipairs(p.alts) do
        local pr = Profs(a)
        if not pr or not next(pr) then
            local ae = GH.roster[a] or {}
            bare[#bare + 1] = "|cff" .. ClassHex(ae.class) .. GH.Short(a) .. "|r" .. (ae.level and (" " .. ae.level) or "") .. (ae.online and " |cff4fd66b(on)|r" or "")
        end
    end
    if #bare > 0 then
        Add(" ")
        Add("|cffd9a421Alts:|r " .. table.concat(bare, ", "))
    end
    d.text:SetText(table.concat(lines, "\n"))
end

function PaintList(list)
    local maxOff = math.max(0, #list - ROWS)
    if state.offset > maxOff then state.offset = maxOff end
    for i = 1, ROWS do
        local r = panel.rows[i]
        local p = list[state.offset + i]
        r.data = p
        if p then
            r:Show()
            local e = p.e
            SetClassIcon(r.cls, e.class)
            local name = GH.Short(p.full)
            if not p.online then name = "|cff8a8a8a" .. name .. "|r" else name = "|cff" .. ClassHex(e.class) .. name .. "|r" end
            r.name:SetText(name .. (#p.alts > 0 and ("  |cffd6c49e+" .. #p.alts .. "|r") or ""))
            r.logo:SetShown(p.ver and true or false)
            r.lvl:SetText(e.level or "")
            r.rank:SetText(e.rankName or "")
            for k = 1, 4 do
                local pid = p.pids[k]
                if pid then r.prof[k]:SetTexture(ProfIcon(pid)); r.prof[k]:Show() else r.prof[k]:Hide() end
            end
            r.last:SetText(LastText({ online = p.online, lastH = p.lastH }))
            r.sel:SetShown(p.full == state.sel)
        else
            r:Hide()
        end
    end
    panel.sb:Update(state.offset, maxOff, ROWS, #list)
end

function Paint()
    if not panel or not panel:IsShown() then return end
    local list, total, on, users = List()
    state.list = list
    local sel
    for _, p in ipairs(list) do if p.full == state.sel then sel = p end end
    if not sel and list[1] then sel = list[1]; state.sel = sel.full end
    panel.count:SetText(("%d members  -  |cff4fd66b%d online|r"):format(total, on))
    -- players (main + alts as one) who run the addon on any of their characters
    panel.key:SetText(("|T%s:14:14|t %d %s Cys's Guild Hall"):format(LOGO, users, users == 1 and "runs" or "run"))
    panel.empty:SetText(#list == 0 and (GH.rosterCount == 0 and "Reading the guild roster..." or "Nobody matches.") or "")
    PaintList(list)
    PaintDetail(sel)
end
UI.Paint = Paint

local paintTimer
function UI.PaintSoon()
    if not panel or not panel:IsShown() or paintTimer then return end
    paintTimer = C_Timer.NewTimer(0.3, function()
        paintTimer = nil
        Paint()
    end)
end
GH.Listen("ROSTER", UI.PaintSoon)
GH.Listen("DATA", UI.PaintSoon)
GH.Listen("ALTS", UI.PaintSoon)

--------------------------------------------------------------------------------
-- Build (called by the main window once)
--------------------------------------------------------------------------------
function UI.Build(frame)
    local T = S.T()
    panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", 1, -31)
    panel:SetPoint("BOTTOMRIGHT", -1, 1)
    panel:SetFrameLevel(frame:GetFrameLevel() + 30)
    panel:EnableMouse(true)
    S.Tex(panel, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 1 }):SetAllPoints()
    panel:Hide()
    panel:SetScript("OnShow", function()
        if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        Paint()
    end)

    -- filter row
    local search = S.EditBox(panel, 170, 22)
    search:SetPoint("TOPLEFT", 10, -10)
    search.hint:SetText("Name, rank or profession")
    search:SetScript("OnTextChanged", function(e)
        e.hint:SetShown(e:GetText() == "")
        state.query = e:GetText() or ""
        state.offset = 0
        Paint()
    end)
    search:SetScript("OnEnterPressed", function(e) e:ClearFocus() end)
    panel.search = search
    local onl = S.Check(panel, "Online", function() return state.online end, function(v)
        state.online = v
        state.offset = 0
        Paint()
    end)
    onl:SetPoint("LEFT", search, "RIGHT", 10, 0)
    local sort = S.Dropdown(panel, 104, 22, function()
        return { { "online", "Last online" }, { "name", "Name" }, { "level", "Level" }, { "rank", "Rank" } }
    end, function() return state.sort end, function(v) state.sort = v; Paint() end)
    sort:SetPoint("TOPLEFT", panel, "TOPLEFT", 326, -10)
    sort:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Sort by", 1, 1, 1)
        GameTooltip:Show()
    end)
    sort:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- members list
    local box = S.Panel(panel, T.field)
    box:SetPoint("TOPLEFT", 10, -40)
    box:SetSize(420, ROWS * ROW_H + 4)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta)
        state.offset = math.max(0, state.offset - delta * 3)
        PaintList(state.list)
    end)
    panel.sb = ScrollBar(box, function(off)
        state.offset = off
        PaintList(state.list)
    end)
    panel.sb:SetPoint("TOPRIGHT", -3, -3)
    panel.sb:SetPoint("BOTTOMRIGHT", -3, 3)
    panel.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, box)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        r:SetPoint("TOPRIGHT", -14, -2 - (i - 1) * ROW_H)
        r.hl = S.Tex(r, "BACKGROUND", T.cardHover)
        r.hl:SetAllPoints()
        r.hl:Hide()
        r.sel = S.Tex(r, "BACKGROUND", T.selected, 1)
        r.sel:SetAllPoints()
        r.sel:Hide()
        r.cls = r:CreateTexture(nil, "ARTWORK")
        r.cls:SetSize(15, 15)
        r.cls:SetPoint("LEFT", 5, 0)
        r.logo = r:CreateTexture(nil, "ARTWORK")
        r.logo:SetSize(15, 15)
        r.logo:SetPoint("LEFT", 22, 0)
        r.logo:SetTexture(LOGO)
        r.name = S.Text(r, 12, T.text)
        r.name:SetPoint("LEFT", 40, 0)
        r.name:SetWidth(132)
        r.name:SetWordWrap(false)
        r.lvl = S.Text(r, 11, T.text, "RIGHT")
        r.lvl:SetPoint("LEFT", 172, 0)
        r.lvl:SetWidth(22)
        r.rank = S.Text(r, 11, SOFT)
        r.rank:SetPoint("LEFT", 202, 0)
        r.rank:SetWidth(86)
        r.rank:SetWordWrap(false)
        r.prof = {}
        for k = 1, 4 do
            local t = r:CreateTexture(nil, "ARTWORK")
            t:SetSize(15, 15)
            t:SetPoint("LEFT", 292 + (k - 1) * 17, 0)
            t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.prof[k] = t
        end
        r.last = S.Text(r, 11, T.dim, "RIGHT")
        r.last:SetPoint("RIGHT", -6, 0)
        r:SetScript("OnClick", function(s)
            if s.data then state.sel = s.data.full; Paint() end
        end)
        r:SetScript("OnEnter", function(s)
            s.hl:Show()
            local p = s.data
            if not p or #p.pids == 0 then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(GH.Short(p.full), 1, 1, 1)
            for _, pid in ipairs(p.pids) do GameTooltip:AddLine(GH.ProfName(pid), 0.84, 0.77, 0.62) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
        panel.rows[i] = r
    end
    panel.empty = S.Text(box, 11, SOFT, "CENTER")
    panel.empty:SetPoint("CENTER")
    panel.count = S.Text(panel, 11, SOFT)
    panel.count:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)
    local key = S.Text(panel, 10, T.dim, "RIGHT")
    key:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", -2, -7)
    key:SetText("|T" .. LOGO .. ":14:14|t runs Cys's Guild Hall")
    panel.key = key

    -- detail
    local d = S.Panel(panel, T.field)
    d:SetPoint("TOPLEFT", 440, -10)
    d:SetPoint("BOTTOMRIGHT", -10, 10)
    panel.detail = d
    d.none = S.Text(d, 11, SOFT, "CENTER")
    d.none:SetPoint("CENTER")
    d.none:SetWidth(220)
    local body = CreateFrame("Frame", nil, d)
    body:SetAllPoints()
    d.body = body
    d.cls = body:CreateTexture(nil, "ARTWORK")
    d.cls:SetSize(20, 20)
    d.cls:SetPoint("TOPLEFT", 10, -10)
    d.name = S.Text(body, 15, T.text)
    d.name:SetPoint("LEFT", d.cls, "RIGHT", 6, 0)
    d.name:SetWordWrap(false)
    d.logo = body:CreateTexture(nil, "ARTWORK")
    d.logo:SetSize(18, 18)
    d.logo:SetPoint("LEFT", d.name, "RIGHT", 6, 0)
    d.logo:SetTexture(LOGO)
    d.sub = S.Text(body, 11, T.text)
    d.sub:SetPoint("TOPLEFT", d.cls, "BOTTOMLEFT", 0, -6)
    d.where = S.Text(body, 11, SOFT)
    d.where:SetPoint("TOPLEFT", d.sub, "BOTTOMLEFT", 0, -4)
    d.where:SetPoint("RIGHT", body, "RIGHT", -10, 0)
    d.where:SetWordWrap(false)
    d.text = S.Text(body, 11, T.text)
    d.text:SetPoint("TOPLEFT", d.where, "BOTTOMLEFT", 0, -10)
    d.text:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -10, 10)
    d.text:SetJustifyV("TOP")
    d.text:SetWordWrap(true)
    if d.text.SetSpacing then d.text:SetSpacing(3) end

    return panel
end
