#!/bin/zsh
# Builds dist/FastLoot-<version>.zip with only what the game needs.
# Your friend unzips it into  World of Warcraft/_forever_/Interface/AddOns
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
VERSION=$(grep -m1 '^## Version:' "$SRC/FastLoot.toc" | sed 's/## Version: *//' | tr -d '\r')
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/FastLoot/Data" "$STAGE/FastLoot/Media" "$SRC/dist"
cp "$SRC/Media/icon.tga" "$SRC/Media/minimap.tga" "$STAGE/FastLoot/Media/"
cp "$SRC"/FastLoot.toc "$SRC"/FastLoot*.lua "$SRC/README.md" "$SRC/README.ru.md" "$SRC/LICENSE" "$STAGE/FastLoot/"
cp "$SRC/Data/DropData.lua" "$STAGE/FastLoot/Data/"
OUT="$SRC/dist/FastLoot-$VERSION.zip"
rm -f "$OUT"
(cd "$STAGE" && zip -qr "$OUT" FastLoot -x '*.DS_Store')
rm -rf "$STAGE"
echo "$OUT"
