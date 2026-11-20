--------------------------------------------------------------------------------
-- Cys's Guild Hall - craft requests
-- open -> claimed (a crafter takes it) -> ready (requester has the mats ready)
--      -> done; the requester can cancel any time before done.
-- Shared with the guild through Comm ("R" messages); the newest revision wins.
--------------------------------------------------------------------------------
local GH = CysGuildHall
local R = {}
GH.Requests = R

local ACTIVE = { open = true, claimed = true, ready = true }
local VALID = { open = true, claimed = true, ready = true, done = true, cancelled = true }
local DAY = 86400

local function List()
    local g = GH.Guild()
    if not g then return nil end
    g.requests = g.requests or {}
    return g.requests
end

function R.IsActive(r) return r and ACTIVE[r.st] or false end

-- Can the current character make this recipe?
function R.ICanMake(recipeID)
    local g = GH.Guild()
    local me = g and g.members[GH.Me()]
    if not me then return false end
    for _, p in pairs(me.profs or {}) do
        for _, id in ipairs(p.r or {}) do
            if id == recipeID then return true end
        end
    end
    return false
end

-- Requests sorted: active first, then newest
function R.All()
    local out = {}
    for _, r in pairs(List() or {}) do out[#out + 1] = r end
    table.sort(out, function(a, b)
        local aa, ba = R.IsActive(a), R.IsActive(b)
        if aa ~= ba then return aa end
        if a.at ~= b.at then return a.at > b.at end
        return a.id < b.id
    end)
    return out
end

function R.Get(id)
    local l = List()
    return l and l[id]
end

-- Active requests the current character can act on (badge count)
function R.ForMe()
    local me = GH.Me()
    local n = 0
    for _, r in pairs(List() or {}) do
        if r.st == "open" and r.by ~= me and R.ICanMake(r.rc) then n = n + 1
        elseif r.st == "ready" and r.cr == me then n = n + 1
        elseif r.st == "claimed" and r.by == me then n = n + 1 end
    end
    return n
end

function R.ActiveCount()
    local n = 0
    for _, r in pairs(List() or {}) do if R.IsActive(r) then n = n + 1 end end
    return n
end

local function Changed(r)
    GH.Fire("REQUESTS", r.id)
    if GH.Comm then GH.Comm.SendRequest(r) end
end

-- Delivery: "m" = mail it to me, "t" = meet to trade
R.DELIVERY = { m = "Mail it to me", t = "Meet to trade" }
function R.DeliveryText(r)
    if r.dl == "m" then return "wants it mailed" elseif r.dl == "t" then return "meet to trade" end
end

function R.New(recipeID, qty, dl)
    local l = List()
    if not l or not recipeID then return nil end
    GH.db.reqSeq = ((GH.db.reqSeq or 0) + 1) % 1296
    local now = GetServerTime()
    local id = GH.To36(now) .. GH.To36(GH.db.reqSeq) .. "." .. GH.Bare(GH.Me())
    local r = { id = id, rc = recipeID, n = math.max(1, qty or 1), by = GH.Me(), at = now, st = "open", rev = now,
        dl = R.DELIVERY[dl or ""] and dl or nil }
    l[id] = r
    Changed(r)
    return r
end

function R.Set(id, state, crafter)
    local r = R.Get(id)
    if not r or not VALID[state] then return end
    local old = r.cr
    r.st = state
    if crafter == false then r.cr = nil elseif crafter then r.cr = crafter end
    if r.cr ~= old then r.ms, r.mp = nil, nil end
    r.rev = math.max(GetServerTime(), (r.rev or 0) + 1)
    Changed(r)
end

-- What the current character may do with a request: list of { label, fn }
function R.Actions(r)
    local me = GH.Me()
    local acts = {}
    local mine = r.by == me
    local crafter = r.cr == me
    local can = R.ICanMake(r.rc)
    if r.st == "open" then
        if can and not mine then acts[#acts + 1] = { "Claim", function() R.Set(r.id, "claimed", me) end } end
        if mine then acts[#acts + 1] = { "Cancel", function() R.Set(r.id, "cancelled") end } end
    elseif r.st == "claimed" then
        if mine then acts[#acts + 1] = { "Mats ready", function() R.Set(r.id, "ready") end } end
        if crafter then
            acts[#acts + 1] = { "Done", function() R.Set(r.id, "done") end }
            acts[#acts + 1] = { "Unclaim", function() R.Set(r.id, "open", false) end }
        elseif mine then
            acts[#acts + 1] = { "Cancel", function() R.Set(r.id, "cancelled") end }
        end
    elseif r.st == "ready" then
        if crafter or mine then acts[#acts + 1] = { "Done", function() R.Set(r.id, "done") end } end
        if mine then acts[#acts + 1] = { "Cancel", function() R.Set(r.id, "cancelled") end } end
    end
    return acts
end

function R.StateText(r)
    local who = r.cr and GH.Short(r.cr)
    if r.st == "open" then return "Open - waiting for a crafter", "dim"
    elseif r.st == "claimed" then return "Claimed by " .. (who or "?") .. " - waiting for mats", "accent"
    elseif r.st == "ready" then return "Mats ready - " .. (who or "?") .. " to craft", "accent"
    elseif r.st == "done" then return "Done" .. (who and (" by " .. who) or ""), "green"
    else return "Cancelled", "dim" end
end

--------------------------------------------------------------------------------
-- Incoming (from Comm)
--------------------------------------------------------------------------------
local told = {}
local dlWaiting = {}   -- [id] = delivery that arrived before its request

local function Notify(r)
    if not GH.db.settings.notify or told[r.id] then return end
    local me = GH.Me()
    local name = GH.Index and GH.Index.RecipeName(r.rc) or ("recipe " .. r.rc)
    if r.st == "open" and r.by ~= me and R.ICanMake(r.rc) then
        told[r.id] = true
        local dl = R.DeliveryText(r)
        GH.Print(("%s asks for %dx %s%s - you can make it. |cffd9a421/guildhall|r, Requests tab."):format(GH.Short(r.by), r.n, name, dl and (" (" .. dl .. ")") or ""))
    elseif r.by == me and r.st == "claimed" and r.cr then
        told[r.id] = true
        GH.Print(("%s claimed your request for %dx %s - send the mats, then mark them ready."):format(GH.Short(r.cr), r.n, name))
    end
end

function R.SetDelivery(id, dl)
    if not R.DELIVERY[dl] then return end
    local r = R.Get(id)
    if not r then dlWaiting[id] = dl; return end
    if r.dl == dl then return end
    r.dl = dl
    GH.Fire("REQUESTS", id)
end

function R.Receive(r)
    if not VALID[r.st] or not r.rc or not r.n or r.n < 1 then return end
    local l = List()
    if not l then return end
    local have = l[r.id]
    if have and (have.rev or 0) >= r.rev then return end
    if have and have.st ~= r.st then told[r.id] = nil end
    -- local-only fields: the crafter's reagent counts + pop-up shown, kept while the crafter is the same
    if have and have.cr and have.cr == r.cr then r.ms, r.mp = have.ms, have.mp end
    -- delivery travels in its own message (older versions ignore it)
    r.dl = r.dl or (have and have.dl) or dlWaiting[r.id]
    dlWaiting[r.id] = nil
    l[r.id] = r
    GH.Fire("REQUESTS", r.id)
    Notify(r)
end

--------------------------------------------------------------------------------
-- Old requests fade out: finished after 3 days, unfinished after 21
--------------------------------------------------------------------------------
local function Purge()
    local l = List()
    if not l then return end
    local now = GetServerTime()
    for id, r in pairs(l) do
        local age = now - (r.rev or r.at or 0)
        if (not ACTIVE[r.st] and age > 3 * DAY) or (now - (r.at or 0) > 21 * DAY) then l[id] = nil end
    end
end

GH.Listen("ROSTER", function()
    if R.purged then return end
    R.purged = true
    Purge()
    -- reminder at login: requests waiting on you
    C_Timer.After(20, function()
        local n = R.ForMe()
        if n > 0 and GH.db.settings.notify then
            GH.Print(("%d guild craft %s waiting on you - |cffd9a421/guildhall|r, Requests tab."):format(n, n == 1 and "request" or "requests"))
        end
    end)
end)
