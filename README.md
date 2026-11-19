# Cys's Guild Hall

A guild crafting directory for World of Warcraft Forever, by **Cyserin (Cys)**.

Works for any guild. Every member who runs it shares the recipes they know, so anyone can search an item and see who in the guild can make it.

## Features
- **Search any item or recipe** to see who can craft it, online first, with their skill level.
- **Reagents with have / need**: counts from your bags and bank, with a Make -/+ for several crafts.
- **Professions overview**: every guild profession with its number of crafters and best skill; click one to browse its recipes.
- **Craft requests**: ask the guild to make something; a crafter claims it, marks the mats ready and done.
- **Gaps tab**: professions nobody in the guild has, and recipes nobody knows yet (from your own characters' recipe lists), with where to learn them: trainers and vendors you visit (Waylaid supply quartermasters included) are marked automatically, and boss / quest drops come from the Forever Dungeon Journal addon when you have it.
- **Options**: tooltip names, chat notes, minimap button, how long done requests stay listed, and your characters' professions (dropped ones are removed by themselves at login).
- **Guild crafters on item tooltips** (`/guildhall tooltip` to turn off).
- **Quiet sync**: hidden guild addon messages, throttled, paused in combat. Only shares professions, skill levels and recipe IDs.

## Getting started
On your first login a welcome window walks you through setup:
1. Click **Initialize**: loads the guild roster and says hello to guildmates already running the addon, so their crafting data starts coming in.
2. Open each of your crafting professions once. A checklist ticks them off as they are read and shared.
3. Once every profession is read, the addon syncs with the guild and you're all set.

Each of your characters gets the welcome once. `/guildhall welcome` shows it again.

Everyone in the guild needs the addon for their recipes to show up. Data travels as hidden guild addon messages, so a guildmate's recipes arrive when you are both online (anyone who already has them passes them on too).

## Use
- `/guildhall` opens the window; `/guildhall <item>` searches. Minimap button: left click Crafting, right click Requests.
- `/guildhall gaps`, `/guildhall requests`, `/guildhall options` open those tabs.
- `/guildhall check` shows what the addon knows; `/guildhall sync` asks the guild for newer data.

## Coming later
Guild bank / bank-alt stock with have / need / missing, raid consumable targets, roster, calendar sign-ups.

## Feedback
Found a bug or have an idea? Open an issue on GitHub.
