--------------------------------------------------------------------------------
-- Cys's Guild Hall - guild sync (hidden addon messages on the GUILD channel)
--
-- Every member's data is one "entry" (their professions + learned recipe IDs)
-- with a revision number (server time of the last change).
--   H  hello: "here are the entries I have and their revisions" (sent once after login)
--   D  data:  one entry, cut in pieces of ~200 characters
-- Whoever hears a hello and holds a newer entry sends it after a short random wait;
-- if someone else starts sending the same entry first, the others stand down.
-- Sends are throttled and wait while you are in combat.
--------------------------------------------------------------------------------
local GH = CysGuildHall
local C = {}
GH.Comm = C

local CHUNK = 200
local HELLO_CHUNK = 220

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(GH.PREFIX)
end

--------------------------------------------------------------------------------
-- Send queue: a small burst, then about one message a second
--------------------------------------------------------------------------------
local queue = {}
local CAP, REFILL = 6, 1.1
local tokens, lastRefill = CAP, GetTime()
local THROTTLED = {
    [3] = true, [8] = true,
}

function C.QueueSize() return #queue end

local function Pump()
    local now = GetTime()
    tokens = math.min(CAP, tokens + (now - lastRefill) / REFILL)
    lastRefill = now
    if #queue == 0 or InCombatLockdown() or not IsInGuild() then return end
    while #queue > 0 and tokens >= 1 do
        local m = queue[1]
        if m.check and not m.check() then
            table.remove(queue, 1)
        else
            if m.start then m.start() end
            local ok, res = pcall(C_ChatInfo.SendAddonMessage, GH.PREFIX, m.text, "GUILD")
            if ok and type(res) == "number" and THROTTLED[res] then
                tokens = 0
                return
            end
            table.remove(queue, 1)
            tokens = tokens - 1
            if m.done then m.done() end
        end
    end
end
C_Timer.NewTicker(0.25, Pump)

local function Push(text, check, done, start)
    queue[#queue + 1] = { text = text, check = check, done = done, start = start }
end

--------------------------------------------------------------------------------
-- Names inside messages: "Name" when on the sender's realm, else "Name-Realm"
--------------------------------------------------------------------------------
local function OutName(full)
    local n, r = full:match("^(.-)%-(.+)$")
    if n and r == GH.MyRealm() then return n end
    return full
end
local function InName(name, senderRealm)
    if name:find("-", 1, true) then return name end
    return name .. "-" .. (senderRealm or GH.MyRealm())
end

--------------------------------------------------------------------------------
-- Entry encoding: "pid:skill:max:recipe.recipe.recipe;pid:..." (all base 36)
--------------------------------------------------------------------------------
function C.Encode(m)
    local pids = {}
    for pid in pairs(m.profs or {}) do pids[#pids + 1] = pid end
    table.sort(pids)
    local parts = {}
    for _, pid in ipairs(pids) do
        local p = m.profs[pid]
        local r = {}
        for i, id in ipairs(p.r or {}) do r[i] = GH.To36(id) end
        parts[#parts + 1] = GH.To36(pid) .. ":" .. GH.To36(p.s or 0) .. ":" .. GH.To36(p.m or 0) .. ":" .. table.concat(r, ".")
    end
    return table.concat(parts, ";")
end

function C.Decode(body)
    local profs = {}
    if body == "" then return profs end
    for part in body:gmatch("[^;]+") do
        local pid, s, mx, list = part:match("^(%w+):(%w*):(%w*):(.*)$")
        pid = GH.From36(pid)
        if not pid then return nil end
        local r = {}
        for id in list:gmatch("[^%.]+") do
            local v = GH.From36(id)
            if v then r[#r + 1] = v end
        end
        table.sort(r)
        profs[pid] = { s = GH.From36(s) or 0, m = GH.From36(mx) or 0, r = r }
    end
    return profs
end

--------------------------------------------------------------------------------
-- Sending one entry
--------------------------------------------------------------------------------
local pending = {}   -- [full name] = { rev, started }

-- Someone else is sending this entry (same or newer): stand down unless we already started
local function Covered(name, rev)
    local p = pending[name]
    if p and not p.started and p.rev <= rev then pending[name] = nil end
end

function C.SendEntry(name, delay)
    local g = GH.Guild()
    local m = g and g.members[name]
    if not m or (m.rev or 0) == 0 then return end
    local rev = m.rev
    local p = pending[name]
    if p and p.rev >= rev then return end
    local pend = { rev = rev }
    pending[name] = pend
    C_Timer.After(delay or 0, function()
        if pending[name] ~= pend then return end
        local cur = GH.Guild()
        cur = cur and cur.members[name]
        if not cur or cur.rev ~= rev then pending[name] = nil; return end
        local body = C.Encode(cur)
        local n = math.max(1, math.ceil(#body / CHUNK))
        local head = "D~" .. OutName(name) .. "~" .. GH.To36(rev) .. "~"
        local function Live() return pending[name] == pend end
        for i = 1, n do
            local piece = body:sub((i - 1) * CHUNK + 1, i * CHUNK)
            Push(head .. i .. "~" .. n .. "~" .. piece, Live,
                i == n and function()
                    pending[name] = nil
                    if name == GH.Me() then cur.sent = rev end
                end or nil,
                i == 1 and function() pend.started = true end or nil)
        end
    end)
end

--------------------------------------------------------------------------------
-- Hello: list of entries we have
--------------------------------------------------------------------------------
local helloSeq = 0
local helloSent = false

function C.Hello(force)
    if helloSent and not force then return end
    local g = GH.Guild()
    if not g then return end
    helloSent = true
    helloSeq = (helloSeq % 35) + 1
    local items = {}
    for name, m in pairs(g.members) do
        items[#items + 1] = OutName(name) .. "=" .. GH.To36(m.rev or 0)
    end
    table.sort(items)
    local msgs, cur = {}, {}
    local len = 0
    for _, it in ipairs(items) do
        if len + #it + 1 > HELLO_CHUNK and #cur > 0 then
            msgs[#msgs + 1] = table.concat(cur, ",")
            cur, len = {}, 0
        end
        cur[#cur + 1] = it
        len = len + #it + 1
    end
    msgs[#msgs + 1] = table.concat(cur, ",")
    local id = GH.To36(helloSeq)
    for i, body in ipairs(msgs) do
        Push("H~" .. GH.PROTO .. "~" .. id .. "~" .. (i == #msgs and "1" or "0") .. "~" .. body)
    end
    -- our own entry if it changed since we last shared it
    local me = g.members[GH.Me()]
    if me and (me.rev or 0) > 0 and me.sent ~= me.rev then C.SendEntry(GH.Me(), 2) end
end

-- After someone's full hello: send what they are missing (with a random wait so one member answers)
local function Answer(sender, theirs)
    local g = GH.Guild()
    if not g then return end
    local me = GH.Me()
    for name, m in pairs(g.members) do
        local rev = m.rev or 0
        if rev > 0 and name ~= sender and (theirs[name] or 0) < rev then
            local delay = (name == me) and (0.5 + math.random() * 2) or (4 + math.random() * 12)
            C.SendEntry(name, delay)
        end
    end
end

--------------------------------------------------------------------------------
-- Receiving
--------------------------------------------------------------------------------
local incoming = {}   -- [name#rev] = { n, got, parts, t }
local hellos = {}     -- [sender] = { id, list }

local function OnData(text, sender, senderRealm)
    local nm, rev36, i, n, piece = text:match("^D~([^~]+)~(%w+)~(%d+)~(%d+)~(.*)$")
    if not nm then return end
    i, n = tonumber(i), tonumber(n)
    local rev = GH.From36(rev36)
    if not rev or n < 1 or n > 60 or i < 1 or i > n then return end
    local name = InName(nm, senderRealm)
    Covered(name, rev)
    if name == GH.Me() then return end   -- our own data is read from our own profession windows
    local g = GH.Guild()
    if not g then return end
    local have = g.members[name]
    if have and (have.rev or 0) >= rev then return end
    local key = name .. "#" .. rev
    local a = incoming[key]
    if not a then
        a = { n = n, got = 0, parts = {}, t = GetTime() }
        incoming[key] = a
    end
    if a.n ~= n then return end
    if not a.parts[i] then
        a.parts[i] = piece
        a.got = a.got + 1
    end
    if a.got < a.n then return end
    incoming[key] = nil
    local profs = C.Decode(table.concat(a.parts))
    if not profs then return end
    g.members[name] = { rev = rev, profs = profs, seen = have and have.seen }
    GH.Fire("DATA", name)
end

local function OnHello(text, sender, senderRealm)
    local proto, id, last, body = text:match("^H~(%d+)~(%w+)~([01])~(.*)$")
    if not proto then return end
    local h = hellos[sender]
    if not h or h.id ~= id then
        h = { id = id, list = {} }
        hellos[sender] = h
    end
    for nm, rev36 in body:gmatch("([^,=]+)=(%w+)") do
        h.list[InName(nm, senderRealm)] = GH.From36(rev36) or 0
    end
    if last == "1" then
        hellos[sender] = nil
        Answer(sender, h.list)
    end
end

GH.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= GH.PREFIX or channel ~= "GUILD" or not GH.db then return end
    sender = GH.Full(sender)
    if not sender or sender == GH.Me() then return end
    local senderRealm = sender:match("%-(.+)$")
    local kind = text:sub(1, 1)
    if kind == "D" then
        OnData(text, sender, senderRealm)
    elseif kind == "H" then
        OnHello(text, sender, senderRealm)
    end
end)

-- drop half-received entries after two minutes
C_Timer.NewTicker(30, function()
    local now = GetTime()
    for k, a in pairs(incoming) do
        if now - a.t > 120 then incoming[k] = nil end
    end
end)

--------------------------------------------------------------------------------
-- Login: say hello once the guild roster is known; forget members who left
--------------------------------------------------------------------------------
local helloTimer
GH.Listen("ROSTER", function()
    local g = GH.Guild()
    if not g then return end
    -- members who left the guild: only when the whole roster was read, never our own
    -- characters, and only after being missing on 3 roster reads in a row
    local total = GetNumGuildMembers() or 0
    if total > 0 and GH.rosterCount >= total then
        g.missing = g.missing or {}
        local gone
        for name in pairs(g.members) do
            if GH.db.mine[name] or name == GH.Me() or GH.RosterEntry(name) then
                g.missing[name] = nil
            else
                g.missing[name] = (g.missing[name] or 0) + 1
                if g.missing[name] >= 3 then
                    g.members[name] = nil
                    g.missing[name] = nil
                    gone = true
                end
            end
        end
        if gone then GH.Fire("DATA") end
    end
    if not helloSent and not helloTimer then
        helloTimer = C_Timer.NewTimer(15, function() C.Hello() end)
    end
end)
