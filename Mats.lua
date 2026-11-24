--------------------------------------------------------------------------------
-- Cys's Guild Hall - materials pop-up
-- When a crafter claims your request, their addon sends how many of each reagent
-- they carry (bags + bank). You get a small window: what the craft needs, what you
-- have, what the crafter has, and what is still short between you two.
-- The crafter re-sends when their counts change while the request is active.
--------------------------------------------------------------------------------
local GH = CysGuildHall
local S = GH.Style
local M = {}
GH.Mats = M

local SOFT = { 0.84, 0.77, 0.62, 1 }
local WIDTH = 400
local ROWS = 8
local frame
local current          -- request id shown
local pendingShow      -- request id waiting for combat to end

local function Me() return GH.Me() end
local function Req(id) return GH.Requests and GH.Requests.Get(id) end

local function Count(itemID)
    return C_Item.GetItemCount(itemID, true, false, true) or 0
end

local function Reagents(r)
    local c = GH.Prof.Resolve(r.rc) or {}
    return c.r or {}, c
end

local function Name(id)
    return GH.Prof.ItemName(id) or ("Item " .. id)
end

--------------------------------------------------------------------------------
-- Crafter side: send my counts for requests I claimed
-- "S~id~time~item.count,item.count" (numbers base 36)
--------------------------------------------------------------------------------
local sent = {}   -- [id] = { sig, at }
local RESEND = 120

local function Snapshot(r)
    local parts, sig = {}, { r.st }
    for _, rg in ipairs((Reagents(r))) do
        local n = Count(rg[1])
        parts[#parts + 1] = GH.To36(rg[1]) .. "." .. GH.To36(n)
        sig[#sig + 1] = rg[1] .. ":" .. n
    end
    return parts, table.concat(sig, ",")
end

local function SendStock(r, force)
    if not (GH.Comm and GH.Comm.Push) or not r or r.cr ~= Me() or not GH.Requests.IsActive(r) then return end
    local parts, sig = Snapshot(r)
    if #parts == 0 then return end
    local last = sent[r.id]
    local now = GetTime()
    if last and last.sig == sig and not (force and now - last.at > RESEND) then return end
    sent[r.id] = { sig = sig, at = now }
    local t = GetServerTime()
    r.ms = { t = t, c = {} }
    for _, rg in ipairs((Reagents(r))) do r.ms.c[rg[1]] = Count(rg[1]) end
    GH.Comm.Push(table.concat({ "S", r.id, GH.To36(t), table.concat(parts, ",") }, "~"))
end

local function MyClaims(force)
    for _, r in ipairs(GH.Requests.All()) do
        if r.cr == Me() and GH.Requests.IsActive(r) then SendStock(r, force) end
    end
end
M.Resend = function() MyClaims(true) end

local bagTimer
GH.On("BAG_UPDATE_DELAYED", function()
    if not GH.db then return end
    if frame and frame:IsShown() then M.Paint() end
    if bagTimer then return end
    bagTimer = C_Timer.NewTimer(10, function()
        bagTimer = nil
        MyClaims(false)
    end)
end)

--------------------------------------------------------------------------------
-- Requester side: incoming counts
--------------------------------------------------------------------------------
function M.Receive(text, sender)
    local id, t36, body = text:match("^S~([^~]+)~(%w+)~(.*)$")
    if not id then return end
    local r = Req(id)
    local t = GH.From36(t36)
    if not r or not t or r.cr ~= sender then return end
    if r.ms and (r.ms.t or 0) > t then return end
    local c = {}
    for item, n in body:gmatch("(%w+)%.(%w+)") do
        local iid, cnt = GH.From36(item), GH.From36(n)
        if iid and cnt then c[iid] = cnt end
    end
    r.ms = { t = t, c = c }
    GH.Fire("REQUESTS", id)
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local function Ago(t)
    local s = math.max(0, GetServerTime() - (t or 0))
    if s < 60 then return "just now" end
    if s < 3600 then return ("%d min ago"):format(math.floor(s / 60)) end
    if s < 86400 then return ("%d h ago"):format(math.floor(s / 3600)) end
    return ("%d days ago"):format(math.floor(s / 86400))
end

local function Build()
    local T = S.T()
    frame = CreateFrame("Frame", "CysGuildHallMats", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetPoint("CENTER", 0, 120)
    S.Tex(frame, "BACKGROUND", T.bg):SetAllPoints()
    S.Border(frame, T.border)

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(30)
    S.Tex(header, "BACKGROUND", T.header):SetAllPoints()
    frame.icon = header:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.icon:SetSize(18, 18)
    frame.icon:SetPoint("LEFT", 9, 0)
    local title = S.Text(header, 14, T.brand)
    title:SetPoint("LEFT", frame.icon, "RIGHT", 7, 0)
    title:SetText("Materials for your request")
    local close = S.Button(header, 22, 22, "x")
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    frame.line1 = S.Text(frame, 12, T.text)
    frame.line1:SetPoint("TOPLEFT", 16, -44)
    frame.line1:SetWidth(WIDTH - 32)
    frame.line1:SetWordWrap(false)
    frame.line2 = S.Text(frame, 12, SOFT)
    frame.line2:SetPoint("TOPLEFT", frame.line1, "BOTTOMLEFT", 0, -4)
    frame.line2:SetWidth(WIDTH - 32)

    frame.field = S.Panel(frame, T.field)
    frame.field:SetPoint("TOPLEFT", frame.line2, "BOTTOMLEFT", 0, -10)
    frame.field:SetWidth(WIDTH - 32)
    frame.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, frame.field)
        r:SetHeight(20)
        r:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 20)
        r:SetPoint("RIGHT", frame.field, "RIGHT", -8, 0)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT")
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = S.Text(r, 12, T.text)
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetPoint("RIGHT")
        r.text:SetWordWrap(false)
        r:SetScript("OnEnter", function(b)
            if not b.itemID then return end
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(b.itemID)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.rows[i] = r
    end

    frame.status = S.Text(frame, 12, T.text)
    frame.status:SetPoint("TOPLEFT", frame.field, "BOTTOMLEFT", 0, -8)
    frame.status:SetWidth(WIDTH - 32)
    frame.status:SetSpacing(2)
    frame.note = S.Text(frame, 11, SOFT)
    frame.note:SetPoint("TOPLEFT", frame.status, "BOTTOMLEFT", 0, -6)
    frame.note:SetWidth(WIDTH - 32)
    frame.note:SetSpacing(2)

    frame.ok = S.Button(frame, 90, 24, "Close")
    frame.ok:SetPoint("BOTTOMRIGHT", -16, 14)
    frame.ok:SetScript("OnClick", function() frame:Hide() end)
    frame.ready = S.Button(frame, 110, 24, "Mats ready")
    frame.ready:SetPoint("RIGHT", frame.ok, "LEFT", -8, 0)
    frame.ready:SetScript("OnClick", function()
        local r = Req(current)
        if r and r.st == "claimed" and r.by == Me() then GH.Requests.Set(r.id, "ready") end
    end)

    -- Escape closes it; other keys pass through (pass-through can only be set out of combat)
    local function KeysOn()
        if frame.keysOn or InCombatLockdown() then return end
        frame:SetPropagateKeyboardInput(true)
        frame:EnableKeyboard(true)
        frame.keysOn = true
    end
    frame:SetScript("OnShow", KeysOn)
    frame:SetScript("OnKeyDown", function(f, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            f:SetPropagateKeyboardInput(false)
            f:Hide()
        else
            f:SetPropagateKeyboardInput(true)
        end
    end)
    frame:SetScript("OnHide", function(f)
        GameTooltip:Hide()
        if f.keysOn and not InCombatLockdown() then f:SetPropagateKeyboardInput(true) end
    end)
    frame:Hide()
end

function M.Paint()
    if not frame or not frame:IsShown() then return end
    local T = S.T()
    local r = Req(current)
    if not r or not r.cr or r.st == "cancelled" then frame:Hide(); return end
    local reagents, c = Reagents(r)
    local name = GH.Index and GH.Index.RecipeName(r.rc) or ("recipe " .. r.rc)
    local tex = c.o and C_Item.GetItemIconByID(c.o)
    frame.icon:SetTexture(tex or 134400)
    local dl = GH.Requests.DELIVERY[r.dl or ""]
    frame.line1:SetText(("You requested |cffffd100%dx %s|r%s."):format(r.n, name, dl and (" (" .. dl:lower() .. ")") or ""))
    local cr, cg, cb = GH.ClassColor(r.cr)
    local crafter = GH.Short(r.cr)
    frame.line2:SetText(("Crafted by |cff%02x%02x%02x%s|r."):format(math.floor(cr * 255), math.floor(cg * 255), math.floor(cb * 255), crafter))

    local ms = r.ms
    local short = {}
    local shown = math.min(ROWS, #reagents)
    for i = 1, ROWS do
        local row = frame.rows[i]
        local rg = reagents[i]
        if rg then
            row:Show()
            local rid = rg[1]
            local need = rg[2] * r.n
            local mine = Count(rid)
            local theirs = ms and ms.c[rid]
            row.itemID = rid
            row.icon:SetTexture(C_Item.GetItemIconByID(rid) or 134400)
            local has = theirs and tostring(theirs) or "?"
            row.text:SetText(("%s - %d (%d) crafter has %s"):format(Name(rid), need, mine, has))
            local total = mine + (theirs or 0)
            if total >= need then
                row.text:SetTextColor(T.green[1], T.green[2], T.green[3])
            else
                row.text:SetTextColor(T.danger[1], T.danger[2], T.danger[3])
                short[#short + 1] = ("%d %s"):format(need - total, Name(rid))
            end
        else
            row:Hide()
            row.itemID = nil
        end
    end
    frame.field:SetHeight(math.max(1, shown) * 20 + 8)

    if #reagents == 0 then
        frame.status:SetText("Recipe details not available yet: open the request in /guildhall.")
        frame.status:SetTextColor(T.dim[1], T.dim[2], T.dim[3])
    elseif #short == 0 then
        frame.status:SetText(("Between you and %s, everything is covered."):format(crafter))
        frame.status:SetTextColor(T.green[1], T.green[2], T.green[3])
    else
        frame.status:SetText("Still short: " .. table.concat(short, ", "))
        frame.status:SetTextColor(T.danger[1], T.danger[2], T.danger[3])
    end
    if ms then
        frame.note:SetText(("Needed, (what you have), then what %s has. Bags + bank; their counts from %s."):format(crafter, Ago(ms.t)))
    else
        frame.note:SetText(("Waiting for %s's counts (they need Cys's Guild Hall 0.3.11 or newer)."):format(crafter))
    end

    frame.ready:SetShown(r.st == "claimed" and r.by == Me())
    frame:SetHeight(44 + 18 + 26 + frame.field:GetHeight() + 8 + frame.status:GetStringHeight() + 6
        + frame.note:GetStringHeight() + 14 + 24 + 14)
end

function M.Show(id)
    local r = Req(id)
    if not r or not r.cr then return end
    if not frame then Build() end
    current = id
    frame:Show()
    M.Paint()
end

-- Latest claimed request of mine (for /guildhall mats)
function M.ShowLatest()
    for _, r in ipairs(GH.Requests.All()) do
        if r.by == Me() and r.cr and GH.Requests.IsActive(r) and r.st ~= "open" then M.Show(r.id); return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Triggers
--------------------------------------------------------------------------------
local waiter = CreateFrame("Frame")
waiter:SetScript("OnEvent", function(w)
    w:UnregisterAllEvents()
    local id = pendingShow
    pendingShow = nil
    if id then M.Show(id) end
end)

GH.Listen("REQUESTS", function(id)
    if not GH.db then return end
    local r = id and Req(id)
    if not r then return end
    -- crafter: share my counts when I claim, on "mats ready", and on any state change
    -- (a second later, so the claim itself reaches the guild first)
    if r.cr == Me() then C_Timer.After(1, function() SendStock(Req(id), false) end) end
    -- requester: pop up once per crafter when someone claims my request
    if r.by == Me() and r.cr and r.cr ~= Me() and GH.Requests.IsActive(r) and r.st ~= "open" then
        if GH.db.settings.matsPopup and r.mp ~= r.cr then
            r.mp = r.cr
            if InCombatLockdown() then
                pendingShow = id
                waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                M.Show(id)
            end
            return
        end
    end
    if frame and frame:IsShown() and current == id then M.Paint() end
end)

--------------------------------------------------------------------------------
-- Shopping list: reagents you are missing, per character. At the auction house a
-- click on a line searches for it. Each line remembers your count when it was added,
-- so buying (or looting) the items ticks it off.
--------------------------------------------------------------------------------
local SHOP_ROWS = 10
local SHOP_W = 300
local shop          -- frame
local shopAuto      -- shown because the auction house opened

local function ShopList()
    local me = Me()
    local l = GH.db.shop[me]
    if not l then l = {}; GH.db.shop[me] = l end
    return l
end

-- still to get for one line
local function Left(e) return math.max(0, e.q - math.max(0, Count(e.id) - e.c)) end

local function AHOpen()
    return AuctionHouseFrame and AuctionHouseFrame:IsShown() and true or false
end

local function Money(c)
    if not c or c <= 0 then return nil end
    if GetCoinTextureString then return GetCoinTextureString(c) end
    return ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
end

local function Price(id)
    local ah = _G.CysAH
    if not (ah and ah.GetPrice) then return nil end
    local ok, p = pcall(ah.GetPrice, id)
    return ok and type(p) == "number" and p or nil
end

-- the game's auction house: Buy tab, search box, search
local function SearchAH(id)
    local name = Name(id)
    local f = AuctionHouseFrame
    if not AHOpen() then GH.Print("open the auction house to search for " .. name .. "."); return end
    if f.SetDisplayMode and AuctionHouseFrameDisplayMode and AuctionHouseFrameDisplayMode.Buy then
        pcall(f.SetDisplayMode, f, AuctionHouseFrameDisplayMode.Buy)
    end
    local bar = f.SearchBar
    if bar and bar.SearchBox and bar.StartSearch then
        bar.SearchBox:SetText(name)
        pcall(bar.StartSearch, bar)
    else
        GH.Print("couldn't reach the auction house search: type " .. name .. " there.")
    end
end

local function BuildShop()
    local T = S.T()
    shop = CreateFrame("Frame", "CysGuildHallShop", UIParent)
    shop:SetWidth(SHOP_W)
    shop:SetFrameStrata("HIGH")
    shop:SetClampedToScreen(true)
    shop:SetMovable(true)
    shop:EnableMouse(true)
    shop:RegisterForDrag("LeftButton")
    shop:SetScript("OnDragStart", function(f) if not f.docked then f:StartMoving() end end)
    shop:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local p, _, _, x, y = f:GetPoint()
        GH.db.settings.shopPos = { p, x, y }
    end)
    S.Tex(shop, "BACKGROUND", T.bg):SetAllPoints()
    S.Border(shop, T.border)

    local header = CreateFrame("Frame", nil, shop)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(28)
    S.Tex(header, "BACKGROUND", T.header):SetAllPoints()
    local title = S.Text(header, 13, T.brand)
    title:SetPoint("LEFT", 10, 0)
    title:SetText("Shopping list")
    local close = S.Button(header, 20, 20, "x")
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function() shop:Hide() end)

    shop.field = S.Panel(shop, T.field)
    shop.field:SetPoint("TOPLEFT", 10, -38)
    shop.field:SetPoint("RIGHT", shop, "RIGHT", -10, 0)
    shop.rows = {}
    for i = 1, SHOP_ROWS do
        local r = CreateFrame("Button", nil, shop.field)
        r:SetHeight(20)
        r:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 20)
        r:SetPoint("RIGHT", shop.field, "RIGHT", -6, 0)
        r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.hl = S.Tex(r, "BACKGROUND", T.cardHover)
        r.hl:SetAllPoints()
        r.hl:Hide()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 2, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.right = S.Text(r, 11, SOFT, "RIGHT")
        r.right:SetPoint("RIGHT", -2, 0)
        r.text = S.Text(r, 12, T.text)
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
        r.text:SetPoint("RIGHT", r.right, "LEFT", -6, 0)
        r.text:SetWordWrap(false)
        r:SetScript("OnClick", function(b, btn)
            if not b.e then return end
            if btn == "RightButton" then
                local l = ShopList()
                for k, e in ipairs(l) do if e == b.e then table.remove(l, k); break end end
                M.PaintShop()
            else
                SearchAH(b.e.id)
            end
        end)
        r:SetScript("OnEnter", function(b)
            b.hl:Show()
            if not b.e then return end
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(b.e.id)
            if b.e.by then GameTooltip:AddLine("For " .. b.e.by, SOFT[1], SOFT[2], SOFT[3], true) end
            GameTooltip:AddLine(AHOpen() and "Click: search the auction house" or "Open the auction house to search", 1, 0.82, 0)
            GameTooltip:AddLine("Right-click: remove", 1, 0.82, 0)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function(b) b.hl:Hide(); GameTooltip:Hide() end)
        shop.rows[i] = r
    end
    shop.status = S.Text(shop, 11, SOFT)
    shop.status:SetPoint("TOPLEFT", shop.field, "BOTTOMLEFT", 0, -6)
    shop.status:SetPoint("RIGHT", shop, "RIGHT", -10, 0)
    shop.status:SetSpacing(2)
    shop.clearAll = S.Button(shop, 70, 20, "Clear all")
    shop.clearAll:SetPoint("BOTTOMRIGHT", -10, 10)
    shop.clearAll:SetScript("OnClick", function(b)
        if b.armed then
            b.armed = nil
            b:SetLabel("Clear all")
            wipe(ShopList())
            M.PaintShop()
        else
            b.armed = true
            b:SetLabel("|cffff4040Sure?|r")
            C_Timer.After(3, function() if b.armed then b.armed = nil; b:SetLabel("Clear all") end end)
        end
    end)
    shop.clearDone = S.Button(shop, 80, 20, "Clear done")
    shop.clearDone:SetPoint("RIGHT", shop.clearAll, "LEFT", -6, 0)
    shop.clearDone:SetScript("OnClick", function()
        local l = ShopList()
        for k = #l, 1, -1 do if Left(l[k]) == 0 then table.remove(l, k) end end
        M.PaintShop()
    end)
    shop:SetScript("OnHide", function(f)
        GameTooltip:Hide()
        shopAuto = nil
    end)
    shop:Hide()
end

local function Place()
    shop:ClearAllPoints()
    shop.docked = nil
    if AHOpen() then
        shop:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
        shop.docked = true
        return
    end
    local pos = GH.db.settings.shopPos
    if pos then shop:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else shop:SetPoint("CENTER", 300, 60) end
end

function M.PaintShop()
    if not shop or not shop:IsShown() then return end
    local T = S.T()
    local l = ShopList()
    -- still needed first, done ones last
    local open, done = {}, {}
    for _, e in ipairs(l) do
        if Left(e) > 0 then open[#open + 1] = e else done[#done + 1] = e end
    end
    local order = {}
    for _, e in ipairs(open) do order[#order + 1] = e end
    for _, e in ipairs(done) do order[#order + 1] = e end
    local total, priced = 0, 0
    for i = 1, SHOP_ROWS do
        local r = shop.rows[i]
        local e = order[i]
        r.e = e
        if e then
            r:Show()
            local left = Left(e)
            r.icon:SetTexture(C_Item.GetItemIconByID(e.id) or 134400)
            r.text:SetText(Name(e.id))
            if left > 0 then
                r.text:SetTextColor(T.text[1], T.text[2], T.text[3])
                local p = Price(e.id)
                local m = p and Money(p * left)
                r.right:SetText(m and (left .. "  " .. m) or tostring(left))
            else
                r.text:SetTextColor(0.55, 0.55, 0.55)
                r.right:SetText("|cff4fd66bgot it|r")
            end
        else
            r:Hide()
        end
    end
    for _, e in ipairs(open) do
        local p = Price(e.id)
        if p then total = total + p * Left(e); priced = priced + 1 end
    end
    local shown = math.max(1, math.min(SHOP_ROWS, #order))
    shop.field:SetHeight(shown * 20 + 8)
    local lines = {}
    if #order == 0 then
        lines[1] = "Nothing on the list. Pick an item on the Crafting tab and press Shopping list."
    else
        if #order > SHOP_ROWS then lines[#lines + 1] = ("+%d more (clear done ones to see them)"):format(#order - SHOP_ROWS) end
        if #open == 0 then
            lines[#lines + 1] = "|cff4fd66bYou have everything on the list.|r"
        elseif priced > 0 then
            lines[#lines + 1] = ("About %s%s (Cys's Auction House prices)"):format(Money(total) or "0",
                priced < #open and (" for " .. priced .. " of " .. #open) or "")
        end
        lines[#lines + 1] = AHOpen() and "Click a line to search; right-click removes it." or "At the auction house, click a line to search for it."
    end
    shop.status:SetText(table.concat(lines, "\n"))
    shop.clearDone:SetShown(#done > 0)
    shop.clearAll:SetShown(#order > 0)
    shop:SetHeight(38 + shop.field:GetHeight() + 6 + shop.status:GetStringHeight() + 10 + 20 + 12)
end

function M.ShowShop()
    if not GH.db then return end
    if not shop then BuildShop() end
    Place()
    shop:Show()
    M.PaintShop()
end

-- Add the reagents you are missing (bags + bank) for count x recipe
function M.ShopAdd(recipeID, count)
    local c = GH.Prof.Resolve(recipeID) or {}
    local l = ShopList()
    local what = GH.Index and GH.Index.RecipeName(recipeID) or nil
    local added = 0
    for _, rg in ipairs(c.r or {}) do
        local id, need = rg[1], rg[2] * (count or 1)
        local have = Count(id)
        if have < need then
            local miss = need - have
            local cur
            for _, e in ipairs(l) do if e.id == id then cur = e; break end end
            if cur then
                -- what is still open on the line, plus this
                cur.q, cur.c = Left(cur) + miss, have
                if what and cur.by and not cur.by:find(what, 1, true) then cur.by = cur.by .. ", " .. what end
            else
                l[#l + 1] = { id = id, q = miss, c = have, by = what and ((count or 1) .. "x " .. what) or nil }
            end
            added = added + 1
        end
    end
    if added == 0 then
        GH.Print("you already have everything for that.")
    else
        GH.Print(("added %d %s to your shopping list."):format(added, added == 1 and "reagent" or "reagents"))
    end
    M.ShowShop()
end

GH.On("AUCTION_HOUSE_SHOW", function()
    if not GH.db or not GH.db.settings.shopAuto then return end
    C_Timer.After(0.2, function()
        local any
        for _, e in ipairs(ShopList()) do if Left(e) > 0 then any = true; break end end
        if not any or not AHOpen() then return end
        local was = shop and shop:IsShown()
        M.ShowShop()
        if not was then shopAuto = true end
    end)
end)
GH.On("AUCTION_HOUSE_CLOSED", function()
    if not shop then return end
    if shopAuto then shop:Hide() elseif shop:IsShown() then Place(); M.PaintShop() end
end)
local shopTimer
GH.On("BAG_UPDATE_DELAYED", function()
    if not shop or not shop:IsShown() or shopTimer then return end
    shopTimer = C_Timer.NewTimer(0.5, function() shopTimer = nil; M.PaintShop() end)
end)
