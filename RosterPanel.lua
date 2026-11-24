--------------------------------------------------------------------------------
-- Cys's Guild Hall - Roster tab
-- Left: every member (alts folded under their main when alt grouping is on) with
-- class, level, rank, professions and when they were last on. Members who run
-- Cys's Guild Hall carry its seal. Right: the picked member in full: notes, alts,
-- every character's professions and skill, addon version.
-- View dropdown > Officer: auto-promote rules (level X+ in rank A -> rank B, one
-- list) and inactive members (whole player offline N+ days). Forever blocks addons from
-- GuildPromote / GuildUninvite, so the buttons open Blizzard's guild window and say who
-- to click; the change itself is made there.
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
local state = { sel = nil, offset = 0, query = "", online = false, sort = "online", list = {}, view = "members", dueOff = 0, idleOff = 0 }

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
    -- addon users: one per player (counted on the main, even if only an alt runs it),
    -- whether or not alts are grouped in the list
    local mains = {}
    for full in pairs(GH.roster) do
        if Version(full) then mains[(GH.altMainAll or {})[full] or full] = true end
    end
    for _ in pairs(mains) do users = users + 1 end
    for _, p in ipairs(Build()) do
        total = total + 1
        if p.online then on = on + 1 end
        if (not state.online or p.online) and Matches(p, q) then out[#out + 1] = p end
    end
    table.sort(out, SORTS[state.sort] or SORTS.online)
    return out, total, on, users
end

--------------------------------------------------------------------------------
-- Officer view: auto-promote rules + inactive members
-- Saved per guild in GH.Guild().off = { rules = { {lvl, from, to} }, days, skip, notice }
-- (rank indexes: 0 = Guild Master, higher = lower rank)
--------------------------------------------------------------------------------
local LEVELS = { 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60 }
local DAYS = { 7, 14, 21, 30, 45, 60, 90 }
local MAX_RULES, DUE_ROWS, IDLE_ROWS = 5, 7, 12

-- Blizzard's guild window (offline members shown). Never touches GuildFrame's own
-- fields: that would taint its Rank dropdown and Remove button.
local function OpenGuild()
    if SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
    if GuildFrame and GuildFrame:IsShown() then return end
    if ToggleGuildFrame then ToggleGuildFrame()
    elseif ToggleFriendsFrame then ToggleFriendsFrame(3) end
end

local function Off()
    local g = GH.Guild()
    if not g then return nil end
    g.off = g.off or { rules = {}, days = 30, skip = -1, notice = true }
    return g.off
end
GH.Officer = Off

local function MyRank()
    local _, _, idx = GetGuildInfo("player")
    return idx
end

local function CanPromote() return CanGuildPromote and CanGuildPromote() and true or false end
local function CanRemove() return CanGuildRemove and CanGuildRemove() and true or false end

local function RankName(idx)
    for _, r in ipairs(GH.RankNames()) do if r[1] == idx then return r[2] end end
    return idx and ("Rank " .. (idx + 1)) or "?"
end

-- members a rule moves up, A-Z
local function Due()
    local o, out = Off(), {}
    if not o then return out end
    local my = MyRank()
    for full, e in pairs(GH.roster) do
        if e.rank and e.level and full ~= GH.Me() then
            local to
            for _, r in ipairs(o.rules) do
                if r.lvl and r.from and r.to and r.to < r.from and e.rank == r.from and e.level >= r.lvl then to = r.to; break end
            end
            -- the game only promotes to ranks below your own
            if to and (not my or to > my) then out[#out + 1] = { full = full, e = e, to = to } end
        end
    end
    -- A-Z, so they're easy to find in the guild window
    table.sort(out, function(a, b) return GH.Short(a.full):lower() < GH.Short(b.full):lower() end)
    return out
end

-- every character of players whose main and alts have all been offline N+ days
local function Idle()
    local o, out = Off(), {}
    if not o then return out end
    local limit = (o.days or 30) * 24
    for _, p in ipairs(Build()) do
        if not p.online and p.lastH and p.lastH >= limit then
            for _, c in ipairs({ p.full, unpack(p.alts) }) do
                local e = GH.roster[c]
                if e and e.rank and e.rank ~= 0 and c ~= GH.Me() and not ((o.skip or -1) >= 0 and e.rank <= o.skip) then
                    out[#out + 1] = { full = c, e = e, main = c ~= p.full and p.full or nil, lastH = p.lastH, key = p.full }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.lastH ~= b.lastH then return a.lastH > b.lastH end
        if a.key ~= b.key then return a.key < b.key end
        if (a.main == nil) ~= (b.main == nil) then return a.main == nil end
        return a.full < b.full
    end)
    return out
end

-- login notice for officers, once per session
local told = false
GH.Listen("ROSTER", function()
    if told or GH.rosterCount == 0 then return end
    told = true
    C_Timer.After(10, function()
        local o = Off()
        if not o or not o.notice then return end
        local parts = {}
        if CanPromote() and #o.rules > 0 then
            local n = #Due()
            if n > 0 then parts[#parts + 1] = n .. (n == 1 and " member is" or " members are") .. " due for promotion" end
        end
        if CanRemove() then
            local n = #Idle()
            if n > 0 then parts[#parts + 1] = n .. (n == 1 and " character has" or " characters have") .. " been offline " .. (o.days or 30) .. "+ days" end
        end
        if #parts > 0 then GH.Print(table.concat(parts, "; ") .. ". /guildhall officer") end
    end)
end)

local function PaintOfficer()
    local f = panel.off
    local o = Off()
    if not o then
        f.L:Hide(); f.R:Hide()
        f.none:SetText(GH.rosterCount == 0 and "Reading the guild roster..." or "You are not in a guild.")
        f.none:Show()
        return
    end
    f.none:Hide(); f.L:Show(); f.R:Show()
    local canP, canR = CanPromote(), CanRemove()

    -- rules
    local L = f.L
    for i = 1, MAX_RULES do
        local row, r = L.rules[i], o.rules[i]
        row:SetShown(r and true or false)
        if r then row.lvl:Refresh(); row.from:Refresh(); row.to:Refresh() end
    end
    L.add:ClearAllPoints()
    L.add:SetPoint("TOPLEFT", 10, -56 - #o.rules * 26)
    L.add:SetShown(#o.rules < MAX_RULES)
    L.noRules:SetShown(#o.rules == 0)

    local due = Due()
    local maxOff = math.max(0, #due - DUE_ROWS)
    if state.dueOff > maxOff then state.dueOff = maxOff end
    L.dueHead:SetText(("Due for promotion  |cffd6c49e%d|r"):format(#due))
    for i = 1, DUE_ROWS do
        local row, d = L.due[i], due[state.dueOff + i]
        row.data = d
        row:SetShown(d and true or false)
        if d then
            row.name:SetText("|cff" .. ClassHex(d.e.class) .. GH.Short(d.full) .. "|r")
            row.lvl:SetText(d.e.level or "")
            row.rank:SetText((d.e.rankName or RankName(d.e.rank)) .. " |cffd9a421>|r " .. RankName(d.to))
            row.btn:SetActive(canP)
        end
    end
    L.dueNote:SetText(#due == 0 and (#o.rules == 0 and "" or "Nobody is due.")
        or not canP and "|cffff6060Your rank can't promote members.|r"
        or maxOff > 0 and ("Scroll for " .. (#due - DUE_ROWS) .. " more.") or "")

    -- inactive
    local R = f.R
    R.days:Refresh(); R.skip:Refresh(); R.notice:Refresh()
    local idle = Idle()
    maxOff = math.max(0, #idle - IDLE_ROWS)
    if state.idleOff > maxOff then state.idleOff = maxOff end
    R.head:SetText(("Inactive members  |cffd6c49e%d|r"):format(#idle))
    for i = 1, IDLE_ROWS do
        local row, d = R.rows[i], idle[state.idleOff + i]
        row.data = d
        row:SetShown(d and true or false)
        if d then
            row.name:SetText("|cff" .. ClassHex(d.e.class) .. GH.Short(d.full) .. "|r" .. (d.main and "  |cff8a8a8aalt|r" or ""))
            row.lvl:SetText(d.e.level or "")
            row.rank:SetText(d.e.rankName or "")
            row.last:SetText(LastText({ lastH = d.lastH }))
            row.btn:SetActive(canR)
        end
    end
    R.note:SetText(#idle == 0 and "Nobody has been away that long."
        or not canR and "|cffff6060Your rank can't remove members.|r"
        or maxOff > 0 and ("Scroll for " .. (#idle - IDLE_ROWS) .. " more.") or "")
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
    local offView = state.view == "off"
    for _, w in ipairs(panel.memberParts) do w:SetShown(not offView) end
    panel.off:SetShown(offView)
    if offView then PaintOfficer(); return end
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

-- "members" or "off" (officer tools)
function UI.SetView(v)
    state.view = v
    if panel and panel.view then panel.view:Refresh() end
    Paint()
end

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
    local search = S.EditBox(panel, 130, 22)
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
    onl:SetPoint("LEFT", search, "RIGHT", 8, 0)
    local sort = S.Dropdown(panel, 96, 22, function()
        return { { "online", "Last online" }, { "name", "Name" }, { "level", "Level" }, { "rank", "Rank" } }
    end, function() return state.sort end, function(v) state.sort = v; Paint() end)
    sort:SetPoint("TOPLEFT", panel, "TOPLEFT", 226, -10)
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

    panel.memberParts = { search, onl, sort, box, panel.count, key, d }

    -- view: members or officer tools
    local view = S.Dropdown(panel, 104, 22, function()
        return { { "members", "Members" }, { "off", "Officer tools" } }
    end, function() return state.view end, function(v) UI.SetView(v) end)
    view:SetPoint("TOPLEFT", panel, "TOPLEFT", 326, -10)
    panel.view = view

    local off = CreateFrame("Frame", nil, panel)
    off:SetPoint("TOPLEFT", 10, -40)
    off:SetPoint("BOTTOMRIGHT", -10, 10)
    off:Hide()
    panel.off = off
    off.none = S.Text(off, 11, SOFT, "CENTER")
    off.none:SetPoint("CENTER")

    local function Wheel(f, key, rows)
        f:EnableMouseWheel(true)
        f:SetScript("OnMouseWheel", function(_, delta)
            state[key] = math.max(0, state[key] - delta * 3)
            PaintOfficer()
        end)
    end

    -- left: auto-promote
    local L = S.Panel(off, T.field)
    L:SetPoint("TOPLEFT")
    L:SetPoint("BOTTOMRIGHT", off, "BOTTOM", -5, 0)
    off.L = L
    Wheel(L, "dueOff")
    local lh = S.Text(L, 13, T.accent)
    lh:SetPoint("TOPLEFT", 10, -8)
    lh:SetText("Auto-promote")
    local help = S.Text(L, 10, T.dim)
    help:SetPoint("TOPLEFT", 10, -26)
    help:SetPoint("RIGHT", L, "RIGHT", -10, 0)
    help:SetWordWrap(true)
    help:SetText("Who your rules say should move up. Find opens the guild window: click the name there and set the Rank.")
    L.noRules = S.Text(L, 11, SOFT)
    L.noRules:SetPoint("TOPLEFT", 110, -60)
    L.noRules:SetText("No rules yet.")
    local function RankItems()
        local out = {}
        for _, r in ipairs(GH.RankNames()) do out[#out + 1] = { r[1], r[2] } end
        return out
    end
    L.rules = {}
    for i = 1, MAX_RULES do
        local row = CreateFrame("Frame", nil, L)
        row:SetSize(310, 22)
        row:SetPoint("TOPLEFT", 10, -56 - (i - 1) * 26)
        local function R() return Off() and Off().rules[i] end
        row.lvl = S.Dropdown(row, 80, 22, function()
            local out = {}
            for _, l in ipairs(LEVELS) do out[#out + 1] = { l, "Level " .. l .. "+" } end
            return out
        end, function() return R() and R().lvl end, function(v) if R() then R().lvl = v; Paint() end end)
        row.lvl:SetPoint("LEFT")
        row.from = S.Dropdown(row, 92, 22, RankItems, function() return R() and R().from end, function(v) if R() then R().from = v; Paint() end end)
        row.from.placeholder = "From rank"
        row.from:SetPoint("LEFT", row.lvl, "RIGHT", 4, 0)
        local arrow = S.Text(row, 12, T.accent, "CENTER")
        arrow:SetPoint("LEFT", row.from, "RIGHT", 0, 0)
        arrow:SetWidth(14)
        arrow:SetText(">")
        row.to = S.Dropdown(row, 92, 22, RankItems, function() return R() and R().to end, function(v) if R() then R().to = v; Paint() end end)
        row.to.placeholder = "To rank"
        row.to:SetPoint("LEFT", arrow, "RIGHT", 0, 0)
        local del = S.Button(row, 22, 22, "x")
        del:SetPoint("LEFT", row.to, "RIGHT", 4, 0)
        del:SetScript("OnClick", function()
            local o = Off()
            if o and o.rules[i] then table.remove(o.rules, i); Paint() end
        end)
        L.rules[i] = row
    end
    L.add = S.Button(L, 90, 22, "Add rule")
    L.add:SetScript("OnClick", function()
        local o = Off()
        if not o or #o.rules >= MAX_RULES then return end
        -- start from the two lowest ranks: lowest -> the one above it
        local ranks = GH.RankNames()
        local lo, up = ranks[#ranks], ranks[#ranks - 1]
        o.rules[#o.rules + 1] = { lvl = 25, from = lo and lo[1], to = up and up[1] }
        Paint()
    end)
    local dueTop = -56 - MAX_RULES * 26 - 6
    L.dueHead = S.Text(L, 12, T.accent)
    L.dueHead:SetPoint("TOPLEFT", 10, dueTop)
    L.due = {}
    for i = 1, DUE_ROWS do
        local row = CreateFrame("Frame", nil, L)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", 8, dueTop - 18 - (i - 1) * 22)
        row:SetPoint("RIGHT", L, "RIGHT", -8, 0)
        row.name = S.Text(row, 11, T.text)
        row.name:SetPoint("LEFT", 2, 0)
        row.name:SetWidth(104)
        row.name:SetWordWrap(false)
        row.lvl = S.Text(row, 11, T.text, "RIGHT")
        row.lvl:SetPoint("LEFT", 106, 0)
        row.lvl:SetWidth(20)
        row.rank = S.Text(row, 11, SOFT)
        row.rank:SetPoint("LEFT", 132, 0)
        row.rank:SetPoint("RIGHT", row, "RIGHT", -54, 0)
        row.rank:SetWordWrap(false)
        row.btn = S.Button(row, 48, 20, "Find")
        row.btn:SetPoint("RIGHT")
        row.btn:SetScript("OnClick", function()
            local dd = row.data
            if not dd then return end
            OpenGuild()
            GH.Print(("promote: click |cffffffff%s|r in the guild window and set Rank to |cffffffff%s|r."):format(GH.Short(dd.full), RankName(dd.to)))
        end)
        L.due[i] = row
    end
    L.dueNote = S.Text(L, 10, T.dim)
    L.dueNote:SetPoint("BOTTOMLEFT", 10, 8)

    -- right: inactive members
    local R = S.Panel(off, T.field)
    R:SetPoint("TOPLEFT", off, "TOP", 5, 0)
    R:SetPoint("BOTTOMRIGHT")
    off.R = R
    Wheel(R, "idleOff")
    R.head = S.Text(R, 13, T.accent)
    R.head:SetPoint("TOPLEFT", 10, -8)
    R.days = S.Dropdown(R, 134, 22, function()
        local out = {}
        for _, n in ipairs(DAYS) do out[#out + 1] = { n, "Offline " .. n .. "+ days" } end
        return out
    end, function() return Off() and Off().days end, function(v) if Off() then Off().days = v; state.idleOff = 0; Paint() end end)
    R.days:SetPoint("TOPLEFT", 10, -30)
    R.skip = S.Dropdown(R, 140, 22, function()
        local out = { { -1, "Check every rank" } }
        for _, r in ipairs(GH.RankNames()) do
            if r[1] > 0 then out[#out + 1] = { r[1], "Skip " .. r[2] .. " and up" } end
        end
        return out
    end, function() return Off() and (Off().skip or -1) end, function(v) if Off() then Off().skip = v; state.idleOff = 0; Paint() end end)
    R.skip:SetPoint("LEFT", R.days, "RIGHT", 6, 0)
    R.notice = S.Check(R, "Tell me at login", function() return Off() and Off().notice end, function(v) if Off() then Off().notice = v end end)
    R.notice:SetPoint("TOPLEFT", 10, -58)
    R.rows = {}
    for i = 1, IDLE_ROWS do
        local row = CreateFrame("Frame", nil, R)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", 8, -82 - (i - 1) * 22)
        row:SetPoint("RIGHT", R, "RIGHT", -8, 0)
        row:EnableMouse(true)
        row.hl = S.Tex(row, "BACKGROUND", T.cardHover)
        row.hl:SetAllPoints()
        row.hl:Hide()
        row.name = S.Text(row, 11, T.text)
        row.name:SetPoint("LEFT", 2, 0)
        row.name:SetWidth(112)
        row.name:SetWordWrap(false)
        row.lvl = S.Text(row, 11, T.text, "RIGHT")
        row.lvl:SetPoint("LEFT", 114, 0)
        row.lvl:SetWidth(20)
        row.rank = S.Text(row, 11, SOFT)
        row.rank:SetPoint("LEFT", 140, 0)
        row.rank:SetWidth(76)
        row.rank:SetWordWrap(false)
        row.last = S.Text(row, 11, T.dim, "RIGHT")
        row.last:SetPoint("RIGHT", row, "RIGHT", -54, 0)
        row.btn = S.Button(row, 48, 20, "Find")
        row.btn:SetPoint("RIGHT")
        row.btn:SetScript("OnClick", function()
            local dd = row.data
            if not dd then return end
            OpenGuild()
            GH.Print(("remove: click |cffffffff%s|r in the guild window, then Remove. Sorting by Last Online puts them together."):format(GH.Short(dd.full)))
        end)
        row:SetScript("OnEnter", function(s)
            s.hl:Show()
            local dd = s.data
            if not dd then return end
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            GameTooltip:SetText(GH.Short(dd.full), 1, 1, 1)
            if dd.main then GameTooltip:AddLine("Alt of " .. GH.Short(dd.main), 0.84, 0.77, 0.62) end
            GameTooltip:AddLine("Player last on " .. LastText({ lastH = dd.lastH }) .. " ago (main and alts)", 0.84, 0.77, 0.62)
            if dd.e.note and dd.e.note ~= "" then GameTooltip:AddLine("Note: " .. dd.e.note, 1, 1, 1, true) end
            if dd.e.onote and dd.e.onote ~= "" then GameTooltip:AddLine("Officer note: " .. dd.e.onote, 1, 1, 1, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(s) s.hl:Hide(); GameTooltip:Hide() end)
        R.rows[i] = row
    end
    R.note = S.Text(R, 10, T.dim)
    R.note:SetPoint("BOTTOMLEFT", 10, 8)

    return panel
end
