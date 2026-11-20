--------------------------------------------------------------------------------
-- Cys's Guild Hall - Raid Prep tab
-- Left: the guild's targets (officers add new ones at the bottom).
-- Right: the picked target: progress, its parts (the item + its materials),
-- who is on the picked part, and your own claim / made / delivered numbers.
--------------------------------------------------------------------------------
local GH = CysGuildHall
local S = GH.Style
local UI = {}
GH.PrepPanel = UI

local SOFT = { 0.84, 0.77, 0.62, 1 }
local LIST_ROWS, LIST_H = 12, 26
local PART_ROWS, PART_H = 7, 22
local WHO_ROWS, WHO_H = 4, 18

local panel
local state = { sel = nil, focus = nil, offset = 0 }

local function Hex(r, g, b) return ("%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255)) end

local function Name(id) return GH.Prof.ItemName(id) or ("Item " .. id) end

local function Icon(id)
    local ok, tex = pcall(C_Item.GetItemIconByID, id)
    return ok and tex or 134400
end

local function QualityName(id)
    local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
    if q then GH.db.quality[id] = q else q = GH.db.quality[id] end
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return "|cff" .. Hex(c.r, c.g, c.b) .. Name(id) .. "|r" end
    return Name(id)
end

local function Ago(t)
    local d = GetServerTime() - (t or 0)
    if d < 3600 then return math.max(1, math.floor(d / 60)) .. " min ago" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    local n = math.floor(d / 86400)
    return n == 1 and "1 day ago" or (n .. " days ago")
end

local function Count(id) return C_Item.GetItemCount(id, true, false, true) or 0 end

local function ItemTip(owner, id)
    if not id then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(id)
    GameTooltip:Show()
end

local function Label(parent, text)
    local T = S.T()
    local fs = S.Text(parent, 11, T.accent)
    fs:SetText(text or "")
    return fs
end

-- Number box: digits only; Enter or clicking away saves, Escape puts the old number back
local function NumBox(parent, w, commit)
    local e = S.EditBox(parent, w, 20)
    e:SetNumeric(true)
    e:SetMaxLetters(4)
    e:SetJustifyH("CENTER")
    e:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(s) s.cancel = true; s:ClearFocus() end)
    e:HookScript("OnEditFocusLost", function(s)
        if s.cancel then
            s.cancel = nil
            if s.shown then s:SetText(tostring(s.shown)) end
            return
        end
        local v = tonumber(s:GetText())
        if v and v ~= s.shown then commit(v) end
        UI.PaintSoon()
    end)
    function e:SetNumber(v)
        self.shown = v
        if not self:HasFocus() then self:SetText(tostring(v or 0)) end
    end
    return e
end

--------------------------------------------------------------------------------
-- Adding a target: shift-click an item into the box, or type its name
--------------------------------------------------------------------------------
local function ResolveItem(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local box = panel.itemBox
    if box.linkID and box.linkName == text then return box.linkID end
    local id = tonumber(text:match("|Hitem:(%d+)"))
    if id then return id end
    local low = text:lower()
    for iid, n in pairs(GH.db.names) do
        if n:lower() == low then return iid end
    end
    if C_Item.GetItemInfoInstant then
        local ok, iid = pcall(C_Item.GetItemInfoInstant, text)
        if ok and type(iid) == "number" then return iid end
    end
    return nil
end

local function AddTarget()
    local id = ResolveItem(panel.itemBox:GetText())
    local n = tonumber(panel.countBox:GetText()) or 0
    if not id then
        GH.Print("item not found. Shift-click it from your bags or a chat link, or type its exact name.")
        return
    end
    if n < 1 then GH.Print("set how many the guild needs.") return end
    local to = GH.db.settings.prepTo or "s"
    if to == "r" then
        local name = (panel.toName:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then GH.Print("type the raider's name (First Last) for the hand-in.") return end
        if not name:find("-", 1, true) then
            local first, last = name:match("^(%S+)%s+(%S+)$")
            name = first and (first .. "-" .. last) or GH.Canon(name)
        end
        to = name
    end
    local t = GH.Prep.New(id, n, to)
    if t then
        panel.itemBox:SetText("")
        panel.itemBox.linkID, panel.itemBox.linkName = nil, nil
        panel.itemBox:ClearFocus()
        state.sel, state.focus, state.offset = t.id, t.it, 0
        UI.Paint()
    end
end

if ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if not panel or not panel:IsShown() or not panel.itemBox:HasFocus() or type(link) ~= "string" then return end
        local id = tonumber(link:match("|Hitem:(%d+)"))
        local name = link:match("%[(.-)%]")
        if id and name then
            panel.itemBox.linkID, panel.itemBox.linkName = id, name
            panel.itemBox:SetText(name)
        end
    end)
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------
local function PaintList(list)
    local T = S.T()
    local maxOff = math.max(0, #list - LIST_ROWS)
    if state.offset > maxOff then state.offset = maxOff end
    for i = 1, LIST_ROWS do
        local row = panel.rows[i]
        local t = list[state.offset + i]
        row.data = t
        if t then
            row:Show()
            row.icon:SetTexture(Icon(t.it))
            row.text:SetText(QualityName(t.it))
            local done = t._deliv >= t.n
            if done then
                row.right:SetText("|cff4fd66bdone|r")
            else
                row.right:SetText(("%d / %d"):format(t._made, t.n))
            end
            row.sub:SetText(t._claimed > t._made and (t._claimed .. " claimed") or "")
            row.sel:SetShown(t.id == state.sel)
        else
            row:Hide()
        end
    end
    panel.empty:SetText(#list == 0 and "No raid prep targets yet.\n\nOfficers add them below: shift-click an item or type its name, set how many, then Add." or "")
    panel.more:SetText(#list > LIST_ROWS and ("%d targets - scroll for more"):format(#list) or "")
end

local function PaintDetail(t)
    local T = S.T()
    local d = panel.detail
    local officer = GH.Prep.IAmOfficer()
    if not t then
        d.body:Hide()
        d.none:SetText(#GH.Prep.All() > 0 and "Pick a target on the left." or "")
        return
    end
    d.none:SetText("")
    d.body:Show()
    local parts = GH.Prep.Parts(t)
    local main = parts[1]
    -- focus: the picked part (the target item when none, or when it left the list)
    local focus
    for _, p in ipairs(parts) do if p.item == state.focus then focus = p end end
    if not focus then focus = main; state.focus = main.item end

    d.icon:SetTexture(Icon(t.it))
    d.name:SetText(QualityName(t.it))
    d.sub:SetText(("Set by %s, %s"):format(GH.Short(t.by), Ago(t.at)))

    -- officer controls
    d.needLabel:SetShown(officer)
    d.need:SetShown(officer)
    d.remove:SetShown(officer)
    if officer then d.need:SetNumber(t.n) end
    if d.remove.armed and d.remove.tid ~= t.id then d.remove.armed = nil; d.remove:SetLabel("Remove") end

    -- progress
    local w = d.barBg:GetWidth()
    if not w or w <= 0 then w = 348 end
    local made, claimed = math.min(main.made, t.n), math.min(main.claimed, t.n)
    d.barClaim:SetWidth(math.max(0.01, w * claimed / t.n))
    d.barMade:SetWidth(math.max(0.01, w * made / t.n))
    d.barClaim:SetShown(claimed > 0)
    d.barMade:SetShown(made > 0)
    local dash = "  |cff" .. Hex(SOFT[1], SOFT[2], SOFT[3]) .. "-|r  "
    if main.deliv >= t.n then
        d.progress:SetText(("|cff4fd66bComplete: %d / %d handed in|r"):format(main.deliv, t.n))
    else
        local verb = main.kind == "craft" and "made" or "brought"
        d.progress:SetText(("%d %s" .. dash .. "%d handed in" .. dash .. "%d claimed" .. dash .. "%d needed"):format(main.made, verb, main.deliv, main.claimed, t.n))
    end
    d.handIn:SetText("Hand in: |cffffffff" .. GH.Prep.HandInText(t) .. "|r")

    -- parts
    for i = 1, PART_ROWS do
        local row = d.parts[i]
        local p = parts[i]
        row.data = p
        if p then
            row:Show()
            row.icon:SetTexture(Icon(p.item))
            local kind = p.kind == "craft" and "Craft" or p.kind == "bring" and "Bring" or "Gather"
            row.kind:SetText(kind)
            row.text:SetText(QualityName(p.item))
            if (i == 1 and p.deliv or p.made) >= p.need then
                row.right:SetText(("|cff4fd66b%d / %d|r"):format(p.made, p.need))
            elseif p.claimed > p.made then
                row.right:SetText(("%d / %d  |cff%s(%d claimed)|r"):format(p.made, p.need, Hex(SOFT[1], SOFT[2], SOFT[3]), p.claimed))
            else
                row.right:SetText(("%d / %d"):format(p.made, p.need))
            end
            row.sel:SetShown(p.item == state.focus)
        else
            row:Hide()
        end
    end
    d.partsMore:SetText(#parts > PART_ROWS and ("+%d more materials"):format(#parts - PART_ROWS) or "")
    d.partsNote:SetText(#parts == 1 and (main.kind == "craft" and "" or "Nobody in the guild has a recipe for this, so it is brought in as is.") or "")

    -- who is on the picked part
    d.whoLabel:SetText("Who is on " .. Name(focus.item))
    local who = GH.Prep.ClaimsOn(t.id, focus.item)
    for i = 1, WHO_ROWS do
        local row = d.who[i]
        local cl = who[i]
        if cl then
            row:Show()
            local r, g, b = 0.55, 0.55, 0.55
            if GH.IsOnline(cl.w) or cl.w == GH.Me() then r, g, b = GH.ClassColor(cl.w) end
            row.text:SetText("|cff" .. Hex(r, g, b) .. GH.Short(cl.w) .. "|r")
            local a, dl, m = cl.a or 0, cl.d or 0, math.max(cl.m or 0, cl.d or 0)
            local dash = "  |cff" .. Hex(SOFT[1], SOFT[2], SOFT[3]) .. "-|r  "
            local verb = focus.kind == "gather" and "gathered" or "made"
            if a > 0 and dl >= a then
                row.right:SetText(("|cff4fd66b%d handed in|r"):format(dl))
            else
                row.right:SetText(("%d claimed" .. dash .. "%d %s" .. dash .. "%d handed in"):format(math.max(a, m), m, verb, dl))
            end
        else
            row:Hide()
        end
    end
    d.whoNone:SetText(#who == 0 and "Nobody yet - claim a part below." or "")
    d.whoMore:SetText(#who > WHO_ROWS and ("+%d more"):format(#who - WHO_ROWS) or "")

    -- your part
    local can = not (focus.kind == "craft" and not GH.Prep.ICanMake(focus.item))
    local mine = GH.Prep.MyClaim(t.id, focus.item)
    d.claim:SetNumber(mine and mine.a or 0)
    d.made:SetNumber(mine and math.max(mine.m or 0, mine.d or 0) or 0)
    d.deliv:SetNumber(mine and mine.d or 0)
    d.madeLabel:SetText(focus.kind == "gather" and "Gathered" or "Made")
    for _, b in ipairs({ d.claim, d.made, d.deliv }) do
        b:EnableMouse(can)
        b:SetAlpha(can and 1 or 0.45)
        if not can then b:ClearFocus() end
    end
    d.allDone:SetActive(can and mine ~= nil and math.max(mine.a or 0, mine.m or 0) > (mine.d or 0))
    -- Claim button: take whatever is still open on this part (others' claims left alone)
    local myPart = mine and math.max(mine.a or 0, mine.d or 0, mine.m or 0) or 0
    local open = focus.need - (focus.claimed - myPart)
    d.claimRest.to = (can and open > myPart) and open or nil
    d.claimRest:SetShown(d.claimRest.to ~= nil)
    if d.claimRest.to then d.claimRest:SetLabel(("Claim %d"):format(open - myPart)) end
    local note
    if not can then
        note = "You can't craft this - pick a material above to gather."
    else
        note = ("You carry %d."):format(Count(focus.item))
        if focus.kind ~= "gather" then
            local kind = GH.Prep.HandIn(t)
            note = note .. (kind == "bank" and " Put them in the guild bank." or (" Send to " .. GH.Prep.HandInText(t) .. "."))
        else
            local crafters = {}
            for _, cl in ipairs(GH.Prep.ClaimsOn(t.id, t.it)) do crafters[#crafters + 1] = GH.Short(cl.w) end
            if #crafters > 0 then note = note .. " Send to: " .. table.concat(crafters, ", ") .. "." end
        end
    end
    d.yourNote:SetText(note)
end

function UI.Paint()
    if not panel or not panel:IsShown() then return end
    local list = GH.Prep.All()
    local sel
    for _, t in ipairs(list) do if t.id == state.sel then sel = t end end
    if not sel and list[1] then
        sel = list[1]
        state.sel, state.focus = sel.id, sel.it
    elseif not sel then
        state.sel, state.focus = nil, nil
    end
    PaintList(list)
    PaintDetail(sel)
    local officer = GH.Prep.IAmOfficer()
    panel.addBox:SetShown(officer)
    panel.notOfficer:SetShown(not officer)
end

local paintTimer
function UI.PaintSoon()
    if not panel or not panel:IsShown() or paintTimer then return end
    paintTimer = C_Timer.NewTimer(0.2, function()
        paintTimer = nil
        UI.Paint()
    end)
end
GH.Listen("PREP", UI.PaintSoon)
GH.Listen("ROSTER", UI.PaintSoon)
GH.Listen("NAMES", UI.PaintSoon)
GH.Listen("DATA", UI.PaintSoon)
GH.On("BAG_UPDATE_DELAYED", UI.PaintSoon)

--------------------------------------------------------------------------------
-- Build (called by the main window once)
--------------------------------------------------------------------------------
local function ListRow(parent, h)
    local T = S.T()
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(h)
    row.hl = S.Tex(row, "BACKGROUND", T.cardHover)
    row.hl:SetAllPoints()
    row.hl:Hide()
    row.sel = S.Tex(row, "BACKGROUND", T.selected, 1)
    row.sel:SetAllPoints()
    row.sel:Hide()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row:SetScript("OnLeave", function(r) r.hl:Hide(); GameTooltip:Hide() end)
    return row
end

function UI.Build(frame)
    local T = S.T()
    panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", 1, -31)
    panel:SetPoint("BOTTOMRIGHT", -1, 1)
    panel:SetFrameLevel(frame:GetFrameLevel() + 30)
    panel:EnableMouse(true)
    S.Tex(panel, "BACKGROUND", { T.bg[1], T.bg[2], T.bg[3], 1 }):SetAllPoints()
    panel:Hide()
    panel:SetScript("OnShow", function() UI.Paint() end)

    -- targets list
    local head = Label(panel, "Raid prep targets")
    head:SetPoint("TOPLEFT", 12, -12)
    panel.more = S.Text(panel, 10, T.dim, "RIGHT")
    panel.more:SetPoint("TOPRIGHT", panel, "TOPLEFT", 310, -13)
    local box = S.Panel(panel, T.field)
    box:SetPoint("TOPLEFT", 10, -30)
    box:SetSize(300, LIST_ROWS * LIST_H + 4)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta)
        state.offset = math.max(0, state.offset - delta * 3)
        UI.Paint()
    end)
    panel.rows = {}
    for i = 1, LIST_ROWS do
        local row = ListRow(box, LIST_H)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * LIST_H)
        row:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * LIST_H)
        row.icon:SetSize(20, 20)
        row.right = S.Text(row, 11, T.text, "RIGHT")
        row.right:SetPoint("TOPRIGHT", -6, -3)
        row.sub = S.Text(row, 10, SOFT, "RIGHT")
        row.sub:SetPoint("BOTTOMRIGHT", -6, 2)
        row.text = S.Text(row, 12, T.text)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -84, 0)
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(r)
            if not r.data then return end
            state.sel, state.focus = r.data.id, r.data.it
            UI.Paint()
        end)
        row:SetScript("OnEnter", function(r)
            r.hl:Show()
            if r.data then ItemTip(r, r.data.it) end
        end)
        panel.rows[i] = row
    end
    panel.empty = S.Text(box, 11, SOFT, "CENTER")
    panel.empty:SetPoint("CENTER")
    panel.empty:SetWidth(260)

    -- new target (officers)
    local add = CreateFrame("Frame", nil, panel)
    add:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)
    add:SetSize(300, 70)
    panel.addBox = add
    local al = Label(add, "New target")
    al:SetPoint("TOPLEFT", 2, 0)
    local item = S.EditBox(add, 196, 22)
    item:SetPoint("TOPLEFT", 0, -16)
    item.hint:SetText("Shift-click or type an item")
    item:SetScript("OnTextChanged", function(e)
        e.hint:SetShown(e:GetText() == "")
        if e.linkName and e:GetText() ~= e.linkName then e.linkID, e.linkName = nil, nil end
    end)
    item:SetScript("OnEnterPressed", function() AddTarget() end)
    panel.itemBox = item
    local count = S.EditBox(add, 44, 22)
    count:SetPoint("LEFT", item, "RIGHT", 4, 0)
    count:SetNumeric(true)
    count:SetMaxLetters(4)
    count:SetJustifyH("CENTER")
    count:SetText("20")
    count:SetScript("OnEnterPressed", function() AddTarget() end)
    count:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("How many the guild needs", 1, 1, 1)
        GameTooltip:Show()
    end)
    count:HookScript("OnLeave", function() GameTooltip:Hide() end)
    panel.countBox = count
    local addBtn = S.Button(add, 52, 22, "Add")
    addBtn:SetPoint("LEFT", count, "RIGHT", 4, 0)
    addBtn:SetScript("OnClick", AddTarget)
    local tl = S.Text(add, 11, SOFT)
    tl:SetPoint("TOPLEFT", item, "BOTTOMLEFT", 2, -10)
    tl:SetText("Hand in to")
    local toName = S.EditBox(add, 116, 20)
    toName.hint:SetText("First Last")
    toName:SetScript("OnTextChanged", function(e) e.hint:SetShown(e:GetText() == "") end)
    toName:SetScript("OnEnterPressed", function() AddTarget() end)
    panel.toName = toName
    local to = S.Dropdown(add, 110, 20, function()
        return { { "s", "Me" }, { "b", "Guild bank" }, { "r", "A raider" } }
    end, function() return GH.db.settings.prepTo or "s" end, function(v)
        GH.db.settings.prepTo = v
        toName:SetShown(v == "r")
    end)
    to:SetPoint("LEFT", tl, "RIGHT", 8, 0)
    toName:SetPoint("LEFT", to, "RIGHT", 4, 0)
    toName:SetShown((GH.db.settings.prepTo or "s") == "r")
    to:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Where finished items go", 1, 1, 1)
        GameTooltip:AddLine("Crafters see it on the target. Gatherers send materials to the crafters.", 0.84, 0.77, 0.62, true)
        GameTooltip:Show()
    end)
    to:HookScript("OnLeave", function() GameTooltip:Hide() end)
    panel.notOfficer = S.Text(panel, 11, SOFT)
    panel.notOfficer:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -12)
    panel.notOfficer:SetWidth(296)
    panel.notOfficer:SetText("Officers set the targets. Pick one and claim a part: how many you will craft, or a material you will gather.")

    -- detail
    local d = S.Panel(panel, T.field)
    d:SetPoint("TOPLEFT", 320, -12)
    d:SetPoint("BOTTOMRIGHT", -10, 10)
    panel.detail = d
    d.none = S.Text(d, 11, SOFT, "CENTER")
    d.none:SetPoint("CENTER")
    local body = CreateFrame("Frame", nil, d)
    body:SetAllPoints()
    d.body = body

    d.icon = body:CreateTexture(nil, "ARTWORK")
    d.icon:SetSize(32, 32)
    d.icon:SetPoint("TOPLEFT", 10, -10)
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local iconHit = CreateFrame("Frame", nil, body)
    iconHit:SetAllPoints(d.icon)
    iconHit:SetScript("OnEnter", function(s)
        local t = state.sel and GH.Prep.Get(state.sel)
        if t then ItemTip(s, t.it) end
    end)
    iconHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    d.name = S.Text(body, 14, T.text)
    d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 8, -1)
    d.name:SetPoint("RIGHT", body, "RIGHT", -118, 0)
    d.name:SetWordWrap(false)
    d.sub = S.Text(body, 11, SOFT)
    d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    d.sub:SetPoint("RIGHT", body, "RIGHT", -118, 0)
    d.sub:SetWordWrap(false)

    d.need = NumBox(body, 50, function(v) if state.sel then GH.Prep.SetCount(state.sel, v) end end)
    d.need:SetPoint("TOPRIGHT", -10, -9)
    d.needLabel = S.Text(body, 11, SOFT, "RIGHT")
    d.needLabel:SetPoint("RIGHT", d.need, "LEFT", -6, 0)
    d.needLabel:SetText("Needed")
    d.remove = S.Button(body, 64, 18, "Remove")
    d.remove:SetPoint("TOPRIGHT", -10, -33)
    -- two clicks: "Remove" then "Sure?" (resets after 3 seconds)
    d.remove:SetScript("OnClick", function(b)
        if not state.sel then return end
        if b.armed and b.tid == state.sel then
            b.armed = nil
            b:SetLabel("Remove")
            GH.Prep.Remove(state.sel)
            state.sel = nil
            UI.Paint()
        else
            b.armed, b.tid = true, state.sel
            b:SetLabel("|cffff4040Sure?|r")
            C_Timer.After(3, function()
                if b.armed then b.armed = nil; b:SetLabel("Remove") end
            end)
        end
    end)

    d.barBg = S.Tex(body, "ARTWORK", T.line)
    d.barBg:SetPoint("TOPLEFT", 10, -50)
    d.barBg:SetPoint("TOPRIGHT", -10, -50)
    d.barBg:SetHeight(8)
    d.barClaim = S.Tex(body, "ARTWORK", { T.accent[1], T.accent[2], T.accent[3], 0.3 }, 1)
    d.barClaim:SetPoint("TOPLEFT", d.barBg, "TOPLEFT")
    d.barClaim:SetHeight(8)
    d.barMade = S.Tex(body, "ARTWORK", T.accent, 2)
    d.barMade:SetPoint("TOPLEFT", d.barBg, "TOPLEFT")
    d.barMade:SetHeight(8)
    d.progress = S.Text(body, 11, T.text)
    d.progress:SetPoint("TOPLEFT", d.barBg, "BOTTOMLEFT", 0, -6)

    local pl = Label(body, "Parts")
    pl:SetPoint("TOPLEFT", 10, -86)
    d.partsMore = S.Text(body, 10, T.dim)
    d.partsMore:SetPoint("LEFT", pl, "RIGHT", 8, 0)
    d.handIn = S.Text(body, 11, SOFT, "RIGHT")
    d.handIn:SetPoint("TOPRIGHT", -10, -87)
    d.handIn:SetWidth(220)
    d.handIn:SetWordWrap(false)
    d.parts = {}
    for i = 1, PART_ROWS do
        local row = ListRow(body, PART_H)
        row:SetPoint("TOPLEFT", 4, -102 - (i - 1) * PART_H)
        row:SetPoint("TOPRIGHT", -4, -102 - (i - 1) * PART_H)
        row.kind = S.Text(row, 10, SOFT)
        row.kind:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.kind:SetWidth(40)
        row.right = S.Text(row, 11, T.text, "RIGHT")
        row.right:SetPoint("RIGHT", -6, 0)
        row.text = S.Text(row, 12, T.text)
        row.text:SetPoint("LEFT", row.kind, "RIGHT", 2, 0)
        row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(r)
            if not r.data then return end
            state.focus = r.data.item
            UI.Paint()
        end)
        row:SetScript("OnEnter", function(r)
            r.hl:Show()
            if r.data then ItemTip(r, r.data.item) end
        end)
        d.parts[i] = row
    end
    d.partsNote = S.Text(body, 11, SOFT)
    d.partsNote:SetPoint("TOPLEFT", 10, -128)
    d.partsNote:SetWidth(340)

    d.whoLabel = Label(body, "")
    d.whoLabel:SetPoint("TOPLEFT", 10, -264)
    d.whoLabel:SetPoint("RIGHT", body, "RIGHT", -70, 0)
    d.whoLabel:SetJustifyH("LEFT")
    d.whoLabel:SetWordWrap(false)
    d.whoMore = S.Text(body, 10, T.dim, "RIGHT")
    d.whoMore:SetPoint("TOPRIGHT", -10, -265)
    d.who = {}
    for i = 1, WHO_ROWS do
        local row = CreateFrame("Frame", nil, body)
        row:SetHeight(WHO_H)
        row:SetPoint("TOPLEFT", 10, -280 - (i - 1) * WHO_H)
        row:SetPoint("TOPRIGHT", -10, -280 - (i - 1) * WHO_H)
        row.right = S.Text(row, 11, T.text, "RIGHT")
        row.right:SetPoint("RIGHT")
        row.text = S.Text(row, 12, T.text)
        row.text:SetPoint("LEFT")
        row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.text:SetWordWrap(false)
        d.who[i] = row
    end
    d.whoNone = S.Text(body, 11, SOFT)
    d.whoNone:SetPoint("TOPLEFT", 10, -282)

    -- your part
    local line = S.Tex(body, "ARTWORK", T.line)
    line:SetPoint("BOTTOMLEFT", 10, 58)
    line:SetPoint("BOTTOMRIGHT", -10, 58)
    line:SetHeight(1)
    d.yourNote = S.Text(body, 11, SOFT)
    d.claimRest = S.Button(body, 80, 20, "Claim")
    d.claimRest:SetPoint("BOTTOMRIGHT", -10, 35)
    d.claimRest:SetScript("OnClick", function(s)
        if not state.sel or not state.focus or not s.to then return end
        d.claim:ClearFocus()
        GH.Prep.SetMine(state.sel, state.focus, s.to, nil)
        UI.Paint()
    end)
    d.claimRest:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Claim what is still open on this part", 1, 1, 1)
        GameTooltip:AddLine("Or type any amount in the Claim box and press Enter.", 0.84, 0.77, 0.62, true)
        GameTooltip:Show()
    end)
    d.claimRest:HookScript("OnLeave", function() GameTooltip:Hide() end)
    d.yourNote:SetPoint("BOTTOMLEFT", 10, 38)
    d.yourNote:SetPoint("RIGHT", d.claimRest, "LEFT", -8, 0)
    d.yourNote:SetWordWrap(false)
    local cl = Label(body, "Claim")
    cl:SetPoint("BOTTOMLEFT", 10, 15)
    d.claim = NumBox(body, 38, function(v)
        if state.sel and state.focus then GH.Prep.SetMine(state.sel, state.focus, v, nil) end
    end)
    d.claim:SetPoint("LEFT", cl, "RIGHT", 5, 0)
    d.madeLabel = S.Text(body, 11, T.text)
    d.madeLabel:SetPoint("LEFT", d.claim, "RIGHT", 8, 0)
    d.madeLabel:SetText("Made")
    d.made = NumBox(body, 38, function(v)
        if state.sel and state.focus then GH.Prep.SetMine(state.sel, state.focus, nil, nil, v) end
    end)
    d.made:SetPoint("LEFT", d.madeLabel, "RIGHT", 5, 0)
    d.made:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Made so far", 1, 1, 1)
        GameTooltip:AddLine("Crafting this item counts here by itself, up to your claim. Gatherers type what they have gathered.", 0.84, 0.77, 0.62, true)
        GameTooltip:Show()
    end)
    d.made:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local dl = S.Text(body, 11, T.text)
    dl:SetPoint("LEFT", d.made, "RIGHT", 8, 0)
    dl:SetText("Handed in")
    d.deliv = NumBox(body, 38, function(v)
        if state.sel and state.focus then GH.Prep.SetMine(state.sel, state.focus, nil, v) end
    end)
    d.deliv:SetPoint("LEFT", dl, "RIGHT", 5, 0)
    d.allDone = S.Button(body, 56, 20, "All in")
    d.allDone:SetPoint("BOTTOMRIGHT", -10, 11)
    d.allDone:SetScript("OnClick", function()
        if not state.sel or not state.focus then return end
        local mine = GH.Prep.MyClaim(state.sel, state.focus)
        local all = mine and math.max(mine.a or 0, mine.m or 0) or 0
        if all > (mine and mine.d or 0) then GH.Prep.SetMine(state.sel, state.focus, nil, all) end
        UI.Paint()
    end)
    d.allDone:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Mark everything you claimed as handed in", 1, 1, 1)
        GameTooltip:AddLine("Only updates the numbers: send or deposit the items yourself.", 0.84, 0.77, 0.62, true)
        GameTooltip:Show()
    end)
    d.allDone:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return panel
end
