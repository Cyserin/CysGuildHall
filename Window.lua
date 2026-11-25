--------------------------------------------------------------------------------
-- Cys's Guild Hall - search index + main window
--------------------------------------------------------------------------------
local GH = CysGuildHall
local S = GH.Style

--------------------------------------------------------------------------------
-- Index: recipe -> crafters, item -> recipes, profession summaries
--------------------------------------------------------------------------------
local I = {}
GH.Index = I

local dirty = true
local byRecipe, byItem, profs = {}, {}, {}
local mineKnown = {}   -- [recipeID] = profID: recipes this character knows
local unresolved, tried = {}, {}
local working = false

GH.Listen("DATA", function() dirty = true end)
GH.Listen("GUILD", function() dirty = true end)

--------------------------------------------------------------------------------
-- Bind on Pickup products are hidden everywhere: a guildmate can't hand them over.
-- Bind type comes with the item data; it is saved once known (db.bind).
--------------------------------------------------------------------------------
local bindAsked, bindTimer = {}, nil
local ItemInfo = C_Item.GetItemInfo or GetItemInfo

function I.IsBoP(recipeID)
    local c = GH.db.recipes[recipeID]
    local o = c and c.o
    if not o then return false end
    local b = GH.db.bind[o]
    if b == nil then
        local bt = select(14, ItemInfo(o))
        if bt then
            GH.db.bind[o] = bt
            b = bt
        elseif not bindAsked[o] then
            bindAsked[o] = true
            C_Item.RequestLoadItemDataByID(o)
        end
    end
    return b == 1
end

GH.On("ITEM_DATA_LOAD_RESULT", function(id, ok)
    if not bindAsked[id] then return end
    bindAsked[id] = nil
    if not ok then return end
    local bt = select(14, ItemInfo(id))
    if bt == nil then return end
    GH.db.bind[id] = bt
    if bt == 1 then
        dirty = true
        if not bindTimer then
            bindTimer = C_Timer.NewTimer(0.5, function()
                bindTimer = nil
                GH.Fire("INDEX")
            end)
        end
    end
end)

--------------------------------------------------------------------------------
-- Level needed to use / equip a product (0 = none). Comes with the item data; saved once known (db.lvl).
--------------------------------------------------------------------------------
local lvlAsked, lvlTimer = {}, nil
function I.ReqLevel(itemID)
    if not itemID or not GH.db then return 0 end
    local v = GH.db.lvl[itemID]
    if v then return v end
    local lv = select(5, ItemInfo(itemID))
    if lv then
        GH.db.lvl[itemID] = lv
        return lv
    end
    if not lvlAsked[itemID] then
        lvlAsked[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end
    return 0
end

GH.On("ITEM_DATA_LOAD_RESULT", function(id, ok)
    if not lvlAsked[id] then return end
    lvlAsked[id] = nil
    if not ok then return end
    local lv = select(5, ItemInfo(id))
    if lv == nil then return end
    GH.db.lvl[id] = lv
    if lv > 1 and not lvlTimer then
        lvlTimer = C_Timer.NewTimer(0.5, function()
            lvlTimer = nil
            GH.Fire("INDEX")
        end)
    end
end)

local Work
function Work()
    if #unresolved == 0 then working = false; return end
    working = true
    local stop = debugprofilestop() + 3
    local got = false
    while #unresolved > 0 do
        local id = table.remove(unresolved)
        local c = GH.Prof.Resolve(id)
        if c and (c.o or c.n) then got = true end
        if debugprofilestop() > stop then break end
    end
    if got then dirty = true end
    if #unresolved > 0 then
        C_Timer.After(0, Work)
    else
        working = false
        GH.Fire("INDEX")
    end
end

function I.Build()
    if not dirty then return end
    dirty = false
    wipe(byRecipe); wipe(byItem); wipe(profs); wipe(mineKnown)
    local g = GH.Guild()
    if not g or not GH.db then return end
    local me = GH.Me()
    for name, m in pairs(g.members) do
        for pid, p in pairs(m.profs or {}) do
            local pr = profs[pid]
            if not pr then
                pr = { pid = pid, crafters = 0, best = 0, max = 0, recipes = {} }
                profs[pid] = pr
            end
            pr.crafters = pr.crafters + 1
            if (p.s or 0) > pr.best then pr.best, pr.max = p.s or 0, p.m or 0 end
            for _, id in ipairs(p.r or {}) do
                if name == me then mineKnown[id] = pid end
                if not I.IsBoP(id) then
                    pr.recipes[id] = true
                    local list = byRecipe[id]
                    if not list then list = {}; byRecipe[id] = list end
                    list[#list + 1] = { name = name, s = p.s or 0, m = p.m or 0, pid = pid }
                end
            end
        end
    end
    for id in pairs(byRecipe) do
        local c = GH.db.recipes[id]
        if c and c.o then
            local l = byItem[c.o]
            if not l then l = {}; byItem[c.o] = l end
            l[#l + 1] = id
        elseif not c and not tried[id] then
            tried[id] = true
            unresolved[#unresolved + 1] = id
        end
    end
    if #unresolved > 0 and not working then C_Timer.After(0, Work) end
end

-- Profession ID when this character knows the recipe
function I.IKnow(recipeID)
    I.Build()
    return mineKnown[recipeID]
end

local function SortCrafters(list)
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.s ~= b.s then return a.s > b.s end
        return a.name < b.name
    end)
    return list
end

-- Alts under their main: one line per player. The line is the main when the main can make
-- it (main's own skill, alt names only in the hover tooltip), else that player's best alt.
-- c.chars = every character of that player in the list (main first), c.altOf = the main's
-- name when the line is an alt whose main can't make it.
local function GroupAlts(list)
    if not GH.db.settings.altGroup or not next(GH.altMain) then return list end
    local groups, order = {}, {}
    for _, c in ipairs(list) do
        local own = GH.RosterName(c.name)
        local key = GH.MainOf(c.name) or own
        c.isMain = (key == own)
        local grp = groups[key]
        if not grp then grp = {}; groups[key] = grp; order[#order + 1] = key end
        grp[#grp + 1] = c
    end
    if #order == #list then
        -- nobody shares a line: only mark alts whose main is not in the list
        for _, c in ipairs(list) do
            if not c.isMain then c.altOf = GH.MainOf(c.name) end
        end
        return list
    end
    local out = {}
    for _, key in ipairs(order) do
        local grp = groups[key]
        table.sort(grp, function(a, b)
            if a.isMain ~= b.isMain then return a.isMain end
            if a.online ~= b.online then return a.online end
            if a.s ~= b.s then return a.s > b.s end
            return a.name < b.name
        end)
        local head = grp[1]
        local e = { name = head.name, s = head.s, m = head.m, pid = head.pid, online = head.online }
        for i = 2, #grp do
            local o = grp[i]
            if o.online then e.online = true end
            if not head.isMain and o.s > e.s then e.s, e.m = o.s, o.m end
        end
        if #grp > 1 then e.chars = grp end
        if not head.isMain then e.altOf = key end
        out[#out + 1] = e
    end
    return out
end
I.GroupAlts = GroupAlts

-- crafters of a recipe, online first
function I.Crafters(recipeID)
    I.Build()
    local out = {}
    for _, c in ipairs(byRecipe[recipeID] or {}) do
        out[#out + 1] = { name = c.name, s = c.s, m = c.m, pid = c.pid, online = GH.IsOnline(c.name) or false }
    end
    return SortCrafters(GroupAlts(out))
end

-- crafters of an item (any recipe that makes it), one line per person
function I.CraftersOfItem(itemID)
    I.Build()
    local recipes = byItem[itemID]
    if not recipes then return nil end
    local seen, out = {}, {}
    for _, rid in ipairs(recipes) do
        for _, c in ipairs(byRecipe[rid] or {}) do
            if not seen[c.name] then
                seen[c.name] = true
                out[#out + 1] = { name = c.name, s = c.s, m = c.m, pid = c.pid, online = GH.IsOnline(c.name) or false }
            end
        end
    end
    return SortCrafters(GroupAlts(out))
end

-- recipes known in the guild that make this item
function I.RecipesOfItem(itemID)
    I.Build()
    return byItem[itemID] or {}
end

function I.RecipeName(id)
    local c = GH.db.recipes[id]
    if c and c.o then
        local n = GH.Prof.ItemName(c.o)
        if n then return n end
    end
    return (c and c.n) or ("Recipe " .. id)
end

-- Summary of one profession across the guild (nil when nobody has it)
function I.ProfInfo(pid)
    I.Build()
    return profs[pid]
end

-- Recipes nobody in the guild knows, from the full recipe lists the guild shares.
-- pid = one profession (nil = all lists); q = name filter
-- Short kind of a recipe source text: "Drop", "Vendor", "Quest"... (nil when unknown)
function I.SourceKind(src)
    if type(src) ~= "string" or src == "" then return nil end
    local plain = src:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return plain:match("^%s*([^:|\n]-)%s*:")
end

-- Gaps source filter: where a recipe is learned (Other = anything else, or not known yet)
I.SRC_FILTERS = { "Trainer", "Vendor", "Drop", "Quest", "Other" }
function I.SourceBucket(kind)
    if type(kind) ~= "string" then return "Other" end
    local k = kind:lower()
    if k:find("trainer", 1, true) then return "Trainer" end
    if k:find("vendor", 1, true) or k:find("quartermaster", 1, true) then return "Vendor" end
    if k:find("quest", 1, true) then return "Quest" end
    if k:find("drop", 1, true) then return "Drop" end
    return "Other"
end

function I.Gaps(pid, q, catKey, srcF)
    I.Build()
    q = q and q:lower() or ""
    local pids = {}
    if pid then pids[1] = pid else for p in pairs(GH.db.allRecipes) do pids[#pids + 1] = p end end
    local out = {}
    for _, p in ipairs(pids) do
        for _, id in ipairs(GH.db.allRecipes[p] or {}) do
            if not byRecipe[id] and not I.IsBoP(id) then
                local c = GH.Prof.Resolve(id)
                if c and not c.p then c.p = p end
                local name = I.RecipeName(id)
                local gr, ca = I.Category(id)
                local inCat = not catKey or (gr .. ">" .. ca) == catKey
                if inCat and (q == "" or name:lower():find(q, 1, true) or (c and c.n and c.n:lower():find(q, 1, true))) then
                    local src = GH.Prof.SourceKind(c) or I.SourceKind(c and c.src)
                    if not srcF or I.SourceBucket(src) == srcF then
                        out[#out + 1] = { kind = "recipe", id = id, name = name, crafters = 0, online = 0, group = gr, cat = ca, gap = true,
                            src = src }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

-- Item types of one profession's unknown recipes, like I.Categories
function I.GapCategories(pid, srcF)
    local counts, out = {}, {}
    for _, r in ipairs(I.Gaps(pid, nil, nil, srcF)) do
        local key = r.group .. ">" .. r.cat
        local e = counts[key]
        if not e then
            e = { kind = "cat", key = key, group = r.group, name = r.cat, count = 0 }
            counts[key] = e
            out[#out + 1] = e
        end
        e.count = e.count + 1
    end
    table.sort(out, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end)
    return out
end

function I.GapCount(pid, srcF)
    if srcF then return #I.Gaps(pid, nil, nil, srcF) end
    I.Build()
    local n = 0
    for _, id in ipairs(GH.db.allRecipes[pid] or {}) do if not byRecipe[id] and not I.IsBoP(id) then n = n + 1 end end
    return n
end

--------------------------------------------------------------------------------
-- Recipe items ("Pattern: Red Linen Robe"): has anyone in the guild learned what it teaches?
-- Matched by name against the shared recipe lists (recipe name or product name).
--------------------------------------------------------------------------------
local byRecipeItem, recipeItemDirty = {}, true
GH.Listen("DATA", function() recipeItemDirty = true end)
GH.Listen("NAMES", function() recipeItemDirty = true end)
GH.Listen("INDEX", function() recipeItemDirty = true end)

local function RecipeItemIndex()
    if not recipeItemDirty then return byRecipeItem end
    recipeItemDirty = false
    wipe(byRecipeItem)
    local Key = GH.Prof.Key
    local function Add(name, id)
        local k = Key(name)
        if not k then return end
        local l = byRecipeItem[k]
        if not l then l = {}; byRecipeItem[k] = l end
        l[#l + 1] = id
    end
    local function AddRecipe(id)
        local c = GH.db.recipes[id]
        if not c then return end
        Add(c.n, id)
        local out = c.o and GH.db.names[c.o]
        if out and out ~= c.n then Add(out, id) end
    end
    for _, list in pairs(GH.db.allRecipes) do
        for _, id in ipairs(list) do AddRecipe(id) end
    end
    for id in pairs(byRecipe) do AddRecipe(id) end
    return byRecipeItem
end

-- true (+ recipe ID) = a recipe item nobody in the guild has learned; false = someone has;
-- nil = not a recipe item, or one we have no data for
function I.RecipeItemGap(itemID, name)
    if not GH.db or not GH.Prof or not GH.Prof.RecipeItemKey then return nil end
    if (not name or name == "") and itemID then name = C_Item.GetItemNameByID(itemID) end
    local isRecipe = false
    if itemID and C_Item.GetItemInfoInstant then
        local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
        isRecipe = ok and classID == 9   -- Enum.ItemClass.Recipe
    end
    local k = GH.Prof.RecipeItemKey(name, isRecipe)
    if not k then return nil end
    I.Build()
    local ids = RecipeItemIndex()[k]
    if not ids then return nil end
    local gap
    for _, id in ipairs(ids) do
        if byRecipe[id] then return false end
        if not gap and not I.IsBoP(id) then gap = id end
    end
    if gap then return true, gap end
    return nil
end

--------------------------------------------------------------------------------
-- Item type of a recipe's product: group (e.g. "Weapon") + category ("One-Handed Swords")
--------------------------------------------------------------------------------
local catCache = {}
GH.Listen("NAMES", function() wipe(catCache) end)

function I.Category(recipeID)
    local hit = catCache[recipeID]
    if hit then return hit[1], hit[2] end
    local c = GH.db.recipes[recipeID]
    local group, cat
    if c and not c.o and c.n then
        group, cat = "Other", "Enchants and other"
    elseif c and c.o then
        local _, itemType, subType, equipLoc, _, classID, subID = C_Item.GetItemInfoInstant(c.o)
        if classID then
            group = itemType or "Other"
            cat = subType or itemType or "Other"
            if classID == 4 then -- armor: type + slot ("Plate Wrist"); misc armor by slot ("Neck")
                local slot = equipLoc and equipLoc ~= "" and _G[equipLoc]
                if subID == 6 then
                    cat = subType
                elseif subID == 0 or not subType then
                    cat = slot or subType or "Misc"
                elseif slot then
                    cat = subType .. " " .. slot
                end
            end
        end
    end
    if not group then return "Other", "Other" end
    catCache[recipeID] = { group, cat }
    return group, cat
end

local function OnlineCount(list)
    local n = 0
    for _, c in ipairs(list) do if GH.IsOnline(c.name) then n = n + 1 end end
    return n
end

-- Search results: { kind = "recipe", id, name, crafters, online } sorted by name
-- filter: pid (profession) and/or catKey ("group>category")
function I.Search(query, pid, catKey)
    I.Build()
    local q = query and query:lower() or ""
    local out = {}
    for id, list in pairs(byRecipe) do
        local inProf = not pid
        if pid then
            for _, c in ipairs(list) do if c.pid == pid then inProf = true; break end end
        end
        if inProf and catKey then
            local gr, ca = I.Category(id)
            inProf = (gr .. ">" .. ca) == catKey
        end
        if inProf then
            local name = I.RecipeName(id)
            local c = GH.db.recipes[id]
            local alt = c and c.n
            if q == "" or name:lower():find(q, 1, true) or (alt and alt:lower():find(q, 1, true)) then
                local gr, ca = I.Category(id)
                out[#out + 1] = { kind = "recipe", id = id, name = name, crafters = #list, online = OnlineCount(list), group = gr, cat = ca }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

function I.Professions()
    I.Build()
    local out = {}
    for pid, p in pairs(profs) do
        local n = 0
        for _ in pairs(p.recipes) do n = n + 1 end
        out[#out + 1] = { kind = "prof", pid = pid, name = GH.ProfName(pid), crafters = p.crafters, best = p.best, max = p.max, recipes = n }
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.pid < b.pid
    end)
    return out
end


-- Item types across the guild: { kind = "cat", key, group, name, count } sorted by group then name
function I.Categories(pid)
    I.Build()
    local counts = {}
    local set = byRecipe
    if pid then set = profs[pid] and profs[pid].recipes or {} end
    for id in pairs(set) do
        local gr, ca = I.Category(id)
        local key = gr .. ">" .. ca
        local e = counts[key]
        if not e then
            e = { kind = "cat", key = key, group = gr, name = ca, count = 0 }
            counts[key] = e
        end
        e.count = e.count + 1
    end
    local out = {}
    for _, e in pairs(counts) do out[#out + 1] = e end
    table.sort(out, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end)
    return out
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local W = {}
GH.Window = W

local WIDTH, HEIGHT = 800, 470
local LIST_W = 300
local ROW_H = 22
local ROWS = 16
local CRAFTER_ROWS = 5

-- "Can make it" line extras: only "alt of Main Name" when just an alt can make it
local function ColorName(full)
    local r, g, b = 0.55, 0.55, 0.55
    if GH.IsOnline(full) then r, g, b = GH.ClassColor(full) end
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), GH.Short(full))
end
local function AltSuffix(c)
    if c.altOf then
        return "  |cffd6c49ealt of " .. GH.Short(c.altOf) .. "|r"
    end
    return ""
end
local function CrafterTip(row)
    local c = row.data
    if not c then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local main = c.altOf or (c.chars and GH.RosterName(c.chars[1].name)) or c.name
    GameTooltip:SetText(GH.Short(main) .. (c.altOf and " (alt can make it)" or ""), 0.85, 0.64, 0.13)
    for _, o in ipairs(c.chars or { c }) do
        local tag = (GH.RosterName(o.name) == main) and "main" or "alt"
        local skill = o.m > 0 and ("%d / %d"):format(o.s, o.m) or tostring(o.s)
        GameTooltip:AddDoubleLine(ColorName(o.name) .. "  |cffd6c49e" .. tag .. "|r",
            skill .. (o.online and "  |cff4fd66bonline|r" or "  |cff8a8a8aoffline|r"), 1, 1, 1, 0.84, 0.77, 0.62)
    end
    GameTooltip:AddLine("Alts come from each player's own main + alts pick (Options tab), else a note naming the main.", 0.84, 0.77, 0.62, true)
    GameTooltip:Show()
end
local REAGENT_ROWS = 7

local frame
local state = { tab = "craft", query = "", prof = nil, cat = nil, results = {}, offset = 0, selected = nil, req = nil, make = 1,
    gapProf = nil, prevTab = "craft", lastList = "craft" }

local function ItemTip(owner, itemID)
    if not itemID then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(itemID)
    GameTooltip:Show()
end

-- The game forgets item data now and then; the last known quality is kept so names never flash white
local function QualityColor(itemID)
    local q = itemID and C_Item.GetItemQualityByID(itemID)
    if itemID then
        if q then
            if GH.db.quality[itemID] ~= q then GH.db.quality[itemID] = q end
        else
            q = GH.db.quality[itemID]
        end
    end
    if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        local c = ITEM_QUALITY_COLORS[q]
        return c.r, c.g, c.b
    end
    return 0.88, 0.88, 0.88
end

local function Icon(itemID, recipeID)
    if itemID then
        local tex = C_Item.GetItemIconByID(itemID)
        if tex then return tex end
    end
    if recipeID and C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(recipeID)
        if tex then return tex end
    end
    return 134400 -- question mark
end

local function Ago(t)
    local d = GetServerTime() - (t or 0)
    if d < 3600 then return math.max(1, math.floor(d / 60)) .. " min ago" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    local days = math.floor(d / 86400)
    return days .. (days == 1 and " day ago" or " days ago")
end

-- warm parchment for secondary text (easier to read than grey on the dark panel)
local SOFT = { 0.84, 0.77, 0.62, 1 }

local STATE_SHORT = { open = "open", claimed = "claimed", ready = "mats ready", done = "done", cancelled = "cancelled" }

--------------------------------------------------------------------------------
-- List (left)
--------------------------------------------------------------------------------
local Paint, PaintDetail, SetTab, PaintOptions, BuildOptions, PaintVersions

local function HintText()
    if state.tab == "requests" then return "Search requests..." end
    if state.tab == "gaps" then return "Search recipes nobody knows..." end
    if state.tab == "options" or state.tab == "prep" or state.tab == "cal" or state.tab == "roster" then return "" end
    return "Search all guild crafts..."
end

-- Crafting tab: level filter / sort (settings.craftSort: "name", "lvl" low first, "mine" up to my level, high first)
local SORTS = { { "name", "A-Z" }, { "lvl", "By level" }, { "mine", "Up to my level" } }
local function LevelOrder(list)
    local mode = GH.db.settings.craftSort or "name"
    if mode == "name" then return list end
    local my = UnitLevel("player") or 60
    local out, head = {}, nil
    for _, r in ipairs(list) do
        if r.kind == "recipe" then
            local c = GH.db.recipes[r.id]
            r.lvl = c and c.o and I.ReqLevel(c.o) or 0
            if mode ~= "mine" or r.lvl <= my then out[#out + 1] = r end
        elseif r.kind == "back" then
            head = r
        end
    end
    local high = mode == "mine"
    table.sort(out, function(a, b)
        if a.lvl ~= b.lvl then
            if high then return a.lvl > b.lvl end
            return a.lvl < b.lvl
        end
        return a.name < b.name
    end)
    if head then table.insert(out, 1, head) end
    return out
end

local function Rebuild()
    if not frame then return end
    local list = {}
    if state.tab == "options" then
        -- the options panel covers the list
        PaintOptions()
    elseif state.tab == "prep" then
        -- so does the raid prep panel
        if GH.PrepPanel then GH.PrepPanel.Paint() end
    elseif state.tab == "cal" then
        -- and the calendar panel
        if GH.CalPanel then GH.CalPanel.Paint() end
    elseif state.tab == "roster" then
        if GH.RosterPanel then GH.RosterPanel.Paint() end
    elseif state.tab == "gaps" then
        if state.query ~= "" then
            for _, r in ipairs(I.Gaps(nil, state.query, nil, state.gapSrc)) do list[#list + 1] = r end
        elseif state.gapProf and state.gapCat then
            list[1] = { kind = "back" }
            for _, r in ipairs(I.Gaps(state.gapProf, nil, state.gapCat.key, state.gapSrc)) do list[#list + 1] = r end
        elseif state.gapProf then
            -- item types under their groups, like the Crafting tab
            list[1] = { kind = "back" }
            local lastGroup
            for _, c in ipairs(I.GapCategories(state.gapProf, state.gapSrc)) do
                if c.group ~= lastGroup then
                    lastGroup = c.group
                    list[#list + 1] = { kind = "group", name = c.group }
                end
                list[#list + 1] = c
            end
        else
            local pids, seen = {}, {}
            for _, pid in ipairs(GH.Prof.CRAFTS) do pids[#pids + 1] = pid; seen[pid] = true end
            for pid in pairs(GH.db.allRecipes) do if not seen[pid] then pids[#pids + 1] = pid end end
            local open, none, wait = {}, {}, {}
            for _, pid in ipairs(pids) do
                local pr = I.ProfInfo(pid)
                local name = GH.ProfName(pid)
                if GH.db.allRecipes[pid] then
                    local n = I.GapCount(pid, state.gapSrc)
                    local right
                    if n > 0 then right = ("%d of %d"):format(n, #GH.db.allRecipes[pid])
                    elseif state.gapSrc then right = "none"
                    else right = "|cff4fd66ball known|r" end
                    open[#open + 1] = { kind = "gapprof", pid = pid, name = name, right = right }
                elseif not pr then
                    none[#none + 1] = { kind = "gapnone", pid = pid, name = name, right = "|cffff4040nobody|r" }
                else
                    wait[#wait + 1] = { kind = "gapwait", pid = pid, name = name,
                        right = pr.max > 0 and ("best %d / %d"):format(pr.best, pr.max) or ("best %d"):format(pr.best) }
                end
            end
            local function ByName(a, b) return a.name < b.name end
            for _, sec in ipairs({ { "Recipes nobody knows", open }, { "No crafter in the guild", none }, { "Not checked yet", wait } }) do
                if #sec[2] > 0 then
                    table.sort(sec[2], ByName)
                    list[#list + 1] = { kind = "header", name = sec[1] }
                    for _, r in ipairs(sec[2]) do list[#list + 1] = r end
                end
            end
        end
    elseif state.tab == "requests" then
        local q = state.query:lower()
        local now = GetServerTime()
        for _, r in ipairs(GH.Requests.All()) do
            local name = I.RecipeName(r.rc)
            local visible = r.st ~= "cancelled" and not (r.st == "done" and now - (r.rev or 0) > (GH.db.settings.doneHours or 24) * 3600)
            if visible and (q == "" or name:lower():find(q, 1, true) or GH.Short(r.by):lower():find(q, 1, true)) then
                list[#list + 1] = { kind = "req", id = r.id, rc = r.rc, name = name, r = r }
            end
        end
    elseif state.query ~= "" then
        -- typing always searches the whole guild (the profession / type you were in comes back when cleared)
        for _, r in ipairs(I.Search(state.query)) do list[#list + 1] = r end
        list = LevelOrder(list)
    elseif state.cat then
        -- one item type: its recipes
        list[1] = { kind = "back" }
        for _, r in ipairs(I.Search("", state.prof, state.cat.key)) do list[#list + 1] = r end
        list = LevelOrder(list)
    elseif state.prof then
        -- one profession: its item types, under their groups (Armor, Weapon, ...)
        list[1] = { kind = "back" }
        local lastGroup
        for _, c in ipairs(I.Categories(state.prof)) do
            if c.group ~= lastGroup then
                lastGroup = c.group
                list[#list + 1] = { kind = "group", name = c.group }
            end
            list[#list + 1] = c
        end
    else
        local profsList = I.Professions()
        if #profsList > 0 then
            list[#list + 1] = { kind = "header", name = "Professions" }
            for _, p in ipairs(profsList) do list[#list + 1] = p end
        end
    end
    state.results = list
    local maxOff = math.max(0, #list - ROWS)
    if state.offset > maxOff then state.offset = maxOff end
    Paint()
end

local function SetQuery(text)
    state.query = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    state.offset = 0
    Rebuild()
end

local function SetFilter(prof, cat)
    state.prof, state.cat, state.offset = prof, cat, 0
    frame.search.hint:SetText(HintText())
    Rebuild()
end

local function ClickRow(row)
    local d = row.data
    if not d then return end
    if d.kind == "gapprof" then
        state.gapProf, state.gapCat, state.offset = d.pid, nil, 0
        Rebuild()
    elseif d.kind == "cat" and state.tab == "gaps" then
        state.gapCat, state.offset = { key = d.key, name = d.name }, 0
        Rebuild()
    elseif d.kind == "back" and state.tab == "gaps" then
        if state.gapCat then state.gapCat = nil else state.gapProf = nil end
        state.offset = 0
        Rebuild()
    elseif d.kind == "prof" then
        SetFilter(d.pid, nil)
    elseif d.kind == "cat" then
        SetFilter(state.prof, { key = d.key, name = d.name })
    elseif d.kind == "back" then
        if state.cat and state.prof then SetFilter(state.prof, nil) else SetFilter(nil, nil) end
    elseif d.kind == "recipe" then
        state.selected, state.req, state.make = d.id, nil, 1
        Paint()
    elseif d.kind == "req" then
        state.selected, state.req, state.make = d.rc, d.id, d.r.n
        Paint()
    end
end

local function PaintTabs()
    local T = S.T()
    for key, b in pairs(frame.tabs) do
        local on = state.tab == key
        b:SetSelected(on)
    end
    local n = GH.Requests.ForMe()
    frame.tabs.requests:SetLabel(n > 0 and ("Requests |cfff5cb55" .. n .. "|r") or "Requests")
end

function Paint()
    if not frame or not frame:IsShown() then return end
    local T = S.T()
    local list = state.results
    for i = 1, ROWS do
        local row = frame.rows[i]
        local d = list[state.offset + i]
        row.data = d
        if d then
            row:Show()
            row.icon:Hide()
            row.right:SetText("")
            row.text:ClearAllPoints()
            row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
            row.text:SetPoint("LEFT", 8, 0)
            S.SetFont(row.text, 12)
            local selected = (d.kind == "recipe" and d.id == state.selected and not state.req) or (d.kind == "req" and d.id == state.req)
            row.sel:SetShown(selected)
            row:EnableMouse(d.kind ~= "header" and d.kind ~= "group" and d.kind ~= "gapnone" and d.kind ~= "gapwait")
            if d.kind == "header" then
                S.SetFont(row.text, 11)
                row.text:SetText(d.name:upper())
                row.text:SetTextColor(T.brand[1], T.brand[2], T.brand[3])
            elseif d.kind == "group" then
                S.SetFont(row.text, 11)
                row.text:SetText(d.name)
                row.text:SetTextColor(T.brand[1], T.brand[2], T.brand[3])
            elseif d.kind == "prof" then
                row.text:SetPoint("LEFT", 14, 0)
                row.text:SetText(d.name)
                row.text:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
                row.right:SetText(("%d %s, best %d"):format(d.crafters, d.crafters == 1 and "crafter" or "crafters", d.best))
            elseif d.kind == "gapprof" or d.kind == "gapnone" or d.kind == "gapwait" then
                row.text:SetPoint("LEFT", 14, 0)
                row.text:SetText(d.name)
                local col = d.kind == "gapprof" and T.accent or T.text
                row.text:SetTextColor(col[1], col[2], col[3])
                row.right:SetText(d.right or "")
            elseif d.kind == "cat" then
                row.text:SetPoint("LEFT", 14, 0)
                row.text:SetText(d.name)
                row.text:SetTextColor(T.text[1], T.text[2], T.text[3])
                row.right:SetText(tostring(d.count))
            elseif d.kind == "back" and state.tab == "gaps" then
                row.text:SetText(state.gapCat and ("< " .. GH.ProfName(state.gapProf)) or "< All professions")
                row.text:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
                row.right:SetText(state.gapCat and state.gapCat.name or GH.ProfName(state.gapProf))
            elseif d.kind == "back" then
                row.text:SetText((state.cat and state.prof) and ("< " .. GH.ProfName(state.prof)) or "< All professions")
                row.text:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
                row.right:SetText(state.cat and state.cat.name or GH.ProfName(state.prof))
            else
                local c = GH.db.recipes[d.kind == "req" and d.rc or d.id]
                row.icon:Show()
                row.icon:SetTexture(Icon(c and c.o, d.kind == "req" and d.rc or d.id))
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetTextColor(QualityColor(c and c.o))
                if d.kind == "req" then
                    local r = d.r
                    row.text:SetText(("%dx %s"):format(r.n, d.name))
                    local col = GH.Requests.IsActive(r) and "ffd100" or "8a8a8a"
                    if r.st == "done" then col = "4fd66b" end
                    row.right:SetText(("%s |cff%s%s|r"):format(GH.Short(r.by), col, STATE_SHORT[r.st] or r.st))
                    if not GH.Requests.IsActive(r) then row.text:SetTextColor(0.55, 0.55, 0.55) end
                elseif d.gap then
                    row.text:SetText(d.name)
                    if state.gapCat and state.query == "" then
                        row.right:SetText(d.src or "")
                    else
                        row.right:SetText(d.cat or "")
                    end
                else
                    row.text:SetText(d.name)
                    local lv = (d.lvl and d.lvl > 1) and ("|cffd6c49e" .. d.lvl .. "|r  ") or ""
                    if d.online > 0 then
                        row.right:SetText(("%s|cff4fd66b%d on|r / %d"):format(lv, d.online, d.crafters))
                    else
                        row.right:SetText(("%s|cff8a8a8a%d|r"):format(lv, d.crafters))
                    end
                end
            end
        else
            row:Hide()
        end
    end
    -- scroll thumb
    local n = #list
    if n > ROWS then
        local track = frame.track
        local h = track:GetHeight()
        local th = math.max(20, h * ROWS / n)
        frame.thumb:SetHeight(th)
        frame.thumb:ClearAllPoints()
        frame.thumb:SetPoint("TOP", track, "TOP", 0, -((h - th) * state.offset / (n - ROWS)))
        frame.thumb:Show()
    else
        frame.thumb:Hide()
    end
    -- empty states
    local g = GH.Guild()
    if not g then
        frame.empty:SetText("You are not in a guild.")
    elseif state.tab == "options" then
        frame.empty:SetText("")
    elseif state.tab == "gaps" and state.query ~= "" and n == 0 then
        frame.empty:SetText("No unknown recipes match.")
    elseif state.tab == "gaps" and state.gapProf and n <= 1 and state.gapSrc then
        frame.empty:SetText("No unknown " .. GH.ProfName(state.gapProf) .. " recipes from: " .. state.gapSrc .. ".\n\nThe source dropdown next to the search box changes this.")
    elseif state.tab == "gaps" and state.gapProf and n <= 1 then
        frame.empty:SetText("Someone in the guild knows every " .. GH.ProfName(state.gapProf) .. " recipe.")
    elseif state.tab == "gaps" then
        frame.empty:SetText("")
    elseif n == 0 and state.tab == "requests" then
        frame.empty:SetText(state.query == "" and "No craft requests yet.\n\nPick an item on the Crafting tab and press Request." or "No requests match.")
    elseif n == 0 and state.query == "" then
        frame.empty:SetText("No crafters yet.\n\nOpen each of your profession windows once so the addon can read your recipes. Guildmates who run Cys's Guild Hall show up here as they log in.")
    elseif state.tab == "craft" and GH.db.settings.craftSort == "mine" and (state.query ~= "" or state.cat)
        and not (list[1] and list[1].kind == "recipe" or list[2] and list[2].kind == "recipe") then
        frame.empty:SetText("Nothing here for your level.\n\nThe dropdown next to the search box shows all levels.")
    elseif n == 0 then
        frame.empty:SetText("Nobody in the guild can make that yet.")
    else
        frame.empty:SetText("")
    end
    PaintTabs()
    PaintDetail()
end

--------------------------------------------------------------------------------
-- Detail (right)
--------------------------------------------------------------------------------
local function SetButton(b, act)
    if act then
        b:Show()
        b:SetLabel(act[1])
        b:SetWidth(math.max(70, b.label:GetStringWidth() + 20))
        b.act = act[2]
    else
        b:Hide()
        b.act = nil
    end
end

-- Craft from the window: the profession window has to be open (the game crafts through it)
local function CraftNow(id, n)
    if InCombatLockdown() then GH.Print("you can't craft in combat."); return end
    local T = C_TradeSkillUI
    if not (T and T.CraftRecipe) then GH.Print("crafting from here isn't available: craft it in your profession window."); return end
    local ok = pcall(T.CraftRecipe, id, n)
    if not ok then GH.Print("couldn't start the craft: craft it in your profession window.") end
end
local function OpenProf(pid)
    local T = C_TradeSkillUI
    local ok, res = false, nil
    if T and T.OpenTradeSkill then ok, res = pcall(T.OpenTradeSkill, pid) end
    if not ok or res == false then
        GH.Print(("open your %s window, then press Craft."):format(GH.ProfName(pid)))
    end
end

function PaintDetail()
    local T = S.T()
    local d = frame.detail
    local id = state.selected
    local req = state.req and GH.Requests.Get(state.req)
    if req and req.st == "cancelled" then req, state.req = nil, nil end
    if state.tab == "requests" and not req then id = nil end
    if not id then
        d.box:Hide()
        local hint = "Search for an item, or pick a profession\nor item type, to see who can make it."
        if state.tab == "requests" then
            hint = "Pick a request to see its reagents\nand what you can do with it."
        elseif state.tab == "gaps" then
            hint = "Pick a profession to see the recipes\nnobody in the guild knows yet.\n\nRecipe lists come from your own characters:\nopen a profession window once to check it."
        end
        d.hint:SetText(hint)
        d.hint:Show()
        d.watermark:SetAlpha(0.09)
        return
    end
    d.hint:Hide()
    d.watermark:SetAlpha(0.03)
    d.box:Show()
    local c = GH.Prof.Resolve(id) or {}
    d.icon:SetTexture(Icon(c.o, id))
    d.icon.itemID = c.o
    d.name:SetText(I.RecipeName(id))
    d.name:SetTextColor(QualityColor(c.o))
    local crafters = I.Crafters(id)
    local pid = c.p or (crafters[1] and crafters[1].pid)
    local sub = pid and GH.ProfName(pid) or ""
    if (c.q or 1) > 1 then sub = sub .. ("  -  makes %d"):format(c.q) end
    local canSwitch = req and req.by == GH.Me() and GH.Requests.IsActive(req) and true or false
    if req then
        sub = ("Requested by %s, %s"):format(GH.Short(req.by), Ago(req.at))
        local dl = GH.Requests.DeliveryText(req)
        if dl and not canSwitch then sub = sub .. " - " .. dl end
    end
    d.sub:SetText(sub)
    d.dlDrop:SetShown(canSwitch)
    -- officers: make this item a raid prep target
    local canPrep = not req and state.tab == "craft" and c.o and GH.Prep and GH.PrepPanel and GH.Guild() and GH.Prep.IAmOfficer() and true or false
    d.prepBtn:SetShown(canPrep)
    d.sub:ClearAllPoints()
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    if canSwitch then
        d.dlDrop:Refresh()
        d.sub:SetPoint("RIGHT", d.dlDrop, "LEFT", -8, 0)
    elseif canPrep then
        d.sub:SetPoint("RIGHT", d.prepBtn, "LEFT", -8, 0)
    else
        d.sub:SetPoint("RIGHT", d.box, "RIGHT", -12, 0)
    end

    -- crafters: a scroll list (wheel or the thin bar), back to the top for a new recipe
    if d.crFor ~= id then d.crFor, d.crOff = id, 0 end
    local crMax = math.max(0, #crafters - CRAFTER_ROWS)
    d.crOff = math.max(0, math.min(d.crOff or 0, crMax))
    d.crMax = crMax
    d.crSb:Update(d.crOff, crMax, CRAFTER_ROWS, math.max(1, #crafters))
    for i = 1, CRAFTER_ROWS do
        local r = d.crafters[i]
        local cr = crafters[d.crOff + i]
        if cr then
            r:Show()
            r.dot:SetColorTexture(cr.online and T.green[1] or 0.35, cr.online and T.green[2] or 0.35, cr.online and T.green[3] or 0.35)
            local cr_r, cr_g, cr_b = GH.ClassColor(cr.name)
            if not cr.online then cr_r, cr_g, cr_b = 0.55, 0.55, 0.55 end
            r.text:SetText(GH.Short(cr.name) .. AltSuffix(cr))
            r.text:SetTextColor(cr_r, cr_g, cr_b)
            r.right:SetText(cr.m > 0 and ("%d / %d"):format(cr.s, cr.m) or tostring(cr.s))
            r.data = (cr.chars or cr.altOf) and cr or nil
            r:EnableMouse(r.data and true or false)
        else
            r.data = nil
            r:Hide()
        end
    end
    d.src:SetShown(#crafters == 0)
    if #crafters == 0 then
        -- nobody can make it: show where the recipe is learned instead
        d.cLabel:SetText("Where to learn it")
        d.crSb:Hide()
        local lines = GH.Prof.SourceLines(c)
        if lines then
            -- trainers / vendors you visited, Dungeon Journal drops, then the game's own source text
            if type(c.src) == "string" and c.src ~= "" then lines[#lines + 1] = c.src end
            d.src:SetText(table.concat(lines, "\n"))
            d.src:SetTextColor(T.text[1], T.text[2], T.text[3])
        elseif c.src == nil then
            -- ask guildmates who read it; nobody answering means nobody has read it yet
            local at = GH.Comm and GH.Comm.AskSource(id)
            if at and GetTime() - at < 15 then
                d.src:SetText("Asking the guild where to learn it...")
                C_Timer.After(15.5 - (GetTime() - at), function() GH.Fire("DATA") end)
            else
                d.src:SetText("Not read yet: anyone with " .. (pid and GH.ProfName(pid) or "this profession")
                    .. " fills this in by opening their profession window once.")
            end
            d.src:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
        elseif c.src == "" then
            d.src:SetText("The game gives no source for this recipe (most likely a trainer: visit one and it gets marked).")
            d.src:SetTextColor(SOFT[1], SOFT[2], SOFT[3])
        else
            d.src:SetText(c.src)
            d.src:SetTextColor(T.text[1], T.text[2], T.text[3])
        end
        local g = GH.Guild()
        local seen = g and g.bank and g.bank[id]
        if seen then
            d.src:SetText(("|cff4fd66bIn the guild bank|r (seen %s)\n"):format(Ago(seen)) .. (d.src:GetText() or ""))
        end
    else
        d.cLabel:SetText(#crafters > CRAFTER_ROWS and ("Can make it (%d)"):format(#crafters) or "Can make it")
    end

    -- reagents: have (bags + bank) / need
    local make = state.make
    d.makeValue:SetText(tostring(make))
    d.minus:SetShown(not req)
    d.plus:SetShown(not req)
    d.makeLabel:SetText(req and "Quantity" or "Make")
    d.mats:SetShown(req and req.by == GH.Me() and req.cr and req.cr ~= GH.Me() and GH.Requests.IsActive(req) and req.st ~= "open" and true or false)
    local reagents = c.r or {}
    local missing = 0
    for i = 1, REAGENT_ROWS do
        local r = d.reagents[i]
        local rg = reagents[i]
        if rg then
            r:Show()
            local rid, per = rg[1], rg[2]
            local need = per * make
            local have = C_Item.GetItemCount(rid, true) or 0
            r.icon:SetTexture(Icon(rid))
            r.itemID = rid
            r.text:SetText(GH.Prof.ItemName(rid) or ("Item " .. rid))
            r.text:SetTextColor(QualityColor(rid))
            if have >= need then
                r.right:SetText(("|cff4fd66b%d|r / %d"):format(have, need))
            else
                r.right:SetText(("|cffff4040%d|r / %d"):format(have, need))
                missing = missing + 1
            end
        else
            r:Hide()
        end
    end
    -- you know it: how many your bags make (the bank doesn't count for crafting)
    local knowPid = not req and I.IKnow(id)
    local canCraft = 0
    if knowPid and #reagents > 0 then
        canCraft = math.huge
        for _, rg in ipairs(reagents) do
            canCraft = math.min(canCraft, math.floor((C_Item.GetItemCount(rg[1], false) or 0) / rg[2]))
        end
    end
    d.shop:SetShown(not req and missing > 0 and GH.Mats and GH.Mats.ShopAdd and true or false)
    if #reagents == 0 then
        d.status:SetText((c.o or c.n) and "No reagents known for this recipe." or "Recipe details not available yet.")
        d.status:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
    elseif missing == 0 then
        d.status:SetText("You have everything for this (bags + bank).")
        d.status:SetTextColor(T.green[1], T.green[2], T.green[3])
    else
        d.status:SetText(("You are missing %d of %d reagents."):format(missing, #reagents))
        d.status:SetTextColor(T.danger[1], T.danger[2], T.danger[3])
    end

    -- action strip
    d.btnB.tip = nil
    d.newDl:Hide()
    if req then
        local text, col = GH.Requests.StateText(req)
        -- open and one of yours can make it: say which character
        if req.st == "open" and req.by ~= GH.Me() then
            local note = GH.Requests.MakerNote(req.rc)
            if note then text, col = "Open - " .. note, "accent" end
        end
        local cc = T[col] or T.text
        d.actText:SetText(text)
        d.actText:SetTextColor(cc[1], cc[2], cc[3])
        local acts = GH.Requests.Actions(req)
        SetButton(d.btnA, acts[1])
        SetButton(d.btnB, acts[2])
    elseif knowPid and canCraft > 0 then
        local n = math.min(make, canCraft)
        d.actText:SetText(("You know this: your bags make %d."):format(canCraft))
        d.actText:SetTextColor(T.green[1], T.green[2], T.green[3])
        if GH.Prof.IsOpen and GH.Prof.IsOpen(knowPid) then
            SetButton(d.btnA, { ("Craft %dx"):format(n), function() CraftNow(id, n) end })
        else
            SetButton(d.btnA, { "Open " .. GH.ProfName(knowPid), function() OpenProf(knowPid) end })
        end
        SetButton(d.btnB, nil)
    elseif knowPid and missing == 0 and #reagents > 0 then
        d.actText:SetText("You know this: take the reagents out of your bank to craft it.")
        d.actText:SetTextColor(T.accent[1], T.accent[2], T.accent[3])
        SetButton(d.btnA, nil)
        SetButton(d.btnB, nil)
    elseif #crafters == 0 then
        d.actText:SetText("Nobody in the guild can make this yet.")
        d.actText:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
        SetButton(d.btnA, nil)
        SetButton(d.btnB, nil)
    else
        local set = GH.db.settings
        d.actText:SetText(GH.Guild() and "Ask the guild:" or "")
        d.actText:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
        SetButton(d.btnA, GH.Guild() and { ("Request %dx"):format(make), function()
            local r = GH.Requests.New(id, state.make, set.delivery)
            if r then
                state.req = r.id
                SetTab("requests")
            end
        end } or nil)
        -- delivery choice: dropdown (remembered)
        SetButton(d.btnB, nil)
        if GH.Guild() then
            if not GH.Requests.DELIVERY[set.delivery] then set.delivery = "m" end
            d.newDl:Show()
            d.newDl:Refresh()
        end
    end
    d.actText:ClearAllPoints()
    d.actText:SetPoint("LEFT")
    d.actText:SetPoint("RIGHT", d.newDl:IsShown() and d.newDl or d.btnB, "LEFT", -8, 0)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------
local function Label(parent, text) return S.Heading(parent, text) end

function SetTab(tab)
    -- Crafting and Gaps each keep their own pick: switching between them clears it
    if (tab == "craft" or tab == "gaps") and tab ~= state.lastList then
        state.selected = nil
        state.lastList = tab
    end
    state.tab = tab
    state.offset = 0
    if tab == "craft" or tab == "gaps" then state.req = nil end
    frame.options:SetShown(tab == "options")
    if frame.altsPanel then frame.altsPanel:Hide() end
    if frame.prep then frame.prep:SetShown(tab == "prep") end
    if frame.cal then frame.cal:SetShown(tab == "cal") end
    if frame.roster then frame.roster:SetShown(tab == "roster") end
    frame.srcBtn:SetShown(tab == "gaps")
    frame.lvlBtn:SetShown(tab == "craft")
    local inset = 6
    if tab == "gaps" then inset = frame.srcBtn:GetWidth() + 10 elseif tab == "craft" then inset = frame.lvlBtn:GetWidth() + 10 end
    frame.search:SetTextInsets(6, inset, 0, 0)
    if tab == "options" or tab == "prep" or tab == "cal" or tab == "roster" then frame.search:ClearFocus() end
    if frame.search:GetText() ~= "" then
        frame.search:SetText("")   -- rebuilds through OnTextChanged
    else
        Rebuild()
    end
    frame.search.hint:SetText(HintText())
end

--------------------------------------------------------------------------------
-- Options panel (covers the list + detail while the Options tab is on)
--------------------------------------------------------------------------------
local OPT_ROWS = 9
local function DoneFmt(v)
    if v >= 24 then return v == 24 and "1 day" or (v / 24 .. " days") end
    return v == 1 and "1 hour" or (v .. " hours")
end

function BuildOptions()
    local T = S.T()
    local set = GH.db.settings
    local opt = CreateFrame("Frame", nil, frame)
    opt:SetPoint("TOPLEFT", 2, -31)
    opt:SetPoint("BOTTOMRIGHT", -2, 2)
    opt:SetFrameLevel(frame:GetFrameLevel() + 30)
    opt:EnableMouse(true)
    S.Tex(opt, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 1 }):SetAllPoints()
    opt:Hide()
    frame.options = opt

    local gen = Label(opt, "General")
    gen:SetPoint("TOPLEFT", 16, -16)
    opt.checks = {}
    local function AddCheck(text, get, setter)
        local c = S.Check(opt, text, get, setter)
        c:SetPoint("TOPLEFT", gen, "BOTTOMLEFT", 0, -10 - #opt.checks * 24)
        opt.checks[#opt.checks + 1] = c
        return c
    end
    AddCheck("Show crafter names on item tooltips", function() return set.tooltip end, function(v) set.tooltip = v end)
    AddCheck("Craft request notes in your chat window", function() return set.notify end, function(v) set.notify = v end)
    AddCheck("Materials pop-up when your request is claimed", function() return set.matsPopup end, function(v) set.matsPopup = v end)
    AddCheck("Guild news pop-ups (recipes, requests, rare loot)", function() return set.toasts end, function(v) set.toasts = v end)
    AddCheck("Tell the guild when you loot a recipe nobody knows", function() return set.lootShare end, function(v) set.lootShare = v end)
    local altCheck = AddCheck("Group alts under their main", function() return set.altGroup end, function(v)
        set.altGroup = v
        GH.BuildAlts()
        GH.Fire("ALTS")
    end)
    -- which rank marks alts: any rank named Alt / Alts, or one picked rank
    opt.altRank = S.Dropdown(opt, 150, 18, function()
        local items = { { "", "Any rank named Alt" } }
        for _, rk in ipairs(GH.RankNames()) do items[#items + 1] = { rk[2], rk[2] } end
        if set.altRank ~= "" then
            local have
            for _, it in ipairs(items) do if it[1] == set.altRank then have = true end end
            if not have then items[#items + 1] = { set.altRank, set.altRank } end
        end
        return items
    end, function() return set.altRank or "" end, function(v)
        set.altRank = v
        opt.altRank:Refresh()
        GH.BuildAlts()
        GH.Fire("ALTS")
    end)
    opt.altRank:SetPoint("LEFT", altCheck, "RIGHT", 10, 0)
    opt.altRank:HookScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText("Guild rank for alts", 0.85, 0.64, 0.13)
        GameTooltip:AddLine("Members of this rank whose public or officer note names another member (e.g. Alt of First Last) are shown under that member.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    opt.altRank:HookScript("OnLeave", function() GameTooltip:Hide() end)
    AddCheck("Show the minimap button", function() return not set.minimapHide end, function(v)
        set.minimapHide = not v
        if GH.UpdateMinimapButton then GH.UpdateMinimapButton() end
    end)
    AddCheck("Pop-up 15 min before events you signed up for", function() return set.calRemind end, function(v) set.calRemind = v end)
    opt.done = S.Stepper(opt, "Done requests stay listed", { 1, 3, 6, 12, 24, 48 },
        function() return set.doneHours or 24 end, function(v) set.doneHours = v end, DoneFmt)
    opt.done:SetWidth(280)
    opt.done:SetPoint("TOPLEFT", gen, "BOTTOMLEFT", 0, -12 - #opt.checks * 24)
    local sync = S.Button(opt, 180, 22, "Sync with the guild now")
    sync:SetPoint("TOPLEFT", opt.done, "BOTTOMLEFT", 0, -18)
    sync:SetScript("OnClick", function()
        if GH.Comm then GH.Comm.Hello(true) end
        GH.Print("asked the guild for newer crafting data.")
    end)
    local news = S.Button(opt, 110, 22, "What's new")
    news:SetPoint("LEFT", sync, "RIGHT", 8, 0)
    news:SetScript("OnClick", function() if GH.WhatsNew then GH.WhatsNew.Show() end end)
    local help = S.Text(opt, 11, SOFT)
    help:SetPoint("TOPLEFT", sync, "BOTTOMLEFT", 0, -14)
    help:SetWidth(300)
    help:SetText("Type /guildhall help for the chat commands.")

    local vl = Label(opt, "Guild Hall versions")
    vl:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -12)
    -- a small scroll list that ends above the window's bottom edge
    local vb = S.Panel(opt, T.field)
    vb:SetPoint("TOPLEFT", vl, "BOTTOMLEFT", 0, -6)
    vb:SetPoint("BOTTOM", opt, "BOTTOM", 0, 12)
    vb:SetWidth(320)
    vb:EnableMouseWheel(true)
    vb:SetScript("OnMouseWheel", function(_, delta)
        opt.versOff = math.max(0, math.min(opt.versMax or 0, (opt.versOff or 0) - delta))
        PaintVersions(opt)
    end)
    opt.versSb = S.ScrollBar(vb, function(off)
        opt.versOff = off
        PaintVersions(opt)
    end)
    opt.versSb:SetPoint("TOPRIGHT", -3, -3)
    opt.versSb:SetPoint("BOTTOMRIGHT", -3, 3)
    opt.versBox = vb
    -- its height is known only after layout: repaint once it has one
    vb:SetScript("OnSizeChanged", function() if opt:IsShown() then PaintVersions(opt) end end)
    opt.versOff = 0
    opt.versRows = {}

    local mine = Label(opt, "Your characters' professions")
    mine:SetPoint("TOPLEFT", 356, -16)
    local note = S.Text(opt, 11, SOFT)
    note:SetPoint("TOPLEFT", mine, "BOTTOMLEFT", 0, -8)
    note:SetWidth(316)
    note:SetText("A dropped profession goes away by itself on that character's next login. Remove one here for a character you no longer play.")
    local field = S.Panel(opt, T.field)
    field:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -10)
    field:SetSize(320, OPT_ROWS * 22 + 8)
    field:EnableMouseWheel(true)
    opt.profOff = 0
    field:SetScript("OnMouseWheel", function(_, delta)
        opt.profOff = math.max(0, math.min(opt.profMax or 0, opt.profOff - delta))
        PaintOptions()
    end)
    opt.profSb = S.ScrollBar(field, function(off)
        opt.profOff = off
        PaintOptions()
    end)
    opt.profSb:SetPoint("TOPRIGHT", -3, -3)
    opt.profSb:SetPoint("BOTTOMRIGHT", -3, 3)
    opt.rows = {}
    for i = 1, OPT_ROWS do
        local r = CreateFrame("Frame", nil, field)
        r:SetHeight(22)
        r:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 22)
        r:SetPoint("RIGHT", field, "RIGHT", -16, 0)
        r.btn = S.Button(r, 64, 18, "Remove")
        r.btn:SetPoint("RIGHT")
        r.right = S.Text(r, 11, SOFT, "RIGHT")
        r.right:SetPoint("RIGHT", r.btn, "LEFT", -8, 0)
        r.text = S.Text(r, 12, T.text)
        r.text:SetPoint("LEFT")
        r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
        r.text:SetWordWrap(false)
        -- two clicks: "Remove" then "Sure?" (resets after 3 seconds)
        r.btn:SetScript("OnClick", function(b)
            if not r.data then return end
            if b.armed then
                b.armed = nil
                GH.Prof.Forget(r.data.name, r.data.pid)
                PaintOptions()
            else
                b.armed = true
                b:SetLabel("|cffff4040Sure?|r")
                C_Timer.After(3, function()
                    if b.armed then b.armed = nil; b:SetLabel("Remove") end
                end)
            end
        end)
        opt.rows[i] = r
    end
    opt.empty = S.Text(field, 11, T.dim, "CENTER")
    opt.empty:SetPoint("CENTER")
    opt.empty:SetWidth(280)

    -- Your main & alts: its own page (button), with a one-line summary here
    local ab = S.Button(opt, 160, 22, "Your main & alts")
    ab:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -14)
    ab:SetScript("OnClick", function() W.OpenAlts() end)
    opt.altsText = S.Text(opt, 11, SOFT)
    opt.altsText:SetPoint("LEFT", ab, "RIGHT", 10, 0)
    opt.altsText:SetWidth(150)
    opt.altsText:SetWordWrap(false)

    for i, it in ipairs({
        { "Shopping list opens with the auction house", function() return set.shopAuto end, function(v) set.shopAuto = v end },
        { "Post guild bank recipes nobody knows in guild chat", function() return set.bankShare end, function(v) set.bankShare = v end },
    }) do
        local c = S.Check(opt, it[1], it[2], it[3])
        c:SetPoint("TOPLEFT", ab, "BOTTOMLEFT", 0, -14 - (i - 1) * 24)
        opt.checks[#opt.checks + 1] = c
    end

    -- Text font: Clean (sharp, default) or Classic (the game's Friz Quadrata); applies after a reload
    local fl = S.Text(opt, 11, T.text)
    fl:SetPoint("TOPLEFT", ab, "BOTTOMLEFT", 0, -14 - 2 * 24 - 3)
    fl:SetText("Text font")
    opt.font = S.Dropdown(opt, 170, 18, function()
        return { { "clean", "Clean (sharper)" }, { "classic", "Classic (Friz Quadrata)" } }
    end, function() return set.font or "clean" end, function(v)
        if set.font == v then return end
        set.font = v
        GH.Print("text font changed: type /reload to apply it everywhere.")
    end)
    opt.font:SetPoint("LEFT", fl, "LEFT", 70, 0)

    -- Window size (also the grip in the bottom-right corner)
    local sl = S.Text(opt, 11, T.text)
    sl:SetPoint("LEFT", opt.font, "RIGHT", 14, 0)
    sl:SetText("Window size")
    opt.size = S.Dropdown(opt, 70, 18, function()
        local t = {}
        for pct = 80, 150, 10 do t[#t + 1] = { pct / 100, pct .. "%" } end
        local cur = set.scale or 1.1
        local listed = false
        for _, it in ipairs(t) do if math.abs(it[1] - cur) < 0.001 then listed = true end end
        if not listed then t[#t + 1] = { cur, math.floor(cur * 100 + 0.5) .. "%" } end
        table.sort(t, function(a, b) return a[1] < b[1] end)
        return t
    end, function() return set.scale or 1.1 end, function(v) W.SetScale(v) end)
    opt.size:SetPoint("LEFT", sl, "RIGHT", 6, 0)
end

-- Who runs which version: newer than yours green, older soft red, same parchment
local VERS_ROW = 16
local function Hex(c) return ("%02x%02x%02x"):format(math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) end
function PaintVersions(opt)
    -- one line per player (alts fold into their main); yours on top
    local function VerCol(v)
        if v and GH.VersionNewer(v, GH.version) then return { 0.4, 0.9, 0.4 } end
        if v and not GH.VersionNewer(GH.version, v) then return SOFT end
        return { 1, 0.45, 0.4 }
    end
    local me = GH.Me()
    local entries = { { name = me, v = GH.version, me = true } }
    for _, e in ipairs(GH.Comm and GH.Comm.Versions() or {}) do
        if e.name ~= me then entries[#entries + 1] = e end
    end
    local groups, byMain = {}, {}
    for _, e in ipairs(entries) do
        local full = GH.RosterName(e.name)
        local main = GH.MainOf(full) or full
        local gr = byMain[main]
        if not gr then
            gr = { main = main, chars = {} }
            byMain[main] = gr
            groups[#groups + 1] = gr
        end
        gr.chars[#gr.chars + 1] = e
        if e.me then gr.mine = true end
        if e.v and (not gr.best or GH.VersionNewer(e.v, gr.best)) then gr.best = e.v end
    end
    table.sort(groups, function(a, b)
        if a.mine ~= b.mine then return a.mine and true or false end
        if (a.best or "") ~= (b.best or "") then
            if not a.best then return false elseif not b.best then return true end
            return GH.VersionNewer(a.best, b.best)
        end
        return a.main < b.main
    end)
    -- one line per player: the main's name with the newest version any of its characters runs
    local lines = {}
    for _, gr in ipairs(groups) do
        local cr, cg, cb = GH.ClassColor(gr.main)
        lines[#lines + 1] = ("|cff%s%s|r%s  |cff%s%s|r"):format(Hex({ cr, cg, cb }), GH.Short(gr.main),
            gr.mine and " (you)" or "", Hex(VerCol(gr.best)), gr.best or "0.3.11 or older")
    end
    if #entries == 1 then lines[#lines + 1] = "|cff" .. Hex(SOFT) .. "No other Guild Hall users seen yet.|r" end
    -- as many rows as fit the box (its height is only known once the window is laid out)
    local vb = opt.versBox
    local fit = math.max(1, math.floor(((vb:GetHeight() or 0) - 6) / VERS_ROW))
    for i = #opt.versRows + 1, fit do
        local t = S.Text(vb, 11, S.T().text)
        t:SetPoint("TOPLEFT", 8, -4 - (i - 1) * VERS_ROW)
        t:SetPoint("RIGHT", vb, "RIGHT", -16, 0)
        t:SetWordWrap(false)
        opt.versRows[i] = t
    end
    opt.versMax = math.max(0, #lines - fit)
    opt.versOff = math.max(0, math.min(opt.versOff or 0, opt.versMax))
    for i, t in ipairs(opt.versRows) do
        t:SetText(i <= fit and lines[opt.versOff + i] or "")
    end
    opt.versSb:Update(opt.versOff, opt.versMax, fit, #lines)
end

function PaintOptions()
    local opt = frame and frame.options
    if not opt or not opt:IsShown() then return end
    for _, c in ipairs(opt.checks) do c:Refresh() end
    opt.done:Refresh()
    opt.altRank:Refresh()
    local list = {}
    local g = GH.Guild()
    for name in pairs(GH.db.mine) do
        local m = g and g.members[name]
        for pid, p in pairs(m and m.profs or {}) do
            list[#list + 1] = { name = name, pid = pid, prof = GH.ProfName(pid), s = p.s or 0, m = p.m or 0 }
        end
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        if a.prof ~= b.prof then return a.prof < b.prof end
        return a.pid < b.pid
    end)
    opt.profMax = math.max(0, #list - OPT_ROWS)
    opt.profOff = math.max(0, math.min(opt.profOff or 0, opt.profMax))
    opt.profSb:Update(opt.profOff, opt.profMax, OPT_ROWS, #list)
    for i = 1, OPT_ROWS do
        local r = opt.rows[i]
        local e = list[opt.profOff + i]
        r.data = e
        r.btn.armed = nil
        r.btn:SetLabel("Remove")
        if e then
            r:Show()
            local cr, cg, cb = GH.ClassColor(e.name)
            r.text:SetText(("|cff%02x%02x%02x%s|r  %s"):format(math.floor(cr * 255), math.floor(cg * 255), math.floor(cb * 255), GH.Short(e.name), e.prof))
            r.right:SetText(e.m > 0 and ("%d / %d"):format(e.s, e.m) or tostring(e.s))
        else
            r:Hide()
        end
    end
    opt.empty:SetText(#list == 0 and "No professions read yet.\nOpen each profession window once." or "")
    PaintVersions(opt)
    local chars = GH.MyChars()
    opt.altsText:SetText("Main: " .. GH.Short(chars[1]) .. (#chars > 1 and ("  +" .. (#chars - 1) .. " alts") or ""))
end

--------------------------------------------------------------------------------
-- Your main & alts page (covers the window; opened from Options or /guildhall alts)
--------------------------------------------------------------------------------
local ALT_ROWS = 9
local PaintAlts

local function BuildAlts()
    local T = S.T()
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 2, -31)
    p:SetPoint("BOTTOMRIGHT", -2, 2)
    p:SetFrameLevel(frame:GetFrameLevel() + 40)
    p:EnableMouse(true)
    S.Tex(p, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 1 }):SetAllPoints()
    p:Hide()
    p:SetScript("OnShow", function() PaintAlts() end)
    frame.altsPanel = p

    local title = Label(p, "Your main & alts")
    title:SetPoint("TOPLEFT", 16, -16)
    local back = S.Button(p, 70, 20, "Back")
    back:SetPoint("TOPRIGHT", -16, -12)
    back:SetScript("OnClick", function() p:Hide() end)
    local intro = S.Text(p, 11, SOFT)
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    intro:SetWidth(640)
    intro:SetText("Pick your main and list your alts. Your guildmates' Guild Hall shows your alts under your main in Can make it, the Roster and the versions list, with no guild rank or note needed. Characters on this account that run Cys's Guild Hall join by themselves; add any other alt by name.")

    local mt = S.Text(p, 12, T.text)
    mt:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -16)
    mt:SetText("Main")
    p.mainDd = S.Dropdown(p, 220, 20, function()
        local chars, _, guess = GH.MyChars()
        local items = { { "", "Highest level (" .. GH.Short(guess) .. ")" } }
        local all = {}
        for _, c in ipairs(chars) do all[#all + 1] = c end
        table.sort(all)
        for _, c in ipairs(all) do items[#items + 1] = { c, GH.Short(c) } end
        return items
    end, function()
        local my = GH.MyAltsCfg()
        return my and my.main or ""
    end, function(v)
        local my = GH.MyAltsCfg()
        if not my then return end
        my.main = (v ~= "") and v or nil
        GH.PublishMyAlts()
        PaintAlts()
    end)
    p.mainDd:SetPoint("LEFT", mt, "LEFT", 50, 0)

    -- characters: one row each, main first
    local field = S.Panel(p, T.field)
    field:SetPoint("TOPLEFT", mt, "BOTTOMLEFT", 0, -16)
    field:SetSize(480, ALT_ROWS * 24 + 8)
    field:EnableMouseWheel(true)
    p.off = 0
    field:SetScript("OnMouseWheel", function(_, delta)
        p.off = math.max(0, math.min(p.max or 0, p.off - delta))
        PaintAlts()
    end)
    p.sb = S.ScrollBar(field, function(off) p.off = off; PaintAlts() end)
    p.sb:SetPoint("TOPRIGHT", -3, -3)
    p.sb:SetPoint("BOTTOMRIGHT", -3, 3)
    p.rows = {}
    for i = 1, ALT_ROWS do
        local r = CreateFrame("Frame", nil, field)
        r:SetHeight(24)
        r:SetPoint("TOPLEFT", 8, -4 - (i - 1) * 24)
        r:SetPoint("RIGHT", field, "RIGHT", -16, 0)
        r.btn = S.Button(r, 70, 18, "Remove")
        r.btn:SetPoint("RIGHT")
        r.src = S.Text(r, 11, T.dim, "RIGHT")
        r.src:SetPoint("RIGHT", r.btn, "LEFT", -10, 0)
        r.src:SetWidth(100)
        r.src:SetWordWrap(false)
        r.name = S.Text(r, 12, T.text)
        r.name:SetPoint("LEFT")
        r.name:SetWidth(156)
        r.lvl = S.Text(r, 11, SOFT)
        r.lvl:SetPoint("LEFT", 164, 0)
        r.lvl:SetWidth(60)
        r.lvl:SetWordWrap(false)
        r.tag = S.Text(r, 11, T.accent)
        r.tag:SetPoint("LEFT", 232, 0)
        r.tag:SetWidth(40)
        r.tag:SetWordWrap(false)
        r.name:SetWordWrap(false)
        -- two clicks: "Remove" then "Sure?" (resets after 3 seconds)
        r.btn:SetScript("OnClick", function(b)
            if not r.full then return end
            if b.armed then
                b.armed = nil
                GH.RemoveMyAlt(r.full)
                PaintAlts()
            else
                b.armed = true
                b:SetLabel("|cffff4040Sure?|r")
                C_Timer.After(3, function()
                    if b.armed then b.armed = nil; b:SetLabel("Remove") end
                end)
            end
        end)
        p.rows[i] = r
    end

    -- add an alt by name
    local add = S.EditBox(p, 220, 22)
    add:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -12)
    add.hint:SetText("Add an alt: First Last")
    add:SetScript("OnTextChanged", function(e) e.hint:SetShown(e:GetText() == "") end)
    local function DoAdd()
        local text = add:GetText()
        add:SetText("")
        add:ClearFocus()
        local full, why = GH.AddMyAlt(text)
        if not full and why then GH.Print(why) end
        PaintAlts()
    end
    add:SetScript("OnEnterPressed", DoAdd)
    local addBtn = S.Button(p, 60, 22, "Add")
    addBtn:SetPoint("LEFT", add, "RIGHT", 6, 0)
    addBtn:SetScript("OnClick", DoAdd)
    local hint = S.Text(p, 10, T.dim)
    hint:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -8)
    hint:SetWidth(480)
    hint:SetText("Removing a character of this account keeps it out until you add it again by name. Changes reach guildmates online now and the rest when they log in.")

    -- right side: how it works, in short
    local how = Label(p, "How the guild finds alts")
    how:SetPoint("TOPLEFT", field, "TOPRIGHT", 24, 0)
    local howText = S.Text(p, 11, SOFT)
    howText:SetPoint("TOPLEFT", how, "BOTTOMLEFT", 0, -8)
    howText:SetWidth(150)
    howText:SetText("1. Each player's own pick here.\n\n2. A note that says alt and names a member (Bob's alt).\n\n3. A member of the alt rank whose note names a member (Options).\n\nSomeone picked as a main is never made an alt by a note.")
end

function PaintAlts()
    local p = frame and frame.altsPanel
    if not p or not p:IsShown() then return end
    p.mainDd:Refresh()
    local chars, picked = GH.MyChars()
    local me = GH.Me()
    p.max = math.max(0, #chars - ALT_ROWS)
    p.off = math.max(0, math.min(p.off or 0, p.max))
    p.sb:Update(p.off, p.max, ALT_ROWS, #chars)
    for i = 1, ALT_ROWS do
        local r = p.rows[i]
        local full = chars[p.off + i]
        r.full = full
        r.btn.armed = nil
        r.btn:SetLabel("Remove")
        if full then
            r:Show()
            local e = GH.RosterEntry(full)
            local cr, cg, cb = GH.ClassColor(full)
            r.name:SetText(("|cff%02x%02x%02x%s|r"):format(math.floor(cr * 255), math.floor(cg * 255), math.floor(cb * 255), GH.Short(full)))
            r.lvl:SetText(e and e.level and ("Level " .. e.level) or "")
            if p.off + i == 1 then
                r.tag:SetText("Main")
            else
                r.tag:SetText("|cffd6c49eAlt|r")
            end
            r.src:SetText(full == me and "this character" or (GH.db.mine[full] and "this account" or "added by name"))
            r.btn:SetShown(#chars > 1)
        else
            r:Hide()
        end
    end
end

function W.OpenAlts()
    if not GH.db then return end
    if not frame then Build() end
    frame:Show()
    if state.tab ~= "options" then SetTab("options") end
    frame.altsPanel:Show()
    PaintAlts()
end

-- Keep the window's top-left corner where it is while the scale changes
function W.PinTopLeft()
    if not frame or not frame:GetLeft() then return end
    local sc = frame:GetScale()
    local x, y = frame:GetLeft() * sc, frame:GetTop() * sc
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / sc, y / sc)
end

-- Window size: 80% to 150% in 5% steps; live = true while dragging the grip (not saved yet)
function W.SetScale(v, live)
    v = math.floor(math.max(0.8, math.min(1.5, v or 1.1)) * 20 + 0.5) / 20
    if not live then GH.db.settings.scale = v end
    if not frame then return end
    if math.abs(frame:GetScale() - v) > 0.001 then
        local old = frame:GetScale()
        local x, y = frame:GetLeft(), frame:GetTop()
        frame:SetScale(v)
        if x then
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x * old / v, y * old / v)
        end
    end
    if not live then
        local p, _, rel, px, py = frame:GetPoint()
        GH.db.settings.pos = { p, px, py, rel }
        if frame.options and frame.options.size then frame.options.size:Refresh() end
    end
end

local function Build()
    local T = S.T()
    frame = CreateFrame("Frame", "CysGuildHallFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local p, _, rel, x, y = f:GetPoint()
        GH.db.settings.pos = { p, x, y, rel }
    end)
    frame:SetScale(GH.db.settings.scale or 1.1)
    local pos = GH.db.settings.pos
    if pos then frame:SetPoint(pos[1], UIParent, pos[4] or pos[1], pos[2], pos[3]) else frame:SetPoint("CENTER", 0, 40) end

    S.Chrome(frame)

    -- resize grip (bottom-right): drag to make the whole window bigger or smaller
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(frame:GetFrameLevel() + 60)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        frame:StopMovingOrSizing()
        W.PinTopLeft()
        grip:SetScript("OnUpdate", function()
            local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
            local left = frame:GetLeft() * frame:GetScale()
            W.SetScale((cx - left) / WIDTH, true)
        end)
    end)
    grip:SetScript("OnMouseUp", function()
        grip:SetScript("OnUpdate", nil)
        W.SetScale(frame:GetScale())
    end)
    grip:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
        GameTooltip:SetText("Window size", 1, 1, 1)
        GameTooltip:AddLine("Drag to make Guild Hall bigger or smaller. Also in Options.", SOFT[1], SOFT[2], SOFT[3], true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- header
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(30)
    S.HeaderBg(header)
    local seal = S.Emblem(header, 24)
    seal:SetPoint("LEFT", 7, 0)
    local title = S.Text(header, 14, T.brand)
    title:SetPoint("LEFT", seal, "RIGHT", 6, 0)
    title:SetText("Cys's Guild Hall")
    frame.guild = S.Text(header, 11, SOFT)
    frame.guild:SetPoint("LEFT", title, "RIGHT", 10, -1)
    local close = S.Close(header)
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.tabs = {}
    local tOpt = S.Tab(header, "Options")
    tOpt:SetPoint("RIGHT", close, "LEFT", -6, 0)
    -- a thin divider between the content tabs and Options
    local div = S.Tex(header, "ARTWORK", T.line)
    div:SetSize(1, 14)
    div:SetPoint("RIGHT", tOpt, "LEFT", -4, 0)
    tOpt:SetScript("OnClick", function()
        if state.tab == "options" then
            SetTab(state.prevTab or "craft")
        else
            state.prevTab = state.tab
            SetTab("options")
        end
    end)
    local tCal = S.Tab(header, "Calendar")
    tCal:SetPoint("RIGHT", div, "LEFT", -4, 0)
    tCal:SetScript("OnClick", function() SetTab("cal") end)
    local tRoster = S.Tab(header, "Roster")
    tRoster:SetPoint("RIGHT", tCal, "LEFT", 0, 0)
    tRoster:SetScript("OnClick", function() SetTab("roster") end)
    local tPrep = S.Tab(header, "Raid Prep")
    tPrep:SetPoint("RIGHT", tRoster, "LEFT", 0, 0)
    tPrep:SetScript("OnClick", function() SetTab("prep") end)
    local tGaps = S.Tab(header, "Gaps")
    tGaps:SetPoint("RIGHT", tPrep, "LEFT", 0, 0)
    tGaps:SetScript("OnClick", function() SetTab("gaps") end)
    local tReq = S.Tab(header, "Requests")
    tReq:SetPoint("RIGHT", tGaps, "LEFT", 0, 0)
    tReq:SetScript("OnClick", function() SetTab("requests") end)
    local tCraft = S.Tab(header, "Crafting")
    tCraft:SetPoint("RIGHT", tReq, "LEFT", 0, 0)
    tCraft:SetScript("OnClick", function() SetTab("craft") end)
    frame.tabs.craft, frame.tabs.requests, frame.tabs.gaps, frame.tabs.options = tCraft, tReq, tGaps, tOpt
    frame.tabs.prep = tPrep
    frame.tabs.cal = tCal
    frame.tabs.roster = tRoster
    -- a long guild name stops before the tabs
    frame.guild:SetPoint("RIGHT", tCraft, "LEFT", -8, 0)
    frame.guild:SetJustifyH("LEFT")
    frame.guild:SetWordWrap(false)

    -- search
    local search = S.EditBox(frame, LIST_W, 24)
    search:SetPoint("TOPLEFT", 10, -40)
    search:SetSearch()
    search.hint:SetText(HintText())
    search:SetScript("OnTextChanged", function(e)
        e.hint:SetShown(e:GetText() == "")
        SetQuery(e:GetText())
    end)
    search:SetScript("OnEscapePressed", function(e)
        if e:GetText() ~= "" then e:SetText("") else e:ClearFocus(); frame:Hide() end
    end)
    frame.search = search

    -- Gaps: source filter dropdown at the right end of the search box
    local srcBtn = S.Dropdown(search, 96, 18, function()
        local list = { { "all", "All sources" } }
        for _, k in ipairs(I.SRC_FILTERS) do list[#list + 1] = { k, k } end
        return list
    end, function() return state.gapSrc or "all" end, function(v)
        state.gapSrc = (v ~= "all") and v or nil
        state.offset = 0
        Rebuild()
    end)
    srcBtn:SetPoint("RIGHT", search, "RIGHT", -3, 0)
    srcBtn:HookScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Where to learn it", 1, 1, 1)
        GameTooltip:AddLine("Show only recipes learned from this source.", SOFT[1], SOFT[2], SOFT[3], true)
        GameTooltip:Show()
    end)
    srcBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    srcBtn:Hide()
    frame.srcBtn = srcBtn

    -- Crafting: level filter / sort dropdown in the same spot
    local lvlBtn = S.Dropdown(search, 104, 18, function() return SORTS end,
        function() return GH.db.settings.craftSort or "name" end, function(v)
        GH.db.settings.craftSort = v
        state.offset = 0
        Rebuild()
    end)
    lvlBtn:SetPoint("RIGHT", search, "RIGHT", -3, 0)
    lvlBtn:HookScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Level", 1, 1, 1)
        GameTooltip:AddLine("A-Z: by name.", SOFT[1], SOFT[2], SOFT[3], true)
        GameTooltip:AddLine("By level: the level needed to use or equip it, lowest first.", SOFT[1], SOFT[2], SOFT[3], true)
        GameTooltip:AddLine("Up to my level: only what you can use now, highest first.", SOFT[1], SOFT[2], SOFT[3], true)
        GameTooltip:AddLine("Works on search results and item types.", SOFT[1], SOFT[2], SOFT[3], true)
        GameTooltip:Show()
    end)
    lvlBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    frame.lvlBtn = lvlBtn

    -- list
    local listBox = S.Panel(frame, T.field)
    listBox:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
    listBox:SetSize(LIST_W, ROWS * ROW_H + 4)
    listBox:EnableMouseWheel(true)
    listBox:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #state.results - ROWS)
        state.offset = math.min(maxOff, math.max(0, state.offset - delta * 3))
        Paint()
    end)
    frame.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, listBox)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", -8, -2 - (i - 1) * ROW_H)
        if i % 2 == 0 then S.Tex(row, "BACKGROUND", { 1, 1, 1, 0.022 }, -1):SetAllPoints() end
        row.hl = S.Tex(row, "BACKGROUND", T.cardHover)
        row.hl:SetAllPoints()
        row.hl:Hide()
        row.sel = S.Selection(row)
        row.sel:SetAllPoints()
        row.sel:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.right = S.Text(row, 10, SOFT, "RIGHT")
        row.right:SetPoint("RIGHT", -4, 0)
        row.text = S.Text(row, 12, T.text)
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", ClickRow)
        row:SetScript("OnEnter", function(r)
            r.hl:Show()
            local dd = r.data
            local rid = dd and (dd.kind == "recipe" and dd.id or dd.kind == "req" and dd.rc)
            local c = rid and GH.db.recipes[rid]
            if c and c.o then ItemTip(r, c.o) end
        end)
        row:SetScript("OnLeave", function(r) r.hl:Hide(); GameTooltip:Hide() end)
        frame.rows[i] = row
    end
    frame.track = CreateFrame("Frame", nil, listBox)
    frame.track:SetPoint("TOPRIGHT", -2, -2)
    frame.track:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.track:SetWidth(4)
    frame.thumb = S.Tex(frame.track, "ARTWORK", { T.brand[1], T.brand[2], T.brand[3], 0.5 })
    frame.thumb:SetWidth(4)
    frame.empty = S.Text(listBox, 11, T.dim, "CENTER")
    frame.empty:SetPoint("CENTER")
    frame.empty:SetWidth(LIST_W - 30)

    -- detail
    local d = {}
    frame.detail = d
    local box = S.Panel(frame, T.card)
    box:SetPoint("TOPLEFT", search, "TOPRIGHT", 10, 0)
    box:SetPoint("BOTTOMRIGHT", -10, 10)
    d.watermark = S.Watermark(box)
    d.watermark:ClearAllPoints()
    d.watermark:SetPoint("CENTER", 0, 40)
    d.hint = S.Text(box, 12, SOFT, "CENTER")
    d.hint:SetPoint("TOP", d.watermark, "BOTTOM", 0, -6)
    d.hint:SetWidth(320)
    local inner = CreateFrame("Frame", nil, box)
    inner:SetAllPoints()
    d.box = inner

    local icon = CreateFrame("Button", nil, inner)
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", 12, -12)
    d.icon = icon:CreateTexture(nil, "ARTWORK")
    d.icon:SetAllPoints()
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    S.Border(icon, T.line)
    icon:SetScript("OnEnter", function(b) ItemTip(b, d.icon.itemID) end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.name = S.Text(inner, 14, T.text)
    d.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    d.name:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
    d.name:SetWordWrap(false)
    d.sub = S.Text(inner, 11, SOFT)
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    d.sub:SetWordWrap(false)
    -- requester only: delivery dropdown (mail / trade) on an active request
    d.dlDrop = S.Dropdown(inner, 124, 18, function() return { { "m", GH.Requests.DELIVERY.m }, { "t", GH.Requests.DELIVERY.t } } end, function()
        local r = state.req and GH.Requests.Get(state.req)
        return r and r.dl
    end, function(v)
        if state.req then GH.Requests.ChangeDelivery(state.req, v) end
    end)
    d.dlDrop.placeholder = "Delivery"
    d.dlDrop:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -12, -32)
    d.dlDrop:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("How you want it delivered. The crafter sees a change.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    d.dlDrop:HookScript("OnLeave", function() GameTooltip:Hide() end)
    d.dlDrop:Hide()
    -- officers (Crafting tab): start a raid prep target for this item
    d.prepBtn = S.Button(inner, 84, 18, "Raid target")
    d.prepBtn:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -12, -32)
    d.prepBtn:SetScript("OnClick", function()
        local itemID = d.icon.itemID
        if not itemID or not GH.PrepPanel then return end
        SetTab("prep")
        GH.PrepPanel.Prefill(itemID)
    end)
    d.prepBtn:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Make this a raid prep target", 1, 1, 1)
        GameTooltip:AddLine("Opens Raid Prep with this item in the New target box: set how many, then Add.", 0.84, 0.77, 0.62, true)
        GameTooltip:Show()
    end)
    d.prepBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    d.prepBtn:Hide()

    local cLabel = Label(inner, "Can make it")
    cLabel:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -12)
    -- the crafter rows sit in a box that scrolls with the mouse wheel
    local crBox = CreateFrame("Frame", nil, inner)
    crBox:SetPoint("TOPLEFT", cLabel, "BOTTOMLEFT", 0, -4)
    crBox:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
    crBox:SetHeight(CRAFTER_ROWS * 18)
    crBox:EnableMouseWheel(true)
    crBox:SetScript("OnMouseWheel", function(_, delta)
        if (d.crMax or 0) <= 0 then return end
        d.crOff = math.max(0, math.min(d.crMax, (d.crOff or 0) - delta))
        PaintDetail()
    end)
    d.crSb = S.ScrollBar(crBox, function(off)
        d.crOff = off
        PaintDetail()
    end)
    d.crSb:SetPoint("TOPRIGHT", crBox, "TOPRIGHT", 0, 0)
    d.crSb:SetPoint("BOTTOMRIGHT", crBox, "BOTTOMRIGHT", 0, 0)
    d.crSb:Hide()
    d.crafters = {}
    for i = 1, CRAFTER_ROWS do
        local r = CreateFrame("Frame", nil, crBox)
        r:SetHeight(18)
        r:SetPoint("TOPLEFT", cLabel, "BOTTOMLEFT", 0, -4 - (i - 1) * 18)
        r:SetPoint("RIGHT", inner, "RIGHT", -24, 0)
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(_, delta) crBox:GetScript("OnMouseWheel")(crBox, delta) end)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(7, 7)
        r.dot:SetPoint("LEFT", 2, 0)
        r.text = S.Text(r, 12, T.text)
        r.text:SetPoint("LEFT", r.dot, "RIGHT", 8, 0)
        r.right = S.Text(r, 11, SOFT, "RIGHT")
        r.right:SetPoint("RIGHT")
        r.text:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
        r.text:SetWordWrap(false)
        r:SetScript("OnEnter", CrafterTip)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d.crafters[i] = r
    end
    d.cLabel = cLabel
    d.src = S.Text(inner, 12, T.text)
    d.src:SetPoint("TOPLEFT", cLabel, "BOTTOMLEFT", 0, -6)
    d.src:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
    d.src:SetHeight(CRAFTER_ROWS * 18)
    d.src:SetJustifyV("TOP")
    d.src:SetSpacing(2)
    d.src:Hide()

    local rLabel = Label(inner, "Reagents")
    rLabel:SetPoint("TOPLEFT", cLabel, "BOTTOMLEFT", 0, -20 - CRAFTER_ROWS * 18)
    -- your claimed request: reopen the materials pop-up (crafter's counts)
    d.mats = S.Button(inner, 104, 18, "Crafter's counts")
    d.mats:SetPoint("LEFT", rLabel, "RIGHT", 10, 0)
    d.mats:SetScript("OnClick", function() if state.req and GH.Mats then GH.Mats.Show(state.req) end end)
    d.mats:Hide()
    -- missing reagents: add them to your shopping list (searches the auction house)
    d.shop = S.Button(inner, 96, 18, "Shopping list")
    d.shop:SetPoint("LEFT", rLabel, "RIGHT", 10, 0)
    d.shop:SetScript("OnClick", function()
        if state.selected and GH.Mats and GH.Mats.ShopAdd then GH.Mats.ShopAdd(state.selected, state.make) end
    end)
    d.shop:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Add what you are missing to your shopping list", 1, 1, 1)
        GameTooltip:AddLine("For the Make amount. At the auction house, click a line to search for it. /guildhall shop opens the list.", SOFT[1], SOFT[2], SOFT[3], true)
        GameTooltip:Show()
    end)
    d.shop:HookScript("OnLeave", function() GameTooltip:Hide() end)
    d.shop:Hide()
    local plus = S.Button(inner, 18, 18, "+")
    plus:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
    plus:SetPoint("TOP", rLabel, "TOP", 0, 3)
    d.makeValue = S.Text(inner, 11, T.accent, "CENTER")
    d.makeValue:SetWidth(28)
    d.makeValue:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    local minus = S.Button(inner, 18, 18, "-")
    minus:SetPoint("RIGHT", d.makeValue, "LEFT", -2, 0)
    d.makeLabel = S.Text(inner, 11, SOFT, "RIGHT")
    d.makeLabel:SetPoint("RIGHT", minus, "LEFT", -6, 0)
    d.plus, d.minus = plus, minus
    plus:SetScript("OnClick", function() state.make = math.min(99, state.make + 1); PaintDetail() end)
    minus:SetScript("OnClick", function() state.make = math.max(1, state.make - 1); PaintDetail() end)

    local field = S.Panel(inner, T.field)
    field:SetPoint("TOPLEFT", rLabel, "BOTTOMLEFT", 0, -6)
    field:SetPoint("RIGHT", inner, "RIGHT", -12, 0)
    field:SetHeight(REAGENT_ROWS * 20 + 8)
    d.reagents = {}
    for i = 1, REAGENT_ROWS do
        local r = CreateFrame("Button", nil, field)
        r:SetHeight(20)
        r:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 20)
        r:SetPoint("RIGHT", field, "RIGHT", -8, 0)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT")
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.right = S.Text(r, 11, T.text, "RIGHT")
        r.right:SetPoint("RIGHT")
        r.text = S.Text(r, 12, T.text)
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
        r.text:SetWordWrap(false)
        r:SetScript("OnEnter", function(b) ItemTip(b, b.itemID) end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d.reagents[i] = r
    end
    d.status = S.Text(inner, 11, T.text)
    d.status:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -6)
    d.status:SetPoint("RIGHT", field, "RIGHT", 0, 0)

    -- action strip (request / claim / mats ready / done)
    local strip = CreateFrame("Frame", nil, inner)
    strip:SetPoint("BOTTOMLEFT", 12, 10)
    strip:SetPoint("BOTTOMRIGHT", -12, 10)
    strip:SetHeight(24)
    S.Tex(strip, "BACKGROUND", T.line):SetPoint("TOPLEFT", strip, "TOPLEFT", 0, 8)
    d.btnA = S.Button(strip, 80, 22, "")
    d.btnA:SetPoint("RIGHT")
    d.btnB = S.Button(strip, 80, 22, "")
    d.btnB:SetPoint("RIGHT", d.btnA, "LEFT", -6, 0)
    for _, b in ipairs({ d.btnA, d.btnB }) do
        b:SetScript("OnClick", function(s) if s.act then s.act() end end)
    end
    d.btnB:HookScript("OnEnter", function(s)
        if not s.tip then return end
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(s.tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    d.btnB:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- new request: delivery dropdown (remembered), sits where btnB would
    d.newDl = S.Dropdown(strip, 124, 22, function() return { { "m", GH.Requests.DELIVERY.m }, { "t", GH.Requests.DELIVERY.t } } end, function() return GH.db.settings.delivery end,
        function(v) GH.db.settings.delivery = v end)
    d.newDl:SetPoint("RIGHT", d.btnA, "LEFT", -6, 0)
    d.newDl:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("How you want it delivered (remembered for next time).", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    d.newDl:HookScript("OnLeave", function() GameTooltip:Hide() end)
    d.newDl:Hide()
    d.actText = S.Text(strip, 11, T.dim)
    d.actText:SetPoint("LEFT")
    d.actText:SetPoint("RIGHT", d.btnB, "LEFT", -8, 0)
    d.actText:SetWordWrap(false)

    BuildOptions()
    BuildAlts()
    if GH.PrepPanel then frame.prep = GH.PrepPanel.Build(frame) end
    if GH.CalPanel then frame.cal = GH.CalPanel.Build(frame) end
    if GH.RosterPanel then frame.roster = GH.RosterPanel.Build(frame) end

    frame:SetScript("OnShow", function()
        frame.guild:SetText(GetGuildInfo("player") or "")
        if GH.NeedsRestart() and not frame.toldRestart then
            frame.toldRestart = true
            GH.Print("|cffff6060some new parts (like the Roster tab) are missing until you exit and restart World of Warcraft.|r")
        end
        if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        Rebuild()
    end)
    frame:SetScript("OnHide", function(f)
        GameTooltip:Hide()
        if not InCombatLockdown() then f:SetPropagateKeyboardInput(true) end
    end)
    -- Escape closes the window; every other key passes through to the game.
    -- (Setting key pass-through is blocked in combat, so it is only ever switched off
    -- for the Escape press itself, out of combat.)
    -- Key pass-through can only be set out of combat. Until it is set, the window does not
    -- listen to keys at all (a listening window without pass-through would eat movement keys).
    local function KeysOn()
        if frame.keysOn or InCombatLockdown() then return end
        frame:SetPropagateKeyboardInput(true)
        frame:EnableKeyboard(true)
        frame.keysOn = true
    end
    if InCombatLockdown() then
        local waiter = CreateFrame("Frame")
        waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
        waiter:SetScript("OnEvent", function(w)
            w:UnregisterAllEvents()
            KeysOn()
        end)
    else
        KeysOn()
    end
    frame:SetScript("OnKeyDown", function(f, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            f:SetPropagateKeyboardInput(false)
            f:Hide()
        else
            f:SetPropagateKeyboardInput(true)
        end
    end)
    frame:Hide()
end

--------------------------------------------------------------------------------
-- Refresh when data changes (batched)
--------------------------------------------------------------------------------
local refreshTimer
local function RefreshSoon()
    if not frame or not frame:IsShown() or refreshTimer then return end
    refreshTimer = C_Timer.NewTimer(0.3, function()
        refreshTimer = nil
        Rebuild()
    end)
end
GH.Listen("DATA", RefreshSoon)
GH.Listen("INDEX", RefreshSoon)
GH.Listen("NAMES", RefreshSoon)
GH.Listen("ROSTER", RefreshSoon)
GH.Listen("ALTS", RefreshSoon)
GH.Listen("ALTS", function() PaintOptions(); PaintAlts() end)
GH.Listen("REQUESTS", RefreshSoon)
GH.Listen("VERSIONS", function() if PaintOptions then PaintOptions() end end)
GH.On("BAG_UPDATE_DELAYED", function()
    if frame and frame:IsShown() and state.selected then PaintDetail() end
end)
-- the Craft button needs the profession window: repaint when it opens or closes
GH.Listen("PROFWIN", function()
    if frame and frame:IsShown() and state.selected then PaintDetail() end
end)

-- Shift-click an item while the search box has focus: search for it
if ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if not frame or not frame:IsShown() or not frame.search:HasFocus() or type(link) ~= "string" then return end
        local name = link:match("%[(.-)%]")
        if name then frame.search:SetText(name) end
    end)
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------
-- Minimap clicks: open on a tab, or close when already showing that tab
function W.ToggleTab(tab)
    if not GH.db then return end
    if not frame then Build() end
    if frame:IsShown() and state.tab == tab then
        frame:Hide()
        return
    end
    frame:Show()
    if state.tab ~= tab then SetTab(tab) end
end

function W.Toggle()
    if not GH.db then return end
    if not frame then Build() end
    frame:SetShown(not frame:IsShown())
end

-- open on one profession's item types (from the profession window button)
function W.OpenProfession(pid)
    if not GH.db then return end
    if not frame then Build() end
    frame:Show()
    if state.tab ~= "craft" then SetTab("craft") end
    if frame.search:GetText() ~= "" then frame.search:SetText("") end
    I.Build()
    SetFilter(pid and profs[pid] and pid or nil, nil)
end

function W.Open(query, tab)
    if not GH.db then return end
    if not frame then Build() end
    frame:Show()
    if tab and tab ~= state.tab then SetTab(tab) end
    if query then
        if state.tab ~= "craft" then SetTab("craft") end
        state.prof, state.cat = nil, nil
        frame.search.hint:SetText(HintText())
        frame.search:SetText(query)   -- fires OnTextChanged -> search
        -- one result: show it right away
        local only
        for _, r in ipairs(state.results) do
            if r.kind == "recipe" then
                if only then only = nil; break end
                only = r
            end
        end
        if only then state.selected, state.req = only.id, nil; Paint() end
    end
end
