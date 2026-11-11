#!/bin/zsh
# Copies FastLoot into the WoW Forever AddOns directory. Then /reload in game.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="/Applications/World of Warcraft/_forever_/Interface/AddOns/FastLoot"
mkdir -p "$DST/Data" "$DST/Media"
cp "$SRC/Media/icon.tga" "$DST/Media/icon.tga"
cp "$SRC/Data/DropData.lua" "$DST/Data/DropData.lua"
cp "$SRC/FastLoot.toc" "$SRC/FastLoot.lua" "$SRC/FastLootUI.lua" "$SRC/FastLootDrops.lua" "$SRC/FastLootRolls.lua" "$SRC/FastLootMinimap.lua" "$DST/"
echo "FastLoot installed to $DST. Type /reload in the game."
