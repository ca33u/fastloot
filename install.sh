#!/bin/zsh
# Copies FastLoot into the WoW Forever AddOns directory. Then /reload in game.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DST="/Applications/World of Warcraft/_forever_/Interface/AddOns/FastLoot"
mkdir -p "$DST"
cp "$SRC/FastLoot.toc" "$SRC/FastLoot.lua" "$DST/"
echo "FastLoot installed to $DST. Type /reload in the game."
