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
    S.Chrome(frame)
    local accent = S.Tex(frame, "ARTWORK", T.brand)
    accent:SetWidth(2)
    accent:SetPoint("TOPLEFT", 2, -2)
    accent:SetPoint("BOTTOMLEFT", 2, 2)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(28, 28)
    frame.icon:SetPoint("LEFT", 9, 0)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.title = S.Text(frame, 10, T.brand)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 46, -10)
    frame.title:SetText("Guild Hall")
    frame.text = S.Text(frame, 11, T.text)
    frame.text:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
    -- fixed width so the wrapped height can be measured before the toast is placed
    frame.text:SetWidth(360 - 46 - 12)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetJustifyV("TOP")
    frame.text:SetWordWrap(true)
    if frame.text.SetMaxLines then frame.text:SetMaxLines(5) end

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
    frame:ClearAllPoints()
    frame:SetPoint(frame.point, UIParent, frame.point, frame.x, frame.baseY - RISE)
    frame.icon:SetTexture(e.icon or "Interface\\Icons\\Trade_BlackSmithing")
    frame.text:SetText(e.text)
    -- grow to fit every wrapped line so the whole note stays inside the box
    local h = frame.text:GetStringHeight() or 0
    frame:SetHeight(math.max(46, math.floor(h + 0.5) + 36))
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

-- Names of newly learned recipes (what they make, in its quality color when known)
local function RecipeNames(ids)
    local names, firstItem = {}, nil
    if not ids or not (GH.Prof and GH.Prof.Resolve) then return names end
    for _, id in ipairs(ids) do
        local ok, c = pcall(GH.Prof.Resolve, id)
        c = ok and c or GH.db.recipes[id]
        if c then
            local n = (c.o and GH.Prof.ItemName(c.o)) or c.n
            if n and n ~= "" then
                local q = c.o and C_Item.GetItemQualityByID and select(2, pcall(C_Item.GetItemQualityByID, c.o))
                local col = type(q) == "number" and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
                names[#names + 1] = { n = n, hex = (col and col.hex) or "|cffffffff" }
                firstItem = firstItem or c.o
            end
        end
    end
    table.sort(names, function(a, b) return a.n < b.n end)
    for i, e in ipairs(names) do names[i] = e.hex .. e.n .. "|r" end
    return names, firstItem
end

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
            local names, item = RecipeNames(e.ids)
            if #names == 0 then
                Toast.Add(("|cffffd100%s|r learned %d new %s %s."):format(who, e.n, prof, e.n == 1 and "recipe" or "recipes"), icon, e.pid)
            else
                local list
                if #names == 1 then
                    list = names[1]
                elseif #names <= 3 and #names == e.n then
                    list = table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
                else
                    local shown = math.min(3, #names)
                    list = table.concat(names, ", ", 1, shown) .. (" and %d more"):format(e.n - shown)
                end
                local text = e.n == 1
                    and ("|cffffd100%s|r learned a new %s recipe: %s."):format(who, prof, list)
                    or ("|cffffd100%s|r learned %d new %s recipes: %s."):format(who, e.n, prof, list)
                -- one recipe: hover shows what it makes
                Toast.Add(text, icon, e.pid, nil, e.n == 1 and item or nil)
            end
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

function Toast.Request(r, name, who)
    local c = GH.db.recipes[r.rc]
    Toast.Add(("|cffffd100%s|r placed a request for %dx %s - %s."):format(GH.Short(r.by), r.n or 1, name, who or "you can make it"),
        ItemIcon(c and c.o), nil, OpenTab("requests"))
end

-- Several at once (login sync): one pop-up naming the first two
function Toast.Requests(list)
    local fresh = {}
    for _, e in ipairs(list) do
        if GetServerTime() - (e.r.at or 0) < 1800 then fresh[#fresh + 1] = e end
    end
    if #fresh == 0 then return end   -- old ones synced at login: the chat line is enough
    if #fresh == 1 then return Toast.Request(fresh[1].r, fresh[1].name, fresh[1].who) end
    local a, b = fresh[1], fresh[2]
    local alts = 0
    for _, e in ipairs(fresh) do if not e.here then alts = alts + 1 end end
    local text = ("|cffffd100%d new craft requests|r you%s can make: %dx %s, %dx %s"):format(#fresh,
        alts == #fresh and "r other characters" or (alts > 0 and " or your other characters" or ""), a.r.n or 1, a.name, b.r.n or 1, b.name)
    if #fresh > 2 then text = text .. (" and %d more."):format(#fresh - 2) else text = text .. "." end
    local c = GH.db.recipes[a.r.rc]
    Toast.Add(text, ItemIcon(c and c.o), nil, OpenTab("requests"))
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

--------------------------------------------------------------------------------
-- Guild bank: recipe items nobody in the guild has learned
-- Read when you open the guild bank (tabs you can see). Saved per guild as
-- g.bank[recipeID] = time last seen (the Gaps detail says "In the guild bank").
-- New ones get a chat line + pop-up; guild chat only with the Options switch (off by default).
--------------------------------------------------------------------------------
local bankTimer, bankOpen
local BANK_SLOTS = MAX_GUILDBANK_SLOTS_PER_TAB or 98
local BANK_AGAIN = 7 * 86400   -- tell again about the same recipe after a week

local function ScanBank()
    local g = GH.Guild()
    if not g or not GH.Index or not GetNumGuildBankTabs then return end
    local tabs = GetNumGuildBankTabs() or 0
    local found, any = {}, false
    for tab = 1, tabs do
        local _, _, viewable = GetGuildBankTabInfo(tab)
        if viewable then
            for slot = 1, BANK_SLOTS do
                local link = GetGuildBankItemLink(tab, slot)
                local id = link and tonumber(link:match("|Hitem:(%d+)"))
                if id then
                    any = true
                    local name = link:match("|h%[(.-)%]|h")
                    local ok, gap, rid = pcall(GH.Index.RecipeItemGap, id, name)
                    if ok and gap and rid and not found[rid] then found[rid] = { id = id, link = link, name = name } end
                end
            end
        end
    end
    if not any then return end   -- tab contents not here yet
    local now = GetServerTime()
    local old = g.bank or {}
    g.bankTold = g.bankTold or {}
    local bank, fresh = {}, {}
    for rid, e in pairs(found) do
        bank[rid] = now
        if not old[rid] and now - (g.bankTold[rid] or 0) > BANK_AGAIN then
            g.bankTold[rid] = now
            fresh[#fresh + 1] = e
        end
    end
    g.bank = bank
    if #fresh == 0 then return end
    table.sort(fresh, function(a, b) return (a.name or "") < (b.name or "") end)
    local links = {}
    for _, e in ipairs(fresh) do links[#links + 1] = e.link end
    GH.Print(("guild bank recipes nobody in the guild has learned: %s"):format(table.concat(links, ", ")))
    local first = fresh[1]
    local text = (#fresh == 1) and ("The guild bank has %s - not learned in the guild."):format(ItemColored(first.id, first.name))
        or ("The guild bank has |cffffd100%d recipes|r nobody in the guild has learned, like %s."):format(#fresh, ItemColored(first.id, first.name))
    Toast.Add(text, ItemIcon(first.id), nil, OpenTab("gaps"), first.id)
    if GH.db.settings.bankShare and IsInGuild() then
        -- chat lines stay under 255 characters: a few links each
        local line = "Guild bank recipes nobody has learned yet:"
        local sent = 0
        for _, l in ipairs(links) do
            if #line + #l + 1 > 250 then
                SendChatMessage(line, "GUILD")
                sent = sent + 1
                if sent >= 3 then return end
                line = "More:"
            end
            line = line .. " " .. l
        end
        SendChatMessage(line, "GUILD")
    end
end

local function BankSoon()
    if not bankOpen then return end
    if bankTimer then bankTimer:Cancel() end
    bankTimer = C_Timer.NewTimer(1.5, function() bankTimer = nil; ScanBank() end)
end

GH.On("GUILDBANKFRAME_OPENED", function()
    bankOpen = true
    if GetNumGuildBankTabs and QueryGuildBankTab then
        for tab = 1, GetNumGuildBankTabs() or 0 do
            local _, _, viewable = GetGuildBankTabInfo(tab)
            if viewable then QueryGuildBankTab(tab) end
        end
    end
    BankSoon()
end)
GH.On("GUILDBANKBAGSLOTS_CHANGED", BankSoon)
GH.On("GUILDBANKFRAME_CLOSED", function() bankOpen = false end)
