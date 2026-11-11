English · [Русский](README.ru.md)

# FastLoot

Fast looting with a filter for **World of Warcraft: Forever** (Interface 16001). Made by **addicted** ([addicted.sh](https://addicted.sh)).

## Two modes

**Normal** (default). When the game auto loots, FastLoot grabs everything at once on the `LOOT_READY` event, before the loot window even appears.

**Filter** (`/fastloot filter`). FastLoot decides for each item whether to take it. The game's built-in auto loot takes everything and an addon can't stop it, so in filter mode FastLoot turns the game's auto loot off and turns it back on when you leave filter mode. Hold **Shift** while looting to take everything as usual.

## What the filter takes (in order)

1. "Never" list: don't take (`/fastloot ignore <item>`).
2. "Always" list: take (`/fastloot always <item>`).
3. Money and currency: take.
4. Quest items: take (`/fastloot quest`).
5. Materials for your professions and recipes: take (`/fastloot prof`). The addon detects your professions by itself: Skinning and Leatherworking → leather, Herbalism and Alchemy → herbs, Mining and Blacksmithing → ore and stone, Tailoring and First Aid → cloth, Cooking and Fishing → meat and fish, Enchanting → enchanting materials, Engineering → metal and parts.
6. Quality at or above the threshold: take (`/fastloot quality 2`, 2 = green and better).
7. Grey and white items: only if turned on (`/fastloot grey`, `/fastloot white`).

Everything else stays on the corpse, and the loot window closes by itself (`/fastloot close` turns that off). **Important for skinning:** you can't skin a corpse that still has loot on it. If that gets in the way, turn on `/fastloot white`.

`<item>` is an item link (Shift-click the item into chat), an ID or a name.

## Window

`/fastloot` or the round bag button by the minimap (right-click the button to switch modes, drag it to move it around the minimap). The window title holds the main **FastLoot on** switch. Below it, from top to bottom:

1. **HOW TO LOOT**: how to loot, one of two: **Take everything** or **Filter by rules below** (take only what the rules below allow).
2. **FILTER TAKES**: what to take in filter mode: quest items, profession materials, grey, white, any quality from the threshold up (click the button to change the threshold), and "leave the rest and close the loot window". While "Take everything" is selected, this block is faded: these checkboxes have no effect.
3. **EXTRAS**: mob drops in the tooltip and the rolls panel. They work in both modes.
4. **ITEM LISTS**: two "banks", **NEVER LOOT** and **ALWAYS LOOT**, for filter mode. Drag an item from your bags into the one you want; right-click an icon to remove it. Esc closes the window.

## Mob drops in the tooltip

Hover over a mob: a line "Drops: N items, you killed K (Shift)" appears under the standard tooltip. **Hold Shift** and the line expands into a list, most common items first:

```
[icon] Item name     38%   2/5
```

- **38%** is the chance from the classic database (cMaNGOS classic-db, Classic 1.12 data). Drops may have changed in Forever.
- **2/5** is your own statistic: the item dropped 2 times in 5 kills. This is the real chance in Forever, and it builds up by itself.
- **(quest)** means it only drops while you're on the quest.
- Items that dropped for you but aren't in the database are added to the list too.

A kill counts when a mob that you or your group can loot dies on a nameplate or as your target. Items are counted when you open the corpse. Statistics are shared across the account (`FastLootDB.stats`). To turn the tooltip off: `/fastloot drops` or the "Mob drops tip" checkbox in the window.

Data: `Data/DropData.lua` (about 360 KB, 4268 mobs) is built by the `tools/build_drops.py` script from the cMaNGOS database (GPL-3.0, github.com/cmangos/classic-db). Chances are calculated by MaNGOS rules: item groups, references to shared tables, quest items. The list includes items with a chance of 0.5% or more, up to 16 per mob. To rebuild:

```
python3 -I tools/build_drops.py ClassicDB_1_12_1_z2815.sql Data/DropData.lua
```

## Group rolls

The **ROLLS** panel (right of screen center by default, can always be dragged with the mouse, position is saved) shows items being rolled on in your group. Under each one: who picked what (Need / Greed / Disenchant / Pass icons) and what number they rolled. The winner is at the top, in gold with a star. While a roll is in progress, a timer bar runs under the item. After the roll ends the item stays for 30 seconds; right-click the panel to clear it right away. The data comes from the system roll messages in the loot chat, and the patterns come from the client's own strings, so it works in any language.

**Is the item for you**: shown to the right of the item in the panel and as a colored border around the standard roll window:

| Label | Meaning |
|---|---|
| green **UPGRADE +6** | you can wear it, and its item level is higher than what you have equipped in that slot (or the slot is empty) |
| white **you can use** | you can wear it, but it's not higher than what you have equipped |
| yellow **needs level 35** | you'll be able to wear it later |
| red **can't use** | your character doesn't have the proficiency for this armor or weapon type |

Proficiency is checked against the skills your character has actually learned (Plate Mail, One-Handed Swords and so on), so both trainers and Forever's class changes are taken into account. Item level is a rough measure: stats are not weighed; for an accurate comparison use the GearQuest tooltip.

## Commands (`/fastloot` or `/fl`)

| Command | What it does |
|---|---|
| `/fastloot` | open the window |
| `/fastloot on`, `off` | turn FastLoot on/off |
| `/fastloot filter` | filter mode on/off |
| `/fastloot ignore <item>` | never take |
| `/fastloot always <item>` | always take |
| `/fastloot remove <item>` | remove from both lists |
| `/fastloot list` | show the lists |
| `/fastloot quest`, `prof`, `grey`, `white`, `close` | toggle a rule |
| `/fastloot quality <0-5>` | take this quality and better (0 grey, 1 white, 2 green, 3 blue, 4 epic) |
| `/fastloot drops` | mob drops in the tooltip on/off |
| `/fastloot rolls` | rolls panel and "for you" labels on/off |
| `/fastloot rollsmove` | show an empty panel so you can place it in advance (the panel can always be moved with the mouse anyway) |
| `/fastloot rollstest` | show a sample roll |
| `/fastloot minimap` | show/hide the minimap button |
| `/fastloot status` | current settings and detected professions |

FastLoot doesn't touch items that are up for a Need/Greed roll or that ask for a Bind on Pickup confirmation.

Installation: `./install.sh`, then `/reload`. Tests: `lua tests/fastloot_test.lua`.

## Sharing

`./package.sh` builds `dist/FastLoot-<version>.zip` with only the game files (no tests or tools). For a friend:

1. Close the game (or log out to character select afterwards).
2. Unzip the archive into `World of Warcraft/_forever_/Interface/AddOns` so that you get an `AddOns/FastLoot` folder with `FastLoot.toc` inside (not `AddOns/FastLoot/FastLoot`).
3. Log in and check under "AddOns" that FastLoot is enabled.

License: GPL-3.0 (`LICENSE` file), because the drop database `Data/DropData.lua` is derived from cMaNGOS classic-db under GPL-3.0. You're free to share and publish it; the source (Lua) is included in the archive.

© 2026 addicted · [addicted.sh](https://addicted.sh)
