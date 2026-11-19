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

local function Finish(pid, skill, max, learned, partial, all)
    -- the full list (learned or not) feeds the Gaps tab: recipes nobody in the guild knows
    if all and not partial and #all > 0 then
        table.sort(all)
        GH.db.allRecipes[pid] = all
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

