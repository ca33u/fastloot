-- Run: lua tests/fastloot_test.lua  (from the repo root)
local handler
function CreateFrame()
	return {
		SetScript = function(_, _, fn)
			handler = fn
		end,
		RegisterEvent = function() end,
		UnregisterEvent = function() end,
	}
end
SlashCmdList = {}
local now = 100
function GetTime()
	return now
end
local timers = {}
C_Timer = { After = function(_, fn)
	timers[#timers + 1] = fn
end }
local function RunTimers()
	for _, fn in ipairs(timers) do
		fn()
	end
	timers = {}
end
local closed = 0
function CloseLoot()
	closed = closed + 1
end

-- Loot window: list of slots { kind, id, name, quality, quest, classID, subclassID }
local loot, taken = {}, {}
function GetNumLootItems()
	return #loot
end
function LootSlot(i)
	taken[#taken + 1] = loot[i].name
end
Enum = { LootSlotType = { Item = 1, Money = 2, Currency = 3 } }
function GetLootSlotType(i)
	local k = loot[i].kind
	return k == "money" and 2 or k == "currency" and 3 or 1
end
function GetLootSlotInfo(i)
	local s = loot[i]
	return 1, s.name, 1, nil, s.quality, false, s.quest
end
function GetLootSlotLink(i)
	local s = loot[i]
	return s.id and ("|cff|Hitem:" .. s.id .. "::|h[" .. s.name .. "]|h|r") or nil
end
local ITEMS = {}
C_Item = { GetItemInfoInstant = function(id)
	local it = ITEMS[id] or {}
	return id, nil, nil, nil, nil, it.classID, it.subclassID
end }
local cvars = { autoLootDefault = "1" }
C_CVar = {
	GetCVarBool = function(n)
		return cvars[n] == "1"
	end,
	SetCVar = function(n, v)
		cvars[n] = v
	end,
}
local mod = false
function IsModifiedClick()
	return mod
end
local skills = { { "Professions", true }, { "Skinning", false }, { "Herbalism", false }, { "Defense", false } }
function GetNumSkillLines()
	return #skills
end
function GetSkillLineInfo(i)
	return skills[i][1], skills[i][2]
end

local fails, total = 0, 0
local function Check(cond, label)
	total = total + 1
	if not cond then
		fails = fails + 1
	end
	io.write(cond and "ok    " or "FAIL  ", label, "\n")
end
local function names(list)
	table.sort(list)
	return table.concat(list, ",")
end

dofile("FastLoot.lua")
local FL = FastLoot

-- Plain mode (unchanged behaviour)
Check(FL.ShouldLoot(true) == true, "LOOT_READY says auto loot")
Check(FL.ShouldLoot(nil, true, true) == false, "cvar on, modifier held: manual")
Check(FL.ShouldLoot(nil, false, true) == true, "cvar off, modifier held: auto")

handler(nil, "ADDON_LOADED", "FastLoot")
handler(nil, "PLAYER_LOGIN")
Check(FastLootDB.enabled == true and FastLootDB.filter == false, "defaults: on, plain mode")

loot = { { name = "a" }, { name = "b" }, { name = "c" } }
handler(nil, "LOOT_READY", true)
Check(#taken == 3 and taken[1] == "c", "plain: takes all slots, last first")
taken = {}
handler(nil, "LOOT_READY", true)
Check(#taken == 0, "plain: second LOOT_READY within 0.3s ignored")

-- Professions
local subs = FL.SubclassesFor(FL.KnownProfessions())
Check(subs[6] and subs[9] and not subs[5], "skinning+herbalism -> leather and herbs, not cloth")
Check(FL.SubclassesFor({ "Горное дело" })[7], "Russian profession names work")

-- Decide
local db = FL.InitDB()
local function D(slot)
	local take, why = FL.Decide(slot, db, subs)
	return take, why
end
Check(D({ kind = "money" }) == true, "money taken")
Check(D({ kind = "item", name = "Quest Thing", quality = 1, quest = true }) == true, "quest flag taken")
Check(D({ kind = "item", name = "Head", quality = 1, classID = 12 }) == true, "quest class taken")
Check(D({ kind = "item", name = "Peacebloom", quality = 1, classID = 7, subclassID = 9 }) == true, "herb taken for herbalist")
Check(D({ kind = "item", name = "Linen Cloth", quality = 1, classID = 7, subclassID = 5 }) == false, "cloth skipped without tailoring")
Check(D({ kind = "item", name = "Green Sword", quality = 2 }) == true, "green taken")
Check(D({ kind = "item", name = "Broken Fang", quality = 0 }) == false, "grey skipped by default")
db.grey = true
Check(D({ kind = "item", name = "Broken Fang", quality = 0 }) == true, "grey taken when on")
db.grey = false
db.ignore[2589] = "Linen Cloth"
db.always["linen cloth"] = "Linen Cloth"
Check(select(2, D({ kind = "item", id = 2589, name = "Linen Cloth", quality = 1 })) == "ignore list", "ignore list beats always list")
db.ignore[2589] = nil
Check(select(2, D({ kind = "item", id = 2589, name = "Linen Cloth", quality = 1 })) == "always list", "always list by name")
db.always["linen cloth"] = nil
db.ignore[999] = "Epic Sword"
Check(D({ kind = "item", id = 999, name = "Epic Sword", quality = 4 }) == false, "ignore list beats quality")
db.ignore[999] = nil
Check(D({ kind = "item", name = "x", quality = 3, locked = true }) == false, "locked (roll) skipped")

-- ParseItem
local key, label = FL.ParseItem("|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r")
Check(key == 2589 and label == "Linen Cloth", "parse item link")
Check(FL.ParseItem("2589") == 2589, "parse item ID")
Check(FL.ParseItem("  Linen Cloth ") == "linen cloth", "parse name")

-- Filter mode end to end
SlashCmdList.FASTLOOT("filter")
Check(FastLootDB.filter and cvars.autoLootDefault == "0", "filter on turns game auto loot off")
ITEMS[2589] = { classID = 7, subclassID = 5 }
ITEMS[765] = { classID = 7, subclassID = 9 }
ITEMS[5] = { classID = 12 }
loot = {
	{ kind = "money", name = "12 copper" },
	{ id = 2589, name = "Linen Cloth", quality = 1 },
	{ id = 765, name = "Silverleaf", quality = 1 },
	{ id = 5, name = "Gnoll Paw", quality = 1 },
	{ id = 7, name = "Broken Fang", quality = 0 },
}
now = now + 1
taken, closed = {}, 0
handler(nil, "LOOT_READY", false)
RunTimers()
Check(names(taken) == "12 copper,Gnoll Paw,Silverleaf", "filter: money, quest item and herb taken; got " .. names(taken))
Check(closed == 1, "filter: window closed with skipped items left")

now = now + 1
taken = {}
mod = true
handler(nil, "LOOT_READY", false)
Check(#taken == 5, "filter: Shift takes everything")
mod = false

SlashCmdList.FASTLOOT("ignore |cffffffff|Hitem:765::::::::|h[Silverleaf]|h|r")
now = now + 1
taken = {}
handler(nil, "LOOT_READY", false)
Check(names(taken) == "12 copper,Gnoll Paw", "filter: ignored herb left behind")

SlashCmdList.FASTLOOT("filter")
Check(not FastLootDB.filter and cvars.autoLootDefault == "1", "filter off restores game auto loot")

SlashCmdList.FASTLOOT("off")
now = now + 1
taken = {}
handler(nil, "LOOT_READY", true)
Check(#taken == 0, "/fastloot off does nothing")

-- Cursor drag into a list
local cursor
function GetCursorInfo()
	if cursor then
		return "item", cursor, "|cffffffff|Hitem:" .. cursor .. "::|h[Thing " .. cursor .. "]|h|r"
	end
end
function ClearCursor()
	cursor = nil
end
FastLootDB.always[42] = "Thing 42"
cursor = 42
Check(FL.AddFromCursor("ignore") == "Thing 42", "drag adds the cursor item")
Check(FastLootDB.ignore[42] == "Thing 42" and FastLootDB.always[42] == nil, "drag moves it off the other list")
Check(cursor == nil, "cursor cleared after the drop")
Check(FL.AddFromCursor("ignore") == nil, "empty cursor adds nothing")
FL.RemoveFromList(42)
Check(FastLootDB.ignore[42] == nil, "remove takes it off")

-- The window file loads and opens on generic widget stubs.
local function Stub()
	return setmetatable({}, { __index = function()
		return function()
			return Stub()
		end
	end })
end
CreateFrame = function()
	return Stub()
end
UIParent, GameTooltip, UISpecialFrames = Stub(), Stub(), {}
GameTooltip_Hide = function() end
local okUI, errUI = pcall(dofile, "FastLootUI.lua")
Check(okUI, "window file loads " .. tostring(errUI or ""))
Check(type(FL.ToggleWindow) == "function", "window toggle exists")

-- Mob drops: data file, parsing, merging with your stats
TooltipDataProcessor, Enum.TooltipDataType = nil, nil
GameTooltip = Stub()
local okData = pcall(dofile, "Data/DropData.lua")
Check(okData and type(FastLootDropData) == "table", "drop data loads")
Check(FastLootDropData[2559] ~= nil, "Highland Lurker (2559) has drops")
local okDrops, errDrops = pcall(dofile, "FastLootDrops.lua")
Check(okDrops, "drops module loads " .. tostring(errDrops or ""))

Check(FL.NpcIDFromGUID("Creature-0-4372-0-1001-2559-00004A1B2C") == 2559, "npc id from creature GUID")
Check(FL.NpcIDFromGUID("Player-91-0ABCDEF") == nil, "player GUID is not an npc")
Check(FL.NpcIDFromGUID(nil) == nil, "nil GUID")

local parsed = FL.ParseDrops("3685:51;4512:33q;1711:3.9")
Check(#parsed == 3 and parsed[2].quest and parsed[3].chance == 3.9, "parse drop string")

local data = { [7] = "100:50;200:5q" }
local stats = { [7] = { k = 4, i = { [200] = 1, [300] = 3 } } }
local rows, kills = FL.DropRows(7, data, stats)
Check(kills == 4 and #rows == 3, "db rows merged with your stats")
Check(rows[1].item == 300 and rows[1].seen == 3, "your-only item sorted by your rate (75%)")
Check(rows[2].item == 100 and rows[3].item == 200 and rows[3].seen == 1 and rows[3].quest, "db items keep chance, quest flag and your count")

FastLootDB.stats = {}
FL.CountKill("g1", 7)
FL.CountKill("g1", 7)
Check(FastLootDB.stats[7].k == 1, "a kill counts once per mob")
FL.CountItem("g2", 7, 100)
FL.CountItem("g2", 7, 100)
Check(FastLootDB.stats[7].k == 2 and FastLootDB.stats[7].i[100] == 1, "looting an uncounted corpse counts the kill, items once")

loot = { { id = 555, name = "Fang" } }
function GetLootSourceInfo()
	return "Creature-0-1-0-1-2559-0000000001", 1
end
FL.RecordLoot()
Check(FastLootDB.stats[2559] and FastLootDB.stats[2559].i[555] == 1, "loot window recorded for the mob")

-- Roll results: English client strings
LOOT_ROLL_NEED = "%s has selected Need for: %s"
LOOT_ROLL_GREED = "%s has selected Greed for: %s"
LOOT_ROLL_PASSED = "%s passed on: %s"
LOOT_ROLL_NEED_SELF = "You have selected Need for: %s"
LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s"
LOOT_ROLL_ROLLED_GREED = "Greed Roll - %d for %s by %s"
LOOT_ROLL_WON = "%s won: %s"
LOOT_ROLL_YOU_WON = "You won: %s"
LOOT_ROLL_ALL_PASSED = "Everyone passed on: %s"
local okRolls, errRolls = pcall(dofile, "FastLootRolls.lua")
Check(okRolls, "rolls module loads " .. tostring(errRolls or ""))
local R = FL.Rolls

local pat, order = R.FormatToPattern("Need Roll - %d for %s by %s")
Check(("Need Roll - 87 for [Boots] by Milk"):match(pat) == "87", "format to pattern escapes '-' and captures numbers")
pat, order = R.FormatToPattern("%2$s gewinnt: %1$s")
Check(order[1] == 2 and order[2] == 1, "positional arguments keep their order")

local link = "|cff1eff00|Hitem:2232::::::::|h[Dark Runner Boots]|h|r"
local ev = R.ParseMessage("Milk has selected Greed for: " .. link, "Saz")
Check(ev and ev.kind == "choice" and ev.choice == "greed" and ev.player == "Milk" and ev.item == link, "parse greed choice")
ev = R.ParseMessage("Need Roll - 87 for " .. link .. " by Saz", "Saz")
Check(ev and ev.kind == "roll" and ev.roll == 87 and ev.player == "Saz" and ev.item == link, "parse need roll")
ev = R.ParseMessage("You have selected Need for: " .. link, "Saz")
Check(ev and ev.player == "Saz" and ev.choice == "need", "parse own choice")
ev = R.ParseMessage("Everyone passed on: " .. link, "Saz")
Check(ev and ev.kind == "allpass", "parse all passed")
Check(R.ParseMessage("You receive loot: " .. link, "Saz") == nil, "ordinary loot line ignored")

R.items = {}
local t = 1000
for _, msg in ipairs({
	"Milk has selected Greed for: " .. link,
	"You have selected Need for: " .. link,
	"Cirilha passed on: " .. link,
	"Need Roll - 87 for " .. link .. " by Saz",
	"Greed Roll - 54 for " .. link .. " by Milk",
	"You won: " .. link,
}) do
	R.Apply(R.ParseMessage(msg, "Saz"), t)
end
Check(#R.items == 1 and R.items[1].done and R.items[1].winner == "Saz", "one item, done, you won")
local sorted = R.Sorted(R.items[1])
Check(sorted[1].name == "Saz" and sorted[1].roll == 87 and sorted[2].name == "Milk" and sorted[3].choice == "pass", "winner first, then greed, then pass")
R.Prune(t + 61)
Check(#R.items == 0, "finished roll disappears after 60 s")

-- Is it for you? (paladin, level 30, knows mail, shields, 1h swords; not plate yet)
local known = { [8737] = true, [9116] = true, [201] = true, [9077] = true, [9078] = true }
local me = {
	level = 30, class = "PALADIN",
	knows = function(id)
		return known[id] or false
	end,
	equipped = function(slot)
		return ({ [8] = 25, [16] = 28, [11] = 20, [12] = 30 })[slot]
	end,
}
local J = R.Judge
Check(J({ classID = 4, subclassID = 3, equipLoc = "INVTYPE_FEET", minLevel = 25, ilvl = 31 }, me) == "upgrade", "mail boots ilvl 31 over 25: upgrade")
Check(select(2, J({ classID = 4, subclassID = 3, equipLoc = "INVTYPE_FEET", minLevel = 25, ilvl = 31 }, me)) == 6, "upgrade by 6 item levels")
Check(J({ classID = 4, subclassID = 4, equipLoc = "INVTYPE_FEET", minLevel = 40, ilvl = 45 }, me) == "unusable", "plate before training: can't use")
Check(J({ classID = 2, subclassID = 15, equipLoc = "INVTYPE_WEAPON", minLevel = 20, ilvl = 30 }, me) == "unusable", "dagger: can't use")
Check(J({ classID = 4, subclassID = 3, equipLoc = "INVTYPE_HEAD", minLevel = 35, ilvl = 40 }, me) == "level", "mail helm for level 35: later")
Check(J({ classID = 4, subclassID = 1, equipLoc = "INVTYPE_CLOAK", minLevel = 20, ilvl = 20 }, me) == "upgrade", "cloak into an empty slot: upgrade")
Check(J({ classID = 4, subclassID = 0, equipLoc = "INVTYPE_FINGER", minLevel = 20, ilvl = 25 }, me) == "upgrade", "ring beats the weaker of two rings")
Check(J({ classID = 4, subclassID = 3, equipLoc = "INVTYPE_FEET", minLevel = 20, ilvl = 22 }, me) == "usable", "weaker boots: usable, not an upgrade")
Check(J({ classID = 4, subclassID = 8, equipLoc = "INVTYPE_RELIC", minLevel = 20, ilvl = 30 }, me) == "unusable", "druid idol: can't use")
Check(J({ classID = 0, subclassID = 0, equipLoc = "", ilvl = 5 }, me) == nil, "potion: no verdict")

io.write(string.format("%d tests, %d failed\n", total, fails))
os.exit(fails == 0 and 0 or 1)
