--------------------------------------------------------------------------------
-- Cys's Guild Hall - What's New
-- After an update, a window lists what changed in every version newer than the
-- one you last saw (once, out of combat). New installs skip it. Reopen it with
-- /guildhall news or the What's new button on the Options tab.
-- Older history lives in CHANGELOG.md. Keep entries plain strings, newest first.
--------------------------------------------------------------------------------
local GH = CysGuildHall
local S = GH.Style
local WN = {}
GH.WhatsNew = WN

WN.ENTRIES = {
    { version = "1.0.2",
        improved = {
            "Craft requests placed while you were offline show up a few seconds after you log in, all together, instead of trickling in one by one. Several at once give one chat line and one pop-up instead of one each.",
            "Can make it is a scroll list: every crafter, not just the first five. Scroll with the mouse wheel or the thin bar on the right; the heading shows how many there are.",
            "Roster tab: the seal legend counts how many players run Cys's Guild Hall (one per player: alts are not counted on their own).",
        },
        fixed = {
            "Options: the Guild Hall versions list stays inside the window (it scrolls now).",
            "Recipe loot pop-ups no longer spill text past the bottom of the box.",
        },
    },
    { version = "1.0.1",
        improved = {
            "Recipe loot pop-ups now say what was found: the recipe in its quality color, plus a line with the profession and what it makes (for example Tailoring - makes Red Linen Robe). Hover the pop-up to see the full item tooltip.",
        },
    },
    { version = "1.0.0",
        added = {
            "Roster tab: every member with alts folded under their main, level, rank, professions and when they were last on. Members who run Cys's Guild Hall carry its seal. Pick one to see their notes, alts and every character's professions and skill. Search by name, rank or profession, or show online only.",
            "Calendar: the event's creator (or a moderator) can Edit or Delete it right from the tab. Edit fills in the form on the left; Delete asks for a second click.",
            "Calendar: Raid Prep targets due on the event's day show on the event. Click the line to open Raid Prep.",
            "Calendar: a pop-up 15 minutes before an event you signed up for (or said maybe to). Click it to open the event. Turn it off on the Options tab.",
            "Calendar: hover a role or class count above Who is coming to see exactly who is going in it.",
        },
        improved = {
            "New look: the Cys's Guild Hall seal on the minimap button and in the addon list.",
        },
    },
    { version = "0.4.0",
        added = {
            "Calendar tab: the guild's events for the next 30 days, straight from the game's calendar. Pick one to sign up, say tentative or remove yourself (or accept / decline an invite) and see who is coming, grouped by answer with class colors.",
            "Officers can add events from the Calendar tab: title, sign-up event or announcement, type, day, start time (realm time) and a description. They land in the game's calendar, so guildmates without the addon see them too.",
            "Roles: pick Tank, Healer or DPS on an event (top right). Who is coming shows each person's class and role icons, and the top line counts the roles and classes of everyone going. Your last pick fills in by itself when you sign up. Roles are shared with guildmates who run Cys's Guild Hall.",
            "Open it with /guildhall calendar.",
        },
    },
    { version = "0.3.19",
        improved = {
            "Can make it is tidier: when a guildmate's main can make the item, the line shows only the main with the main's own skill. Alt names show only when just an alt can make it (alt of Main Name). Hover a line to see every character.",
            "Item tooltips follow the same rule: no more +1 alt after a main's name.",
        },
    },
    { version = "0.3.18",
        added = {
            "Raid Prep due dates: officers can give a target a due date (optional). Targets due soonest sort first, the list shows due Nov 24, and it turns yellow the day before and red once overdue.",
            "Officers can change the hand-in and the due date of an existing target from the dropdowns above its parts: the officer who set it, the guild bank, you, or a raider by name.",
            "Raid target button: officers see it on an item in the Crafting tab. It opens Raid Prep with that item ready in the New target box.",
            "Mail your raid prep: at a mailbox, the Send Mail panel also lists your claimed target items that go to a person, and gathered materials when one crafter is on that target. Mail it fills in the name, subject and items; once you press Send, your Handed in goes up by what you mailed.",
        },
    },
    { version = "0.3.17",
        added = {
            "Alts under their main: in Can make it, a guildmate's alt shares one line with their main, with the best skill of the two and a green dot if either is online. Hover the line to see every character.",
            "Alts are found from the guild roster: a member with an Alt rank whose public or officer note names another member (for example Alt of First Last). Turn it off or pick which rank means alt on the Options tab.",
            "Item tooltips show crafters with their alts folded in.",
            "Claim button: one click claims whatever is still open on the part you picked. Or type any amount in the Claim box.",
            "Made counts by itself: craft a target item while you have a claim on it and your Made number goes up (up to your claim). Handed in is still yours to set, or press All in.",
            "Hand-in: when adding a target, officers pick where finished items go: themselves, the guild bank or a named raider. Crafters see it on the target.",
        },
    },
    { version = "0.3.16",
        added = {
            "Raid Prep tab: officers set guild targets, an item and how many the guild needs (shift-click an item or type its name). Officers can change the count or remove a target.",
            "Each target lists its parts: the item itself, plus the materials from its recipe with how many the whole target takes.",
            "Claim a part: crafters claim how many they will make, gatherers claim an amount of a material. Keep your Delivered number up to date (or press All in) and the whole guild sees the progress.",
            "Who is on it: every part shows who claimed how much and what they delivered. Gatherers see which crafters to send their materials to.",
            "A pop-up and a chat note when an officer sets a new target, and one when a target is done. Item tooltips show raid prep progress for target items and their materials.",
        },
        improved = {
            "A long guild name in the window title no longer runs under the tabs.",
        },
    },
    { version = "0.3.15",
        added = {
            "Recipe items show Not learned in the guild on their tooltip when nobody in the guild has learned that recipe yet (bags, loot, the Auction House and chat links).",
            "Loot a recipe nobody in the guild knows and the guild gets a pop-up about it. Switch on the Options tab.",
            "Request pop-up: when a guildmate asks for something you can make, a pop-up shows who asked and what. Only crafters who know that recipe see it. Click it to open the Requests tab.",
            "Gaps tab source filter: a dropdown at the end of the search box shows only recipes learned from a Trainer, Vendor, Drop, Quest or Other.",
            "Change delivery on your own open request with the delivery dropdown next to the request details. The crafter gets a chat note about the change.",
        },
        improved = {
            "Picking mail or trade for a new request is now a dropdown instead of a button you click to switch.",
        },
    },
    { version = "0.3.14",
        fixed = {
            "Guild news pop-ups: the text is a bit smaller and wraps onto a second line, so the whole note shows instead of being cut off.",
        },
    },
    { version = "0.3.13",
        added = {
            "Gaps tab covers the whole guild: each profession's full recipe list is shared, so you see recipes nobody knows for every profession anyone in the guild has, not only your own.",
            "Where to learn it, from the guild: opening a recipe nobody knows asks guildmates, and one who has read it sends the source and the trainers and vendors they visited.",
            "This What's New window (after updates, /guildhall news, or What's new on the Options tab).",
        },
    },
    { version = "0.3.12",
        added = {
            "Version check: a chat note when a guildmate runs a newer Guild Hall, and who runs which version on the Options tab (/guildhall versions).",
            "Mail it: at a mailbox, the Send Mail tab lists your claimed requests that asked for mail. One click fills in the name and subject and attaches the items; the request is marked done once you send it.",
        },
    },
    { version = "0.3.11",
        added = {
            "Materials pop-up when a crafter claims your request: each reagent as needed, what you have and what the crafter has, plus what is still short (/guildhall mats).",
            "Requests: choose Mail it to me or Meet to trade.",
            "Guild news pop-ups when a guildmate adds a profession or learns new recipes.",
        },
        improved = {
            "Recipes that make Bind on Pickup items are hidden everywhere, since a guildmate can't hand them over.",
        },
    },
    { version = "0.3.10",
        fixed = {
            "Guildmates now show with their real first and last names (the last name comes from the guild roster). Names saved wrong are repaired by themselves.",
        },
    },
}

local SOFT = { 0.84, 0.77, 0.62, 1 }
local WIDTH, MAXH = 440, 440
local frame

local function Hex(c) return ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end

-- Text for every entry newer than since (nil = all entries)
local function Body(since)
    local T = S.T()
    local gold, soft, text = Hex(T.brand), Hex(SOFT), Hex(T.text)
    local out = {}
    for _, e in ipairs(WN.ENTRIES) do
        if not since or GH.VersionNewer(e.version, since) then
            out[#out + 1] = ("|cff%s%s|r"):format(gold, e.version)
            for _, sec in ipairs({ { "added", "Added" }, { "improved", "Improved" }, { "fixed", "Fixed" } }) do
                local list = e[sec[1]]
                if list and #list > 0 then
                    out[#out + 1] = ("|cff%s%s|r"):format(soft, sec[2])
                    for _, l in ipairs(list) do out[#out + 1] = ("|cff%s-  %s|r"):format(text, l) end
                end
            end
            out[#out + 1] = " "
        end
    end
    out[#out + 1] = ("|cff%sOlder versions: CHANGELOG.md on GitHub (Cyserin/CysGuildHall).|r"):format(soft)
    return table.concat(out, "\n")
end

local function Build()
    local T = S.T()
    frame = CreateFrame("Frame", "CysGuildHallWhatsNew", UIParent)
    frame:SetWidth(WIDTH)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetPoint("CENTER", 0, 60)
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
    frame.title = S.Text(header, 14, T.brand)
    frame.title:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    local x = S.Button(header, 22, 22, "x")
    x:SetPoint("RIGHT", -4, 0)
    x:SetScript("OnClick", function() frame:Hide() end)

    -- scrolling text box (mouse wheel)
    local box = S.Panel(frame, T.field)
    box:SetPoint("TOPLEFT", 14, -42)
    box:SetPoint("BOTTOMRIGHT", -14, 52)
    local sf = CreateFrame("ScrollFrame", nil, box)
    sf:SetPoint("TOPLEFT", 12, -10)
    sf:SetPoint("BOTTOMRIGHT", -12, 10)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(WIDTH - 52, 10)
    sf:SetScrollChild(child)
    frame.text = S.Text(child, 12, T.text)
    frame.text:SetPoint("TOPLEFT")
    frame.text:SetWidth(WIDTH - 52)
    frame.text:SetJustifyV("TOP")
    frame.text:SetSpacing(3)
    frame.child, frame.sf = child, sf
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, frame.child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 40)))
    end)

    local note = S.Text(frame, 11, SOFT)
    note:SetPoint("BOTTOMLEFT", 20, 22)
    note:SetText("Reopen with /guildhall news")
    local close = S.Button(frame, 100, 26, "Close")
    close:SetPoint("BOTTOMRIGHT", -14, 14)
    close:SetScript("OnClick", function() frame:Hide() end)
end

-- since = only versions newer than this one (nil = everything in the list)
function WN.Show(since)
    if not frame then Build() end
    frame.title:SetText("What's new in Cys's Guild Hall " .. tostring(GH.version))
    frame.text:SetText(Body(since))
    local h = frame.text:GetStringHeight() or 200
    frame.child:SetHeight(h + 4)
    frame:SetHeight(math.min(MAXH, math.max(200, h + 42 + 52 + 24)))
    frame.sf:SetVerticalScroll(0)
    frame:Show()
end

-- Players updating from 0.3.12 (before this window) have data but no lastSeen yet
GH.Listen("LOADED", function()
    local db = GH.db
    if not db.lastSeen and (next(db.init) or next(db.recipes) or next(db.allRecipes)) then db.lastSeen = "0.3.12" end
end)

-- Login: once per update, out of combat, never on a fresh install or over the welcome window
local function MaybeShow()
    local db = GH.db
    if not db then return end
    local last = db.lastSeen
    if last == GH.version then return end
    if not last or not GH.VersionNewer(GH.version, last) then
        db.lastSeen = GH.version
        return
    end
    if GH.Welcome and _G.CysGuildHallWelcome and _G.CysGuildHallWelcome:IsShown() then
        db.lastSeen = GH.version
        return
    end
    if InCombatLockdown() then
        local w = CreateFrame("Frame")
        w:RegisterEvent("PLAYER_REGEN_ENABLED")
        w:SetScript("OnEvent", function(f) f:UnregisterAllEvents(); C_Timer.After(2, MaybeShow) end)
        return
    end
    db.lastSeen = GH.version
    WN.Show(last)
end

-- after the welcome window's own check (6 s)
GH.On("PLAYER_LOGIN", function() C_Timer.After(9, MaybeShow) end)
