--------------------------------------------------------------------------------
-- Cys's Guild Hall - minimap button + profession window button
-- Standalone: no libraries, works with round and square minimaps.
--------------------------------------------------------------------------------
local GH = CysGuildHall

local ICON = "Interface\\Icons\\Trade_BlackSmithing"

local function Tooltip(owner, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
    GameTooltip:AddLine("Cys's Guild Hall", 0.85, 0.64, 0.13)
    local n = GH.Requests and GH.Requests.ForMe() or 0
    if n > 0 then
        GameTooltip:AddLine(("%d craft %s waiting on you"):format(n, n == 1 and "request" or "requests"), 1, 0.82, 0)
    end
    GameTooltip:AddLine("Left-click: open", 0.84, 0.77, 0.62)
    GameTooltip:AddLine("Right-click: requests", 0.84, 0.77, 0.62)
    if owner.isMinimap then GameTooltip:AddLine("Drag: move around the minimap", 0.84, 0.77, 0.62) end
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------
local mm

local function Place()
    if not mm then return end
    local angle = math.rad(GH.db.settings.minimapAngle or 215)
    local x, y = math.cos(angle), math.sin(angle)
    local w = (Minimap:GetWidth() / 2) + 6
    local h = (Minimap:GetHeight() / 2) + 6
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        -- push the point out to the square's edge
        local m = math.max(math.abs(x), math.abs(y))
        x, y = x / m, y / m
    end
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end

local function Build()
    mm = CreateFrame("Button", "CysGuildHallMinimapButton", Minimap)
    mm.isMinimap = true
    mm:SetSize(31, 31)
    mm:SetFrameStrata("MEDIUM")
    mm:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mm:RegisterForDrag("LeftButton")

    local bg = mm:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    -- full square icon inside the ring (no round mask: that squashed it)
    local icon = mm:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19)
    icon:SetPoint("TOPLEFT", 6, -6)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mm.icon = icon
    local ring = mm:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetVertexColor(1, 0.85, 0.45)   -- warm gold ring
    mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- waiting-requests dot
    mm.badge = mm:CreateFontString(nil, "OVERLAY")
    mm.badge:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    mm.badge:SetPoint("BOTTOMRIGHT", 2, -1)
    mm.badge:SetTextColor(1, 0.82, 0)

    mm:SetScript("OnClick", function(_, button)
        GameTooltip:Hide()
        if button == "RightButton" then GH.Window.Open(nil, "requests") else GH.Window.Toggle() end
    end)
    mm:SetScript("OnEnter", function(b) Tooltip(b) end)
    mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mm:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 7, -7) end)
    mm:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 6, -6) end)
    mm:SetScript("OnDragStart", function(b)
        GameTooltip:Hide()
        b:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / scale, cy / scale
            GH.db.settings.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
            Place()
        end)
    end)
    mm:SetScript("OnDragStop", function(b)
        b:SetScript("OnUpdate", nil)
        icon:SetPoint("TOPLEFT", 6, -6)
    end)
    Place()
end

function GH.UpdateMinimapButton()
    if not GH.db then return end
    if GH.db.settings.minimapHide then
        if mm then mm:Hide() end
        return
    end
    if not mm then Build() end
    mm:Show()
    local n = GH.Requests and GH.Requests.ForMe() or 0
    mm.badge:SetText(n > 0 and tostring(n) or "")
end

GH.On("PLAYER_LOGIN", function() GH.UpdateMinimapButton() end)
GH.Listen("REQUESTS", function() if mm then GH.UpdateMinimapButton() end end)
GH.Listen("DATA", function() if mm then GH.UpdateMinimapButton() end end)

--------------------------------------------------------------------------------
-- Button on the profession window: opens the Guild Hall on that profession
--------------------------------------------------------------------------------
local profBtn

local function BuildProfButton()
    if profBtn or not ProfessionsFrame then return end
    profBtn = CreateFrame("Button", "CysGuildHallProfessionButton", ProfessionsFrame)
    profBtn:SetSize(36, 36)
    profBtn:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 6, -60)
    local bg = profBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.05, 0.04, 0.95)
    local icon = profBtn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    GH.Style.Border(profBtn, GH.Style.T().border)
    profBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    profBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    profBtn:SetScript("OnClick", function(_, button)
        GameTooltip:Hide()
        if button == "RightButton" then
            GH.Window.Open(nil, "requests")
            return
        end
        local pid
        local T = C_TradeSkillUI
        local base = T and T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
        if base and base.professionID and base.professionID > 0 then pid = base.professionID end
        GH.Window.OpenProfession(pid)
    end)
    profBtn:SetScript("OnEnter", function(b) Tooltip(b, "ANCHOR_RIGHT") end)
    profBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- sit at the end of the game's own side-tab column (its tab count changes per character)
    local function Dock()
        local last
        local tabs = ProfessionsFrame.rightProfessionTabs
        if type(tabs) == "table" then
            for _, t in ipairs(tabs) do
                if t.IsShown and t:IsShown() then last = t end
            end
        end
        last = last or ProfessionsFrame.ProfessionsOverviewTab
        profBtn:ClearAllPoints()
        if last then
            profBtn:SetPoint("TOP", last, "BOTTOM", 0, -6)
        else
            profBtn:SetPoint("TOPLEFT", ProfessionsFrame, "TOPRIGHT", 6, -60)
        end
    end
    ProfessionsFrame:HookScript("OnShow", function() C_Timer.After(0, Dock) end)
    Dock()
end

GH.On("ADDON_LOADED", function(name)
    if name == "Blizzard_Professions" then BuildProfButton() end
end)
GH.On("PLAYER_LOGIN", function()
    if ProfessionsFrame then BuildProfButton() end
end)
