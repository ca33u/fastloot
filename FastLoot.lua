--[[
  FastLoot 1.0.0 for WoW Forever (interface 16001).

  The game's own auto loot takes items one by one while the loot window is
  drawn. FastLoot takes them all on LOOT_READY, before the window shows, so
  looting a mob is instant.

  It follows the game's auto loot rule: auto loot on (Esc > Options >
  Controls > Auto Loot) and no modifier, or auto loot off and the auto-loot
  key held (Shift by default). Otherwise the normal loot window opens.

  Items that cannot be taken (bags full, a need/greed roll, a bind-on-pickup
  confirmation) stay in the window as usual.

  /fastloot   turn FastLoot on or off
]]

local FL = {}
_G.FastLoot = FL

local PREFIX = "|cff7fd4ffFastLoot|r "
local THROTTLE = 0.3

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) and true or false
end

local function Bool(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value = pcall(fn, ...)
	if not ok or IsSecret(value) then
		return nil
	end
	return value and true or false
end

-- autoLootArg: LOOT_READY's argument (true when the game is auto looting).
-- When the client does not pass it, use the CVar xor the modifier key.
function FL.ShouldLoot(autoLootArg, cvarOn, modifierDown)
	if autoLootArg ~= nil then
		return autoLootArg and true or false
	end
	return (cvarOn and true or false) ~= (modifierDown and true or false)
end

-- Loots every slot, last to first so indexes stay valid. Returns the count.
function FL.LootAll()
	local okN, n = pcall(GetNumLootItems)
	if not okN or type(n) ~= "number" or IsSecret(n) then
		return 0
	end
	local taken = 0
	for slot = n, 1, -1 do
		if pcall(LootSlot, slot) then
			taken = taken + 1
		end
	end
	return taken
end

local last = -1
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, autoLoot)
	if event == "ADDON_LOADED" then
		if autoLoot == "FastLoot" then
			if type(FastLootDB) ~= "table" then
				FastLootDB = {}
			end
			if FastLootDB.enabled == nil then
				FastLootDB.enabled = true
			end
			frame:UnregisterEvent("ADDON_LOADED")
		end
		return
	end
	if not (FastLootDB and FastLootDB.enabled) then
		return
	end
	local arg = autoLoot
	if IsSecret(arg) then
		arg = nil
	end
	local cvar = Bool(C_CVar and C_CVar.GetCVarBool or GetCVarBool, "autoLootDefault")
	local mod = Bool(IsModifiedClick, "AUTOLOOTTOGGLE")
	if not FL.ShouldLoot(arg, cvar, mod) then
		return
	end
	local now = GetTime()
	if now - last < THROTTLE then
		return
	end
	last = now
	FL.LootAll()
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("LOOT_READY")

SLASH_FASTLOOT1 = "/fastloot"
SlashCmdList.FASTLOOT = function()
	FastLootDB = FastLootDB or {}
	FastLootDB.enabled = not FastLootDB.enabled
	print(PREFIX .. (FastLootDB.enabled and "on" or "off"))
end
