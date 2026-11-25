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
        local name, rankName, rankIndex, level, _, zone, note, onote, online, _, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(i)
        if type(name) == "string" and name ~= "" then
            local e = { online = online and true or false, class = classFile, level = level, raw = name, rank = rankIndex,
                zone = type(zone) == "string" and zone or nil,
                rankName = type(rankName) == "string" and rankName or nil,
                note = type(note) == "string" and note or nil, onote = type(onote) == "string" and onote or nil }
            -- Forever's roster writes "Name Realm" (a space): make it "Name-Realm" like chat names
            name = name:gsub("^(%S+) (%S+)$", "%1-%2")
            e.full = GH.Full(name)
            -- hours since last online (Roster tab)
            if not e.online and GetGuildRosterLastOnline then
                local ok, y, mo, d, h = pcall(GetGuildRosterLastOnline, i)
                if ok and type(y) == "number" then e.lastH = ((y * 365 + (mo or 0) * 30 + (d or 0)) * 24) + (h or 0) end
            end
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
        GH.PublishMyAlts()
    end
end

--------------------------------------------------------------------------------
-- Alts. Three sources, strongest first:
--   1. links players set themselves (Options > Your main & alts), shared with the guild
--      ("A" messages); every character on your account that runs the addon is added
--      by itself, so a player only has to pick which one is the main
--   2. a note (public, then officer) that says "alt" and names another member
--   3. a member of the alt rank whose note names another member
-- A character someone marked as a main is never made an alt by a note.
--------------------------------------------------------------------------------
GH.altMain = {}      -- [alt full] = main full (only while "Group alts" is on)
GH.altMainAll = {}   -- same, always

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

-- Same, but only when the note itself says "alt" (any rank): "Alt of Bob", "Bob's alt"
local function NoteAltOf(text, self)
    if type(text) ~= "string" then return nil end
    local t = " " .. text:lower() .. " "
    if not t:find("[^%a]alts?[^%a]") then return nil end
    return NoteMain(text, self)
end

-- A member's roster name, or nil when not in the guild
local function InGuild(full)
    local e = full and GH.RosterEntry(full)
    return e and e.full
end

function GH.BuildAlts()
    local lower = {}
    for full, e in pairs(GH.roster) do lower[full:lower()] = e end
    GH.rosterLower = lower
    local all, isMain, owner = {}, {}, {}
    -- 1. links players set themselves (newest wins when two disagree)
    local g = GH.Guild()
    for _, L in pairs(g and g.links or {}) do
        local main = InGuild(L.m)
        if main then
            isMain[main] = true
            for _, a in ipairs(L.a or {}) do
                local alt = InGuild(a)
                if alt and alt ~= main and (not owner[alt] or (L.rev or 0) > owner[alt]) then
                    all[alt], owner[alt] = main, L.rev or 0
                end
            end
        end
    end
    -- 2 + 3. notes
    for full, e in pairs(GH.roster) do
        if not all[full] and not isMain[full] then
            local main
            if GH.IsAltRank(e.rankName) then
                main = NoteMain(e.note, full) or NoteMain(e.onote, full)
            else
                main = NoteAltOf(e.note, full) or NoteAltOf(e.onote, full)
            end
            if main then all[full] = main end
        end
    end
    -- an alt's main that is itself an alt: go up to the real main (no loops)
    local final = {}
    for alt, main in pairs(all) do
        local m, hops = main, 0
        while all[m] and hops < 5 do m, hops = all[m], hops + 1 end
        if m ~= alt then final[alt] = m end
    end
    GH.altMainAll = final
    local map = {}
    if GH.db and GH.db.settings.altGroup then
        for k, v in pairs(final) do map[k] = v end
    end
    GH.altMain = map
end
GH.rosterLower = {}

-- Main of an alt ("First-Last"), or nil when this character is not a known alt
function GH.MainOf(full)
    local e = GH.RosterEntry(full)
    return e and e.full and GH.altMain[e.full] or nil
end

-- Same, whatever the "Group alts" setting
function GH.MainOfAny(full)
    local e = GH.RosterEntry(full)
    return e and e.full and GH.altMainAll[e.full] or nil
end

--------------------------------------------------------------------------------
-- Your own main + alts (one link per account and guild, shared with the guild)
-- g.my = { main = full or nil (nil = guess: highest level), add = { full, ... } typed in,
--          off = { [full] = true } account characters taken out }
-- g.links[account id] = { rev, m = main, a = { alts } }
--------------------------------------------------------------------------------
local function My()
    local g = GH.Guild()
    if not g then return nil end
    g.my = g.my or { add = {}, off = {} }
    g.my.add, g.my.off = g.my.add or {}, g.my.off or {}
    return g.my, g
end
GH.MyAltsCfg = My

-- Every character of yours in this guild: main first, then alts (sorted). Also returns
-- whether the main was picked by you (false = guessed) and the guess (highest level).
function GH.MyChars()
    local my = My()
    if not my then return { GH.Me() }, false, GH.Me() end
    local set, list = {}, {}
    local function Add(full)
        full = InGuild(full)
        if full and not set[full] and not my.off[full] then set[full] = true; list[#list + 1] = full end
    end
    Add(GH.Me())
    for full in pairs(GH.db.mine) do Add(full) end
    for _, full in ipairs(my.add) do Add(full) end
    if #list == 0 then return { GH.Me() }, false, GH.Me() end
    local guess
    for _, full in ipairs(list) do
        local e, b = GH.RosterEntry(full), guess and GH.RosterEntry(guess)
        if not guess or (e.level or 0) > (b.level or 0) or ((e.level or 0) == (b.level or 0) and full < guess) then guess = full end
    end
    local picked = my.main and InGuild(my.main)
    if picked and not set[picked] then picked = nil end
    local main = picked or guess
    local out = { main }
    for _, full in ipairs(list) do if full ~= main then out[#out + 1] = full end end
    table.sort(out, function(a, b)
        if a == main or b == main then return a == main end
        return a < b
    end)
    return out, picked and true or false, guess
end

-- Add an alt by typed name ("First Last" or a first name only one member has).
-- Returns the member's name, or nil + why not.
function GH.AddMyAlt(text)
    local my = My()
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not my or text == "" then return nil end
    local first, last = text:match("^(%S+)[%s%-]+(%S+)$")
    local e = first and GH.rosterLower[(first .. "-" .. last):lower()]
    local full = e and e.full
    if not full then
        local list = GH.rosterFirst[GH.Bare(text)]
        if list and #list == 1 then full = list[1]
        elseif list and #list > 1 then return nil, "more than one member is named " .. text .. ": type the last name too." end
    end
    if not full then return nil, text .. " is not in the guild roster." end
    my.off[full] = nil
    local have
    for _, a in ipairs(my.add) do if a == full then have = true end end
    if not have then my.add[#my.add + 1] = full end
    GH.PublishMyAlts()
    return full
end

-- Take a character out of your alts (an account character stays out until added again)
function GH.RemoveMyAlt(full)
    local my = My()
    if not my or not full then return end
    for i = #my.add, 1, -1 do if my.add[i] == full then table.remove(my.add, i) end end
    my.off[full] = true
    if my.main == full then my.main = nil end
    GH.PublishMyAlts()
end

-- Your main (picked or guessed)
function GH.MyMain()
    return GH.MyChars()[1]
end

-- Your characters as a set: [full] = true
function GH.MyCharSet()
    local set = {}
    for _, c in ipairs(GH.MyChars()) do set[c] = true end
    return set
end

-- Share your link when it changed (and only once you have alts or had a link before)
function GH.PublishMyAlts()
    if not GH.db or not GH.db.acct or GH.rosterCount == 0 then return end
    local _, g = My()
    if not g then return end
    local chars = GH.MyChars()
    local main = chars[1]
    local alts = {}
    for i = 2, #chars do alts[#alts + 1] = chars[i] end
    g.links = g.links or {}
    local have = g.links[GH.db.acct]
    if not have and #alts == 0 then return end
    if have and have.m == main and table.concat(have.a or {}, ",") == table.concat(alts, ",") then return end
    local rev = math.max(GetServerTime(), (have and have.rev or 0) + 1)
    g.links[GH.db.acct] = { rev = rev, m = main, a = alts }
    GH.BuildAlts()
    GH.Fire("ALTS")
    if GH.Comm and GH.Comm.SendLink then GH.Comm.SendLink(GH.db.acct, 0.5) end
end

-- A link from the guild (Comm); the newest revision wins
function GH.ReceiveLink(acct, rev, main, alts)
    local g = GH.Guild()
    if not g or not acct or not rev or acct == GH.db.acct then return end
    g.links = g.links or {}
    local have = g.links[acct]
    if have and (have.rev or 0) >= rev then return end
    g.links[acct] = { rev = rev, m = main, a = alts }
    GH.BuildAlts()
    GH.Fire("ALTS")
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
local DEFAULTS = { font = "clean", tooltip = true, notify = true, doneHours = 24, matsPopup = true, delivery = "m", toasts = true, lootShare = true, altGroup = true, altRank = "", calRemind = true,
    craftSort = "name", shopAuto = true, bankShare = false }

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
    db.lvl = db.lvl or {}           -- [itemID] = level needed to use / equip (0 = none)
    db.shop = db.shop or {}         -- [full] = { { id, q = still to buy when added, c = count then, by = what for } } (shopping list)
    db.mine = db.mine or {}         -- [full] = true for characters on this account (never pruned)
    db.init = db.init or {}         -- [full] = 1 initialized / 2 set up (first-run welcome)
    db.allRecipes = db.allRecipes or {} -- [profID] = { every recipe ID of that profession, learned or not } (Gaps tab)
    db.allRev = db.allRev or {}     -- [profID] = revision of that full list (shared with the guild)
    for pid in pairs(db.allRecipes) do db.allRev[pid] = db.allRev[pid] or GetServerTime() end
    db.acct = db.acct or (GH.To36(math.random(100000000, 2000000000)))  -- this account's id (main + alts link)
    db.guilds = db.guilds or {}     -- [guildKey] = { members = { [full] = { rev, profs = { [profID] = { s, m, r = {recipeIDs} } } } } }
    GH.db = db
    GH.Fire("LOADED")
end)

-- Files added in an update only load after a full game restart (a /reload keeps the
-- old file list). Each release that adds a file lists one table it creates here.
GH.NEW_FILES = { "RosterPanel" }
function GH.NeedsRestart()
    for _, k in ipairs(GH.NEW_FILES) do
        if GH[k] == nil then return true end
    end
    return false
end
GH.On("PLAYER_LOGIN", function()
    if GH.NeedsRestart() then
        C_Timer.After(8, function()
            GH.Print("|cffff6060updated with new files: exit and restart World of Warcraft (a /reload is not enough) to finish the update.|r")
        end)
    end
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
    elseif msg == "alts" or msg == "main" then
        if GH.Window then GH.Window.OpenAlts() end
    elseif msg == "roster" or msg == "members" then
        if GH.RosterPanel then GH.RosterPanel.SetView("members") end
        if GH.Window then GH.Window.Open(nil, "roster") end
    elseif msg == "officer" or msg == "officers" then
        if GH.RosterPanel then GH.RosterPanel.SetView("off") end
        if GH.Window then GH.Window.Open(nil, "roster") end
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
    elseif msg == "shop" or msg == "shopping" or msg == "list" then
        if GH.Mats then GH.Mats.ShowShop() end
    elseif msg == "mats" then
        if not (GH.Mats and GH.Mats.ShowLatest()) then GH.Print("none of your requests has been claimed yet.") end
    elseif msg == "sync" then
        if GH.Comm then GH.Comm.Hello(true) end
        GH.Print("asked the guild for newer crafting data.")
    elseif msg == "help" then
        GH.Print("/guildhall - open or close the window; /guildhall <item> - search; requests, prep, calendar, roster, officer, alts, mats, shop, gaps, options, versions, news, welcome, minimap, check, sync, tooltip, notify.")
    elseif msg ~= "" then
        if GH.Window then GH.Window.Open(msg) end
    else
        if GH.Window then GH.Window.Toggle() end
    end
end
