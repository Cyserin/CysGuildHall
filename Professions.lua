--------------------------------------------------------------------------------
-- Cys's Guild Hall - professions
-- Reads your own recipes when you open a profession window, and turns recipe IDs
-- into output items + reagents (cached in CysGuildHallDB.recipes).
--------------------------------------------------------------------------------
local GH = CysGuildHall
local P = {}
GH.Prof = P

-- English fallback names for the classic skill lines (the game's own name wins when it has one)
local PROF_NAMES = {
    [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
    [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting",
    [393] = "Skinning", [185] = "Cooking", [129] = "First Aid", [356] = "Fishing", [755] = "Jewelcrafting",
}

function GH.ProfName(pid)
    pid = tonumber(pid)
    if not pid then return "?" end
    local known = GH.db and GH.db.profNames[pid]
    if known then return known end
    local T = C_TradeSkillUI
    if T and T.GetProfessionInfoBySkillLineID then
        local ok, info = pcall(T.GetProfessionInfoBySkillLineID, pid)
        if ok and info and info.professionName and info.professionName ~= "" then
            local name = info.parentProfessionName ~= "" and info.parentProfessionName or info.professionName
            if GH.db then GH.db.profNames[pid] = name end
            return name
        end
    end
    return PROF_NAMES[pid] or ("Profession " .. pid)
end

--------------------------------------------------------------------------------
-- Recipe details
--------------------------------------------------------------------------------
local BASIC = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1

-- Returns the cache entry for a recipe, filling it from the game when possible.
function P.Resolve(recipeID, force)
    local c = GH.db.recipes[recipeID]
    if c and not force and (c.o or c.n) then return c end
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeSchematic) then return c end
    local ok, s = pcall(T.GetRecipeSchematic, recipeID, false)
    if not ok or type(s) ~= "table" then return c end
    local e = c or {}
    e.n = (s.name ~= "" and s.name) or e.n
    e.q = s.quantityMin or e.q or 1
    local out = s.outputItemID
    if (not out or out == 0) and T.GetRecipeOutputItemData then
        local ok2, data = pcall(T.GetRecipeOutputItemData, recipeID)
        if ok2 and type(data) == "table" and data.itemID and data.itemID > 0 then out = data.itemID end
    end
    if out and out > 0 then e.o = out end
    local reagents = {}
    for _, slot in ipairs(s.reagentSlotSchematics or {}) do
        local r = slot.reagents and slot.reagents[1]
        if r and r.itemID and (slot.reagentType == nil or slot.reagentType == BASIC) then
            reagents[#reagents + 1] = { r.itemID, slot.quantityRequired or 1 }
        end
    end
    if #reagents > 0 or not e.r then e.r = reagents end
    if e.o or e.n then
        GH.db.recipes[recipeID] = e
        if e.o then P.RequestName(e.o) end
        for _, r in ipairs(e.r) do P.RequestName(r[1]) end
    end
    return GH.db.recipes[recipeID]
end

--------------------------------------------------------------------------------
-- Item names (cached so search works before item data loads)
--------------------------------------------------------------------------------
local pendingNames, nameTimer = {}, nil

function P.ItemName(id)
    if not id then return nil end
    local n = C_Item.GetItemNameByID(id)
    if n and n ~= "" then
        if GH.db.names[id] ~= n then GH.db.names[id] = n end
        return n
    end
    P.RequestName(id)
    return GH.db.names[id]
end

function P.RequestName(id)
    if not id or GH.db.names[id] or pendingNames[id] then return end
    local n = C_Item.GetItemNameByID(id)
    if n and n ~= "" then GH.db.names[id] = n; return end
    pendingNames[id] = true
    C_Item.RequestLoadItemDataByID(id)
end

GH.On("ITEM_DATA_LOAD_RESULT", function(id, ok)
    if not pendingNames[id] then return end
    pendingNames[id] = nil
    if ok then
        local n = C_Item.GetItemNameByID(id)
        if n and n ~= "" then GH.db.names[id] = n end
    end
    -- batch: one refresh for a burst of arrivals
    if not nameTimer then
        nameTimer = C_Timer.NewTimer(0.5, function()
            nameTimer = nil
            GH.Fire("NAMES")
        end)
    end
end)

--------------------------------------------------------------------------------
-- Reading your own profession window
--------------------------------------------------------------------------------
local function CanScan()
    local T = C_TradeSkillUI
    if not T then return false end
    for _, fn in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsNPCCrafting", "IsRuneforging" }) do
        if T[fn] then
            local ok, v = pcall(T[fn])
            if ok and v then return false end
        end
    end
    return true
end

local function RecipeIDs()
    local T = C_TradeSkillUI
    local fn = T.GetAllRecipeIDs or T.GetFilteredRecipeIDs
    if not fn then return {} end
    local ok, list = pcall(fn)
    return ok and type(list) == "table" and list or {}
end

-- Which profession is open: id, name, skill, max
local function OpenProfession()
    local T = C_TradeSkillUI
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
    local pid, name
    if base and base.professionID and base.professionID > 0 then
        pid, name = base.professionID, base.professionName
    elseif child and child.professionID and child.professionID > 0 then
        pid = child.parentProfessionID or child.professionID
        name = child.parentProfessionName or child.professionName
    end
    if not pid then return nil end
    local skill, max = 0, 0
    for _, info in ipairs({ child, base }) do
        if info and (info.maxSkillLevel or 0) > 0 then
            skill, max = info.skillLevel or 0, info.maxSkillLevel or 0
            break
        end
    end
    return pid, name, skill, max
end

local scanToken = 0

-- Adds recipe IDs to a profession's full list. Returns the list and whether it grew
-- (extra = the IDs we have that are not in ids).
function P.MergeList(pid, ids)
    local cur = GH.db.allRecipes[pid]
    local have, out, grew = {}, {}, false
    for _, id in ipairs(cur or {}) do
        if not have[id] then have[id] = true; out[#out + 1] = id end
    end
    local theirs = {}
    for _, id in ipairs(ids) do
        theirs[id] = true
        if not have[id] then have[id] = true; out[#out + 1] = id; grew = true end
    end
    local extra = false
    for _, id in ipairs(cur or {}) do if not theirs[id] then extra = true; break end end
    table.sort(out)
    GH.db.allRecipes[pid] = out
    return out, grew or not cur, extra
end

local function Finish(pid, skill, max, learned, partial, all)
    -- the full list (learned or not) feeds the Gaps tab: recipes nobody in the guild knows
    if all and not partial and #all > 0 then
        -- merged with what the guild sent (a list never shrinks); a longer list is shared again
        local merged, grew = P.MergeList(pid, all)
        if grew or not GH.db.allRev[pid] then
            GH.db.allRev[pid] = math.max(GetServerTime(), (GH.db.allRev[pid] or 0) + 1)
            if GH.Comm then GH.Comm.SendList(pid, 3) end
        end
    end
    local g = GH.Guild()
    if not g then return end
    local me = GH.Me()
    local m = g.members[me]
    if not m then
        m = { rev = 0, profs = {} }
        g.members[me] = m
    end
    local old = m.profs[pid]
    -- only the filtered list was readable: keep recipes we saw before (never shrink on a filter)
    if partial and old and old.r then
        local have = {}
        for _, id in ipairs(learned) do have[id] = true end
        for _, id in ipairs(old.r) do if not have[id] then learned[#learned + 1] = id end end
    end
    table.sort(learned)
    local changed = not old or old.s ~= skill or old.m ~= max or #(old.r or {}) ~= #learned
    if not changed then
        for i = 1, #learned do
            if old.r[i] ~= learned[i] then changed = true; break end
        end
    end
    m.profs[pid] = { s = skill, m = max, r = learned }
    GH.db.mine[me] = true
    m.seen = GetServerTime()
    if changed then
        m.rev = math.max(GetServerTime(), (m.rev or 0) + 1)
        GH.Fire("DATA", me)
        if GH.Comm then GH.Comm.SendEntry(me) end
    end
end

function P.Scan()
    if not GH.db or not CanScan() then return end
    local pid, name, skill, max = OpenProfession()
    if not pid then return end
    if name and name ~= "" then GH.db.profNames[pid] = name end
    local ids = RecipeIDs()
    if #ids == 0 then return end
    scanToken = scanToken + 1
    local token = scanToken
    local learned, all, i = {}, {}, 1
    -- time budget: a few ms a frame, so a big recipe list never stutters
    local function Step()
        if token ~= scanToken then return end
        local stop = debugprofilestop() + 3
        while i <= #ids do
            local id = ids[i]
            i = i + 1
            local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, id)
            if ok and info then all[#all + 1] = id end
            -- where an unknown recipe is learned (drop, vendor, quest...): the game only answers
            -- while the profession window is open, so it is saved now for the Gaps tab
            if ok and info and not info.learned and C_TradeSkillUI.GetRecipeSourceText then
                local c = P.Resolve(id)
                if c then
                    local ok2, src = pcall(C_TradeSkillUI.GetRecipeSourceText, id)
                    c.src = (ok2 and type(src) == "string") and src or ""
                    c.p = c.p or pid
                end
            end
            if ok and info and info.learned then
                learned[#learned + 1] = id
                local c = P.Resolve(id, true)
                if c then c.p = pid end
            end
            if debugprofilestop() > stop then
                C_Timer.After(0, Step)
                return
            end
        end
        Finish(pid, skill, max, learned, not C_TradeSkillUI.GetAllRecipeIDs, all)
    end
    Step()
end

local scanTimer
local function ScanSoon()
    if scanTimer then scanTimer:Cancel() end
    scanTimer = C_Timer.NewTimer(0.6, function() scanTimer = nil; P.Scan() end)
end

GH.On("TRADE_SKILL_SHOW", ScanSoon)

-- Which profession window is open right now (for the Craft button)
local profShown = false
GH.On("TRADE_SKILL_SHOW", function()
    profShown = true
    C_Timer.After(0.3, function() GH.Fire("PROFWIN") end)
end)
GH.On("TRADE_SKILL_CLOSE", function()
    profShown = false
    GH.Fire("PROFWIN")
end)
local winTimer
GH.On("TRADE_SKILL_LIST_UPDATE", function()
    if not profShown or winTimer then return end
    winTimer = C_Timer.NewTimer(0.5, function() winTimer = nil; GH.Fire("PROFWIN") end)
end)
function P.IsOpen(pid)
    if not profShown or not CanScan() then return false end
    local ok, open = pcall(OpenProfession)
    return ok and open == pid
end
GH.On("TRADE_SKILL_LIST_UPDATE", ScanSoon)
GH.On("NEW_RECIPE_LEARNED", ScanSoon)

--------------------------------------------------------------------------------
-- Professions you dropped: removed from your shared entry
--------------------------------------------------------------------------------
-- Primary professions (the two slots). Secondary ones (Cooking, First Aid, Fishing) are never
-- removed by themselves: the game does not always list them.
local PRIMARY = { [164] = true, [165] = true, [171] = true, [182] = true, [186] = true, [197] = true,
    [202] = true, [333] = true, [393] = true, [755] = true }
P.PRIMARY = PRIMARY

-- Professions listed on the Gaps tab (ones with a crafting window; gathering-only ones never show crafters)
P.CRAFTS = { 171, 164, 185, 333, 202, 129, 165, 186, 197 }

-- Skill lines the game says this character knows: set, gotPrimary (nil when the API is missing)
function P.Learned()
    if not GetProfessions or not GetProfessionInfo then return nil end
    local ok, a, b, c, d, e, f = pcall(GetProfessions)
    if not ok then return nil end
    local set, primary = {}, false
    for slot, idx in pairs({ a, b, c, d, e, f }) do
        if idx then
            local ok2, _, _, _, _, _, _, line = pcall(GetProfessionInfo, idx)
            if ok2 and type(line) == "number" and line > 0 then
                set[line] = true
                -- counts only when the ID is one we store (if Forever numbered skill lines
                -- differently, nothing is ever removed)
                if slot <= 2 and PRIMARY[line] then primary = true end
            end
        end
    end
    return set, primary
end

-- Remove one profession from a character's entry (yours or one of your own characters)
function P.Forget(full, pid)
    local g = GH.Guild()
    local m = g and g.members[full]
    if not m or not m.profs or not m.profs[pid] then return false end
    m.profs[pid] = nil
    m.rev = math.max(GetServerTime(), (m.rev or 0) + 1)
    GH.Fire("DATA", full)
    if GH.Comm then GH.Comm.SendEntry(full) end
    return true
end

local function PruneMine()
    local g = GH.Guild()
    local m = g and g.members[GH.Me()]
    if not m or not m.profs then return end
    local set, primary = P.Learned()
    -- only trust the game when it lists at least one primary profession (an empty answer
    -- can just mean the data is not loaded yet)
    if not set or not primary then return end
    local gone = {}
    for pid in pairs(m.profs) do
        if PRIMARY[pid] and not set[pid] then gone[#gone + 1] = pid end
    end
    for _, pid in ipairs(gone) do
        local name = GH.ProfName(pid)
        if P.Forget(GH.Me(), pid) then GH.Print(name .. " is no longer one of your professions: removed from the guild list.") end
    end
end

local pruneTimer
local function PruneSoon(delay)
    if pruneTimer then pruneTimer:Cancel() end
    pruneTimer = C_Timer.NewTimer(delay or 2, function() pruneTimer = nil; PruneMine() end)
end
GH.On("PLAYER_LOGIN", function() PruneSoon(8) end)
GH.On("SKILL_LINES_CHANGED", function() PruneSoon(2) end)


--------------------------------------------------------------------------------
-- Where unknown recipes come from (Gaps tab), besides the game's own source text:
--   trainers and vendors you visit (saved on the recipe as c.t), and boss / trash / quest
--   drops read live from the Forever Dungeon Journal addon when it is loaded
--------------------------------------------------------------------------------
local STATE_WORDS = { available = true, unavailable = true, used = true, header = true }
local MAX_PLACES = 4   -- trainers + vendors remembered per recipe
local PREFIXES = { pattern = true, plans = true, recipe = true, formula = true, schematic = true,
    blueprint = true, manual = true, design = true }

local function Key(s)
    if type(s) ~= "string" or s == "" then return nil end
    return (s:lower():gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "Pattern: Red Linen Robe" -> "red linen robe" (nil when the name is not a recipe item)
local function RecipeItemKey(name, force)
    if type(name) ~= "string" then return nil end
    local pre, rest = name:match("^%s*([^:]+):%s*(.+)$")
    if pre and (force or PREFIXES[pre:lower()]) then return Key(rest) end
    return nil
end
P.Key, P.RecipeItemKey = Key, RecipeItemKey

-- Saves one trainer / vendor on a recipe; true when it is new for that recipe
local function Mark(c, kind, who, where, skill)
    c.t = c.t or {}
    for _, t in ipairs(c.t) do
        if t.n == who and t.k == kind then
            t.z, t.s = where, skill
            return false
        end
    end
    if #c.t >= MAX_PLACES then return false end
    c.t[#c.t + 1] = { k = kind, n = who, z = where, s = skill }
    return true
end

-- Marks sent by a guildmate: { { k, n, z, s }, ... }; true when any was new
function P.MergeMarks(c, marks)
    local new = false
    for _, t in ipairs(marks or {}) do
        if t.n and t.n ~= "" and Mark(c, t.k or "Trainer", t.n, t.z, t.s) then new = true end
    end
    return new
end

local function Here()
    local zone = (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or ""
    local sub = GetSubZoneText and GetSubZoneText() or ""
    return (sub ~= "" and sub ~= zone) and (sub .. ", " .. zone) or zone
end

-- Matches names against every recipe of the professions your characters have read
-- (recipe name and item name), time-budgeted. wanted = { { k = key, s = skill }, ... }
local markToken = 0
local function MarkRecipes(kind, wanted, verb)
    if #wanted == 0 then return end
    local ids = {}
    for _, list in pairs(GH.db.allRecipes) do
        for _, id in ipairs(list) do ids[#ids + 1] = id end
    end
    if #ids == 0 then return end
    local who, where = UnitName("npc") or kind, Here()
    markToken = markToken + 1
    local token = markToken
    local byName, i = {}, 1
    local function Add(name, id)
        local k = Key(name)
        if not k then return end
        byName[k] = byName[k] or {}
        byName[k][id] = true
    end
    local function Step()
        if token ~= markToken then return end
        local stop = debugprofilestop() + 3
        while i <= #ids do
            local id = ids[i]
            i = i + 1
            local c = GH.db.recipes[id]
            if not (c and c.n) then c = P.Resolve(id) end
            if c then
                Add(c.n, id)
                if c.o then Add(GH.db.names[c.o], id) end
            end
            if debugprofilestop() > stop then
                C_Timer.After(0, Step)
                return
            end
        end
        local new, seen = 0, {}
        for _, w in ipairs(wanted) do
            for id in pairs(byName[w.k] or {}) do
                local c = GH.db.recipes[id]
                if c and not seen[id] then
                    seen[id] = true
                    if Mark(c, kind, who, where, w.s) then new = new + 1 end
                end
            end
        end
        if next(seen) then GH.Fire("DATA") end
        if new > 0 then
            GH.Print(("%s %s %d recipe%s: marked on the Gaps tab."):format(who, verb, new, new == 1 and "" or "s"))
        end
    end
    Step()
end

-- Trainers: every service line is a recipe name
local function ReadTrainer()
    if not GH.db or not GetNumTrainerServices or not GetTrainerServiceInfo then return end
    local ok, num = pcall(GetNumTrainerServices)
    if not ok or not num or num == 0 then return end
    local wanted = {}
    for i = 1, num do
        local t = { pcall(GetTrainerServiceInfo, i) }
        if t[1] and type(t[2]) == "string" then
            local state
            for k = 3, 9 do
                if type(t[k]) == "string" and STATE_WORDS[t[k]] then state = t[k]; break end
            end
            local skill
            if GetTrainerServiceSkillReq then
                local ok2, _, lvl = pcall(GetTrainerServiceSkillReq, i)
                if ok2 and tonumber(lvl) and tonumber(lvl) > 0 then skill = tonumber(lvl) end
            end
            local k = Key(t[2])
            if k and state ~= "header" then wanted[#wanted + 1] = { k = k, s = skill } end
        end
    end
    MarkRecipes("Trainer", wanted, "teaches")
end

-- Vendors (incl. the Waylaid supply quartermasters): only items named "Pattern: ...", "Plans: ..."
local function MerchantName(i)
    local ok, link = pcall(GetMerchantItemLink, i)
    local name = ok and type(link) == "string" and link:match("%[(.-)%]")
    if name then return name end
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok2, info = pcall(C_MerchantFrame.GetItemInfo, i)
        if ok2 and type(info) == "table" then return info.name end
    end
    if GetMerchantItemInfo then
        local ok3, n = pcall(GetMerchantItemInfo, i)
        if ok3 and type(n) == "string" then return n end
    end
end

local function ReadVendor()
    if not GH.db or not GetMerchantNumItems or not GetMerchantItemLink then return end
    local ok, num = pcall(GetMerchantNumItems)
    if not ok or not num or num == 0 then return end
    local wanted = {}
    for i = 1, num do
        local k = RecipeItemKey(MerchantName(i))
        if k then wanted[#wanted + 1] = { k = k } end
    end
    MarkRecipes("Vendor", wanted, "sells")
end

local trainTimer, vendTimer
local function TrainerSoon()
    if trainTimer then trainTimer:Cancel() end
    trainTimer = C_Timer.NewTimer(0.4, function() trainTimer = nil; ReadTrainer() end)
end
local function VendorSoon()
    if vendTimer then vendTimer:Cancel() end
    vendTimer = C_Timer.NewTimer(0.6, function() vendTimer = nil; ReadVendor() end)
end
GH.On("TRAINER_SHOW", TrainerSoon)
GH.On("TRAINER_UPDATE", TrainerSoon)
GH.On("MERCHANT_SHOW", VendorSoon)
GH.On("MERCHANT_UPDATE", VendorSoon)
P.ReadTrainer, P.ReadVendor = ReadTrainer, ReadVendor

-- Dungeon Journal drops: [recipe key] = { "Boss (Dungeon)", ... }, built once on first use
local drops
local function JournalDrops()
    if drops then return drops end
    local ns = _G.ForeverDungeonJournal_NS
    local db = type(ns) == "table" and type(ns.DB) == "table" and ns.DB
    if not db then return nil end
    drops = {}
    local function Add(name, isRecipe, text)
        local k = RecipeItemKey(name, isRecipe)
        if not k then return end
        local list = drops[k] or {}
        drops[k] = list
        for _, s in ipairs(list) do if s == text then return end end
        list[#list + 1] = text
    end
    for dname, d in pairs(db) do
        if type(d) == "table" then
            for _, b in ipairs(type(d.bosses) == "table" and d.bosses or {}) do
                if type(b) == "table" and type(b.loot) == "table" and not b.recipeTab then
                    for _, it in ipairs(b.loot) do
                        if type(it) == "table" and type(it[2]) == "string" then
                            local isRecipe = type(it[3]) == "string" and it[3]:find("^Recipe") ~= nil
                            local text = b.trash and ("Trash in " .. dname .. (type(it[5]) == "string" and (": " .. it[5]) or ""))
                                or ("Drop: " .. tostring(b.name or "a boss") .. " (" .. dname .. ")")
                            Add(it[2], isRecipe, text)
                        end
                    end
                end
            end
            for _, q in ipairs(type(d.quests) == "table" and d.quests or {}) do
                if type(q) == "table" and type(q.rewardItems) == "table" then
                    for _, it in ipairs(q.rewardItems) do
                        if type(it) == "table" then
                            Add(it[2], false, "Quest reward: " .. tostring(q.name or "a quest") .. " (" .. dname .. ")")
                        end
                    end
                end
            end
        end
    end
    return drops
end

local function DropsFor(c)
    local idx = JournalDrops()
    if not idx or not c then return nil end
    return idx[Key(c.n) or ""] or (c.o and idx[Key(GH.db.names[c.o]) or ""]) or nil
end

-- Short kind for list rows: "Trainer", "Vendor", "Drop", "Quest" (nil = use the game's text)
function P.SourceKind(c)
    if not c then return nil end
    if c.t and c.t[1] then return c.t[1].k or "Trainer" end
    local d = DropsFor(c)
    if d then return d[1]:match("^Quest") and "Quest" or "Drop" end
    return nil
end

-- Detail lines (nil when we know nothing beyond the game's own source text)
function P.SourceLines(c)
    if not c then return nil end
    local lines = {}
    for _, t in ipairs(c.t or {}) do
        lines[#lines + 1] = (t.k or "Trainer") .. ": " .. t.n .. ((t.z and t.z ~= "") and (" (" .. t.z .. ")") or "")
            .. (t.s and (", needs skill " .. t.s) or "")
    end
    local d = DropsFor(c)
    if d then
        for i = 1, math.min(3, #d) do lines[#lines + 1] = d[i] end
        if #d > 3 then lines[#lines + 1] = ("...and %d more in the Dungeon Journal"):format(#d - 3) end
    end
    return #lines > 0 and lines or nil
end

function P.DropCount()
    local idx = JournalDrops()
    if not idx then return nil end
    local n = 0
    for _ in pairs(idx) do n = n + 1 end
    return n
end
