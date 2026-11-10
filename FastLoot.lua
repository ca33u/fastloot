--[[
  FastLoot 1.1.0 for WoW Forever (interface 16001).

  Plain mode (default): when the game auto loots, FastLoot takes every item
  on LOOT_READY, before the loot window is drawn, so looting is instant.

  Filter mode (/fastloot filter): FastLoot decides item by item. The game's
  own auto loot takes everything and cannot be stopped by an addon, so filter
  mode turns the game's auto loot off (and puts it back when you leave
  filter mode). Holding Shift while looting then takes everything, as usual.

  What filter mode takes, in this order:
    1. your "never" list   -> skip   (/fastloot ignore <item>)
    2. your "always" list  -> take   (/fastloot always <item>)
    3. money and currency  -> take
    4. quest items         -> take   (/fastloot quest)
    5. materials for your professions -> take   (/fastloot prof)
    6. quality at or above the threshold -> take (/fastloot quality 2 = green)
    7. grey / white items  -> only if turned on  (/fastloot grey, /fastloot white)
  Everything else stays on the corpse; the loot window closes on its own
  (/fastloot close turns that off). A corpse with loot left on it cannot be
  skinned, so skinners may want /fastloot white on.

  <item> is a shift-clicked item link, an item ID, or a name.
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

local function Print(msg)
	print(PREFIX .. msg)
end

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------

local DEFAULTS = {
	enabled = true,
	filter = false,
	close = true,
	quest = true,
	prof = true,
	grey = false,
	white = false,
	minQuality = 2, -- 0 grey, 1 white, 2 green, 3 blue, 4 epic
	drops = true, -- drop list in mob tooltips (FastLootDrops.lua)
	rolls = true, -- roll results panel and "for you" frames (FastLootRolls.lua)
}

function FL.InitDB()
	if type(FastLootDB) ~= "table" then
		FastLootDB = {}
	end
	for k, v in pairs(DEFAULTS) do
		if FastLootDB[k] == nil then
			FastLootDB[k] = v
		end
	end
	FastLootDB.ignore = type(FastLootDB.ignore) == "table" and FastLootDB.ignore or {}
	FastLootDB.always = type(FastLootDB.always) == "table" and FastLootDB.always or {}
	return FastLootDB
end

------------------------------------------------------------------------
-- Professions -> trade goods subclasses (item class 7)
------------------------------------------------------------------------

local CLASS_TRADEGOODS, CLASS_RECIPE, CLASS_QUEST = 7, 9, 12
local SUB = { parts = 1, explosives = 2, devices = 3, cloth = 5, leather = 6, metal = 7, cooking = 8, herb = 9, elemental = 10, enchanting = 12 }

FL.PROFESSION_SUBCLASSES = {
	["tailoring"] = { SUB.cloth },
	["first aid"] = { SUB.cloth },
	["leatherworking"] = { SUB.leather },
	["skinning"] = { SUB.leather },
	["mining"] = { SUB.metal, SUB.elemental },
	["blacksmithing"] = { SUB.metal },
	["engineering"] = { SUB.metal, SUB.parts, SUB.explosives, SUB.devices },
	["herbalism"] = { SUB.herb },
	["alchemy"] = { SUB.herb, SUB.elemental },
	["enchanting"] = { SUB.enchanting },
	["cooking"] = { SUB.cooking },
	["fishing"] = { SUB.cooking },
	-- Russian client names, as the client writes them (string.lower does not
	-- lowercase Cyrillic, so these keys are matched exactly)
	["Портняжное дело"] = { SUB.cloth },
	["Первая помощь"] = { SUB.cloth },
	["Кожевничество"] = { SUB.leather },
	["Снятие шкур"] = { SUB.leather },
	["Горное дело"] = { SUB.metal, SUB.elemental },
	["Кузнечное дело"] = { SUB.metal },
	["Инженерное дело"] = { SUB.metal, SUB.parts, SUB.explosives, SUB.devices },
	["Травничество"] = { SUB.herb },
	["Алхимия"] = { SUB.herb, SUB.elemental },
	["Наложение чар"] = { SUB.enchanting },
	["Кулинария"] = { SUB.cooking },
	["Рыбная ловля"] = { SUB.cooking },
}

-- names: list of profession names -> set of trade goods subclasses
function FL.SubclassesFor(names)
	local set = {}
	for _, name in ipairs(names) do
		local list = FL.PROFESSION_SUBCLASSES[name] or FL.PROFESSION_SUBCLASSES[string.lower(name)]
		if list then
			for _, sub in ipairs(list) do
				set[sub] = true
			end
		end
	end
	return set
end

function FL.KnownProfessions()
	local names = {}
	local okN, n = pcall(GetNumSkillLines)
	if not okN or type(n) ~= "number" or IsSecret(n) then
		return names
	end
	for i = 1, math.min(n, 80) do
		local ok, name, isHeader = pcall(GetSkillLineInfo, i)
		if ok and type(name) == "string" and not IsSecret(name) and not isHeader then
			if FL.PROFESSION_SUBCLASSES[name] or FL.PROFESSION_SUBCLASSES[string.lower(name)] then
				names[#names + 1] = name
			end
		end
	end
	return names
end

------------------------------------------------------------------------
-- The decision (pure, tested in tests/fastloot_test.lua)
------------------------------------------------------------------------

-- slot: { kind = "item"|"money"|"currency", id, name, quality, quest,
--         classID, subclassID, locked }
-- Returns take (bool), reason (string).
function FL.Decide(slot, db, profSubs)
	if slot.locked then
		return false, "locked"
	end
	if slot.kind == "money" or slot.kind == "currency" then
		return true, "money"
	end
	local nameKey = slot.name and string.lower(slot.name)
	if (slot.id and db.ignore[slot.id]) or (nameKey and db.ignore[nameKey]) then
		return false, "ignore list"
	end
	if (slot.id and db.always[slot.id]) or (nameKey and db.always[nameKey]) then
		return true, "always list"
	end
	if db.quest and (slot.quest or slot.classID == CLASS_QUEST) then
		return true, "quest"
	end
	if db.prof and slot.classID == CLASS_TRADEGOODS and slot.subclassID and profSubs[slot.subclassID] then
		return true, "profession"
	end
	if db.prof and slot.classID == CLASS_RECIPE then
		return true, "recipe"
	end
	local q = slot.quality
	if type(q) == "number" then
		if q >= (db.minQuality or 2) then
			return true, "quality"
		end
		if q == 0 and db.grey then
			return true, "grey"
		end
		if q == 1 and db.white then
			return true, "white"
		end
	end
	return false, "filtered"
end

-- autoLootArg: LOOT_READY's argument (true when the game is auto looting).
-- When the client does not pass it, use the CVar xor the modifier key.
function FL.ShouldLoot(autoLootArg, cvarOn, modifierDown)
	if autoLootArg ~= nil then
		return autoLootArg and true or false
	end
	return (cvarOn and true or false) ~= (modifierDown and true or false)
end

------------------------------------------------------------------------
-- Reading the loot window
------------------------------------------------------------------------

local function ItemIDFromLink(link)
	if type(link) ~= "string" or IsSecret(link) then
		return nil
	end
	local id = link:match("item:(%d+)")
	return id and tonumber(id) or nil
end

local function SlotKind(slot)
	local ok, t = pcall(GetLootSlotType, slot)
	if not ok or IsSecret(t) then
		return "item"
	end
	local E = Enum and Enum.LootSlotType
	if t == (E and E.Money or 2) then
		return "money"
	end
	if t == (E and E.Currency or 3) then
		return "currency"
	end
	return "item"
end

function FL.ReadSlot(slot)
	local info = { kind = SlotKind(slot) }
	local ok, _, name, _, _, quality, locked, isQuest = pcall(GetLootSlotInfo, slot)
	if ok then
		info.name = not IsSecret(name) and name or nil
		info.quality = not IsSecret(quality) and quality or nil
		info.locked = not IsSecret(locked) and locked or nil
		info.quest = not IsSecret(isQuest) and isQuest or nil
	end
	local okL, link = pcall(GetLootSlotLink, slot)
	if okL then
		info.id = ItemIDFromLink(link)
	end
	if info.id then
		local getInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
		local okI, _, _, _, _, _, classID, subclassID = pcall(getInstant, info.id)
		if okI then
			info.classID = not IsSecret(classID) and classID or nil
			info.subclassID = not IsSecret(subclassID) and subclassID or nil
		end
	end
	return info
end

------------------------------------------------------------------------
-- Looting
------------------------------------------------------------------------

local function NumSlots()
	local okN, n = pcall(GetNumLootItems)
	if not okN or type(n) ~= "number" or IsSecret(n) then
		return 0
	end
	return n
end

-- Loots every slot, last to first so indexes stay valid. Returns the count.
function FL.LootAll()
	local taken = 0
	for slot = NumSlots(), 1, -1 do
		if pcall(LootSlot, slot) then
			taken = taken + 1
		end
	end
	return taken
end

-- Returns taken, skipped.
function FL.LootFiltered(db, profSubs)
	local taken, skipped = 0, 0
	for slot = NumSlots(), 1, -1 do
		local take = FL.Decide(FL.ReadSlot(slot), db, profSubs)
		if take then
			if pcall(LootSlot, slot) then
				taken = taken + 1
			end
		else
			skipped = skipped + 1
		end
	end
	return taken, skipped
end

local profSubs = {}
local function RefreshProfessions()
	profSubs = FL.SubclassesFor(FL.KnownProfessions())
end

local function SetGameAutoLoot(on)
	local set = C_CVar and C_CVar.SetCVar or SetCVar
	pcall(set, "autoLootDefault", on and "1" or "0")
end

local function GameAutoLoot()
	return Bool(C_CVar and C_CVar.GetCVarBool or GetCVarBool, "autoLootDefault")
end

function FL.SetFilter(on)
	local db = FL.InitDB()
	if on == db.filter then
		return
	end
	db.filter = on
	if on then
		db.savedAutoLoot = GameAutoLoot()
		SetGameAutoLoot(false)
	else
		SetGameAutoLoot(db.savedAutoLoot ~= false)
		db.savedAutoLoot = nil
	end
end

local last = -1
local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, arg)
	if event == "ADDON_LOADED" then
		if arg == "FastLoot" then
			FL.InitDB()
			frame:UnregisterEvent("ADDON_LOADED")
		end
		return
	end
	if event == "PLAYER_LOGIN" or event == "SKILL_LINES_CHANGED" then
		RefreshProfessions()
		local db = FastLootDB
		if event == "PLAYER_LOGIN" and db and db.enabled and db.filter and GameAutoLoot() then
			SetGameAutoLoot(false) -- something turned it back on
		end
		return
	end
	-- Drop statistics read the slots before anything is taken.
	if FL.RecordLoot then
		pcall(FL.RecordLoot)
	end
	local db = FastLootDB
	if not (db and db.enabled) then
		return
	end
	local autoArg = arg
	if IsSecret(autoArg) then
		autoArg = nil
	end
	local now = GetTime()
	if now - last < THROTTLE then
		return
	end
	if db.filter then
		-- Shift (the auto-loot key) means "take everything": the game does it.
		local mod = Bool(IsModifiedClick, "AUTOLOOTTOGGLE")
		if autoArg == true or mod then
			last = now
			FL.LootAll()
			return
		end
		last = now
		local _, skipped = FL.LootFiltered(db, profSubs)
		if skipped > 0 and db.close then
			C_Timer.After(0.1, function()
				pcall(CloseLoot)
			end)
		end
		return
	end
	local cvar = GameAutoLoot()
	local mod = Bool(IsModifiedClick, "AUTOLOOTTOGGLE")
	if not FL.ShouldLoot(autoArg, cvar, mod) then
		return
	end
	last = now
	FL.LootAll()
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("LOOT_READY")
pcall(frame.RegisterEvent, frame, "SKILL_LINES_CHANGED")

------------------------------------------------------------------------
-- Slash
------------------------------------------------------------------------

local QUALITY_NAMES = { [0] = "grey", [1] = "white", [2] = "green", [3] = "blue", [4] = "epic", [5] = "legendary" }

-- "<link>", "12345" or "Linen Cloth" -> key (number id or lowercased name), label
function FL.ParseItem(text)
	text = text and text:match("^%s*(.-)%s*$") or ""
	if text == "" then
		return nil
	end
	local id = ItemIDFromLink(text)
	if id then
		local label = text:match("%[(.-)%]") or tostring(id)
		return id, label
	end
	if text:match("^%d+$") then
		return tonumber(text), text
	end
	return string.lower(text), text
end

-- list: "ignore" or "always". Putting an item on one list takes it off the other.
function FL.AddToList(list, key, label)
	local db = FL.InitDB()
	if key == nil or (list ~= "ignore" and list ~= "always") then
		return false
	end
	db.ignore[key], db.always[key] = nil, nil
	db[list][key] = label or tostring(key)
	if FL.OnListsChanged then
		FL.OnListsChanged()
	end
	return true
end

function FL.RemoveFromList(key)
	local db = FL.InitDB()
	db.ignore[key], db.always[key] = nil, nil
	if FL.OnListsChanged then
		FL.OnListsChanged()
	end
end

-- Takes the item held on the cursor (dragged from a bag) into a list.
-- Returns the item's label, or nil when the cursor holds no item.
function FL.AddFromCursor(list)
	local ok, kind, itemID, link = pcall(GetCursorInfo)
	if not ok or kind ~= "item" or IsSecret(itemID) or type(itemID) ~= "number" then
		return nil
	end
	local label = (type(link) == "string" and not IsSecret(link) and link:match("%[(.-)%]")) or tostring(itemID)
	FL.AddToList(list, itemID, label)
	pcall(ClearCursor)
	return label
end

local function OnOff(v)
	return v and "on" or "off"
end

local function PrintStatus()
	local db = FL.InitDB()
	Print("mode: " .. (db.filter and "filter" or "take everything") .. (db.enabled and "" or " (FastLoot off)"))
	if db.filter then
		Print(string.format("quest %s, professions %s, quality %s+, grey %s, white %s, close window %s",
			OnOff(db.quest), OnOff(db.prof), QUALITY_NAMES[db.minQuality] or tostring(db.minQuality),
			OnOff(db.grey), OnOff(db.white), OnOff(db.close)))
		local profs = FL.KnownProfessions()
		Print("your professions: " .. (#profs > 0 and table.concat(profs, ", ") or "none found"))
	end
end

local function PrintList(title, list)
	local items = {}
	for _, label in pairs(list) do
		items[#items + 1] = tostring(label)
	end
	table.sort(items)
	Print(title .. " (" .. #items .. "): " .. (#items > 0 and table.concat(items, ", ") or "empty"))
end

local function Help()
	Print("commands:")
	print("  /fastloot                open the window (drag items from bags into the lists)")
	print("  /fastloot on | off       FastLoot itself")
	print("  /fastloot filter         filter mode on/off (turns game auto loot off while on)")
	print("  /fastloot ignore <item>  never loot it (shift-click the item into chat)")
	print("  /fastloot always <item>  always loot it")
	print("  /fastloot remove <item>  take it off both lists")
	print("  /fastloot list           show both lists")
	print("  /fastloot quest | prof | grey | white | close   toggle a rule")
	print("  /fastloot drops          drop list in mob tooltips (hold Shift to expand)")
	print("  /fastloot rolls          roll results panel and \"for you\" marks on roll windows")
	print("  /fastloot rollsmove | rollstest   move the rolls panel / show a sample")
	print("  /fastloot quality <0-5>  take this quality and better (2 = green)")
	print("  /fastloot minimap        show or hide the minimap button")
	print("  /fastloot status         current settings")
end

SLASH_FASTLOOT1 = "/fastloot"
SLASH_FASTLOOT2 = "/fl"
SlashCmdList.FASTLOOT = function(msg)
	local db = FL.InitDB()
	msg = msg or ""
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = string.lower(cmd or "")
	if cmd == "" or cmd == "show" or cmd == "options" then
		if FL.ToggleWindow then
			FL.ToggleWindow()
		else
			Help()
		end
	elseif cmd == "on" or cmd == "off" then
		db.enabled = cmd == "on"
		Print(OnOff(db.enabled))
	elseif cmd == "filter" then
		FL.SetFilter(not db.filter)
		if db.filter then
			Print("filter mode on. Game auto loot is off while it is on; hold Shift to take everything.")
		else
			Print("filter mode off. Game auto loot restored.")
		end
	elseif cmd == "ignore" or cmd == "always" or cmd == "remove" then
		local key, label = FL.ParseItem(rest)
		if not key then
			Print("give an item: shift-click it into chat, or type its name or ID.")
			return
		end
		if cmd == "remove" then
			FL.RemoveFromList(key)
			Print("removed: " .. label)
		else
			FL.AddToList(cmd, key, label)
			Print((cmd == "ignore" and "never loot: " or "always loot: ") .. label)
		end
	elseif cmd == "list" then
		PrintList("never", db.ignore)
		PrintList("always", db.always)
	elseif cmd == "quest" or cmd == "prof" or cmd == "grey" or cmd == "white" or cmd == "close" or cmd == "drops" or cmd == "rolls" then
		db[cmd] = not db[cmd]
		Print(cmd .. ": " .. OnOff(db[cmd]))
	elseif cmd == "quality" then
		local q = tonumber(rest)
		if q and q >= 0 and q <= 5 then
			db.minQuality = math.floor(q)
			Print("take quality " .. (QUALITY_NAMES[db.minQuality] or rest) .. " and better")
		else
			Print("quality 0-5: 0 grey, 1 white, 2 green, 3 blue, 4 epic")
		end
	elseif cmd == "minimap" then
		db.minimap = db.minimap == false
		if FL.PlaceMinimapButton then
			FL.PlaceMinimapButton()
		end
		Print("minimap button: " .. OnOff(db.minimap))
	elseif cmd == "rollsmove" and FL.Rolls then
		FL.rollsUnlocked = not FL.rollsUnlocked
		FL.Rolls.SetUnlocked(FL.rollsUnlocked)
		Print(FL.rollsUnlocked and "rolls panel unlocked: drag it, then /fastloot rollsmove" or "rolls panel locked")
	elseif cmd == "rollstest" and FL.Rolls then
		FL.Rolls.Test()
	elseif cmd == "status" then
		PrintStatus()
	else
		Help()
	end
end
