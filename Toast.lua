--------------------------------------------------------------------------------
-- Cys's Guild Hall - guild news toasts
-- A small note that rises in and fades out when a guildmate shares a profession
-- ("Father Stonecipher added their Tailoring recipes to the Guild Hall") or learns
-- new recipes. Only fresh news (changed in the last 30 minutes), one at a time,
-- never in combat. Click it to open that profession; drag to move.
--------------------------------------------------------------------------------
local GH = CysGuildHall
local S = GH.Style
local Toast = {}
GH.Toast = Toast

local SOFT = { 0.84, 0.77, 0.62, 1 }
local IN, HOLD, OUT, RISE = 0.35, 4.5, 0.8, 14
local MAX_QUEUE = 6
local frame
local queue = {}
local playing

local PROF_ICON = {
    [164] = "Interface\\Icons\\Trade_BlackSmithing", [165] = "Interface\\Icons\\Trade_LeatherWorking",
    [171] = "Interface\\Icons\\Trade_Alchemy", [197] = "Interface\\Icons\\Trade_Tailoring",
    [202] = "Interface\\Icons\\Trade_Engineering", [333] = "Interface\\Icons\\Trade_Engraving",
    [185] = "Interface\\Icons\\INV_Misc_Food_15", [129] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
}

local function Build()
    local T = S.T()
    frame = CreateFrame("Button", "CysGuildHallToast", UIParent)
    frame:SetSize(360, 46)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    S.Tex(frame, "BACKGROUND", T.bg):SetAllPoints()
    S.Border(frame, T.border)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(28, 28)
    frame.icon:SetPoint("LEFT", 9, 0)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.title = S.Text(frame, 10, T.brand)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 46, -10)
    frame.title:SetText("Guild Hall")
    frame.text = S.Text(frame, 11, T.text)
    frame.text:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
    frame.text:SetPoint("RIGHT", -10, 0)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetWordWrap(true)
    if frame.text.SetMaxLines then frame.text:SetMaxLines(3) end

    frame:SetScript("OnDragStart", function(f) f.dragging = true; f:StartMoving() end)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        f.dragging = nil
        local p, _, _, x, y = f:GetPoint()
        GH.db.settings.toastPos = { p, x, y }
        f.baseY = y
        f.point, f.x = p, x
    end)
    frame:SetScript("OnClick", function(f, button)
        if button == "LeftButton" and f.onClick then
            f.onClick()
        elseif button == "LeftButton" and f.pid and GH.Window and GH.Window.OpenProfession then
            GH.Window.OpenProfession(f.pid)
        end
        f.t = IN + HOLD   -- start fading out
    end)
    frame:SetScript("OnEnter", function(f)
        f.hover = true
        -- recipe loot toasts: hover shows the item itself
        if f.item and GameTooltip.SetItemByID then
            GameTooltip:SetOwner(f, "ANCHOR_BOTTOM", 0, -4)
            GameTooltip:SetItemByID(f.item)
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function(f)
        f.hover = nil
        if GameTooltip:IsOwned(f) then GameTooltip:Hide() end
    end)
    frame:SetScript("OnHide", function(f)
        f.hover = nil
        if GameTooltip:IsOwned(f) then GameTooltip:Hide() end
    end)
    frame:SetScript("OnUpdate", function(f, elapsed)
        if f.dragging then return end
        if not (f.hover and f.t > IN and f.t < IN + HOLD) then f.t = f.t + elapsed end
        local t = f.t
        local alpha, rise
        if t < IN then
            alpha, rise = t / IN, RISE * (1 - t / IN)
        elseif t < IN + HOLD then
            alpha, rise = 1, 0
        elseif t < IN + HOLD + OUT then
            local k = (t - IN - HOLD) / OUT
            alpha, rise = 1 - k, -RISE * k
        else
            f:Hide()
            playing = nil
            C_Timer.After(0.3, Toast.Next)
            return
        end
        f:SetAlpha(alpha)
        f:ClearAllPoints()
        f:SetPoint(f.point, UIParent, f.point, f.x, f.baseY - rise)
    end)
    frame:Hide()
end

local function Place()
    local pos = GH.db.settings.toastPos
    frame.point, frame.x, frame.baseY = "TOP", 0, -150
    if pos then frame.point, frame.x, frame.baseY = pos[1], pos[2], pos[3] end
end

function Toast.Next()
    if playing or #queue == 0 then return end
    if InCombatLockdown() then return end   -- shown after the fight
    if not frame then Build() end
    local e = table.remove(queue, 1)
    playing = true
    Place()
    frame.icon:SetTexture(e.icon or "Interface\\Icons\\Trade_BlackSmithing")
    frame.text:SetText(e.text)
    -- grow to fit a second line so the whole note shows
    local h = frame.text:GetStringHeight() or 0
    frame:SetHeight(math.max(46, math.floor(h + 0.5) + 33))
    frame.pid = e.pid
    frame.onClick = e.onClick
    frame.item = e.item
    frame.t = 0
    frame:SetAlpha(0)
    frame:Show()
end

function Toast.Add(text, icon, pid, onClick, item)
    if not GH.db or not GH.db.settings.toasts then return end
    if #queue >= MAX_QUEUE then
        -- a burst: the rest folds into one closing line
        local last = queue[#queue]
        if not last.summary then
            last = { summary = true, more = 0 }
            queue[#queue + 1] = last
        end
        last.more = last.more + 1
        last.text = ("+%d more guild crafting %s - open /guildhall to see them."):format(last.more, last.more == 1 and "update" or "updates")
        return
    end
    queue[#queue + 1] = { text = text, icon = icon, pid = pid, onClick = onClick, item = item }
    Toast.Next()
end

GH.On("PLAYER_REGEN_ENABLED", function() C_Timer.After(1, Toast.Next) end)

GH.Listen("SHARED", function(name, news)
    local who = GH.Short(name)
    for _, e in ipairs(news) do
        local prof = GH.ProfName(e.pid) or "profession"
        local icon = PROF_ICON[e.pid]
        if not icon and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillTexture then
            local ok, tex = pcall(C_TradeSkillUI.GetTradeSkillTexture, e.pid)
            if ok then icon = tex end
        end
        if e.new then
            Toast.Add(("|cffffd100%s|r added their %s recipes to the Guild Hall."):format(who, prof), icon, e.pid)
        else
            Toast.Add(("|cffffd100%s|r learned %d new %s %s."):format(who, e.n, prof, e.n == 1 and "recipe" or "recipes"), icon, e.pid)
        end
    end
end)

--------------------------------------------------------------------------------
-- Craft requests: only crafters who can make the item see it (fresh requests only)
--------------------------------------------------------------------------------
local function ItemIcon(id)
    if not id then return nil end
    local ok, tex = pcall(C_Item.GetItemIconByID, id)
    return ok and tex or nil
end

local function OpenTab(tab)
    return function() if GH.Window then GH.Window.Open(nil, tab) end end
end

function Toast.Request(r, name)
    local c = GH.db.recipes[r.rc]
    Toast.Add(("|cffffd100%s|r placed a request for %dx %s - you can make it."):format(GH.Short(r.by), r.n or 1, name),
        ItemIcon(c and c.o), nil, OpenTab("requests"))
end

--------------------------------------------------------------------------------
-- Recipe items nobody in the guild knows: whoever loots one tells the guild
--------------------------------------------------------------------------------
-- The recipe item's name in its quality color
local function ItemColored(itemID, name)
    local q = itemID and C_Item.GetItemQualityByID and select(2, pcall(C_Item.GetItemQualityByID, itemID))
    local c = type(q) == "number" and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c and c.hex then return c.hex .. name .. "|r" end
    return "|cffffffff" .. name .. "|r"
end

local function RecipeProf(rid, c)
    if c and c.p then return c.p end
    for pid, list in pairs(GH.db.allRecipes or {}) do
        for _, id in ipairs(list) do if id == rid then return pid end end
    end
end

-- What the recipe teaches: "Tailoring - makes Red Linen Robe (Chest)"
local function LootDetail(itemID, name)
    if not GH.Index or not GH.Prof then return nil end
    local ok, gap, rid = pcall(GH.Index.RecipeItemGap, itemID, name)
    if not ok or not rid then return nil end
    local c = GH.Prof.Resolve(rid)
    if not c then return nil end
    local pid = RecipeProf(rid, c)
    local prof = pid and GH.ProfName(pid)
    local what
    if c.o then
        local product = GH.Prof.ItemName and GH.Prof.ItemName(c.o)
        if (not product or product == "") then product = C_Item.GetItemNameByID(c.o) end
        if product and product ~= "" then
            local _, cat = GH.Index.Category(rid)
            what = "makes " .. ItemColored(c.o, product) .. "|cffd6c49e"
            if cat and cat ~= "" and cat ~= "Enchants and other" then what = what .. " (" .. cat .. ")" end
        end
    elseif c.n and c.n ~= "" then
        what = "teaches " .. c.n
    end
    if prof and what then return prof .. " - " .. what, pid end
    return what or prof, pid
end

local function LootToast(who, itemID, name)
    local text
    local item = ItemColored(itemID, name)
    if who == GH.Me() then
        text = ("You looted %s - not learned in the guild."):format(item)
    else
        text = ("|cffffd100%s|r looted %s - not learned in the guild."):format(GH.Short(who), item)
    end
    local detail = LootDetail(itemID, name)
    if detail then text = text .. "\n|cffd6c49e" .. detail .. "|r" end
    Toast.Add(text, ItemIcon(itemID), nil, OpenTab("gaps"), itemID)
end

local function Prefix(fmt) return type(fmt) == "string" and fmt:match("^(.-)%%s") or nil end
local LOOT_PREFIXES = { Prefix(LOOT_ITEM_SELF), Prefix(LOOT_ITEM_SELF_MULTIPLE) }
local lootSeen = {}   -- [itemID] = GetTime() of the last share (one per item every 10 minutes)

GH.On("CHAT_MSG_LOOT", function(text)
    if not GH.db or not GH.db.settings.lootShare or not GH.Index then return end
    if issecretvalue and issecretvalue(text) then return end
    if type(text) ~= "string" then return end
    local mine
    for _, pre in pairs(LOOT_PREFIXES) do
        if pre ~= "" and text:sub(1, #pre) == pre then mine = true; break end
    end
    if not mine then return end
    local id = tonumber(text:match("|Hitem:(%d+)"))
    local name = text:match("|h%[(.-)%]|h")
    if not id or not name then return end
    local now = GetTime()
    if lootSeen[id] and now - lootSeen[id] < 600 then return end
    if not GH.Index.RecipeItemGap(id, name) then return end
    lootSeen[id] = now
    if GH.Comm and IsInGuild() then GH.Comm.SendLoot(id, name) end
    LootToast(GH.Me(), id, name)
end)

GH.Listen("LOOTED", function(sender, itemID, name)
    if not name or name == "" then return end
    -- skip when our own data says someone already knows it
    if GH.Index and GH.Index.RecipeItemGap(itemID, name) == false then return end
    LootToast(sender, itemID, name)
end)
