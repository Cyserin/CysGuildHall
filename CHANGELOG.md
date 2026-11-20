# Changelog

All notable changes to Cys's Guild Hall, by Cyserin (Cys). Newest first.

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
