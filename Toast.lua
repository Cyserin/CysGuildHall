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
    if frame.text.SetMaxLines then frame.text:SetMaxLines(2) end

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
        if button == "LeftButton" and f.pid and GH.Window and GH.Window.OpenProfession then
            GH.Window.OpenProfession(f.pid)
        end
        f.t = IN + HOLD   -- start fading out
    end)
    frame:SetScript("OnEnter", function(f) f.hover = true end)
    frame:SetScript("OnLeave", function(f) f.hover = nil end)
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
    frame.t = 0
    frame:SetAlpha(0)
    frame:Show()
end

function Toast.Add(text, icon, pid)
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
    queue[#queue + 1] = { text = text, icon = icon, pid = pid }
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
