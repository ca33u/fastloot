#!/usr/bin/env python3
"""
Builds Data/DropData.lua from the cMaNGOS classic database (GPL-3.0,
https://github.com/cmangos/classic-db, Full_DB/ClassicDB_1_12_1_*.sql).

    python3 -I tools/build_drops.py /path/to/ClassicDB.sql Data/DropData.lua

Loot rules (MaNGOS loot system):
  * ChanceOrQuestChance < 0  -> quest item, drops only while on the quest
  * mincountOrRef < 0        -> reference to reference_loot_template
                                entry = -mincountOrRef, rolled `maxcount` times
                                with ChanceOrQuestChance %
  * groupid > 0              -> exactly one item of the group drops per roll;
                                entries with chance 0 share what is left of 100 %
The result is one "effective" chance per item per creature. Items under
MIN_CHANCE % are left out, and at most MAX_ITEMS items per creature are kept.
"""
import re
import sys

MIN_CHANCE = 0.5
MAX_ITEMS = 16

TABLES = ("creature_template", "creature_loot_template", "reference_loot_template", "item_template")


def parse_values(blob):
    """Yields tuples from "(a,b,'c'),(...)" with MySQL string escapes."""
    i, n = 0, len(blob)
    while i < n:
        if blob[i] != "(":
            i += 1
            continue
        i += 1
        row, cur, in_str = [], [], False
        while i < n:
            c = blob[i]
            if in_str:
                if c == "\\" and i + 1 < n:
                    cur.append(blob[i + 1])
                    i += 2
                    continue
                if c == "'":
                    in_str = False
                else:
                    cur.append(c)
            else:
                if c == "'":
                    in_str = True
                elif c == ",":
                    row.append("".join(cur))
                    cur = []
                elif c == ")":
                    row.append("".join(cur))
                    yield row
                    i += 1
                    break
                else:
                    cur.append(c)
            i += 1


def read_tables(path):
    rows = {t: [] for t in TABLES}
    pat = re.compile(r"^INSERT INTO `(\w+)` VALUES (.*);\s*$")
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not line.startswith("INSERT INTO `"):
                continue
            m = pat.match(line)
            if m and m.group(1) in rows:
                rows[m.group(1)].extend(parse_values(m.group(2)))
    return rows


def roll_table(rows):
    """rows: list of (item, chance, group, minOrRef, maxcount).
    Returns {key: chance%} where key is ("item", id, quest) or ("ref", id, times)."""
    out = {}
    groups = {}
    for item, chance, group, mref, maxc in rows:
        quest = chance < 0
        chance = abs(chance)
        if mref < 0:
            key = ("ref", -mref, max(1, maxc))
        else:
            key = ("item", item, quest)
        if group == 0:
            out[key] = max(out.get(key, 0), chance)
        else:
            groups.setdefault(group, []).append((key, chance))
    for entries in groups.values():
        explicit = sum(c for _, c in entries if c > 0)
        zeros = [k for k, c in entries if c == 0]
        share = max(0.0, 100.0 - explicit) / len(zeros) if zeros else 0
        for key, c in entries:
            out[key] = max(out.get(key, 0), c if c > 0 else share)
    return out


def resolve(table, refs, depth=0):
    """Expands references. Returns {(item, quest): chance%}."""
    result = {}
    for key, chance in table.items():
        if key[0] == "item":
            _, item, quest = key
            k = (item, quest)
            # independent sources: P = 1 - (1-a)(1-b)
            prev = result.get(k, 0) / 100
            result[k] = (1 - (1 - prev) * (1 - chance / 100)) * 100
        elif depth < 4 and key[1] in refs:
            _, ref, times = key
            inner = resolve(refs[key[1]], refs, depth + 1)
            p_ref = chance / 100
            for k, c in inner.items():
                once = p_ref * c / 100
                p = 1 - (1 - once) ** times
                prev = result.get(k, 0) / 100
                result[k] = (1 - (1 - prev) * (1 - p)) * 100
    return result


def main(src, dst):
    rows = read_tables(src)

    def loot_rows(raw):
        by = {}
        for r in raw:
            entry, item = int(r[0]), int(r[1])
            by.setdefault(entry, []).append((item, float(r[2]), int(r[3]), int(r[4]), int(r[5])))
        return {e: roll_table(v) for e, v in by.items()}

    creature_loot = loot_rows(rows["creature_loot_template"])
    refs = loot_rows(rows["reference_loot_template"])

    names = {}
    loot_of = {}
    for r in rows["creature_template"]:
        entry, name, loot_id = int(r[0]), r[1], int(r[56])
        if loot_id:
            loot_of[entry] = loot_id
            names[entry] = name

    out_lines = []
    count_items = 0
    for npc in sorted(loot_of):
        table = creature_loot.get(loot_of[npc])
        if not table:
            continue
        items = resolve(table, refs)
        kept = sorted(((c, item, q) for (item, q), c in items.items() if c >= MIN_CHANCE), reverse=True)[:MAX_ITEMS]
        if not kept:
            continue
        parts = []
        for c, item, q in kept:
            num = ("%.0f" % c) if c >= 10 else ("%.1f" % c)
            parts.append("%d:%s%s" % (item, num, "q" if q else ""))
        count_items += len(parts)
        out_lines.append('[%d]="%s",' % (npc, ";".join(parts)))

    with open(dst, "w", encoding="utf-8") as fh:
        fh.write("-- Generated by tools/build_drops.py from the cMaNGOS classic database\n")
        fh.write("-- (GPL-3.0, github.com/cmangos/classic-db). Do not edit by hand.\n")
        fh.write("-- [npcID] = \"itemID:chance%[q];...\"  q = only while on the quest\n")
        fh.write("FastLootDropData = {\n")
        fh.write("\n".join(out_lines))
        fh.write("\n}\n")
    print("creatures:", len(out_lines), "items:", count_items)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
