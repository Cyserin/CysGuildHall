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

-- "Name" when on my realm, else "Name-Realm"
function GH.Short(full)
    if not full then return "?" end
    local n, r = full:match("^(.-)%-(.+)$")
    if n and r == GH.MyRealm() then return n end
    return full
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
GH.rosterCount = 0

local function Bare(full)
    return ((full or ""):match("^([^%-]+)") or ""):lower()
end
GH.Bare = Bare

-- roster entry of a member, matched by full name, else by name alone
function GH.RosterEntry(full)
    return GH.roster[full] or GH.rosterBare[Bare(full)]
end

local function ReadRoster()
    if not IsInGuild() then wipe(GH.roster); GH.rosterCount = 0; return end
    local n = GetNumGuildMembers() or 0
    if n == 0 then return end
    local new, bare = {}, {}
    local count = 0
    for i = 1, n do
        local name, _, _, level, _, _, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if type(name) == "string" and name ~= "" then
            local e = { online = online and true or false, class = classFile, level = level, raw = name }
            new[GH.Full(name)] = e
            bare[Bare(name)] = e
            count = count + 1
        end
    end
    if count > 0 then
        GH.roster = new
        GH.rosterBare = bare
        GH.rosterCount = count
        GH.Fire("ROSTER")
    end
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
local DEFAULTS = { tooltip = true, notify = true }

GH.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    CysGuildHallDB = CysGuildHallDB or {}
    local db = CysGuildHallDB
    db.v = db.v or 1
    db.settings = db.settings or {}
    for k, v in pairs(DEFAULTS) do if db.settings[k] == nil then db.settings[k] = v end end
    db.recipes = db.recipes or {}   -- [recipeID] = { o = itemID, q = qty, n = recipe name, p = profID, r = { {itemID, qty}, ... } }
    db.names = db.names or {}       -- [itemID] = name (search works before item data loads)
    db.profNames = db.profNames or {} -- [profID] = name
    db.mine = db.mine or {}         -- [full] = true for characters on this account (never pruned)
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
        if not re then
            local n = GetNumGuildMembers() or 0
            local sample = {}
            for i = 1, math.min(3, n) do sample[#sample + 1] = tostring((GetGuildRosterInfo(i))) end
            print("  roster sample: " .. table.concat(sample, ", "))
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
    end
    print(("  recipe details cached: %d"):format(Count(GH.db.recipes)))
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
    elseif msg == "requests" then
        if GH.Window then GH.Window.Open(nil, "requests") end
    elseif msg == "notify" then
        GH.db.settings.notify = not GH.db.settings.notify
        GH.Print("craft request notes in your chat window " .. (GH.db.settings.notify and "on" or "off") .. ".")
    elseif msg == "sync" then
        if GH.Comm then GH.Comm.Hello(true) end
        GH.Print("asked the guild for newer crafting data.")
    elseif msg == "help" then
        GH.Print("/guildhall - open or close the window; /guildhall <item> - search; requests, check, sync, tooltip, notify.")
    elseif msg ~= "" then
        if GH.Window then GH.Window.Open(msg) end
    else
        if GH.Window then GH.Window.Toggle() end
    end
end
