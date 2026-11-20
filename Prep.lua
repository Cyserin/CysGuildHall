--------------------------------------------------------------------------------
-- Cys's Guild Hall - raid prep targets + gathering assignments
-- Officers set guild targets (an item x a count, e.g. 40 Major Healing Potions).
-- Members claim a part: crafters claim how many of the item they will make,
-- gatherers claim an amount of one of its materials. Everyone keeps their own
-- claim up to date (claimed + delivered), so the guild sees progress.
--
-- Shared through Comm:
--   T~tid~item~count~by~at~state~rev~editor     one target (state a = active, x = removed)
--   C~tid~who~item~claimed~delivered~rev        one member's claim on one part
-- Targets are edited by officers only; a claim only by the member it belongs to,
-- so two people never overwrite each other. Numbers base 36; newest revision wins.
--------------------------------------------------------------------------------
local GH = CysGuildHall
local P = {}
GH.Prep = P

local DAY = 86400
local MAX_N = 9999

local function Targets()
    local g = GH.Guild()
    if not g then return nil end
    g.prep = g.prep or {}
    return g.prep
end

local function ClaimsAll()
    local g = GH.Guild()
    if not g then return nil end
    g.prepC = g.prepC or {}
    return g.prepC
end

local function Claims(tid)
    local all = ClaimsAll()
    if not all then return nil end
    all[tid] = all[tid] or {}
    return all[tid]
end

local function Key(who, item) return who .. "^" .. item end

local function Clamp(n)
    n = math.floor(tonumber(n) or 0)
    if n < 0 then return 0 end
    if n > MAX_N then return MAX_N end
    return n
end

--------------------------------------------------------------------------------
-- Officers: the guild master, or a rank with officer privileges (rank flag 22).
-- Older rank layouts: officer chat speak (flag 4) counts too.
--------------------------------------------------------------------------------
local rankCache = {}   -- [rankIndex] = bool (this session)

local function RankIsOfficer(rankIndex)
    if rankIndex == nil then return nil end
    if rankIndex == 0 then return true end
    if rankCache[rankIndex] ~= nil then return rankCache[rankIndex] end
    local fn = C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags
    local ok, flags = false, nil
    if fn then ok, flags = pcall(fn, rankIndex + 1) end
    local v
    if ok and type(flags) == "table" then
        v = (flags[22] or flags[4]) and true or false
    else
        v = rankIndex <= 1
    end
    rankCache[rankIndex] = v
    return v
end
GH.On("GUILD_RANKS_UPDATE", function() wipe(rankCache) end)

function P.IAmOfficer()
    if IsGuildLeader and IsGuildLeader() then return true end
    if C_GuildInfo and C_GuildInfo.IsGuildOfficer then
        local ok, v = pcall(C_GuildInfo.IsGuildOfficer)
        if ok and v then return true end
    end
    local e = GH.RosterEntry(GH.Me())
    return RankIsOfficer(e and e.rank) and true or false
end

-- Is this member allowed to set targets? Unknown (roster not read / not matched) = yes.
function P.IsOfficer(full)
    if full == GH.Me() then return P.IAmOfficer() end
    local e = GH.RosterEntry(full)
    if not e or e.rank == nil then return true end
    return RankIsOfficer(e.rank) and true or false
end

--------------------------------------------------------------------------------
-- Recipe that makes an item (guild-known first), for the materials list
--------------------------------------------------------------------------------
local recipeCache = {}
GH.Listen("DATA", function() wipe(recipeCache) end)
GH.Listen("INDEX", function() wipe(recipeCache) end)

function P.RecipeFor(itemID)
    local hit = recipeCache[itemID]
    if hit ~= nil then return hit or nil end
    local best, bestKnown
    local I = GH.Index
    for _, rid in ipairs(I and I.RecipesOfItem and I.RecipesOfItem(itemID) or {}) do
        local c = GH.Prof.Resolve(rid)
        if c and c.r and #c.r > 0 and (not best or rid < best) then best, bestKnown = rid, true end
    end
    if not best then
        -- not known in the guild: any cached recipe that makes it (from the shared recipe lists)
        for rid, c in pairs(GH.db.recipes) do
            if c.o == itemID and c.r and #c.r > 0 and (not best or rid < best) then best = rid end
        end
    end
    recipeCache[itemID] = best or false
    return best, bestKnown
end

-- Can the current character make this item?
function P.ICanMake(itemID)
    local I = GH.Index
    for _, rid in ipairs(I and I.RecipesOfItem and I.RecipesOfItem(itemID) or {}) do
        if GH.Requests.ICanMake(rid) then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------
function P.Get(tid)
    local t = Targets()
    return t and t[tid]
end

function P.IsActive(t) return t and t.st == "a" end

-- Parts of a target: the item itself first, then the materials of its recipe.
-- { item, need, made (delivered), claimed, kind = "craft" | "bring" | "gather" }
function P.Parts(t)
    local rid = P.RecipeFor(t.it)
    local c = rid and GH.db.recipes[rid]
    local parts = { { item = t.it, need = t.n, kind = c and "craft" or "bring" } }
    if c and c.r then
        local crafts = math.ceil(t.n / math.max(1, c.q or 1))
        for _, rg in ipairs(c.r) do
            parts[#parts + 1] = { item = rg[1], need = crafts * (rg[2] or 1), kind = "gather" }
        end
    end
    for _, p in ipairs(parts) do p.made, p.claimed, p.people = 0, 0, 0 end
    local idx = {}
    for i, p in ipairs(parts) do idx[p.item] = idx[p.item] or i end
    for _, cl in pairs(Claims(t.id) or {}) do
        local p = idx[cl.i] and parts[idx[cl.i]]
        if p and ((cl.a or 0) > 0 or (cl.d or 0) > 0) then
            p.made = p.made + (cl.d or 0)
            p.claimed = p.claimed + math.max(cl.a or 0, cl.d or 0)
            p.people = p.people + 1
        end
    end
    return parts, rid
end

-- Claims on one part, biggest first: { w, i, a, d, rev }
function P.ClaimsOn(tid, item)
    local out = {}
    for _, cl in pairs(Claims(tid) or {}) do
        if cl.i == item and ((cl.a or 0) > 0 or (cl.d or 0) > 0) then out[#out + 1] = cl end
    end
    table.sort(out, function(a, b)
        local x, y = math.max(a.a or 0, a.d or 0), math.max(b.a or 0, b.d or 0)
        if x ~= y then return x > y end
        return a.w < b.w
    end)
    return out
end

function P.MyClaim(tid, item)
    local l = Claims(tid)
    return l and l[Key(GH.Me(), item)]
end

-- Targets: active first (unfinished before complete), then newest
function P.All()
    local out = {}
    for _, t in pairs(Targets() or {}) do
        if t.st == "a" then
            local parts = P.Parts(t)
            t._made, t._claimed = parts[1].made, parts[1].claimed
            out[#out + 1] = t
        end
    end
    table.sort(out, function(a, b)
        local da, db = a._made >= a.n, b._made >= b.n
        if da ~= db then return db end
        if a.at ~= b.at then return a.at > b.at end
        return a.id < b.id
    end)
    return out
end

--------------------------------------------------------------------------------
-- Changing (sends to the guild)
--------------------------------------------------------------------------------
local function TargetChanged(t)
    GH.Fire("PREP", t.id)
    if GH.Comm and GH.Comm.SendTarget then GH.Comm.SendTarget(t) end
end

local function ClaimChanged(tid, cl, delay)
    GH.Fire("PREP", tid)
    if GH.Comm and GH.Comm.SendClaim then GH.Comm.SendClaim(tid, cl, delay) end
end

function P.New(itemID, n)
    local l = Targets()
    n = Clamp(n)
    if not l or not itemID or n < 1 or not P.IAmOfficer() then return nil end
    GH.db.reqSeq = ((GH.db.reqSeq or 0) + 1) % 1296
    local now = GetServerTime()
    local id = "p" .. GH.To36(now) .. GH.To36(GH.db.reqSeq) .. "." .. GH.Bare(GH.Me())
    local t = { id = id, it = itemID, n = n, by = GH.Me(), at = now, st = "a", rev = now, ed = GH.Me() }
    l[id] = t
    GH.Prof.RequestName(itemID)
    TargetChanged(t)
    return t
end

function P.SetCount(tid, n)
    local t = P.Get(tid)
    n = Clamp(n)
    if not t or n < 1 or t.n == n or not P.IAmOfficer() then return end
    t.n, t.ed = n, GH.Me()
    t.rev = math.max(GetServerTime(), (t.rev or 0) + 1)
    TargetChanged(t)
end

function P.Remove(tid)
    local t = P.Get(tid)
    if not t or t.st ~= "a" or not P.IAmOfficer() then return end
    t.st, t.ed = "x", GH.Me()
    t.rev = math.max(GetServerTime(), (t.rev or 0) + 1)
    TargetChanged(t)
end

-- My claim on one part: claimed and / or delivered (nil keeps the old value)
function P.SetMine(tid, item, claimed, delivered)
    local t = P.Get(tid)
    local l = Claims(tid)
    if not t or not l or not item then return end
    local me = GH.Me()
    local k = Key(me, item)
    local cl = l[k] or { w = me, i = item, a = 0, d = 0, rev = 0 }
    local a = claimed ~= nil and Clamp(claimed) or (cl.a or 0)
    local d = delivered ~= nil and Clamp(delivered) or (cl.d or 0)
    if l[k] and a == cl.a and d == cl.d then return end
    if not l[k] and a == 0 and d == 0 then return end
    cl.a, cl.d = a, d
    cl.rev = math.max(GetServerTime(), (cl.rev or 0) + 1)
    l[k] = cl
    ClaimChanged(tid, cl, 1.5)   -- short wait: quick edits go out as one message
end

--------------------------------------------------------------------------------
-- Incoming (from Comm)
--------------------------------------------------------------------------------
local seenLive = {}   -- [tid] = made count last painted (complete note once)

local function Name(id) return GH.Prof.ItemName(id) or ("item " .. id) end

local function Icon(id)
    local ok, tex = pcall(C_Item.GetItemIconByID, id)
    return ok and tex or nil
end

local function OpenPrep()
    if GH.Window then GH.Window.Open(nil, "prep") end
end

function P.ReceiveTarget(t, sender)
    if not t.id or not t.it or not t.n or t.n < 1 or (t.st ~= "a" and t.st ~= "x") then return end
    local l = Targets()
    if not l then return end
    local have = l[t.id]
    if have and (have.rev or 0) >= t.rev then return end
    -- only officers set or change targets (anyone may pass a copy on: the last editor counts)
    if not P.IsOfficer(t.ed or t.by) then return end
    l[t.id] = t
    GH.Prof.RequestName(t.it)
    GH.Fire("PREP", t.id)
    -- a fresh target (not an old one synced at login)
    if not have and t.st == "a" and t.by ~= GH.Me() and GetServerTime() - (t.at or 0) < 1800 then
        local text = ("%s set a raid prep target: %dx %s."):format(GH.Short(t.by), t.n, Name(t.it))
        if GH.db.settings.notify then GH.Print(text .. " |cffd9a421/guildhall prep|r to claim a part.") end
        if GH.Toast then
            GH.Toast.Add(("|cffffd100%s|r set a raid prep target: %dx %s."):format(GH.Short(t.by), t.n, Name(t.it)), Icon(t.it), nil, OpenPrep)
        end
    end
end

function P.ReceiveClaim(tid, cl, sender)
    -- a claim travels from its owner, or is passed on by anyone in answer to a hello (rev decides)
    if not tid or not cl.w or not cl.i or not cl.rev then return end
    local l = Claims(tid)
    if not l then return end
    local k = Key(cl.w, cl.i)
    local have = l[k]
    if have and (have.rev or 0) >= cl.rev then return end
    if cl.w == GH.Me() and have then return end   -- our own claim: ours is the truth (unless we lost it)
    l[k] = cl
    GH.Fire("PREP", tid)
    -- target just finished: one note while playing
    local t = P.Get(tid)
    if t and t.st == "a" and cl.i == t.it then
        local made = P.Parts(t)[1].made
        local before = seenLive[tid]
        seenLive[tid] = made
        if before and before < t.n and made >= t.n and GH.Toast then
            GH.Toast.Add(("Raid prep done: |cffffd100%dx %s|r."):format(t.n, Name(t.it)), Icon(t.it), nil, OpenPrep)
        end
    end
end

-- remember the current made counts, so only live changes give the "done" note
GH.Listen("ROSTER", function()
    if P.primed then return end
    P.primed = true
    for _, t in pairs(Targets() or {}) do
        if t.st == "a" then seenLive[t.id] = P.Parts(t)[1].made end
    end
end)

--------------------------------------------------------------------------------
-- Hello / answer support (Comm calls these)
--------------------------------------------------------------------------------
-- "$tid=rev" per target, "%tid^who^item=rev" per claim; "$=1" = we understand raid prep
function P.HelloItems(items)
    items[#items + 1] = "$=1"
    for tid, t in pairs(Targets() or {}) do
        items[#items + 1] = "$" .. tid .. "=" .. GH.To36(t.rev or 0)
    end
    for tid, l in pairs(ClaimsAll() or {}) do
        for _, cl in pairs(l) do
            items[#items + 1] = "%" .. tid .. "^" .. cl.w .. "^" .. GH.To36(cl.i) .. "=" .. GH.To36(cl.rev or 0)
        end
    end
end

function P.Answer(theirs)
    if not theirs["$"] or not GH.Comm then return end
    local me = GH.Me()
    for tid, t in pairs(Targets() or {}) do
        if (theirs["$" .. tid] or 0) < (t.rev or 0) then
            GH.Comm.SendTarget(t, (t.by == me) and (0.5 + math.random() * 2) or (4 + math.random() * 12))
        end
    end
    for tid, l in pairs(ClaimsAll() or {}) do
        if Targets()[tid] then
            for _, cl in pairs(l) do
                if (theirs["%" .. tid .. "^" .. cl.w .. "^" .. GH.To36(cl.i)] or 0) < (cl.rev or 0) then
                    GH.Comm.SendClaim(tid, cl, (cl.w == me) and (1 + math.random() * 2) or (6 + math.random() * 14))
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Tooltip lines: "Raid prep: 12 / 40 made" on target items, materials too
--------------------------------------------------------------------------------
function P.TooltipLines(itemID)
    local out
    for _, t in pairs(Targets() or {}) do
        if t.st == "a" then
            local parts = P.Parts(t)
            for i, p in ipairs(parts) do
                if p.item == itemID and p.made < p.need then
                    out = out or {}
                    if i == 1 then
                        out[#out + 1] = ("%d / %d %s"):format(p.made, p.need, p.kind == "craft" and "made" or "in")
                    else
                        out[#out + 1] = ("%d / %d gathered for %s"):format(p.made, p.need, Name(t.it))
                    end
                end
            end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- Old targets fade out: removed after 3 days, any target after 30 days
--------------------------------------------------------------------------------
GH.Listen("ROSTER", function()
    if P.purged then return end
    P.purged = true
    local l, all = Targets(), ClaimsAll()
    if not l then return end
    local now = GetServerTime()
    for tid, t in pairs(l) do
        if (t.st ~= "a" and now - (t.rev or 0) > 3 * DAY) or now - (t.at or 0) > 30 * DAY then l[tid] = nil end
    end
    for tid in pairs(all) do
        if not l[tid] then all[tid] = nil end
    end
end)
