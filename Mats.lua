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
