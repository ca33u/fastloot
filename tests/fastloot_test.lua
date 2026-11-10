-- Run: lua tests/fastloot_test.lua  (from the repo root)
local handler
local registered = {}
function CreateFrame()
	return {
		SetScript = function(_, _, fn)
			handler = fn
		end,
		RegisterEvent = function(_, e)
			registered[e] = true
		end,
		UnregisterEvent = function(_, e)
			registered[e] = nil
		end,
	}
end
SlashCmdList = {}
local now = 100
function GetTime()
	return now
end
local loot, taken = {}, {}
function GetNumLootItems()
	return #loot
end
function LootSlot(i)
	taken[#taken + 1] = loot[i]
end
local cvar, mod = true, false
C_CVar = { GetCVarBool = function()
	return cvar
end }
function IsModifiedClick()
	return mod
end

local fails, total = 0, 0
local function Check(cond, label)
	total = total + 1
	if not cond then
		fails = fails + 1
	end
	io.write(cond and "ok    " or "FAIL  ", label, "\n")
end

dofile("FastLoot.lua")
local FL = FastLoot

Check(FL.ShouldLoot(true) == true, "LOOT_READY says auto loot")
Check(FL.ShouldLoot(false, true, false) == false, "LOOT_READY says manual")
Check(FL.ShouldLoot(nil, true, false) == true, "cvar on, no modifier")
Check(FL.ShouldLoot(nil, true, true) == false, "cvar on, modifier held: manual")
Check(FL.ShouldLoot(nil, false, true) == true, "cvar off, modifier held: auto")
Check(FL.ShouldLoot(nil, false, false) == false, "cvar off, no modifier: manual")

handler(nil, "ADDON_LOADED", "FastLoot")
Check(FastLootDB.enabled == true, "enabled by default")

loot = { "a", "b", "c" }
handler(nil, "LOOT_READY", true)
Check(#taken == 3 and taken[1] == "c", "takes all slots, last first")

taken = {}
handler(nil, "LOOT_READY", true)
Check(#taken == 0, "second LOOT_READY within 0.3s ignored")

now = now + 1
taken = {}
handler(nil, "LOOT_READY", false)
Check(#taken == 0, "manual loot leaves the window alone")

SlashCmdList.FASTLOOT()
now = now + 1
handler(nil, "LOOT_READY", true)
Check(#taken == 0 and FastLootDB.enabled == false, "/fastloot turns it off")

io.write(string.format("%d tests, %d failed\n", total, fails))
os.exit(fails == 0 and 0 or 1)
