--------------------------------------------------------------------------------
-- Cys's Guild Hall - Calendar tab
-- Left: the guild's events for the next 30 days (from the game's own calendar),
-- officers add new ones at the bottom. Right: the picked event, your answer
-- (sign up / tentative / remove, or accept / tentative / decline) and who is coming.
-- Everything goes through C_Calendar, so players without the addon see the same
-- events in the game's calendar. Event creators / moderators can edit or delete from
-- here; Raid Prep targets due that day show on the event; a pop-up reminds you 15
-- minutes before an event you said yes / maybe to.
--------------------------------------------------------------------------------
local GH = CysGuildHall
local S = GH.Style
local UI = {}
GH.CalPanel = UI

local SOFT = { 0.84, 0.77, 0.62, 1 }
local LIST_ROWS, LIST_H = 8, 32
local WHO_ROWS, WHO_H = 10, 18
local DAYS_AHEAD = 30

local panel
local state = { sel = nil, offset = 0, whoOff = 0, events = {}, opened = nil, info = nil, invites = nil, locked = false,
    form = { kind = "s", type = 0, day = 0, hour = 7, min = 0, ampm = "PM" } }

local WD = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local MON = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local TYPES = { [0] = "Raid", "Dungeon", "PvP", "Meeting", "Other" }
local ICONS = { [0] = 236454, 237021, 236396, 133734, 134400 }

-- CalendarStatus: name, color, bucket (1 going, 2 tentative, 3 standby, 4 not going, 5 no answer)
local STATUS = {
    [0] = { "Invited", "d6c49e", 5 }, [1] = { "Accepted", "4fd66b", 1 }, [2] = { "Declined", "ff6060", 4 },
    [3] = { "Confirmed", "4fd66b", 1 }, [4] = { "Out", "ff6060", 4 }, [5] = { "Standby", "ffd100", 3 },
    [6] = { "Signed up", "4fd66b", 1 }, [7] = { "Not signed up", "d6c49e", 5 }, [8] = { "Tentative", "ffd100", 2 },
}
local BUCKETS = { "going", "tentative", "standby", "not going", "no answer" }

local SIGNUP = Enum and Enum.CalendarInviteType and Enum.CalendarInviteType.Signup or 1

-- Roles: picked per event by each player, shared with guildmates who run the addon
-- (E~event~role; F~event asks everyone to resend theirs). Saved per guild in calRoles.
local ROLE_TEX = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE = {
    T = { "Tank", { 0, 19 / 64, 22 / 64, 41 / 64 }, 1 },
    H = { "Healer", { 20 / 64, 39 / 64, 1 / 64, 20 / 64 }, 2 },
    D = { "DPS", { 20 / 64, 39 / 64, 22 / 64, 41 / 64 }, 3 },
}
local CLASS_TEX = "Interface\\TargetingFrame\\UI-Classes-Circles"

local function SetRoleIcon(tex, role)
    local r = role and ROLE[role]
    if r then
        tex:SetTexture(ROLE_TEX)
        tex:SetTexCoord(unpack(r[2]))
        tex:Show()
    else
        tex:Hide()
    end
end

local function SetClassIcon(tex, class)
    local c = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if c then
        tex:SetTexture(CLASS_TEX)
        tex:SetTexCoord(unpack(c))
        tex:Show()
    else
        tex:Hide()
    end
end

local function Roles(key, make)
    local g = GH.Guild()
    if not g or not key then return nil end
    g.calRoles = g.calRoles or {}
    local r = g.calRoles[key]
    if not r and make then r = {}; g.calRoles[key] = r end
    return r
end

local function RoleOf(key, name)
    local r = Roles(key)
    local e = r and name and r[name]
    return e and e.r
end

local function SetRole(key, name, role)
    local r = Roles(key, role and true)
    if not r or not name then return end
    r[name] = role and { r = role, t = time() } or nil
end

local function SendRole(key)
    if not GH.Comm or not GH.Comm.Push then return end
    GH.Comm.Push("E~" .. key .. "~" .. (RoleOf(key, GH.Me()) or ""))
end

local function SetMyRole(key, role)
    SetRole(key, GH.Me(), role)
    if role then
        GH.db.calLastRole = GH.db.calLastRole or {}
        GH.db.calLastRole[GH.Me()] = role
    end
    SendRole(key)
end

-- answering an event: use the role you picked last time when none is set for it yet
local function AutoRole(key)
    if RoleOf(key, GH.Me()) then return end
    local last = GH.db.calLastRole and GH.db.calLastRole[GH.Me()]
    if last then SetMyRole(key, last) end
end

local asked, answering = {}, {}
local function AskRoles(key)
    if asked[key] or not GH.Comm or not GH.Comm.Push then return end
    asked[key] = true
    GH.Comm.Push("F~" .. key)
end

local pruned
local function Prune()
    local g = GH.Guild()
    if pruned or not g or not g.calRoles then return end
    pruned = true
    local old = time() - 40 * 86400
    for k, r in pairs(g.calRoles) do
        for n, e in pairs(r) do
            if (e.t or 0) < old then r[n] = nil end
        end
        if not next(r) then g.calRoles[k] = nil end
    end
end

local Paint

local function Label(parent, text)
    local fs = S.Text(parent, 11, S.T().accent)
    fs:SetText(text or "")
    return fs
end

local function StatusText(st)
    local s = STATUS[st]
    if not s then return "" end
    return "|cff" .. s[2] .. s[1] .. "|r"
end

local function H12(h, m)
    local hh = h % 12
    if hh == 0 then hh = 12 end
    return ("%d:%02d %s"):format(hh, m or 0, h >= 12 and "PM" or "AM")
end

local function Key(y, m, d) return y * 10000 + m * 100 + d end

local function Noon(t) return time({ year = t.year, month = t.month, day = t.monthDay or t.day, hour = 12 }) end

-- n days after the calendar time t: year, month, day, wday
local function DayAfter(t, n)
    local d = date("*t", Noon(t) + n * 86400)
    return d.year, d.month, d.day, d.wday
end

local function DayLabel(y, m, d, wday)
    local now = C_DateAndTime.GetCurrentCalendarTime()
    local k = Key(y, m, d)
    if k == Key(now.year, now.month, now.monthDay) then return "Today" end
    local ty, tm, td = DayAfter(now, 1)
    if k == Key(ty, tm, td) then return "Tomorrow" end
    wday = wday or date("*t", time({ year = y, month = m, day = d, hour = 12 })).wday
    return ("%s %s %d"):format(WD[wday] or "", MON[m] or "", d)
end

local function WhenText(t)
    return DayLabel(t.year, t.month, t.monthDay, t.weekday) .. ", " .. H12(t.hour, t.minute)
end

local function Who(name)
    if not name or name == "" then return "?" end
    return GH.Short(GH.Canon(name) or name)
end

local function Msg(text, err)
    if not panel then return end
    panel.msg:SetText(text or "")
    local c = err and { 1, 0.38, 0.38 } or SOFT
    panel.msg:SetTextColor(c[1], c[2], c[3])
end

--------------------------------------------------------------------------------
-- Reading the game's calendar
--------------------------------------------------------------------------------
local function Scan()
    local now = C_DateAndTime.GetCurrentCalendarTime()
    local cur = C_Calendar.GetMonthInfo(0)
    if cur.month ~= now.month or cur.year ~= now.year then C_Calendar.SetAbsMonth(now.month, now.year) end
    local nowK = Key(now.year, now.month, now.monthDay) * 10000 + now.hour * 100 + now.minute
    local ey, em, ed = DayAfter(now, DAYS_AHEAD)
    local endK = Key(ey, em, ed)
    local out = {}
    for off = 0, 1 do
        local mi = C_Calendar.GetMonthInfo(off)
        for day = (off == 0 and now.monthDay or 1), mi.numDays do
            for i = 1, C_Calendar.GetNumDayEvents(off, day) do
                local e = C_Calendar.GetDayEvent(off, day, i)
                local ct = e and e.calendarType
                if (ct == "GUILD_EVENT" or ct == "GUILD_ANNOUNCEMENT") and e.sequenceType ~= "END" and e.sequenceType ~= "ONGOING" then
                    local st = e.startTime
                    local dk = Key(st.year, st.month, st.monthDay)
                    local k = dk * 10000 + st.hour * 100 + st.minute
                    -- keep events that started under an hour ago
                    if k >= nowK - 100 and dk <= endK then
                        out[#out + 1] = {
                            key = (tostring(e.eventID or ((e.title or "") .. k)):gsub("~", ""):sub(1, 40)), off = off, day = day, idx = i, k = k,
                            title = e.title or "?", t = st, type = e.eventType, ct = ct, it = e.inviteType,
                            st = e.inviteStatus, by = e.invitedBy, icon = e.iconTexture, mod = e.modStatus,
                            past = k < nowK,
                        }
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.k ~= b.k then return a.k < b.k end
        if a.title ~= b.title then return a.title < b.title end
        return a.key < b.key
    end)
    return out
end

local function Rescan()
    local ok, list = pcall(Scan)
    state.locked = not ok
    if ok then state.events = list end
end

local function Selected()
    for _, e in ipairs(state.events) do if e.key == state.sel then return e end end
end

-- the game keeps one "open" event; actions act on it
local function OpenSel()
    local e = Selected()
    if not e then return end
    state.info, state.invites, state.whoOff = nil, nil, 0
    state.opened, state.tried = nil, e.key
    local ok, res = pcall(C_Calendar.OpenEvent, e.off, e.day, e.idx)
    if ok and res ~= false then state.opened = e.key end
end

local function ReadOpen()
    if not state.opened or not C_Calendar.IsEventOpen() then return end
    local ok = pcall(function()
        local info = C_Calendar.GetEventInfo()
        local e = Selected()
        -- another addon / the game's calendar opened a different event
        if not info or (e and info.title ~= e.title) then state.opened = nil; return end
        state.info = info
        local list = {}
        for i = 1, C_Calendar.GetNumInvites() do
            local inv = C_Calendar.EventGetInvite(i)
            if inv and inv.name then
                local s = STATUS[inv.inviteStatus]
                local full = GH.Canon(inv.name) or inv.name
                local role = e and RoleOf(e.key, full)
                list[#list + 1] = { name = inv.name, lvl = inv.level, class = inv.classFilename, st = inv.inviteStatus,
                    b = s and s[3] or 5, mine = inv.inviteIsMine, role = role, ro = role and ROLE[role][3] or 4 }
            end
        end
        table.sort(list, function(a, b)
            if a.b ~= b.b then return a.b < b.b end
            if a.ro ~= b.ro then return a.ro < b.ro end
            return a.name < b.name
        end)
        state.invites = list
        if e then AskRoles(e.key) end
    end)
    if not ok then state.locked = true end
end

--------------------------------------------------------------------------------
-- Your answer
--------------------------------------------------------------------------------
local function Act(fn)
    local e = Selected()
    if not e or state.opened ~= e.key or not C_Calendar.IsEventOpen() then
        OpenSel()
        Msg("Loading the event, press again in a moment.")
        return
    end
    if C_Calendar.IsActionPending() then return end
    local ok, err = pcall(fn)
    if not ok then Msg("The game would not take that: " .. tostring(err), true) else Msg("") end
end

local function Buttons(e)
    local d = panel.detail
    for _, b in ipairs(d.acts) do b:Hide() end
    if not e or e.ct == "GUILD_ANNOUNCEMENT" or e.past then return end
    local st = e.st
    local set = {}
    if e.it == SIGNUP then
        if st == 7 or st == nil then
            set = { { "Sign up", C_Calendar.EventSignUp }, { "Tentative", C_Calendar.EventTentative } }
        elseif e.mod ~= "CREATOR" then
            set = { { "Remove me", C_Calendar.RemoveEvent } }
        end
    elseif st == 0 or st == 1 or st == 2 or st == 8 then
        if st ~= 1 then set[#set + 1] = { "Accept", C_Calendar.EventAvailable } end
        if st ~= 8 then set[#set + 1] = { "Tentative", C_Calendar.EventTentative } end
        if st ~= 2 then set[#set + 1] = { "Decline", C_Calendar.EventDecline } end
    end
    local prev
    for i = #set, 1, -1 do
        local b = d.acts[i]
        local label, fn = set[i][1], set[i][2]
        b:SetLabel(label)
        local yes = label == "Sign up" or label == "Tentative" or label == "Accept"
        b:SetScript("OnClick", function()
            Act(fn)
            if yes then AutoRole(e.key) end
        end)
        b:ClearAllPoints()
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -4, 0) else b:SetPoint("TOPRIGHT", d.body, "TOPRIGHT", -10, d.actY) end
        b:Show()
        prev = b
    end
end

--------------------------------------------------------------------------------
-- New event (officers)
--------------------------------------------------------------------------------
local function DayItems()
    local now = C_DateAndTime.GetCurrentCalendarTime()
    local items = {}
    for i = 0, math.max(13, state.form.day or 0) do
        local y, m, d, wd = DayAfter(now, i)
        items[#items + 1] = { i, DayLabel(y, m, d, wd) }
    end
    return items
end

local ExitEdit

local function Save()
    local f = state.form
    local e
    for _, x in ipairs(state.events) do if x.key == state.edit then e = x end end
    if not e then ExitEdit(); Msg("That event is gone from the calendar.", true); return end
    local title = (panel.titleBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if title == "" then Msg("Give the event a title.", true); return end
    if state.opened ~= e.key or not C_Calendar.IsEventOpen() then
        state.sel = e.key
        OpenSel()
        Msg("Loading the event, press Save again in a moment.")
        return
    end
    local now = C_DateAndTime.GetCurrentCalendarTime()
    local y, m, d = DayAfter(now, f.day)
    local h = (f.hour % 12) + (f.ampm == "PM" and 12 or 0)
    if f.day == 0 and h * 60 + f.min <= now.hour * 60 + now.minute then
        Msg("That time has already passed today.", true)
        return
    end
    local ok, err = pcall(function()
        C_Calendar.EventSetType(f.type)
        C_Calendar.EventSetTitle(title)
        C_Calendar.EventSetDescription(panel.descBox:GetText() or "")
        C_Calendar.EventSetDate(m, d, y)
        C_Calendar.EventSetTime(h, f.min)
        if C_Calendar.EventHaveSettingsChanged() then C_Calendar.UpdateEvent() end
    end)
    if not ok then Msg("The game would not take it: " .. tostring(err), true); return end
    ExitEdit()
    Msg("Saved " .. title .. ".")
end

local function Create()
    if state.edit then return Save() end
    local f = state.form
    local title = (panel.titleBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if title == "" then Msg("Give the event a title.", true); return end
    local now = C_DateAndTime.GetCurrentCalendarTime()
    local y, m, d = DayAfter(now, f.day)
    local h = (f.hour % 12) + (f.ampm == "PM" and 12 or 0)
    if f.day == 0 and h * 60 + f.min <= now.hour * 60 + now.minute then
        Msg("That time has already passed today.", true)
        return
    end
    local ok, err = pcall(function()
        if C_Calendar.IsEventOpen() then C_Calendar.CloseEvent() end
        state.opened = nil
        if f.kind == "a" then C_Calendar.CreateGuildAnnouncementEvent() else C_Calendar.CreateGuildSignUpEvent() end
        C_Calendar.EventSetType(f.type)
        C_Calendar.EventSetTitle(title)
        C_Calendar.EventSetDescription(panel.descBox:GetText() or "")
        C_Calendar.EventSetDate(m, d, y)
        C_Calendar.EventSetTime(h, f.min)
        if not C_Calendar.CanAddEvent() then
            C_Calendar.CloseEvent()
            error("not allowed", 0)
        end
        C_Calendar.AddEvent()
    end)
    if not ok then
        Msg(err == "not allowed" and "The game won't add it: check your guild rank can create events." or ("The game would not take it: " .. tostring(err)), true)
        return
    end
    panel.titleBox:SetText("")
    panel.descBox:SetText("")
    Msg("Added " .. title .. ". It shows up in a moment.")
end

--------------------------------------------------------------------------------
-- Paint
--------------------------------------------------------------------------------
local function PaintList()
    local list = state.events
    local maxOff = math.max(0, #list - LIST_ROWS)
    if state.offset > maxOff then state.offset = maxOff end
    for i = 1, LIST_ROWS do
        local row = panel.rows[i]
        local e = list[state.offset + i]
        row.data = e
        if e then
            row:Show()
            row.icon:SetTexture(e.icon or ICONS[e.type] or 134400)
            row.text:SetText(e.title)
            row.when:SetText(WhenText(e.t) .. "  |cff8a8a8a" .. (e.ct == "GUILD_ANNOUNCEMENT" and "Announcement" or (TYPES[e.type] or "")) .. "|r")
            row.right:SetText(e.ct == "GUILD_ANNOUNCEMENT" and "" or StatusText(e.st))
            row.sel:SetShown(e.key == state.sel)
        else
            row:Hide()
        end
    end
    local empty
    if state.locked then
        empty = "The calendar can't be read right now.\nIt refreshes after combat."
    elseif #list == 0 then
        empty = "No guild events in the next 30 days."
    end
    panel.empty:SetText(empty or "")
    panel.more:SetText(#list > LIST_ROWS and ("%d events - scroll for more"):format(#list) or "")
end

local function PaintWho()
    local d = panel.detail
    local list = state.invites
    if not list then
        d.whoHead:SetText("Who is coming")
        d.whoNote:SetText(state.opened and "Loading..." or "")
        for i = 1, WHO_ROWS do d.who[i]:Hide() end
        return
    end
    local n = { 0, 0, 0, 0, 0 }
    local roles, classes, order = { T = 0, H = 0, D = 0, ["?"] = 0 }, {}, {}
    local roleWho, classWho = { T = {}, H = {}, D = {}, ["?"] = {} }, {}
    for _, p in ipairs(list) do
        n[p.b] = n[p.b] + 1
        if p.b == 1 then
            local r = p.role or "?"
            roles[r] = roles[r] + 1
            table.insert(roleWho[r], p)
            if p.class then
                if not classes[p.class] then classes[p.class] = 0; order[#order + 1] = p.class; classWho[p.class] = {} end
                classes[p.class] = classes[p.class] + 1
                table.insert(classWho[p.class], p)
            end
        end
    end
    table.sort(order, function(a, b)
        if classes[a] ~= classes[b] then return classes[a] > classes[b] end
        return a < b
    end)
    -- makeup strip: going only
    local mk = d.mk
    local x = 0
    for i, r in ipairs({ "T", "H", "D", "?" }) do
        local s = mk.roles[i]
        if roles[r] > 0 then
            if r == "?" then s.icon:Hide() else SetRoleIcon(s.icon, r) end
            s.text:SetText((r == "?" and "|cff8a8a8a? |r" or "") .. roles[r])
            s.title = r == "?" and "No role picked" or ROLE[r][1]
            s.who = roleWho[r]
            s:ClearAllPoints()
            s:SetPoint("LEFT", mk, "LEFT", x, 0)
            s:Show()
            x = x + 32
        else
            s:Hide()
        end
    end
    x = x + 6
    for i = 1, #mk.classes do
        local s = mk.classes[i]
        local c = order[i]
        if c then
            SetClassIcon(s.icon, c)
            s.text:SetText(classes[c])
            s.title = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or (c:sub(1, 1) .. c:sub(2):lower())
            s.who = classWho[c]
            s:ClearAllPoints()
            s:SetPoint("LEFT", mk, "LEFT", x, 0)
            s:Show()
            x = x + 28
        else
            s:Hide()
        end
    end
    local parts = {}
    for b = 1, 4 do if n[b] > 0 then parts[#parts + 1] = n[b] .. " " .. BUCKETS[b] end end
    if n[5] > 0 then parts[#parts + 1] = n[5] .. " no answer" end
    d.whoHead:SetText("Who is coming  |cffd6c49e" .. table.concat(parts, "  -  ") .. "|r")
    d.whoNote:SetText(#list == 0 and "Nobody yet." or "")
    local maxOff = math.max(0, #list - WHO_ROWS)
    if state.whoOff > maxOff then state.whoOff = maxOff end
    for i = 1, WHO_ROWS do
        local r = d.who[i]
        local p = list[state.whoOff + i]
        if p then
            r:Show()
            SetClassIcon(r.cls, p.class)
            SetRoleIcon(r.role, p.role)
            local c = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
            r.name:SetText(Who(p.name) .. (p.lvl and p.lvl > 0 and ("  |cff8a8a8a" .. p.lvl .. "|r") or ""))
            if c then r.name:SetTextColor(c.r, c.g, c.b) else r.name:SetTextColor(0.88, 0.88, 0.88) end
            r.st:SetText(StatusText(p.st))
        else
            r:Hide()
        end
    end
    d.whoMore:SetText(#list > WHO_ROWS and ("%d people - scroll for more"):format(#list) or "")
end

local function PaintDetail(e)
    local d = panel.detail
    d.body:SetShown(e and true or false)
    d.none:SetShown(not e)
    if not e then
        d.none:SetText(GH.Prep.IAmOfficer() and "Pick an event, or add one on the left." or "Pick an event to see who is coming.")
        Buttons(nil)
        return
    end
    d.title:SetText(e.title)
    local kind = e.ct == "GUILD_ANNOUNCEMENT" and "Announcement" or (TYPES[e.type] or "Event")
    d.when:SetText(kind .. "  -  " .. WhenText(e.t) .. "  |cff8a8a8a(realm time)|r")
    local info = state.info
    local by = info and info.creator
    if e.ct == "GUILD_ANNOUNCEMENT" then
        d.by:SetText(by and ("Posted by " .. Who(by)) or "")
    elseif e.it == SIGNUP then
        d.by:SetText("Sign-up event" .. (by and (" by " .. Who(by)) or ""))
    else
        d.by:SetText("Invite" .. ((e.by and e.by ~= "") and (" from " .. Who(e.by)) or (by and (" from " .. Who(by)) or "")))
    end
    local desc = info and info.description or ""
    d.desc:SetText(desc ~= "" and desc or (info and "|cff8a8a8aNo description.|r" or ""))
    -- raid prep targets due that day
    local prep = UI.PrepFor(e)
    d.prep.list = prep
    if prep and #prep > 0 then
        local done, names = 0, {}
        for _, t in ipairs(prep) do
            if (t._deliv or 0) >= t.n then done = done + 1 end
            names[#names + 1] = GH.Prof.ItemName(t.it) or ("Item " .. t.it)
        end
        d.prep.text:SetText(("|cffd9a421Raid prep:|r %d due, %d done  |cffd6c49e%s|r"):format(#prep, done, table.concat(names, ", ")))
        d.prep:Show()
    else
        d.prep:Hide()
    end
    -- edit / delete (creator or moderator)
    local ok, can = pcall(C_Calendar.ContextMenuEventCanEdit, e.off, e.day, e.idx)
    local canEdit = ok and can and not e.past and true or false
    d.editBtn:SetShown(canEdit)
    d.delBtn:SetShown(canEdit)
    if e.ct == "GUILD_ANNOUNCEMENT" then
        d.you:SetText("")
    elseif e.past then
        d.you:SetText("You: " .. StatusText(e.st) .. "  |cff8a8a8a(started)|r")
    else
        d.you:SetText("You: " .. StatusText(e.st))
    end
    Buttons(e)
    local canRole = e.ct ~= "GUILD_ANNOUNCEMENT" and not e.past
    d.roleDrop:SetShown(canRole)
    if canRole then d.roleDrop:Refresh() end
    d.title:SetPoint("RIGHT", d.body, "RIGHT", canRole and -100 or -12, 0)
    d.mk:SetShown(e.ct ~= "GUILD_ANNOUNCEMENT")
    d.whoBox:SetShown(e.ct ~= "GUILD_ANNOUNCEMENT")
    d.whoHead:SetShown(e.ct ~= "GUILD_ANNOUNCEMENT")
    if e.ct ~= "GUILD_ANNOUNCEMENT" then PaintWho() end
end

function Paint()
    if not panel or not panel:IsShown() then return end
    local e = Selected()
    if not e and state.events[1] then
        e = state.events[1]
        state.sel = e.key
    elseif not e then
        state.sel = nil
    end
    if e and state.tried ~= e.key then OpenSel() end
    PaintList()
    PaintDetail(e)
    local officer = GH.Prep.IAmOfficer()
    panel.addBox:SetShown(officer or state.edit ~= nil)
    panel.notOfficer:SetShown(not officer and not state.edit)
end
UI.Paint = Paint

-- Raid Prep targets whose due day is the event's day (realm date vs your local due day)
function UI.PrepFor(e)
    if not e or not GH.Prep or not GH.Prep.All then return nil end
    local ok, list = pcall(GH.Prep.All)
    if not ok or not list then return nil end
    local out = {}
    for _, t in ipairs(list) do
        if t.du and t.du > 0 then
            local d = date("*t", t.du - 60)
            if d.year == e.t.year and d.month == e.t.month and d.day == e.t.monthDay then out[#out + 1] = t end
        end
    end
    return out
end

-- open the tab on one event (reminder pop-up)
function UI.Select(key)
    state.sel = key
    if GH.Window and GH.Window.Open then GH.Window.Open(nil, "cal") end
    Paint()
end

local function FillForm(e)
    local f = state.form
    local now = C_DateAndTime.GetCurrentCalendarTime()
    f.day = math.max(0, math.floor((Noon(e.t) - Noon(now)) / 86400 + 0.5))
    f.type = e.type or 4
    f.hour = e.t.hour % 12 == 0 and 12 or e.t.hour % 12
    f.min = e.t.minute - e.t.minute % 15
    f.ampm = e.t.hour >= 12 and "PM" or "AM"
    panel.titleBox:SetText(e.title or "")
    panel.descBox:SetText(state.info and state.info.description or "")
    for _, dd in ipairs(panel.formDrops) do dd:Refresh() end
end

local function EnterEdit(e)
    state.edit = e.key
    FillForm(e)
    panel.formHead:SetText("Edit event")
    panel.kindDrop:Hide()
    panel.titleBox:SetWidth(296)
    panel.addBtn:SetLabel("Save")
    panel.cancelBtn:Show()
    Msg("Change what you need, then Save.")
    Paint()
end

function ExitEdit()
    state.edit = nil
    panel.formHead:SetText("New event")
    panel.kindDrop:Show()
    panel.titleBox:SetWidth(190)
    panel.titleBox:SetText("")
    panel.descBox:SetText("")
    panel.addBtn:SetLabel("Add")
    panel.cancelBtn:Hide()
    Paint()
end

local function Delete(e)
    local ok, err = pcall(function()
        C_Calendar.ContextMenuSelectEvent(e.off, e.day, e.idx)
        C_Calendar.ContextMenuEventRemove()
    end)
    if not ok then Msg("The game would not delete it: " .. tostring(err), true); return end
    if state.edit == e.key then ExitEdit() end
    state.sel, state.tried, state.opened = nil, nil, nil
    Msg("Deleted " .. e.title .. ".")
    UI.PaintSoon(true)
end
UI.EnterEdit, UI.Delete = EnterEdit, Delete

-- from Comm: a guildmate's role for an event, and a request to resend ours
function UI.OnRole(text, sender)
    local key, role = text:match("^E~([^~]+)~(%a?)$")
    if not key or not sender then return end
    SetRole(key, sender, ROLE[role] and role or nil)
    if state.opened == key then ReadOpen() end
    UI.PaintSoon()
end

function UI.OnAsk(text)
    local key = text:match("^F~([^~]+)$")
    if not key or answering[key] or not RoleOf(key, GH.Me()) then return end
    answering[key] = true
    -- spread the answers out a little
    C_Timer.After(1 + math.random() * 4, function()
        answering[key] = nil
        SendRole(key)
    end)
end

local paintTimer
function UI.PaintSoon(rescan)
    if rescan then state.dirty = true end
    if not panel or not panel:IsShown() or paintTimer then return end
    paintTimer = C_Timer.NewTimer(0.2, function()
        paintTimer = nil
        if state.dirty then state.dirty = false; Rescan() end
        Paint()
    end)
end

GH.On("CALENDAR_UPDATE_EVENT_LIST", function() UI.PaintSoon(true) end)
GH.On("CALENDAR_UPDATE_GUILD_EVENTS", function() UI.PaintSoon(true) end)
GH.On("CALENDAR_NEW_EVENT", function() UI.PaintSoon(true) end)
GH.On("CALENDAR_OPEN_EVENT", function() ReadOpen(); UI.PaintSoon(true) end)
GH.On("CALENDAR_UPDATE_EVENT", function() ReadOpen(); UI.PaintSoon(true) end)
GH.On("CALENDAR_UPDATE_INVITE_LIST", function() ReadOpen(); UI.PaintSoon(true) end)
GH.On("CALENDAR_CLOSE_EVENT", function() state.opened = nil end)
GH.On("CALENDAR_UPDATE_ERROR", function(reason)
    if panel and panel:IsShown() and type(reason) == "string" then Msg(reason, true) end
end)
GH.On("PLAYER_REGEN_ENABLED", function() if state.locked then UI.PaintSoon(true) end end)

--------------------------------------------------------------------------------
-- Reminder: a pop-up 15 minutes before an event you said yes / maybe to
--------------------------------------------------------------------------------
local REMIND_MIN = 15
local YES = { [1] = true, [3] = true, [5] = true, [6] = true, [8] = true }
local reminded = {}
local function CheckReminders()
    if not GH.db or not GH.db.settings.calRemind or InCombatLockdown() or not IsInGuild() then return end
    -- don't move the game's calendar while someone is browsing it
    if CalendarFrame and CalendarFrame:IsShown() then return end
    Rescan()
    local now = C_DateAndTime.GetCurrentCalendarTime()
    local nowT = time({ year = now.year, month = now.month, day = now.monthDay, hour = now.hour, min = now.minute })
    for _, e in ipairs(state.events) do
        if YES[e.st] and not reminded[e.key] and e.ct == "GUILD_EVENT" then
            local t = time({ year = e.t.year, month = e.t.month, day = e.t.monthDay, hour = e.t.hour, min = e.t.minute })
            local mins = (t - nowT) / 60
            if mins >= 0 and mins <= REMIND_MIN then
                reminded[e.key] = true
                if GH.Toast and GH.Toast.Add then
                    local text = mins < 1 and (e.title .. " starts now.")
                        or ("%s starts in %d min (%s)."):format(e.title, math.floor(mins + 0.5), H12(e.t.hour, e.t.minute))
                    local key = e.key
                    GH.Toast.Add(text, e.icon or ICONS[e.type] or 134400, nil, function() UI.Select(key) end)
                end
            end
        end
    end
    if panel and panel:IsShown() then Paint() end
end
GH.On("PLAYER_LOGIN", function()
    C_Timer.After(15, function()
        pcall(C_Calendar.OpenCalendar)
        C_Timer.After(5, CheckReminders)
        C_Timer.NewTicker(60, CheckReminders)
    end)
end)

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
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 6, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row:SetScript("OnEnter", function(r) r.hl:Show() end)
    row:SetScript("OnLeave", function(r) r.hl:Hide() end)
    return row
end

local function Tip(w, title, text)
    w:HookScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        if text then GameTooltip:AddLine(text, 0.84, 0.77, 0.62, true) end
        GameTooltip:Show()
    end)
    w:HookScript("OnLeave", function() GameTooltip:Hide() end)
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
    panel:SetScript("OnShow", function()
        Prune()
        pcall(C_Calendar.OpenCalendar)
        Rescan()
        Paint()
    end)

    -- events list
    local head = Label(panel, "Guild events")
    head:SetPoint("TOPLEFT", 12, -12)
    panel.more = S.Text(panel, 10, T.dim, "RIGHT")
    panel.more:SetPoint("TOPRIGHT", panel, "TOPLEFT", 310, -13)
    local box = S.Panel(panel, T.field)
    box:SetPoint("TOPLEFT", 10, -30)
    box:SetSize(300, LIST_ROWS * LIST_H + 4)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(_, delta)
        state.offset = math.max(0, state.offset - delta * 2)
        Paint()
    end)
    panel.rows = {}
    for i = 1, LIST_ROWS do
        local row = ListRow(box, LIST_H)
        row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * LIST_H)
        row:SetPoint("TOPRIGHT", -2, -2 - (i - 1) * LIST_H)
        row.right = S.Text(row, 10, T.text, "RIGHT")
        row.right:SetPoint("TOPRIGHT", -6, -4)
        row.text = S.Text(row, 12, T.text)
        row.text:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 3)
        row.text:SetPoint("RIGHT", row, "RIGHT", -80, 0)
        row.text:SetWordWrap(false)
        row.when = S.Text(row, 10, SOFT)
        row.when:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -3)
        row.when:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.when:SetWordWrap(false)
        row:SetScript("OnClick", function(r)
            if not r.data then return end
            if state.sel ~= r.data.key then
                state.sel = r.data.key
                Msg("")
                OpenSel()
            end
            Paint()
        end)
        panel.rows[i] = row
    end
    panel.empty = S.Text(box, 11, SOFT, "CENTER")
    panel.empty:SetPoint("CENTER")
    panel.empty:SetWidth(260)

    -- new event (officers)
    local add = CreateFrame("Frame", nil, panel)
    add:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -10)
    add:SetSize(300, 122)
    panel.addBox = add
    local al = Label(add, "New event")
    al:SetPoint("TOPLEFT", 2, 0)
    panel.formHead = al
    local cancel = S.Button(add, 60, 16, "Cancel")
    cancel:SetPoint("TOPRIGHT", add, "TOPRIGHT", 0, 2)
    cancel:SetScript("OnClick", function() ExitEdit(); Msg("") end)
    cancel:Hide()
    panel.cancelBtn = cancel
    local f = state.form

    local title = S.EditBox(add, 190, 22)
    title:SetPoint("TOPLEFT", 0, -16)
    title:SetMaxLetters(31)
    title.hint:SetText("Title")
    title:SetScript("OnTextChanged", function(e) e.hint:SetShown(e:GetText() == "") end)
    title:SetScript("OnEnterPressed", function(e) e:ClearFocus() end)
    panel.titleBox = title
    local kind = S.Dropdown(add, 106, 22, function()
        return { { "s", "Sign-up event" }, { "a", "Announcement" } }
    end, function() return f.kind end, function(v) f.kind = v end)
    kind:SetPoint("LEFT", title, "RIGHT", 4, 0)
    panel.kindDrop = kind
    Tip(kind, "Sign-up event or announcement", "Sign-up: guildmates sign up or say tentative. Announcement: a note on the calendar, no answers.")

    local typ = S.Dropdown(add, 74, 20, function()
        local items = {}
        for i = 0, 4 do items[#items + 1] = { i, TYPES[i] } end
        return items
    end, function() return f.type end, function(v) f.type = v end)
    typ:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    local day = S.Dropdown(add, 86, 20, DayItems, function() return f.day end, function(v) f.day = v end)
    day:SetPoint("LEFT", typ, "RIGHT", 2, 0)
    panel.dayDrop = day
    local hour = S.Dropdown(add, 40, 20, function()
        local items = {}
        for i = 1, 12 do items[#items + 1] = { i, tostring(i) } end
        return items
    end, function() return f.hour end, function(v) f.hour = v end)
    hour:SetPoint("LEFT", day, "RIGHT", 2, 0)
    local min = S.Dropdown(add, 44, 20, function()
        return { { 0, ":00" }, { 15, ":15" }, { 30, ":30" }, { 45, ":45" } }
    end, function() return f.min end, function(v) f.min = v end)
    min:SetPoint("LEFT", hour, "RIGHT", 2, 0)
    local ampm = S.Dropdown(add, 48, 20, function()
        return { { "AM", "AM" }, { "PM", "PM" } }
    end, function() return f.ampm end, function(v) f.ampm = v end)
    ampm:SetPoint("LEFT", min, "RIGHT", 2, 0)
    Tip(hour, "Start time", "Realm time, the same time the game's calendar shows.")
    panel.formDrops = { typ, day, hour, min, ampm }

    local desc = S.EditBox(add, 240, 22)
    desc:SetPoint("TOPLEFT", typ, "BOTTOMLEFT", 0, -8)
    desc:SetMaxLetters(255)
    desc.hint:SetText("Description (optional)")
    desc:SetScript("OnTextChanged", function(e) e.hint:SetShown(e:GetText() == "") end)
    desc:SetScript("OnEnterPressed", function(e) e:ClearFocus() end)
    panel.descBox = desc
    local addBtn = S.Button(add, 56, 22, "Add")
    addBtn:SetPoint("LEFT", desc, "RIGHT", 4, 0)
    addBtn:SetScript("OnClick", Create)
    panel.addBtn = addBtn
    Tip(addBtn, "Add to the guild calendar", "Everyone in the guild sees it in the game's calendar too, with or without this addon.")

    panel.msg = S.Text(panel, 11, SOFT)
    panel.msg:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -120)
    panel.msg:SetWidth(296)
    panel.msg:SetWordWrap(false)

    panel.notOfficer = S.Text(panel, 11, SOFT)
    panel.notOfficer:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -12)
    panel.notOfficer:SetWidth(296)
    panel.notOfficer:SetText("Officers add events. Pick one to sign up and see who is coming. They are the same events as the game's calendar.")

    -- detail
    local d = S.Panel(panel, T.field)
    d:SetPoint("TOPLEFT", 320, -12)
    d:SetPoint("BOTTOMRIGHT", -10, 10)
    panel.detail = d
    d.none = S.Text(d, 11, SOFT, "CENTER")
    d.none:SetPoint("CENTER")
    d.none:SetWidth(300)
    local body = CreateFrame("Frame", nil, d)
    body:SetAllPoints()
    d.body = body

    d.title = S.Text(body, 16, T.accent)
    d.title:SetPoint("TOPLEFT", 12, -12)
    d.title:SetPoint("RIGHT", body, "RIGHT", -12, 0)
    d.title:SetWordWrap(false)
    d.when = S.Text(body, 11, T.text)
    d.when:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -6)
    d.by = S.Text(body, 11, SOFT)
    d.by:SetPoint("TOPLEFT", d.when, "BOTTOMLEFT", 0, -4)
    d.desc = S.Text(body, 11, T.text)
    d.desc:SetPoint("TOPLEFT", d.by, "BOTTOMLEFT", 0, -8)
    d.desc:SetPoint("RIGHT", body, "RIGHT", -12, 0)
    d.desc:SetHeight(28)
    d.desc:SetJustifyV("TOP")
    d.desc:SetWordWrap(true)
    if d.desc.SetMaxLines then d.desc:SetMaxLines(2) end
    -- raid prep due that day (click: Raid Prep tab)
    local prep = CreateFrame("Button", nil, body)
    prep:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", 0, -4)
    prep:SetPoint("RIGHT", body, "RIGHT", -12, 0)
    prep:SetHeight(16)
    prep.text = S.Text(prep, 11, T.text)
    prep.text:SetAllPoints()
    prep.text:SetWordWrap(false)
    prep:SetScript("OnClick", function() if GH.Window and GH.Window.Open then GH.Window.Open(nil, "prep") end end)
    prep:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Raid prep due this day", 1, 1, 1)
        for _, t in ipairs(s.list or {}) do
            local left = GH.Prof.ItemName(t.it) or ("Item " .. t.it)
            GameTooltip:AddDoubleLine(left, ("%d / %d handed in"):format(t._deliv or 0, t.n), 0.84, 0.77, 0.62, 1, 1, 1)
        end
        GameTooltip:AddLine("Click to open Raid Prep.", 0.84, 0.77, 0.62)
        GameTooltip:Show()
    end)
    prep:SetScript("OnLeave", function() GameTooltip:Hide() end)
    prep:Hide()
    d.prep = prep

    d.actY = -128
    d.you = S.Text(body, 12, T.text)
    d.you:SetPoint("TOPLEFT", 12, d.actY - 4)
    d.acts = {}
    for i = 1, 3 do
        local b = S.Button(body, 76, 22, "")
        b:Hide()
        d.acts[i] = b
    end

    -- your role for this event (top right)
    d.roleDrop = S.Dropdown(body, 84, 22, function()
        return { { "T", "Tank" }, { "H", "Healer" }, { "D", "DPS" } }
    end, function()
        local e = Selected()
        return e and RoleOf(e.key, GH.Me())
    end, function(v)
        local e = Selected()
        if not e then return end
        SetMyRole(e.key, v)
        ReadOpen()
        Paint()
    end)
    d.roleDrop.placeholder = "Pick role"
    d.roleDrop:SetPoint("TOPRIGHT", body, "TOPRIGHT", -10, -10)
    Tip(d.roleDrop, "Your role for this event", "Guildmates who run Cys's Guild Hall see it beside your name.")

    d.whoHead = Label(body, "Who is coming")
    d.whoHead:SetPoint("TOPLEFT", 12, -162)
    -- makeup of who is going: role counts, then class icons with counts
    local mk = CreateFrame("Frame", nil, body)
    mk:SetPoint("TOPLEFT", 12, -178)
    mk:SetPoint("RIGHT", body, "RIGHT", -10, 0)
    mk:SetHeight(18)
    local function Slot()
        local s = CreateFrame("Frame", nil, mk)
        s:SetSize(28, 18)
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetSize(15, 15)
        s.icon:SetPoint("LEFT")
        s.text = S.Text(s, 11, T.text)
        s.text:SetPoint("LEFT", s.icon, "RIGHT", 2, 0)
        -- hover: who is going in this role / class
        s:EnableMouse(true)
        s:SetScript("OnEnter", function(f)
            if not f.who then return end
            GameTooltip:SetOwner(f, "ANCHOR_BOTTOM")
            GameTooltip:SetText(("%s  |cffd6c49e%d going|r"):format(f.title or "", #f.who), 1, 0.82, 0)
            for _, p in ipairs(f.who) do
                local c = p.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[p.class]
                local role = p.role and ROLE[p.role] and ROLE[p.role][1] or ""
                GameTooltip:AddDoubleLine(Who(p.name), role, c and c.r or 0.88, c and c.g or 0.88, c and c.b or 0.88, 0.84, 0.77, 0.62)
            end
            GameTooltip:Show()
        end)
        s:SetScript("OnLeave", function() GameTooltip:Hide() end)
        s:Hide()
        return s
    end
    mk.roles, mk.classes = {}, {}
    for i = 1, 4 do mk.roles[i] = Slot() end
    mk.roles[4].text:ClearAllPoints()
    mk.roles[4].text:SetPoint("LEFT")
    for i = 1, 10 do mk.classes[i] = Slot() end
    d.mk = mk
    local wb = S.Panel(body, T.bg)
    wb:SetPoint("TOPLEFT", 10, -200)
    wb:SetPoint("RIGHT", body, "RIGHT", -10, 0)
    wb:SetHeight(WHO_ROWS * WHO_H + 4)
    wb:EnableMouseWheel(true)
    wb:SetScript("OnMouseWheel", function(_, delta)
        state.whoOff = math.max(0, state.whoOff - delta * 3)
        PaintWho()
    end)
    d.whoBox = wb
    d.who = {}
    for i = 1, WHO_ROWS do
        local r = CreateFrame("Frame", nil, wb)
        r:SetHeight(WHO_H)
        r:SetPoint("TOPLEFT", 6, -2 - (i - 1) * WHO_H)
        r:SetPoint("TOPRIGHT", -6, -2 - (i - 1) * WHO_H)
        r.cls = r:CreateTexture(nil, "ARTWORK")
        r.cls:SetSize(14, 14)
        r.cls:SetPoint("LEFT")
        r.role = r:CreateTexture(nil, "ARTWORK")
        r.role:SetSize(14, 14)
        r.role:SetPoint("LEFT", 17, 0)
        r.name = S.Text(r, 11, T.text)
        r.name:SetPoint("LEFT", 35, 0)
        r.st = S.Text(r, 11, T.text, "RIGHT")
        r.st:SetPoint("RIGHT")
        d.who[i] = r
    end
    d.whoNote = S.Text(wb, 11, SOFT, "CENTER")
    d.whoNote:SetPoint("CENTER")
    d.whoMore = S.Text(body, 10, T.dim, "RIGHT")
    d.whoMore:SetPoint("TOPRIGHT", wb, "BOTTOMRIGHT", 0, -3)

    d.editBtn = S.Button(body, 60, 18, "Edit")
    d.editBtn:SetPoint("TOPLEFT", wb, "BOTTOMLEFT", 0, -4)
    d.editBtn:SetScript("OnClick", function()
        local e = Selected()
        if e then EnterEdit(e) end
    end)
    Tip(d.editBtn, "Edit this event", "Fills in the form on the left. Save sends it to the game's calendar.")
    d.delBtn = S.Button(body, 60, 18, "Delete")
    d.delBtn:SetPoint("LEFT", d.editBtn, "RIGHT", 4, 0)
    d.delBtn:SetScript("OnClick", function(b)
        local e = Selected()
        if not e then return end
        if not b.armed then
            b.armed = true
            b:SetLabel("|cffff6060Sure?|r")
            C_Timer.After(3, function() b.armed = nil; b:SetLabel("Delete") end)
            return
        end
        b.armed = nil
        b:SetLabel("Delete")
        Delete(e)
    end)
    Tip(d.delBtn, "Delete this event", "Click twice. It is removed from the guild calendar for everyone.")
    d.editBtn:Hide()
    d.delBtn:Hide()

    return panel
end
