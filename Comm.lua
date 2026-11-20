--------------------------------------------------------------------------------
-- Cys's Guild Hall - guild sync (hidden addon messages on the GUILD channel)
--
-- Every member's data is one "entry" (their professions + learned recipe IDs)
-- with a revision number (server time of the last change).
--   H  hello: "here are the entries I have and their revisions" (sent once after login)
--   D  data:  one entry, cut in pieces of ~200 characters
--   L  list:  one profession's full recipe list (Gaps), cut the same way (0.3.13+)
--   W / X     "where is recipe N learned?" and the answer (source text + trainers / vendors)
--   N  someone looted a recipe item nobody in the guild knows (0.3.15+)
--   T / C     raid prep targets and members' claims on them (0.3.16+, see Prep.lua)
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
            C.lastResult = ok and res or ("error: " .. tostring(res))
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
C.Push = Push

--------------------------------------------------------------------------------
-- Names inside messages: always the full "First-Last" (Forever's last name sits where a
-- realm would). Names without one (older versions) get theirs from the guild roster.
--------------------------------------------------------------------------------
local function OutName(full)
    return full
end
local function InName(name)
    return GH.Canon(name)
end
C.OutName, C.InName = OutName, InName

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
    for id, r in pairs(g.requests or {}) do
        items[#items + 1] = "#" .. id .. "=" .. GH.To36(r.rev or 0)
    end
    -- full recipe lists (Gaps); "@=1" tells others we understand lists (older versions skip it)
    items[#items + 1] = "@=1"
    for pid, rev in pairs(GH.db.allRev) do
        if GH.db.allRecipes[pid] then items[#items + 1] = "@" .. GH.To36(pid) .. "=" .. GH.To36(rev) end
    end
    -- raid prep targets + claims ("$=1" marks that we understand them)
    if GH.Prep then GH.Prep.HelloItems(items) end
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
    C.SendGuid(0)
    for i, body in ipairs(msgs) do
        Push("H~" .. GH.PROTO .. "~" .. id .. "~" .. (i == #msgs and "1" or "0") .. "~" .. body)
    end
    -- our own entry if it changed since we last shared it
    local me = g.members[GH.Me()]
    if me and (me.rev or 0) > 0 and me.sent ~= me.rev then C.SendEntry(GH.Me(), 2) end
end

-- After someone's full hello: send what they are missing (with a random wait so one member answers)
-- Our character ID, so others can match us in the guild roster (online state, cleanup)
local guidPending = false
function C.SendGuid(delay)
    if guidPending then return end
    local guid = UnitGUID("player")
    if not guid then return end
    guidPending = true
    C_Timer.After(delay or 0, function()
        guidPending = false
        Push("G~" .. OutName(GH.Me()) .. "~" .. guid)
        Push("V~" .. OutName(GH.Me()) .. "~" .. tostring(GH.version))
    end)
end

--------------------------------------------------------------------------------
-- Versions: "V~name~0.3.12" goes out with our character ID (hello + answers).
-- Members whose hello arrives without one run 0.3.11 or older.
--------------------------------------------------------------------------------
C.live = {}          -- [name] = version string, or false = older than 0.3.12 (this session)
local toldNewer      -- newest version we already told the player about

local function SeenVersion(name, ver)
    if not name or name == GH.Me() then return end
    C.live[name] = ver or (C.live[name] or false)
    local g = GH.Guild()
    if g and ver then
        g.vers = g.vers or {}
        g.vers[name] = { v = ver, t = GetServerTime() }
    end
    if ver and GH.VersionNewer(ver, GH.version) and (not toldNewer or GH.VersionNewer(ver, toldNewer)) then
        toldNewer = ver
        GH.Print(("a newer version is out (%s, you have %s). Update from CurseForge when you can."):format(ver, tostring(GH.version)))
    end
    GH.Fire("VERSIONS")
end

-- Guild Hall users and their versions: { name, v (string or nil), live, t }, newest first
function C.Versions()
    local out, seen = {}, {}
    local g = GH.Guild()
    for name, e in pairs(g and g.vers or {}) do
        -- members who left the guild drop off (only once the roster has been read)
        if C.live[name] ~= nil or GH.rosterCount == 0 or GH.RosterEntry(name) then
            seen[name] = true
            local l = C.live[name]
            out[#out + 1] = { name = name, v = (l ~= nil and l) or e.v, live = l ~= nil, t = e.t }
        end
    end
    for name, l in pairs(C.live) do
        if not seen[name] then out[#out + 1] = { name = name, v = l or nil, live = true } end
    end
    table.sort(out, function(a, b)
        if (a.v or "") ~= (b.v or "") then
            if not a.v then return false elseif not b.v then return true end
            return GH.VersionNewer(a.v, b.v)
        end
        return a.name < b.name
    end)
    return out
end

local function Answer(sender, theirs)
    local g = GH.Guild()
    if not g then return end
    C.SendGuid(1 + math.random() * 4)
    local me = GH.Me()
    for name, m in pairs(g.members) do
        local rev = m.rev or 0
        if rev > 0 and name ~= sender and (theirs[name] or 0) < rev then
            local delay = (name == me) and (0.5 + math.random() * 2) or (4 + math.random() * 12)
            C.SendEntry(name, delay)
        end
    end
    for id, r in pairs(g.requests or {}) do
        if (theirs["#" .. id] or 0) < (r.rev or 0) then
            C.SendRequest(r, (r.by == me) and (0.5 + math.random() * 2) or (4 + math.random() * 12))
        end
    end
    -- full recipe lists, only to members who understand them
    if theirs["@"] then
        for pid, rev in pairs(GH.db.allRev) do
            if GH.db.allRecipes[pid] and (theirs["@" .. GH.To36(pid)] or 0) < rev then C.SendList(pid, 6 + math.random() * 14) end
        end
    end
    -- raid prep targets + claims, only to members who understand them
    if GH.Prep then GH.Prep.Answer(theirs) end
    -- my reagent counts for requests I claimed (after the requests themselves)
    if GH.Mats then C_Timer.After(5 + math.random() * 3, GH.Mats.Resend) end
end

--------------------------------------------------------------------------------
-- Craft requests: one message each
-- "R~id~recipe~qty~by~at~state~crafter~rev" (numbers base 36)
--------------------------------------------------------------------------------
local pendingReq = {}   -- [id] = rev waiting to be sent

function C.SendRequest(r, delay)
    if not r or not r.id then return end
    local id, rev = r.id, r.rev
    if pendingReq[id] and pendingReq[id] >= rev then return end
    pendingReq[id] = rev
    C_Timer.After(delay or 0, function()
        if pendingReq[id] ~= rev then return end
        local g = GH.Guild()
        local cur = g and g.requests and g.requests[id]
        if not cur or cur.rev ~= rev then pendingReq[id] = nil; return end
        local text = table.concat({ "R", id, GH.To36(cur.rc), GH.To36(cur.n), OutName(cur.by), GH.To36(cur.at),
            cur.st, cur.cr and OutName(cur.cr) or "", GH.To36(rev) }, "~")
        Push(text, function() return pendingReq[id] == rev end, function() pendingReq[id] = nil end)
        if cur.dl then Push("Q~" .. id .. "~" .. cur.dl) end
    end)
end

local function OnRequest(text, sender, senderRealm)
    local id, rc, n, by, at, st, cr, rev = text:match("^R~([^~]+)~(%w+)~(%w+)~([^~]+)~(%w+)~(%a+)~([^~]*)~(%w+)$")
    if not id then return end
    rev = GH.From36(rev)
    if not rev then return end
    if pendingReq[id] and pendingReq[id] <= rev then pendingReq[id] = nil end
    if GH.Requests then
        GH.Requests.Receive({
            id = id, rc = GH.From36(rc), n = GH.From36(n), by = InName(by, senderRealm), at = GH.From36(at),
            st = st, cr = cr ~= "" and InName(cr, senderRealm) or nil, rev = rev,
        })
    end
end

--------------------------------------------------------------------------------
-- Raid prep (0.3.16+): "T~tid~item~count~by~at~state~rev~editor" and
-- "C~tid~who~item~claimed~delivered~rev" (numbers base 36)
--------------------------------------------------------------------------------
local pendingT = {}   -- [tid] = rev waiting to be sent
local pendingC = {}   -- [tid^who^item] = rev waiting to be sent

function C.SendTarget(t, delay)
    if not t or not t.id then return end
    local id, rev = t.id, t.rev
    if pendingT[id] and pendingT[id] >= rev then return end
    pendingT[id] = rev
    C_Timer.After(delay or 0, function()
        if pendingT[id] ~= rev then return end
        local cur = GH.Prep and GH.Prep.Get(id)
        if not cur or cur.rev ~= rev then pendingT[id] = nil; return end
        local text = table.concat({ "T", id, GH.To36(cur.it), GH.To36(cur.n), OutName(cur.by), GH.To36(cur.at),
            cur.st, GH.To36(rev), OutName(cur.ed or cur.by) }, "~")
        Push(text, function() return pendingT[id] == rev end, function() pendingT[id] = nil end)
    end)
end

function C.SendClaim(tid, cl, delay)
    if not tid or not cl or not cl.w then return end
    local k = tid .. "^" .. cl.w .. "^" .. cl.i
    local rev = cl.rev
    if pendingC[k] and pendingC[k] >= rev then return end
    pendingC[k] = rev
    C_Timer.After(delay or 0, function()
        if pendingC[k] ~= rev or cl.rev ~= rev then return end
        local text = table.concat({ "C", tid, OutName(cl.w), GH.To36(cl.i), GH.To36(cl.a or 0), GH.To36(cl.d or 0), GH.To36(rev) }, "~")
        Push(text, function() return pendingC[k] == rev end, function() pendingC[k] = nil end)
    end)
end

local function OnTarget(text, sender, senderRealm)
    local id, it, n, by, at, st, rev, ed = text:match("^T~([^~]+)~(%w+)~(%w+)~([^~]+)~(%w+)~(%a)~(%w+)~([^~]+)$")
    rev = rev and GH.From36(rev)
    if not rev or not GH.Prep then return end
    if pendingT[id] and pendingT[id] <= rev then pendingT[id] = nil end
    GH.Prep.ReceiveTarget({
        id = id, it = GH.From36(it), n = GH.From36(n), by = InName(by, senderRealm), at = GH.From36(at),
        st = st, rev = rev, ed = InName(ed, senderRealm),
    }, sender)
end

local function OnClaim(text, sender, senderRealm)
    local tid, w, it, a, d, rev = text:match("^C~([^~]+)~([^~]+)~(%w+)~(%w+)~(%w+)~(%w+)$")
    rev = rev and GH.From36(rev)
    if not rev or not GH.Prep then return end
    local cl = { w = InName(w, senderRealm), i = GH.From36(it), a = GH.From36(a) or 0, d = GH.From36(d) or 0, rev = rev }
    if not cl.i then return end
    local k = tid .. "^" .. cl.w .. "^" .. cl.i
    if pendingC[k] and pendingC[k] <= rev then pendingC[k] = nil end
    GH.Prep.ReceiveClaim(tid, cl, sender)
end

--------------------------------------------------------------------------------
-- Full recipe lists (Gaps tab): "L~pid~rev~i~n~id.id.id" (base 36). Lists only grow:
-- what arrives is merged; if we had recipes the sender lacked, ours goes out again.
--------------------------------------------------------------------------------
local pendingList = {}   -- [pid] = { rev, started }
local incomingList = {}  -- [pid#rev] = { n, got, parts, t }

function C.SendList(pid, delay)
    local rev = GH.db.allRev[pid]
    if not rev or not GH.db.allRecipes[pid] then return end
    local p = pendingList[pid]
    if p and p.rev >= rev then return end
    local pend = { rev = rev }
    pendingList[pid] = pend
    C_Timer.After(delay or 0, function()
        if pendingList[pid] ~= pend then return end
        if GH.db.allRev[pid] ~= rev then pendingList[pid] = nil; return end
        local r = {}
        for i, id in ipairs(GH.db.allRecipes[pid]) do r[i] = GH.To36(id) end
        local body = table.concat(r, ".")
        local n = math.max(1, math.ceil(#body / CHUNK))
        if n > 60 then pendingList[pid] = nil; return end
        local head = "L~" .. GH.To36(pid) .. "~" .. GH.To36(rev) .. "~"
        local function Live() return pendingList[pid] == pend end
        for i = 1, n do
            Push(head .. i .. "~" .. n .. "~" .. body:sub((i - 1) * CHUNK + 1, i * CHUNK), Live,
                i == n and function() pendingList[pid] = nil end or nil,
                i == 1 and function() pend.started = true end or nil)
        end
    end)
end

local function OnList(text)
    local pid36, rev36, i, n, piece = text:match("^L~(%w+)~(%w+)~(%d+)~(%d+)~(.*)$")
    if not pid36 then return end
    local pid, rev = GH.From36(pid36), GH.From36(rev36)
    i, n = tonumber(i), tonumber(n)
    if not pid or not rev or n < 1 or n > 60 or i < 1 or i > n then return end
    -- someone else is sending this list (same or newer): stand down unless we already started
    local p = pendingList[pid]
    if p and not p.started and p.rev <= rev then pendingList[pid] = nil end
    local mine = GH.db.allRev[pid]
    if mine and mine >= rev then return end
    local key = pid .. "#" .. rev
    local a = incomingList[key]
    if not a then
        a = { n = n, got = 0, parts = {}, t = GetTime() }
        incomingList[key] = a
    end
    if a.n ~= n then return end
    if not a.parts[i] then a.parts[i] = piece; a.got = a.got + 1 end
    if a.got < a.n then return end
    incomingList[key] = nil
    local ids = {}
    for id in table.concat(a.parts):gmatch("[^%.]+") do
        local v = GH.From36(id)
        if v then ids[#ids + 1] = v end
    end
    if #ids == 0 then return end
    local _, _, extra = GH.Prof.MergeList(pid, ids)
    if extra then
        -- we know recipes the sender did not: ours (the bigger list) goes out
        GH.db.allRev[pid] = math.max(rev, mine or 0) + 1
        C.SendList(pid, 4 + math.random() * 8)
    else
        GH.db.allRev[pid] = rev
    end
    GH.Fire("DATA")
end

--------------------------------------------------------------------------------
-- Where a recipe nobody knows is learned: the game only tells a player who has that
-- profession window open, so the viewer asks ("W~recipe") and a guildmate who read it
-- answers "X~recipe~i~n~marks~source" (marks = kind;name;place;skill joined by ^).
--------------------------------------------------------------------------------
local asked = {}        -- [recipeID] = GetTime() we asked (once a session)
local answering = {}    -- [recipeID] = true while our answer waits
local incomingSrc = {}  -- [recipeID] = { n, got, parts, t }

function C.AskSource(id)
    if not id or asked[id] or not IsInGuild() then return asked[id] end
    asked[id] = GetTime()
    Push("W~" .. GH.To36(id))
    return asked[id]
end

local function Clean(s) return (tostring(s or ""):gsub("[~;%^]", " ")) end

-- A recipe nobody in the guild knows was looted: "N~itemID~name" (0.3.15+)
function C.SendLoot(itemID, name)
    if not itemID then return end
    Push("N~" .. GH.To36(itemID) .. "~" .. Clean(name):sub(1, 120))
end

local function Answerable(c)
    return c and (c.src ~= nil or (c.t and c.t[1] ~= nil))
end

local function OnAsk(text)
    local id = GH.From36(text:match("^W~(%w+)$") or "")
    if not id or answering[id] then return end
    local c = GH.db.recipes[id]
    if not Answerable(c) then return end
    answering[id] = true
    C_Timer.After(1 + math.random() * 5, function()
        if not answering[id] then return end   -- someone answered first
        answering[id] = nil
        local marks = {}
        for _, t in ipairs(c.t or {}) do
            marks[#marks + 1] = table.concat({ Clean(t.k), Clean(t.n), Clean(t.z), t.s and tostring(t.s) or "" }, ";")
        end
        local src = type(c.src) == "string" and c.src:gsub("\r?\n", "|n") or ""
        local body = table.concat(marks, "^") .. "~" .. (c.src == nil and "?" or "=" .. src)
        local n = math.max(1, math.ceil(#body / CHUNK))
        if n > 8 then return end
        local head = "X~" .. GH.To36(id) .. "~"
        for i = 1, n do Push(head .. i .. "~" .. n .. "~" .. body:sub((i - 1) * CHUNK + 1, i * CHUNK)) end
    end)
end

local function OnSource(text)
    local id36, i, n, piece = text:match("^X~(%w+)~(%d+)~(%d+)~(.*)$")
    local id = GH.From36(id36 or "")
    if not id then return end
    i, n = tonumber(i), tonumber(n)
    if n < 1 or n > 8 or i < 1 or i > n then return end
    answering[id] = nil
    local a = incomingSrc[id]
    if not a or a.n ~= n then
        a = { n = n, got = 0, parts = {}, t = GetTime() }
        incomingSrc[id] = a
    end
    if not a.parts[i] then a.parts[i] = piece; a.got = a.got + 1 end
    if a.got < a.n then return end
    incomingSrc[id] = nil
    local marksText, src = table.concat(a.parts):match("^([^~]*)~(.*)$")
    if not marksText then return end
    local c = GH.Prof.Resolve(id)
    if not c then
        c = {}
        GH.db.recipes[id] = c
    end
    local changed = false
    if c.src == nil and src:sub(1, 1) == "=" then c.src = src:sub(2); changed = true end
    local marks = {}
    for m in marksText:gmatch("[^%^]+") do
        local k, nm, z, s = m:match("^([^;]*);([^;]*);([^;]*);([^;]*)$")
        if nm then marks[#marks + 1] = { k = k ~= "" and k or nil, n = nm, z = z, s = tonumber(s) } end
    end
    if GH.Prof.MergeMarks(c, marks) then changed = true end
    if changed then GH.Fire("DATA") end
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
    -- fresh news (changed in the last 30 minutes): a new profession or new recipes
    if GetServerTime() - rev < 1800 then
        local news = {}
        for pid, p in pairs(profs) do
            local old = have and have.profs and have.profs[pid]
            local n = #(p.r or {})
            if not old then
                if n > 0 then news[#news + 1] = { pid = pid, new = true, n = n } end
            elseif n > #(old.r or {}) then
                news[#news + 1] = { pid = pid, n = n - #(old.r or {}) }
            end
        end
        if #news > 0 then GH.Fire("SHARED", name, news) end
    end
end

local function OnHello(text, sender, senderRealm)
    local proto, id, last, body = text:match("^H~(%d+)~(%w+)~([01])~(.*)$")
    if not proto then return end
    if C.live[sender] == nil then SeenVersion(sender, nil) end
    local h = hellos[sender]
    if not h or h.id ~= id then
        h = { id = id, list = {} }
        hellos[sender] = h
    end
    for nm, rev36 in body:gmatch("([^,=]+)=(%w+)") do
        local first = nm:sub(1, 1)
        local key = (first == "#" or first == "@" or first == "$" or first == "%") and nm or InName(nm, senderRealm)
        h.list[key] = GH.From36(rev36) or 0
    end
    if last == "1" then
        hellos[sender] = nil
        Answer(sender, h.list)
    end
end

GH.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if prefix ~= GH.PREFIX or channel ~= "GUILD" or not GH.db then return end
    sender = GH.Canon(sender)
    if not sender or sender == "" or sender == GH.Me() then return end
    local senderRealm = sender:match("%-(.+)$")
    local kind = text:sub(1, 1)
    if kind == "D" then
        OnData(text, sender, senderRealm)
    elseif kind == "H" then
        OnHello(text, sender, senderRealm)
    elseif kind == "R" then
        OnRequest(text, sender, senderRealm)
    elseif kind == "L" then
        OnList(text)
    elseif kind == "W" then
        OnAsk(text)
    elseif kind == "X" then
        OnSource(text)
    elseif kind == "N" then
        local id, name = text:match("^N~(%w+)~(.+)$")
        id = id and GH.From36(id)
        if id then GH.Fire("LOOTED", sender, id, name) end
    elseif kind == "T" then
        OnTarget(text, sender, senderRealm)
    elseif kind == "C" then
        OnClaim(text, sender, senderRealm)
    elseif kind == "Q" then
        local id, dl = text:match("^Q~([^~]+)~(%a)$")
        if id and GH.Requests then GH.Requests.SetDelivery(id, dl) end
    elseif kind == "S" then
        if GH.Mats then GH.Mats.Receive(text, sender) end
    elseif kind == "V" then
        local nm, ver = text:match("^V~([^~]+)~(%d+[%d%.]*)$")
        if nm then SeenVersion(InName(nm, senderRealm), ver) end
    elseif kind == "G" then
        local nm, guid = text:match("^G~([^~]+)~(Player%-[%w%-]+)$")
        local g = GH.Guild()
        if nm and g then
            g.guids = g.guids or {}
            g.guids[InName(nm, senderRealm)] = guid
            GH.Fire("DATA")
        end
    end
end)

-- drop half-received entries after two minutes
C_Timer.NewTicker(30, function()
    local now = GetTime()
    for _, t in ipairs({ incoming, incomingList, incomingSrc }) do
        for k, a in pairs(t) do
            if now - a.t > 120 then t[k] = nil end
        end
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
    -- characters, only members we can check (name match or a known character ID),
    -- and only after being missing on 3 roster reads in a row
    local total = GetNumGuildMembers() or 0
    if total > 0 and GH.rosterCount >= total then
        g.missing = g.missing or {}
        local gone
        for name in pairs(g.members) do
            if GH.db.mine[name] or name == GH.Me() or GH.RosterEntry(name) or not GH.GuidOf(name) then
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
