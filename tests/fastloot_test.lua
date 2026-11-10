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

io.write(string.format("%d tests, %d failed\n", total, fails))
os.exit(fails == 0 and 0 or 1)
