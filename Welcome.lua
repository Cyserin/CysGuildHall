--------------------------------------------------------------------------------
-- Cys's Guild Hall - first run welcome
-- Shows once per character: what the addon does, an Initialize button (loads the
-- guild roster and says hello to guildmates running the addon), then a checklist
-- of this character's crafting professions to open once. When every one is read,
-- a full sync runs and the window says you are all set.
--------------------------------------------------------------------------------
local GH = CysGuildHall
local S = GH.Style
local Wel = {}
GH.Welcome = Wel

local SOFT = { 0.84, 0.77, 0.62, 1 }
local WIDTH = 400
local frame, rows = nil, {}
local shownThisSession = false

-- db.init[full]: nil = never started, 1 = initialized (professions pending), 2 = done
local function State() return GH.db.init[GH.Me()] end
local function SetState(v) GH.db.init[GH.Me()] = v end

-- This character's crafting professions: list of { pid, name, read }
local function Crafts()
    local list = {}
    local set = GH.Prof and GH.Prof.Learned and GH.Prof.Learned()
    if not set then return list, false end
    local g = GH.Guild()
    local me = g and g.members[GH.Me()]
    for _, pid in ipairs(GH.Prof.CRAFTS or {}) do
        if set[pid] then
            local read = me and me.profs and me.profs[pid] and true or false
            list[#list + 1] = { pid = pid, name = GH.ProfName(pid), read = read }
        end
    end
    return list, true
end

local function Pending()
    local n = 0
    for _, c in ipairs((Crafts())) do if not c.read then n = n + 1 end end
    return n
end

local function GuildmatesWithData()
    local g = GH.Guild()
    local n = 0
    if g then
        local me = GH.Me()
        for name, m in pairs(g.members) do
            if name ~= me and m.profs and next(m.profs) then n = n + 1 end
        end
    end
    return n
end

local function Initialize()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    if GH.Comm then GH.Comm.Hello(true) end
    SetState(1)
    GH.Print("initialized: said hello to the guild and asked for their crafting data.")
end

local function FinalSync()
    if GH.Comm then GH.Comm.Hello(true) end
    SetState(2)
    GH.Print("all your professions are read and shared with the guild. You're all set!")
end

--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------
local Paint

local function Row(i)
    if rows[i] then return rows[i] end
    local T = S.T()
    local r = CreateFrame("Frame", nil, frame.body)
    r:SetSize(WIDTH - 60, 20)
    r.box = CreateFrame("Frame", nil, r)
    r.box:SetSize(14, 14)
    r.box:SetPoint("LEFT")
    S.Tex(r.box, "BACKGROUND", T.field):SetAllPoints()
    r.edges = S.Border(r.box, T.border)
    r.tick = r.box:CreateTexture(nil, "OVERLAY")
    r.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    r.tick:SetPoint("CENTER")
    r.tick:SetSize(16, 16)
    r.name = S.Text(r, 12, T.text)
    r.name:SetPoint("LEFT", r.box, "RIGHT", 8, 0)
    r.state = S.Text(r, 11, SOFT, "RIGHT")
    r.state:SetPoint("RIGHT")
    rows[i] = r
    return r
end

local function Build()
    local T = S.T()
    frame = CreateFrame("Frame", "CysGuildHallWelcome", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetPoint("CENTER", 0, 80)
    S.Tex(frame, "BACKGROUND", T.bg):SetAllPoints()
    S.Border(frame, T.border)

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(30)
    S.Tex(header, "BACKGROUND", T.header):SetAllPoints()
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 9, 0)
    local title = S.Text(header, 14, T.brand)
    title:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    title:SetText("Welcome to Cys's Guild Hall")
    local close = S.Button(header, 22, 22, "x")
    close:SetPoint("RIGHT", -4, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", 20, -46)
    frame.body:SetPoint("TOPRIGHT", -20, -46)
    frame.body:SetHeight(10)

    frame.step = S.Text(frame.body, 11, T.brand)
    frame.step:SetPoint("TOPLEFT")
    frame.text = S.Text(frame.body, 12, T.text)
    frame.text:SetWidth(WIDTH - 40)
    frame.text:SetSpacing(3)
    frame.note = S.Text(frame.body, 11, SOFT)
    frame.note:SetWidth(WIDTH - 40)
    frame.note:SetSpacing(2)

    frame.main = S.Button(frame, 150, 26, "Initialize")
    frame.main:SetPoint("BOTTOMRIGHT", -20, 16)
    frame.later = S.Button(frame, 90, 26, "Later")
    frame.later:SetPoint("RIGHT", frame.main, "LEFT", -8, 0)
    frame.later:SetScript("OnClick", function() frame:Hide() end)
    frame.skip = CreateFrame("Button", nil, frame)
    frame.skip:SetSize(150, 18)
    frame.skip:SetPoint("BOTTOMLEFT", 20, 20)
    frame.skip.label = S.Text(frame.skip, 11, SOFT)
    frame.skip.label:SetPoint("LEFT")
    frame.skip.label:SetText("Don't remind me")
    frame.skip:SetScript("OnEnter", function(b) b.label:SetTextColor(1, 0.82, 0) end)
    frame.skip:SetScript("OnLeave", function(b) b.label:SetTextColor(SOFT[1], SOFT[2], SOFT[3]) end)
    frame.skip:SetScript("OnClick", function()
        SetState(2)
        frame:Hide()
        GH.Print("welcome closed. Type /guildhall welcome to see it again.")
    end)

    frame:SetScript("OnShow", function() Paint() end)
    frame:Hide()
end

function Paint()
    if not frame then return end
    local T = S.T()
    local state = State()
    local list, readable = Crafts()
    for _, r in ipairs(rows) do r:Hide() end
    frame.main:SetActive(true)
    frame.skip:Hide()
    frame.later:Show()

    local y = 0
    local function Place(fs, gap)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, -(y + (gap or 0)))
        y = y + (gap or 0) + fs:GetStringHeight()
    end

    if not state then
        frame.step:SetText("STEP 1 OF 2")
        frame.text:SetText("Every guildmate who runs this addon shares the recipes they know. "
            .. "Search any item and see who in the guild can make it, what it takes, and send them a craft request.\n\n"
            .. "Click |cffffd100Initialize|r to load the guild roster and say hello to guildmates who already run the addon. "
            .. "Their crafting data starts coming in right away.")
        if IsInGuild() then
            frame.note:SetText("Next you'll open each of your professions once so your recipes can be shared too.")
            frame.main:SetLabel("Initialize")
        else
            frame.note:SetText("|cffff6060You're not in a guild yet.|r Join one and this will be ready to go.")
            frame.main:SetLabel("Initialize")
            frame.main:SetActive(false)
        end
        frame.main:SetScript("OnClick", function() Initialize(); Paint() end)
        Place(frame.step)
        Place(frame.text, 8)
        Place(frame.note, 12)
    else
        local pending = 0
        for _, c in ipairs(list) do if not c.read then pending = pending + 1 end end
        if #list == 0 then
            frame.step:SetText("ALL SET")
            frame.text:SetText(readable
                and "This character has no crafting professions, so there is nothing to share. "
                    .. "You can still search the whole guild and send craft requests."
                or "Open each of your profession windows once so your recipes can be shared with the guild.")
        elseif pending > 0 then
            frame.step:SetText("STEP 2 OF 2")
            frame.text:SetText("Now open each of your professions once (from your spellbook or the profession button). "
                .. "The addon reads your recipes and shares them with the guild by itself.")
        else
            frame.step:SetText("ALL SET")
            frame.text:SetText("Your recipes are shared and the guild has been asked for theirs. "
                .. "Open the Guild Hall any time with the minimap button or |cffffd100/guildhall|r.")
        end
        Place(frame.step)
        Place(frame.text, 8)
        y = y + 8
        for i, c in ipairs(list) do
            local r = Row(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 10, -y)
            r.name:SetText(c.name or ("Profession " .. c.pid))
            r.tick:SetShown(c.read)
            r.state:SetText(c.read and "|cff4fd66bread and shared|r" or "open it once")
            r:Show()
            y = y + 22
        end
        local others = GuildmatesWithData()
        frame.note:SetText(others > 0
            and ("Crafting data received so far from %d %s."):format(others, others == 1 and "guildmate" or "guildmates")
            or "No guildmates' data yet: it arrives as soon as someone else running the addon is online.")
        Place(frame.note, 10)

        if pending > 0 then
            frame.main:SetLabel("Open Guild Hall")
            frame.skip:Show()
        else
            if state ~= 2 then FinalSync() end
            frame.main:SetLabel("Open Guild Hall")
            frame.later:Hide()
        end
        frame.main:SetScript("OnClick", function()
            frame:Hide()
            if GH.Window then GH.Window.Open(nil, "craft") end
        end)
    end
    frame.body:SetHeight(math.max(10, y))
    frame:SetHeight(46 + y + 66)
end

function Wel.Show()
    if InCombatLockdown() then return end
    if not frame then Build() end
    frame:Show()
    Paint()
end

-- Live updates while the window is open (professions read, guild data arriving)
local paintTimer
local function PaintSoon()
    if not frame or not frame:IsShown() or paintTimer then return end
    paintTimer = C_Timer.NewTimer(0.3, function() paintTimer = nil; Paint() end)
end
GH.Listen("DATA", PaintSoon)
GH.On("SKILL_LINES_CHANGED", PaintSoon)

-- A profession read after Initialize while the window is closed still finishes the
-- setup (one full sync once every crafting profession is read).
GH.Listen("DATA", function(who)
    if who ~= GH.Me() or State() ~= 1 then return end
    C_Timer.After(1, function()
        if State() == 1 and #(Crafts()) > 0 and Pending() == 0 then
            FinalSync()
            if frame and frame:IsShown() then Paint() end
        end
    end)
end)

-- First login per character: show it once things have settled, out of combat
local function MaybeShow()
    if shownThisSession or State() == 2 then return end
    if not IsInGuild() then return end
    -- already set up before this window existed (professions read and shared): never shown
    if not State() and #(Crafts()) > 0 and Pending() == 0 then SetState(2); return end
    if State() == 1 and Pending() == 0 then
        local list = Crafts()
        if #list > 0 then FinalSync() end
        SetState(2)
        return
    end
    if InCombatLockdown() then
        local w = CreateFrame("Frame")
        w:RegisterEvent("PLAYER_REGEN_ENABLED")
        w:SetScript("OnEvent", function(f) f:UnregisterAllEvents(); C_Timer.After(2, MaybeShow) end)
        return
    end
    shownThisSession = true
    Wel.Show()
end

GH.On("PLAYER_LOGIN", function() C_Timer.After(6, MaybeShow) end)
