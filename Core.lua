--------------------------------------------------------------------------------
-- Cys's Guild Hall - core
-- by Cyserin (Cys). Works for any guild: every member running it shares the
-- recipes they know, so anyone can search an item and see who can make it.
--------------------------------------------------------------------------------
local ADDON = ...
local GH = {}
_G.CysGuildHall = GH

GH.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "0.1.0"
GH.PREFIX = "CysGH"
GH.PROTO = 1

--------------------------------------------------------------------------------
-- Events: GH.On(event, fn); errors go to the error handler (BugSack) but never stop other handlers
--------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local handlers = {}
function GH.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        ev:RegisterEvent(event)
    end
    local list = handlers[event]
    list[#list + 1] = fn
end
ev:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Internal messages (data changed etc.)
local cbs = {}
function GH.Listen(name, fn)
    cbs[name] = cbs[name] or {}
    table.insert(cbs[name], fn)
end
function GH.Fire(name, ...)
    for _, fn in ipairs(cbs[name] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end

-- Is version string a newer than b? ("0.3.12" > "0.3.9")
function GH.VersionNewer(a, b)
    a, b = tostring(a or ""), tostring(b or "")
    local pa, pb = {}, {}
    for n in a:gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in b:gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y end
    end
    return false
end

function GH.Print(msg)
    print("|cffd9a421Cys's Guild Hall|r: " .. tostring(msg))
end

--------------------------------------------------------------------------------
-- Names. Everything is stored as "Name-Realm".
--------------------------------------------------------------------------------
-- The realm part the game puts in player names. On Forever UnitName("player") gives the
-- character's realm (e.g. Valorguard) while GetNormalizedRealmName gives an internal server name.
function GH.MyRealm()
    if GH._realm then return GH._realm end
    local _, r = UnitName("player")
    if (not r or r == "") and UnitFullName then
        local _, r2 = UnitFullName("player")
        r = r2
    end
    if not r or r == "" then r = GetNormalizedRealmName and GetNormalizedRealmName() end
    if r and r ~= "" then
        GH._realm = (r:gsub("[%s%-]", ""))
        return GH._realm
    end
    return ((GetRealmName() or ""):gsub("[%s%-]", ""))
end

function GH.Full(name, realm)
    if not name or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. (realm or GH.MyRealm())
end

function GH.Me()
    return GH.Full(UnitName("player"))
end

-- Display name. On Forever the part after the dash is the character's last name, so show
-- "First Last". An internal server name (digits, e.g. CAMWOWUS2Realm5PvE) is dropped.
-- A bare first name (not matched to the roster yet) shows as is.
function GH.Short(full)
    if not full then return "?" end
    local n, r = full:match("^(.-)%-(.+)$")
    if not n then return full end
    if r:find("%d") then return n end
    return n .. " " .. r
end

-- Key for the guild we are in: "Realm-Guild Name", or nil when not in a guild
function GH.GuildKey()
    if not IsInGuild() then return nil end
    local gname = GetGuildInfo("player")
    if not gname or gname == "" then return nil end
    return GH.MyRealm() .. "-" .. gname
end

-- Saved data of the current guild (created on demand)
function GH.Guild()
    local key = GH.GuildKey()
    if not key or not GH.db then return nil end
    local g = GH.db.guilds[key]
    if not g then
        -- 0.1.x keyed guilds by GetNormalizedRealmName(): move that data over once
        local old = GetNormalizedRealmName and GetNormalizedRealmName()
        local gname = GetGuildInfo("player")
        old = old and gname and (old .. "-" .. gname)
        if old and old ~= key and GH.db.guilds[old] then
            g = GH.db.guilds[old]
            GH.db.guilds[old] = nil
            GH.db.guilds[key] = g
            return g
        end
        g = { members = {} }
        GH.db.guilds[key] = g
    end
    return g
end

--------------------------------------------------------------------------------
-- Base 36 (keeps addon messages short)
--------------------------------------------------------------------------------
local DIG = "0123456789abcdefghijklmnopqrstuvwxyz"
function GH.To36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = DIG:sub(d + 1, d + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end
function GH.From36(s)
    return tonumber(s or "", 36)
end

--------------------------------------------------------------------------------
-- Guild roster: online state + class of every member
--------------------------------------------------------------------------------
GH.roster = {}       -- [full] = { online, class (file), level, raw }
GH.rosterBare = {}   -- [lowercase name without realm] = same entry (realm spellings can differ)
GH.rosterFirst = {}  -- [lowercase first name] = { "First-Last", ... } (to find a member's real last name)
GH.rosterCount = 0

local function Bare(full)
    return ((full or ""):match("^([^%-%s]+)") or ""):lower()
end
GH.Bare = Bare

-- roster entry of a member, matched by full name, else by name alone
GH.rosterGuid = {}   -- [GUID] = same entry

-- Character IDs: our own from the game, other members' from their hidden hello
function GH.GuidOf(full)
    if full == GH.Me() then return UnitGUID("player") end
    local g = GH.Guild()
    return g and g.guids and g.guids[full]
end

-- Roster entry of a member: by name (full or bare), else by character ID
-- (on Forever the roster's name format does not match chat names)
function GH.RosterEntry(full)
    local e = GH.roster[full] or GH.rosterBare[Bare(full)]
    if not e then
        local guid = GH.GuidOf(full)
        e = guid and GH.rosterGuid[guid]
    end
    return e
end

local function ReadRoster()
    if not IsInGuild() then wipe(GH.roster); GH.rosterCount = 0; return end
    local n = GetNumGuildMembers() or 0
    if n == 0 then return end
    local new, bare, byGuid, first = {}, {}, {}, {}
    local count = 0
    for i = 1, n do
        local name, rankName, rankIndex, level, _, _, note, onote, online, _, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if type(name) == "string" and name ~= "" then
            local e = { online = online and true or false, class = classFile, level = level, raw = name, rank = rankIndex,
                rankName = type(rankName) == "string" and rankName or nil,
                note = type(note) == "string" and note or nil, onote = type(onote) == "string" and onote or nil }
            -- Forever's roster writes "Name Realm" (a space): make it "Name-Realm" like chat names
            name = name:gsub("^(%S+) (%S+)$", "%1-%2")
            e.full = GH.Full(name)
            new[e.full] = e
            bare[Bare(name)] = e
            local fl = first[Bare(name)]
            if not fl then fl = {}; first[Bare(name)] = fl end
            fl[#fl + 1] = e.full
            if type(guid) == "string" then byGuid[guid] = e end
            count = count + 1
        end
    end
    if count > 0 then
        GH.roster = new
        GH.rosterBare = bare
        GH.rosterGuid = byGuid
        GH.rosterFirst = first
        GH.rosterCount = count
        GH.FixNames()
        GH.BuildAlts()
        GH.Fire("ROSTER")
    end
end

--------------------------------------------------------------------------------
-- Alts: a member whose guild rank is an alt rank and whose note (public, then officer)
-- names another guild member is that member's alt. Lists then show the alt under its main.
--------------------------------------------------------------------------------
GH.altMain = {}      -- [alt full] = main full

-- Is this rank name an alt rank? The setting picks one rank by name; empty = any rank
-- with the word "alt" or "alts" in it (so "Exalted" does not count).
function GH.IsAltRank(rankName)
    if type(rankName) ~= "string" or rankName == "" then return false end
    local want = GH.db and GH.db.settings.altRank or ""
    if want ~= "" then return rankName:lower() == want:lower() end
    local r = " " .. rankName:lower() .. " "
    return r:find("[^%a]alts?[^%a]") ~= nil
end

-- Guild rank names as { { rankIndex, name }, ... }, from the roster
function GH.RankNames()
    local seen, out = {}, {}
    for _, e in pairs(GH.roster) do
        if e.rankName and e.rank and not seen[e.rank] then
            seen[e.rank] = true
            out[#out + 1] = { e.rank, e.rankName }
        end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

local SKIP = { alt = true, alts = true, of = true, main = true, mains = true, is = true, my = true, the = true, s = true, ["and"] = true, char = true, toon = true }

-- The guild member a note names, or nil. Tries "First Last" pairs first, then a first
-- name only one member has. Never the alt itself.
local function NoteMain(text, self)
    if type(text) ~= "string" or text == "" then return nil end
    local words = {}
    for w in text:gmatch("[%a\128-\255]+") do words[#words + 1] = w:lower() end
    for i = 1, #words - 1 do
        local e = GH.rosterLower[words[i] .. "-" .. words[i + 1]]
        if e and e.full ~= self then return e.full end
    end
    for i = 1, #words do
        local w = words[i]
        if not SKIP[w] then
            local list = GH.rosterFirst[w]
            if list and #list == 1 and list[1] ~= self then return list[1] end
        end
    end
    return nil
end

function GH.BuildAlts()
    local map = {}
    local lower = {}
    for full, e in pairs(GH.roster) do lower[full:lower()] = e end
    GH.rosterLower = lower
    if GH.db and GH.db.settings.altGroup then
        for full, e in pairs(GH.roster) do
            if GH.IsAltRank(e.rankName) then
                local main = NoteMain(e.note, full) or NoteMain(e.onote, full)
                if main then map[full] = main end
            end
        end
    end
    GH.altMain = map
end
GH.rosterLower = {}

-- Main of an alt ("First-Last"), or nil when this character is not a known alt
function GH.MainOf(full)
    local e = GH.RosterEntry(full)
    return e and e.full and GH.altMain[e.full] or nil
end

-- Roster spelling of a member's name (falls back to the name given)
function GH.RosterName(full)
    local e = GH.RosterEntry(full)
    return e and e.full or full
end

-- A member's real "First-Last" name. On Forever the game gives addon messages only the
-- first name, so the last name comes from the guild roster: by character ID, exact name,
-- or a first name only one member has. Unknown: the name as given (never our last name).
function GH.Canon(name)
    if not name or name == "" then return name end
    if name == GH.Me() or name == UnitName("player") then return GH.Me() end
    if GH.roster[name] or (GH.db and GH.db.mine[name]) then return name end
    local guid = GH.GuidOf(name)
    local e = guid and GH.rosterGuid[guid]
    if e and e.full then return e.full end
    local list = GH.rosterFirst[Bare(name)]
    if list and #list == 1 then return list[1] end
    return name
end

-- Repair names saved under the wrong last name (0.3.9 and older gave everyone ours)
local function Rekey(t, merge)
    if not t then return false end
    local moves
    for k in pairs(t) do
        local c = GH.Canon(k)
        if c ~= k then moves = moves or {}; moves[k] = c end
    end
    if not moves then return false end
    for old, new in pairs(moves) do
        local v = t[old]
        t[old] = nil
        if t[new] == nil then t[new] = v elseif merge then t[new] = merge(t[new], v) end
    end
    return true
end
function GH.FixNames()
    local g = GH.Guild()
    if not g then return end
    local changed = Rekey(g.members, function(a, b) return ((b.rev or 0) > (a.rev or 0)) and b or a end)
    Rekey(g.missing)
    for _, r in pairs(g.requests or {}) do
        local by, cr = r.by and GH.Canon(r.by), r.cr and GH.Canon(r.cr)
        if by ~= r.by or cr ~= r.cr then r.by, r.cr, changed = by, cr, true end
    end
    if Rekey(g.guids) then changed = true end   -- last: Canon reads guids by the old names
    if changed then GH.Fire("DATA") end
end

function GH.IsOnline(full)
    local r = GH.RosterEntry(full)
    return r and r.online
end

function GH.ClassColor(full)
    local r = GH.RosterEntry(full)
    local c = r and r.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.class]
    if c then return c.r, c.g, c.b end
    return 0.88, 0.88, 0.88
end

GH.On("GUILD_ROSTER_UPDATE", ReadRoster)
GH.On("PLAYER_GUILD_UPDATE", function()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    GH.Fire("GUILD")
end)

--------------------------------------------------------------------------------
-- Saved data
--------------------------------------------------------------------------------
local DEFAULTS = { tooltip = true, notify = true, doneHours = 24, matsPopup = true, delivery = "m", toasts = true, lootShare = true, altGroup = true, altRank = "" }

GH.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    CysGuildHallDB = CysGuildHallDB or {}
    local db = CysGuildHallDB
    db.v = db.v or 1
    db.settings = db.settings or {}
    for k, v in pairs(DEFAULTS) do if db.settings[k] == nil then db.settings[k] = v end end
    db.recipes = db.recipes or {}   -- [recipeID] = { o = itemID, q = qty, n = recipe name, p = profID, r = { {itemID, qty}, ... } }
    db.names = db.names or {}       -- [itemID] = name (search works before item data loads)
    db.quality = db.quality or {}   -- [itemID] = quality (names keep their color while item data reloads)
    db.bind = db.bind or {}         -- [itemID] = bind type (1 = Bind on Pickup: those recipes are hidden)
    db.profNames = db.profNames or {} -- [profID] = name
    db.mine = db.mine or {}         -- [full] = true for characters on this account (never pruned)
    db.init = db.init or {}         -- [full] = 1 initialized / 2 set up (first-run welcome)
    db.allRecipes = db.allRecipes or {} -- [profID] = { every recipe ID of that profession, learned or not } (Gaps tab)
    db.allRev = db.allRev or {}     -- [profID] = revision of that full list (shared with the guild)
    for pid in pairs(db.allRecipes) do db.allRev[pid] = db.allRev[pid] or GetServerTime() end
    db.guilds = db.guilds or {}     -- [guildKey] = { members = { [full] = { rev, profs = { [profID] = { s, m, r = {recipeIDs} } } } } }
    GH.db = db
    GH.Fire("LOADED")
end)

GH.On("PLAYER_LOGIN", function()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    -- keep the roster fresh while playing (online dots)
    C_Timer.NewTicker(60, function()
        if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    end)
end)

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------
local function Count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

local function Check()
    local T = C_TradeSkillUI or {}
    GH.Print("version " .. GH.version .. ", guild: " .. tostring(GH.GuildKey()))
    print(("  APIs: GetAllRecipeIDs %s, GetFilteredRecipeIDs %s, GetRecipeSchematic %s, IsGuildTradeSkillsEnabled %s"):format(
        tostring(T.GetAllRecipeIDs ~= nil), tostring(T.GetFilteredRecipeIDs ~= nil), tostring(T.GetRecipeSchematic ~= nil),
        T.IsGuildTradeSkillsEnabled and tostring(T.IsGuildTradeSkillsEnabled()) or "missing"))
    local restricted = C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()
    print(("  addon messages restricted: %s, send queue: %d, roster: %d"):format(tostring(restricted), GH.Comm and GH.Comm.QueueSize() or 0, GH.rosterCount))
    local g = GH.Guild()
    if g then
        local crafters, recipes, unresolved, seen = 0, 0, 0, {}
        for _, m in pairs(g.members) do
            crafters = crafters + 1
            for _, p in pairs(m.profs or {}) do
                for _, id in ipairs(p.r or {}) do
                    if not seen[id] then
                        seen[id] = true
                        recipes = recipes + 1
                        local c = GH.db.recipes[id]
                        if not c or (not c.o and not c.n) then unresolved = unresolved + 1 end
                    end
                end
            end
        end
        print(("  crafters known: %d, different recipes: %d, without details: %d"):format(crafters, recipes, unresolved))
        local re = GH.RosterEntry(GH.Me())
        print(("  you are %s; roster has you as %s"):format(GH.Me(), re and tostring(re.raw) or "NOT FOUND"))
        local n = GetNumGuildMembers() or 0
        local sample = {}
        for i = 1, math.min(3, n) do sample[#sample + 1] = tostring((GetGuildRosterInfo(i))) end
        print("  roster sample: " .. table.concat(sample, ", "))
        for name in pairs(g.members) do
            if name ~= GH.Me() then
                local e = GH.RosterEntry(name)
                print(("  member %s: id %s, roster %s"):format(name, GH.GuidOf(name) and "known" or "unknown", e and (e.online and "online" or "offline") or "not matched"))
            end
        end
        if GH.Comm and GH.Comm.lastResult ~= nil then
            print(("  last addon message: result %s (0 = sent)"):format(tostring(GH.Comm.lastResult)))
        end
        local me = g.members[GH.Me()]
        if me then
            for pid, p in pairs(me.profs or {}) do
                print(("  you: %s (%d) %d/%d, %d recipes"):format(GH.ProfName(pid), pid, p.s or 0, p.m or 0, #(p.r or {})))
            end
        else
            print("  you: no professions read yet - open each profession window once.")
        end
        if GH.Prof and GH.Prof.Learned then
            local lines, primary = GH.Prof.Learned()
            local t = {}
            for pid in pairs(lines or {}) do t[#t + 1] = GH.ProfName(pid) .. " (" .. pid .. ")" end
            print(("  game says you know: %s%s"):format(#t > 0 and table.concat(t, ", ") or "nothing readable", primary and "" or " (no primary read)"))
        end
        local lists = {}
        for pid, l in pairs(GH.db.allRecipes) do lists[#lists + 1] = GH.ProfName(pid) .. " " .. #l .. (GH.db.allRev[pid] and "" or " (unshared)") end
        print("  full recipe lists (Gaps): " .. (#lists > 0 and table.concat(lists, ", ") or "none yet"))
    end
    local marked = 0
    for _, c in pairs(GH.db.recipes) do if c.t and #c.t > 0 then marked = marked + 1 end end
    local dc = GH.Prof and GH.Prof.DropCount and GH.Prof.DropCount()
    print(("  recipe details cached: %d, with trainer / vendor marks: %d, Dungeon Journal recipe drops: %s"):format(
        Count(GH.db.recipes), marked, dc and tostring(dc) or "addon not loaded"))
end

SLASH_CYSGUILDHALL1 = "/guildhall"
SLASH_CYSGUILDHALL2 = "/cysgh"
SlashCmdList.CYSGUILDHALL = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "check" then
        Check()
    elseif msg == "tooltip" then
        GH.db.settings.tooltip = not GH.db.settings.tooltip
        GH.Print("crafter names on item tooltips " .. (GH.db.settings.tooltip and "on" or "off") .. ".")
    elseif msg == "options" or msg == "settings" or msg == "config" then
        if GH.Window then GH.Window.Open(nil, "options") end
    elseif msg == "gaps" then
        if GH.Window then GH.Window.Open(nil, "gaps") end
    elseif msg == "requests" then
        if GH.Window then GH.Window.Open(nil, "requests") end
    elseif msg == "prep" or msg == "raid" or msg == "raidprep" then
        if GH.Window then GH.Window.Open(nil, "prep") end
    elseif msg == "calendar" or msg == "cal" or msg == "events" then
        if GH.Window then GH.Window.Open(nil, "cal") end
    elseif msg == "minimap" then
        GH.db.settings.minimapHide = not GH.db.settings.minimapHide
        if GH.UpdateMinimapButton then GH.UpdateMinimapButton() end
        GH.Print("minimap button " .. (GH.db.settings.minimapHide and "hidden" or "shown") .. ".")
    elseif msg == "notify" then
        GH.db.settings.notify = not GH.db.settings.notify
        GH.Print("craft request notes in your chat window " .. (GH.db.settings.notify and "on" or "off") .. ".")
    elseif msg == "versions" or msg == "version" then
        GH.Print("you have " .. tostring(GH.version) .. ".")
        local list = GH.Comm and GH.Comm.Versions() or {}
        for _, e in ipairs(list) do
            print(("  %s: %s%s"):format(GH.Short(e.name), e.v or "0.3.11 or older", e.live and "" or " (last seen)"))
        end
        if #list == 0 then print("  no other Guild Hall users seen yet.") end
    elseif msg == "news" or msg == "new" or msg == "changes" then
        if GH.WhatsNew then GH.WhatsNew.Show() end
    elseif msg == "welcome" or msg == "setup" then
        if GH.Welcome then GH.Welcome.Show() end
    elseif msg == "mats" then
        if not (GH.Mats and GH.Mats.ShowLatest()) then GH.Print("none of your requests has been claimed yet.") end
    elseif msg == "sync" then
        if GH.Comm then GH.Comm.Hello(true) end
        GH.Print("asked the guild for newer crafting data.")
    elseif msg == "help" then
        GH.Print("/guildhall - open or close the window; /guildhall <item> - search; requests, prep, calendar, mats, gaps, options, versions, news, welcome, minimap, check, sync, tooltip, notify.")
    elseif msg ~= "" then
        if GH.Window then GH.Window.Open(msg) end
    else
        if GH.Window then GH.Window.Toggle() end
    end
end
