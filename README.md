# Cys's Guild Hall

A guild crafting directory for World of Warcraft Forever, by **Cyserin (Cys)**.

Works for any guild. Every member who runs it shares the recipes they know, so anyone can search an item and see who in the guild can make it.

## Features
- **Search any item or recipe** to see who can craft it, online first, with their skill level. Alts share a line with their main (found from the guild's Alt rank and the note naming the main).
- **Reagents with have / need**: counts from your bags and bank, with a Make -/+ for several crafts.
- **Professions overview**: every guild profession with its number of crafters and best skill; click one to browse its recipes.
- **Craft requests**: ask the guild to make something and pick how you want it (mail it to me, or meet to trade); a crafter claims it, marks the mats ready and done.
- **Materials pop-up**: when a crafter claims your request you see each reagent as needed, (what you have) and what the crafter has, plus what is still short between you two (`/guildhall mats` reopens it).
- **Gaps tab**: professions nobody in the guild has, and recipes nobody knows yet, for every profession anyone in the guild has (full recipe lists are shared, so you don't need the profession yourself). Each shows where to learn it: trainers and vendors visited (Waylaid supply quartermasters included) are marked automatically, boss / quest drops come from the Forever Dungeon Journal addon when you have it, and opening a recipe asks the guild for what a guildmate has read.
- **Raid Prep tab**: officers set guild targets (an item and how many the guild needs). Each target lists the item and the materials from its recipe; crafters claim how many they will make, gatherers claim an amount of a material, and everyone keeps their delivered count up to date, so the guild sees the progress.
- **Options**: tooltip names, chat notes, materials pop-up, guild news pop-ups, minimap button, how long done requests stay listed, and your characters' professions (dropped ones are removed by themselves at login).
- **Mail it**: at a mailbox, the Send Mail tab shows your claimed requests whose requester asked for mail. One click fills in their name and a subject and attaches the crafted items; you press Send, and the request is marked done when it goes out.
- **Version check**: a quiet chat note when a guildmate runs a newer Guild Hall, and who runs which version in Options (`/guildhall versions`).
- **Guild news pop-ups**: a small note when a guildmate adds a profession or learns new recipes (click it to browse that profession).
- **No Bind on Pickup items**: recipes that make BoP items are left out, since a guildmate can't hand them over.
- **Guild crafters on item tooltips** (`/guildhall tooltip` to turn off).
- **Quiet sync**: hidden guild addon messages, throttled, paused in combat. Only shares professions, skill levels, recipe IDs, each profession's full recipe list, where recipes are learned, a crafter's reagent counts for requests they claimed, and raid prep targets and claims.

## Getting started
On your first login a welcome window walks you through setup:
1. Click **Initialize**: loads the guild roster and says hello to guildmates already running the addon, so their crafting data starts coming in.
2. Open each of your crafting professions once. A checklist ticks them off as they are read and shared.
3. Once every profession is read, the addon syncs with the guild and you're all set.

Each of your characters gets the welcome once. `/guildhall welcome` shows it again.

Everyone in the guild needs the addon for their recipes to show up. Data travels as hidden guild addon messages, so a guildmate's recipes arrive when you are both online (anyone who already has them passes them on too).

## Use
- `/guildhall` opens the window; `/guildhall <item>` searches. Minimap button: left click Crafting, right click Requests.
- `/guildhall gaps`, `/guildhall requests`, `/guildhall prep`, `/guildhall options` open those tabs.
- `/guildhall news` (or What's new on the Options tab) shows what changed; it also opens once by itself after an update. Full history: [CHANGELOG.md](CHANGELOG.md).
- `/guildhall versions` lists who runs which version; `/guildhall check` shows what the addon knows; `/guildhall sync` asks the guild for newer data.

## Coming later
Guild bank / bank-alt stock with have / need / missing, roster, calendar sign-ups.

## Feedback
Found a bug or have an idea? Open an issue on GitHub.
