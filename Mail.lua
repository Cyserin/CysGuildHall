--------------------------------------------------------------------------------
-- Cys's Guild Hall - "Mail it" helper (crafter side)
-- At a mailbox, on the Send Mail tab, a small panel lists your claimed requests whose
-- requester asked "Mail it to me". One click fills in the requester's name, a subject
-- and attaches the crafted items from your bags. You press Send yourself; when that
-- mail goes out the request is marked done.
-- Raid prep: your claimed target items (hand-in to a person) and gathered materials
-- (to the one crafter on that target) show here too; sending raises your Handed in.
--------------------------------------------------------------------------------
local GH = CysGuildHall
local S = GH.Style
local ML = {}
GH.Mail = ML

local SOFT = { 0.84, 0.77, 0.62, 1 }
local WIDTH, ROW_H, ROWS = 250, 40, 5
local panel
local pending       -- { id, to, t } filled by our button, waiting for the send
local lastTo        -- recipient of the last SendMail call

local function Me() return GH.Me() end

-- Item the recipe makes and how many the request is for
local function Product(r)
    local c = GH.db.recipes[r.rc]
    if not c or not c.o then return nil end
    return c.o, r.n * math.max(1, c.q or 1)
end

local function Carried(itemID)
    return C_Item.GetItemCount(itemID) or 0
end

-- Requests I claimed that want mailing
function ML.ToMail()
    local out = {}
    if not (GH.db and GH.Requests) then return out end
    local me = Me()
    for _, r in ipairs(GH.Requests.All()) do
        if r.cr == me and r.dl == "m" and (r.st == "claimed" or r.st == "ready") and r.by ~= me and Product(r) then
            out[#out + 1] = r
        end
    end
    return out
end

-- Raid prep parts I still have to hand in by mail: { prep, tid, item, n, to, gather }
function ML.PrepToMail()
    local out = {}
    local P = GH.Prep
    if not (GH.db and P and GH.Guild()) then return out end
    local me = Me()
    for _, t in ipairs(P.All()) do
        for i, p in ipairs(P.Parts(t)) do
            local cl = P.MyClaim(t.id, p.item)
            local left = cl and (math.max(cl.a or 0, cl.m or 0) - (cl.d or 0)) or 0
            if left > 0 then
                local to
                if i == 1 then
                    local kind, who = P.HandIn(t)
                    if kind == "person" then to = who end
                else
                    local crafters = P.ClaimsOn(t.id, t.it)
                    if #crafters == 1 then to = crafters[1].w end
                end
                if to and to ~= me then
                    out[#out + 1] = { prep = true, tid = t.id, item = p.item, n = left, to = to, gather = i > 1 }
                end
            end
        end
    end
    return out
end

-- Everything to mail: requests first, then raid prep
local function AllToMail()
    local out = {}
    for _, r in ipairs(ML.ToMail()) do out[#out + 1] = { r = r } end
    for _, e in ipairs(ML.PrepToMail()) do out[#out + 1] = e end
    return out
end

local function Attached(itemID)
    local n, free = 0, 0
    for i = 1, ATTACHMENTS_MAX_SEND or 12 do
        if HasSendMailItem(i) then
            local _, id, _, count = GetSendMailItem(i)
            if id == itemID then n = n + (count or 1) end
        else
            free = free + 1
        end
    end
    return n, free
end

local function Bags()
    local list = {}
    for b = 0, NUM_BAG_SLOTS or 4 do list[#list + 1] = b end
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then list[#list + 1] = Enum.BagIndex.ReagentBag end
    return list
end

-- Attach up to `want` of itemID (splits a stack when it holds more than needed)
local function Attach(itemID, want)
    local have, free = Attached(itemID)
    want = want - have
    for _, bag in ipairs(Bags()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            if want <= 0 or free <= 0 then return want end
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and not info.isLocked then
                local count = info.stackCount or 1
                if count > want then
                    C_Container.SplitContainerItem(bag, slot, want)
                    count = want
                else
                    C_Container.PickupContainerItem(bag, slot)
                end
                ClickSendMailItemButton()
                if GetCursorInfo() then ClearCursor(); return want end
                want = want - count
                free = free - 1
            end
        end
    end
    return want
end

local function MailIt(r)
    if not (SendMailFrame and SendMailFrame:IsShown()) then return end
    if GetCursorInfo() then GH.Print("put down what is on your cursor first."); return end
    local itemID, n = Product(r)
    local name = GH.Index and GH.Index.RecipeName(r.rc) or GH.Prof.ItemName(itemID) or ("Item " .. itemID)
    local to = GH.Short(r.by)
    SendMailNameEditBox:SetText(to)
    local subject = ("Guild Hall: %dx %s"):format(n, name)
    SendMailSubjectEditBox:SetText(subject)
    local short = Attach(itemID, n)
    -- the mail window may put the item name in an empty subject: keep ours
    C_Timer.After(0.3, function()
        local s = SendMailSubjectEditBox:GetText()
        if s == "" or s == name then SendMailSubjectEditBox:SetText(subject) end
    end)
    pending = { id = r.id, to = to, t = GetTime() }
    if short > 0 then
        GH.Print(("attached what you carry; %d more %s still needed (or no free attachment slot)."):format(short, name))
    else
        GH.Print(("ready to send to %s - check it, then press Send. The request is marked done once it goes out."):format(to))
    end
end

local function MailPrep(e)
    if not (SendMailFrame and SendMailFrame:IsShown()) then return end
    if GetCursorInfo() then GH.Print("put down what is on your cursor first."); return end
    local name = GH.Prof.ItemName(e.item) or ("Item " .. e.item)
    local to = GH.Short(e.to)
    SendMailNameEditBox:SetText(to)
    local subject = ("Raid prep: %dx %s"):format(e.n, name)
    SendMailSubjectEditBox:SetText(subject)
    local short = Attach(e.item, e.n)
    C_Timer.After(0.3, function()
        local s = SendMailSubjectEditBox:GetText()
        if s == "" or s == name then SendMailSubjectEditBox:SetText(subject) end
    end)
    pending = { prep = e, item = e.item, att = e.n - short, to = to, t = GetTime() }
    if short > 0 then
        GH.Print(("attached what you carry; %d more %s still to hand in (or no free attachment slot)."):format(short, name))
    else
        GH.Print(("ready to send to %s - check it, then press Send. Your Handed in goes up once it goes out."):format(to))
    end
end

--------------------------------------------------------------------------------
-- Panel beside the mail window (only on the Send Mail tab, only with requests to mail)
--------------------------------------------------------------------------------
local function Build()
    local T = S.T()
    panel = S.Panel(MailFrame, T.bg, T.border)
    panel:SetWidth(WIDTH)
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
    panel:EnableMouse(true)
    panel:Hide()
    local title = S.Text(panel, 12, T.accent)
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText("Guild Hall - to mail")
    panel.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 8, -28 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
        row.btn = S.Button(row, 64, 22, "Mail it")
        row.btn:SetPoint("RIGHT")
        row.btn:SetScript("OnClick", function()
            local e = row.e
            if not e then return end
            if e.r then MailIt(e.r) else MailPrep(e) end
        end)
        row.name = S.Text(row, 12, T.text)
        row.name:SetPoint("TOPLEFT", 0, -4)
        row.name:SetPoint("RIGHT", row.btn, "LEFT", -6, 0)
        row.name:SetWordWrap(false)
        row.sub = S.Text(row, 11, SOFT)
        row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
        row.sub:SetPoint("RIGHT", row.btn, "LEFT", -6, 0)
        row.sub:SetWordWrap(false)
        panel.rows[i] = row
    end
    panel.more = S.Text(panel, 10, T.dim)
    panel.more:SetPoint("BOTTOMLEFT", 10, 6)
    SendMailFrame:HookScript("OnShow", function() ML.Paint() end)
    SendMailFrame:HookScript("OnHide", function() if panel then panel:Hide() end end)
end

function ML.Paint()
    if not (MailFrame and SendMailFrame) then return end
    if not panel then Build() end
    local list = AllToMail()
    if #list == 0 or not SendMailFrame:IsShown() then panel:Hide(); return end
    local T = S.T()
    for i = 1, ROWS do
        local row, e = panel.rows[i], list[i]
        row.e = e
        if e and e.r then
            local r = e.r
            local itemID, n = Product(r)
            local have = Carried(itemID)
            local name = GH.Index and GH.Index.RecipeName(r.rc) or GH.Prof.ItemName(itemID) or ("Item " .. itemID)
            row.name:SetText(("%dx %s"):format(n, name))
            local col = have >= n and "4fd66b" or "ff7066"
            row.sub:SetText(("to %s - |cff%shave %d|r"):format(GH.Short(r.by), col, have))
            row.btn:SetActive(have > 0)
            row:Show()
        elseif e then
            local have = Carried(e.item)
            row.name:SetText(("%dx %s"):format(e.n, GH.Prof.ItemName(e.item) or ("Item " .. e.item)))
            local col = have >= e.n and "4fd66b" or "ff7066"
            row.sub:SetText(("%s to %s - |cff%shave %d|r"):format(e.gather and "Raid prep mats" or "Raid prep", GH.Short(e.to), col, have))
            row.btn:SetActive(have > 0)
            row:Show()
        else
            row:Hide()
        end
    end
    local shown = math.min(#list, ROWS)
    panel.more:SetText(#list > ROWS and ("+%d more"):format(#list - ROWS) or "")
    panel:SetHeight(34 + shown * ROW_H + (#list > ROWS and 12 or 0))
    panel:Show()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
GH.On("MAIL_SHOW", function()
    C_Timer.After(0, function()
        if not GH.db then return end
        local n = #ML.ToMail()
        if n > 0 then
            GH.Print(("%d guild %s to mail - open the Send Mail tab."):format(n, n == 1 and "request" or "requests"))
        end
        local p = #ML.PrepToMail()
        if p > 0 then
            GH.Print(("%d raid prep %s to hand in by mail - open the Send Mail tab."):format(p, p == 1 and "part" or "parts"))
        end
        ML.Paint()
    end)
end)
GH.On("BAG_UPDATE_DELAYED", function() if panel and panel:IsShown() then ML.Paint() end end)
GH.Listen("REQUESTS", function() if panel and SendMailFrame and SendMailFrame:IsShown() then ML.Paint() end end)
GH.Listen("PREP", function() if panel and SendMailFrame and SendMailFrame:IsShown() then ML.Paint() end end)

hooksecurefunc("SendMail", function(to)
    lastTo = to
    -- raid prep: count what actually went into the mail
    if pending and pending.item then
        local n = Attached(pending.item)
        if n > 0 then pending.att = n end
    end
end)

GH.On("MAIL_SEND_SUCCESS", function()
    local p = pending
    pending = nil
    if not p or GetTime() - p.t > 600 or not lastTo then return end
    if lastTo:lower():gsub("%s+$", "") ~= p.to:lower() then return end
    if p.prep then
        local e = p.prep
        local cl = GH.Prep and GH.Prep.MyClaim(e.tid, e.item)
        local sent = p.att or 0
        if cl and sent > 0 then
            GH.Prep.SetMine(e.tid, e.item, nil, (cl.d or 0) + sent)
            GH.Print(("mailed %d to %s - raid prep Handed in updated."):format(sent, p.to))
        end
        return
    end
    local r = GH.Requests.Get(p.id)
    if r and GH.Requests.IsActive(r) and r.cr == Me() then
        GH.Requests.Set(p.id, "done")
        GH.Print(("mailed to %s - request marked done."):format(p.to))
    end
end)
GH.On("MAIL_FAILED", function() lastTo = nil end)
