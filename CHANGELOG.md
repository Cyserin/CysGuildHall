# Changelog

All notable changes to Cys's Guild Hall, by Cyserin (Cys). Newest first.

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
