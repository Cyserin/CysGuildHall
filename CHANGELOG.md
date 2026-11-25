# Changelog

All notable changes to Cys's Guild Hall, by Cyserin (Cys). Newest first.

## 1.2.0
- **Visual overhaul**: darker, crisper windows with a soft drop shadow, a black outer edge and a fine gold inner edge; title bars carry the Guild Hall seal and a gold hairline that fades at both ends.
- **Tabs** are text tabs with a gold underline on the active one (Options sits apart after a divider). The Requests count shows in gold next to the name.
- **Clean font** (Arial Narrow) by default for sharper small text; titles keep Friz Quadrata. Options > Text font switches back to Classic (applies after /reload).
- Selected rows get a gold bar on the left; list rows have faint stripes; section headings have a gold tick; search boxes have a magnifier.
- Buttons have a soft sheen, gold hover edge and a pressed nudge; close buttons are a thin X that turns red on hover.
- Dropdown arrows point down; menus get the window look with a gold marker on the current pick.
- Checkboxes show a gold check mark with a gold edge on hover; scroll bars are slimmer.
- Empty detail panels show a faint Guild Hall seal.
- Pop-ups (guild news toasts with a gold edge stripe, materials, shopping list, welcome, What's new) share the new look.
- **Bigger window**: wider (800 px) and shown at 110% by default. Drag the grip in the bottom-right corner to size it (80-150%), or pick Options > Window size. The top-left corner stays put while resizing.
- Roster: wider member list, so long names fit.
- Roster: column headers (Name, Lvl, Rank, Professions, Status); click Name, Lvl, Rank or Status to sort (the Sort dropdown follows). Online members show their zone instead of "Online"; the row tooltip says who is on and where. The detail side uses gold-tick **Professions** and **Alts** headings, one alt per line.
- Crafting detail: Reagents sit right under the last crafter line (or the "where to learn it" text), so there is no empty gap when few people can make it.
- Can make it: online crafters first; hover the dot for online / last seen with the zone; hovering a row highlights it and shows Whisper, click to whisper (the online character of that player).
- Crafting lists: "1/4 online" instead of "1 on / 4"; the recipe tooltip adds "N crafters in the guild, M online now".
- Requests: **Show** dropdown next to the search box (All / Open / Claimed / Mine; Mine = asked for or claimed by any of your characters). The Reagents heading says who brings the mats (the requester, or the crafter when their shared counts cover everything); the list tooltip spells it out.
- The faint Guild Hall seal behind detail panels is softer.
- Roster detail: **Whisper** button (top right) when the player is online; it whispers the character they're on.
- **Officers: alt links** for members who don't run the addon. The Roster detail of such a member shows "Alt of [name] Set / Clear" to officers; the link is shared with everyone running Cys's Guild Hall (same A message). A player's own main & alts always win over an officer link.
- Roster: the Professions column header reads "Profs" (it was cut off); the gold tick on detail headings lines up with the text.
- Fixed: the hint on the right of Crafting, Requests and Gaps was drawn behind the detail panel and never showed.

## 1.1.1
- **Main & alts in the welcome**: setup is now 3 steps. After Initialize, pick your main and add your alts by name (or click Next if you have none). Asked once per account and guild, so your other characters skip it.

## 1.1.0
- **New recipe pop-ups name the recipes**: "Jarvik Ironfang learned a new Engineering recipe: Goblin Sapper Charge." Up to three names, then "and N more"; with a single recipe, hover shows the item it makes.
- **Level dropdown** on the Crafting tab (next to the search box): A-Z, By level (level needed to use or equip, shown on each line, lowest first) or Up to my level (only what you can use now, highest first). Works on search results and item types.
- **Craft from the Guild Hall**: when this character knows the recipe and the reagents are in your bags, the bottom button says Open (profession) and then Craft Nx (the Make amount, capped at what your bags make).
- **Shopping list**: the Shopping list button next to Reagents adds the reagents you are missing for the Make amount. The list opens beside the auction house (Options switch); click a line to search for it, right-click removes it. Lines tick off as the items reach your bags or bank. Prices from Cys's Auction House when installed. `/guildhall shop`.
- **Officer tools** (Roster tab > View dropdown, or `/guildhall officer`): **Auto-promote** rules (up to 5: Level N+ in rank A moves to rank B) list who is due, A-Z by name. **Inactive members**: every character of players whose main and alts have all been offline 7-90+ days (dropdown), with a Skip "rank and up" dropdown and notes on hover. Find opens Blizzard's guild window (offline shown) with a chat line saying who to click and what to set: the game blocks addons from promoting or removing. Login chat line with the counts (checkbox). Find greys out when your rank can't promote or remove. Saved per guild.
- **Guild bank recipes**: opening the guild bank checks the tabs you can see for recipes nobody in the guild has learned: one chat line and a pop-up for new ones (again after a week), and the Gaps detail of that recipe says "In the guild bank". Options switch to post them in guild chat (off by default).
- **Your main & alts** page (button on the Options tab, or `/guildhall alts`): pick your main, see every character with level and where it came from, add an alt by name or remove one. Every character on your account that runs the addon joins by itself; type a name to add one that doesn't. Shared with the guild (new message A; older versions ignore it), so everyone's lists group your characters without relying on guild ranks.
- **Better alt detection**: a note that says "alt" and names a member (e.g. "Bob's alt") now counts in any rank, not just the alt rank. Someone marked as a main is never made an alt by a note, and alt-of-an-alt goes up to the real main.
- **Versions list** (Options): one line per player under the main's name (alts fold in), yours on top.
- **Craft requests your alts can make**: the chat line and pop-up say which of your characters can make it ("your alt Bob Smith can make it - log over to craft", or "you can make it on this alt / on your main"); the request detail says the same.
- Options: your characters' professions list scrolls (mouse wheel or bar).
- **Requests at login**: craft requests placed while you were offline arrive a few seconds after login, together, instead of trickling in one by one. Several at once give one chat line and one pop-up. (New message B packs several requests in one; older versions still get them one by one.)
- **Can make it** is a scroll list (mouse wheel or the thin bar) showing every crafter; the heading shows the count.
- **Roster tab**: the seal legend counts how many players run Cys's Guild Hall (one per main; alts named in the alt rank's notes don't count on their own, even with alt grouping off).
- Fixed: the Options versions list ran past the bottom border (it scrolls now).
- Fixed: recipe loot pop-up text overflowed the box.

## 1.0.1
- **Recipe loot pop-ups** say what was found: the recipe in its quality color, a second line with the profession and what it makes, and the full item tooltip on hover.

## 1.0.0
- **Roster tab**: every member (alts folded under their main) with class, level, rank, professions and last online; Cys's Guild Hall users carry its seal. Detail shows notes, alts, every character's professions with skill and recipe count, and addon version. Search by name, rank or profession; online only; sort by last online, name, level or rank. `/guildhall roster`.
- **Calendar**: Edit and Delete for the event's creator or a moderator (Delete needs a second click).
- **Calendar**: Raid Prep targets due on the event's day show on the event (click to open Raid Prep).
- **Calendar**: a pop-up 15 minutes before events you signed up for or said maybe to (Options switch).
- **Calendar**: hover a role or class count above Who is coming to see who is going in it.
- The **Cys's Guild Hall seal** on the minimap button and in the addon list.

## 0.4.0
- **Calendar tab**: the guild's events for the next 30 days, read from the game's calendar. Pick one to sign up, go tentative or remove yourself (or accept / tentative / decline an invite), and see who is coming grouped by answer with class colors.
- Officers can **add events** from the tab: title, sign-up event or announcement, type, day, start time (realm time), description. They are real guild calendar events, so guildmates without the addon see them in the game's calendar.
- **Roles**: pick Tank / Healer / DPS on an event. Who is coming shows class + role icons per person, and a makeup line counts roles and classes of everyone going. Your last pick is used when you sign up. Shared with guildmates who run the addon (new messages E / F; older versions ignore them).
- `/guildhall calendar` opens it.

## 0.3.19
- **Tidier Can make it**: when a guildmate's main can make the item, the line shows only the main (with the main's own skill). An alt's name shows only when just that alt can make it ("alt of Main Name"). Hover still lists every character.
- Item tooltips drop the "+1 alt" tag the same way.

## 0.3.18
- **Raid Prep due dates**: officers can set an optional due date when adding a target or on an existing one. Targets due soonest sort first; the list shows "due Nov 24", yellow the day before, red once overdue.
- Officers can **change the hand-in and due date** of an existing target (dropdowns on the Parts row): the officer who set it, the guild bank, themselves or a named raider.
- **Raid target** button on the Crafting tab item detail (officers): opens Raid Prep with that item in the New target box.
- **Mail your raid prep**: the Send Mail panel also lists your claimed target items that go to a person, and gathered materials when a single crafter is on that target. Mail it fills in the name, subject and items; after you press Send, your Handed in goes up by what you mailed.
- Due dates sync with a new message that older versions ignore: they still see the targets, just without the date.

## 0.3.17
- **Alts under their main**: in Can make it, a guildmate's alt shares one line with their main ("Main Name + Alt Name"), with the best skill of the two and online if either is. Hover the line for every character, its skill and online state. An alt whose main can't make the item shows "alt of Main Name".
- Alts come from the guild roster: a member with an Alt rank (any rank named Alt / Alts, or one rank picked on the Options tab) whose public or officer note names another member. Options switch "Group alts under their main".
- Item tooltips list crafters with their alts folded in ("+1 alt").
- **Raid Prep**: a Claim button takes whatever is still open on the picked part in one click. Each claim has Claim / Made / Handed in: crafting a target item raises Made by itself (up to your claim); the target is complete when enough is handed in. Officers pick the hand-in when adding a target (themselves, the guild bank or a named raider).
- The Options tab lists up to 5 other Guild Hall versions (was 6) to make room.

## 0.3.16
- **Raid Prep tab** (`/guildhall prep`): officers set guild targets, an item and how many the guild needs (shift-click an item or type its name), change the count or remove a target. Only officer ranks can set targets.
- **Parts**: each target lists the item itself plus the materials from its recipe, with how many the whole target takes.
- **Claims**: crafters claim how many they will make, gatherers claim an amount of a material; everyone keeps their own Delivered number up to date (or presses All in). Progress bar with made / claimed / needed.
- **Who is on it**: each part lists who claimed how much and what they delivered; gatherers see which crafters to send materials to.
- Pop-up + chat note when an officer sets a new target, a pop-up when a target is done; item tooltips show raid prep progress on target items and their materials.
- A long guild name in the window title no longer runs under the tabs.

## 0.3.15
- **Not learned in the guild**: recipe items (Pattern, Plans, Recipe, Formula, Schematic...) show this line on their tooltip when nobody in the guild has learned that recipe yet.
- **Looted recipe pop-up**: loot a recipe nobody in the guild knows and every guildmate with the Guild Hall gets a pop-up; click it to open the Gaps tab. Options switch "Tell the guild when you loot a recipe nobody knows".
- **Request pop-up**: a new craft request pops up for the guildmates who can make it (only them); click it to open the Requests tab.
- **Gaps source filter**: a dropdown at the end of the search box on the Gaps tab shows only recipes learned from a Trainer, Vendor, Drop, Quest or Other. Profession counts follow the filter.
- **Change delivery**: on your own active request, a delivery dropdown switches between mail and trade. The crafter gets a chat note.
- New requests pick mail or trade from a dropdown (was a click-to-switch button).

## 0.3.14
- Guild news pop-ups: smaller text that wraps onto a second line, so the whole note shows instead of being cut off.

## 0.3.13
- **Gaps tab covers the whole guild**: each profession's full recipe list is shared with guildmates, so you see recipes nobody knows for every profession anyone in the guild has, not only your own characters' professions.
- **Where to learn it, from the guild**: opening a recipe nobody knows asks guildmates, and one who has read it sends the game's source text and the trainers / vendors they visited.
- **What's New window**: opens once after an update with everything that changed since the version you last saw (out of combat, never on a fresh install). Reopen with `/guildhall news` or What's new on the Options tab.
- Changelog added (this file).

## 0.3.12
- **Version check**: each copy shares its version with the guild; a chat note when a guildmate runs a newer Guild Hall.
- Options: Guild Hall versions list (who runs what); `/guildhall versions`.
- **Mail it**: at a mailbox, the Send Mail tab lists your claimed requests that asked for mail. One click fills in the name and subject and attaches the items; the request is marked done once you send it.

## 0.3.11
- **Materials pop-up** when a crafter claims your request: each reagent as needed (yours), what the crafter has, and what is still short; Mats ready button. Crafters share bags + bank counts for requests they claimed. Reopen with "Crafter's counts" or `/guildhall mats`.
- Requests: choose Mail it to me or Meet to trade (remembered); shown to the crafter.
- **Guild news pop-ups** when a guildmate adds a profession or learns new recipes; click to browse it, drag to move, Options switch.
- Recipes that make Bind on Pickup items are hidden everywhere (search, lists, tooltips, Gaps).

## 0.3.10
- Guildmates' real first and last names: each member's last name now comes from the guild roster (by character ID, or the only member with that first name). Names saved wrong are repaired when the roster loads; names show as "First Last".

## 0.3.9
- **Welcome window** on first login per character: Initialize loads the guild roster and asks guildmates for their crafting data, then a checklist ticks off each crafting profession as it is read and shared. `/guildhall welcome` shows it again.

## 0.3.8
- **Where to learn recipes**: visiting a profession trainer marks the recipes it teaches (trainer, place, skill needed); visiting a vendor marks the recipe items it sells (Waylaid supply quartermasters included).
- Boss drops, trash drops and dungeon quest rewards from the Forever Dungeon Journal addon when it is loaded.
- Gaps list shows Trainer / Vendor / Drop / Quest per recipe.

## 0.3.7
- **Gaps tab**: professions nobody in the guild has, and recipes nobody knows yet, sorted into item types.
- **Options tab**: tooltip names, chat notes, minimap button, how long done requests stay listed, sync now, your characters' professions with a Remove button.
- Dropped professions are removed from the guild list by themselves at login.
- Item names keep their quality color while item data reloads.

## 0.3.6
- Fixed: opening the window for the first time in combat caused a blocked-action error.

## 0.3.5
- Fixed: guild roster names ("Name Realm" with a space) now match, so online dots and cleanup work for everyone.

## 0.3.4
- Fixed: guildmates' crafts were removed a few minutes after syncing. Players now share their character ID and cleanup only removes members it can check.

## 0.3.3
- Minimap left-click opens or closes Crafting, right-click Requests. Escape closes the window.

## 0.3.2
- Fixed: the minimap icon was squashed by a round crop.

## 0.3.0
- Minimap button (drag to move, works on square minimaps, count of requests waiting on you). Button on the profession window that opens the Guild Hall on that profession. New addon list icon.

## 0.2.1
- Professions list on the start page; a profession shows its item types, a type shows its items. Typing searches the whole guild from anywhere.

## 0.2.0
- Browse by item type. **Craft requests**: request an item, crafters claim it, mark mats ready, done or cancel; Requests tab, synced with the guild. Shift-click an item into the search box.

## 0.1.1
- First release: search any item to see who in the guild can craft it, with reagents and have / need counts.
