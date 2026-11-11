--[[
  FastLoot: what a mob drops, in its tooltip.

  Hover a mob: one line under the tooltip says how many items it can drop
  and how many of these mobs you have killed. Hold Shift: the line expands
  into the list, best chance first:

      [icon] Item name          38%   you 2/5

    38%       chance from the classic database (cMaNGOS, Data/DropData.lua)
    you 2/5   your own loot: it dropped 2 times in 5 kills (Forever's real rate)
    (quest)   only drops while you are on the quest

  Items you looted that the database does not list are added from your stats.

  Your stats count a kill when a mob you could loot (tapped by you or your
  group) dies on a nameplate or as your target, and count items when you
  open its corpse. They are stored account-wide in FastLootDB.stats.

  /fastloot drops   turn the tooltip lines on or off
]]

local FL = _G.FastLoot
if not FL then
	return
end

local MAX_LINES = 14

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) and true or false
end

local function Read(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b = pcall(fn, ...)
	if not ok or IsSecret(a) then
		return nil
	end
	return a, b
end

------------------------------------------------------------------------
-- Pure helpers (tests/fastloot_test.lua)
------------------------------------------------------------------------

-- "Creature-0-1-2-3-2559-0000ABCD" -> 2559. Players, pets, objects -> nil.
function FL.NpcIDFromGUID(guid)
	if type(guid) ~= "string" or IsSecret(guid) then
		return nil
	end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if kind ~= "Creature" and kind ~= "Vehicle" then
		return nil
	end
	return tonumber(id)
end

-- "3685:51;4512:33q" -> { {item=3685, chance=51}, {item=4512, chance=33, quest=true} }
function FL.ParseDrops(text)
	local list = {}
	if type(text) ~= "string" then
		return list
	end
	for item, chance, q in text:gmatch("(%d+):([%d%.]+)(q?)") do
		list[#list + 1] = { item = tonumber(item), chance = tonumber(chance), quest = q == "q" }
	end
	return list
end

-- Merges database drops with your stats. Returns the rows sorted by the
-- best known chance, plus your kill count.
function FL.DropRows(npcID, data, stats)
	local rows, byItem = {}, {}
	for _, d in ipairs(FL.ParseDrops(data and data[npcID])) do
		local row = { item = d.item, chance = d.chance, quest = d.quest }
		rows[#rows + 1] = row
		byItem[d.item] = row
	end
	local s = stats and stats[npcID]
	local kills = s and s.k or 0
	if s and type(s.i) == "table" then
		for item, n in pairs(s.i) do
			local row = byItem[item]
			if not row then
				row = { item = item }
				rows[#rows + 1] = row
				byItem[item] = row
			end
			row.seen = n
		end
	end
	local function score(r)
		if r.chance then
			return r.chance
		end
		return kills > 0 and (r.seen or 0) / kills * 100 or 0
	end
	table.sort(rows, function(a, b)
		local sa, sb = score(a), score(b)
		if sa ~= sb then
			return sa > sb
		end
		return a.item < b.item
	end)
	return rows, kills
end

------------------------------------------------------------------------
-- Own statistics
------------------------------------------------------------------------

local function Stats()
	if type(FastLootDB) ~= "table" then
		return nil
	end
	FastLootDB.stats = type(FastLootDB.stats) == "table" and FastLootDB.stats or {}
	return FastLootDB.stats
end

local counted = {}  -- guid -> true, kills already counted this session
local watched = {}  -- guid -> npcID, lootable mobs seen alive
local looted = {}   -- guid -> { [itemID] = true } items already counted

function FL.CountKill(guid, npcID)
	local st = Stats()
	if not st or not npcID or counted[guid] then
		return
	end
	counted[guid] = true
	local s = st[npcID] or { k = 0, i = {} }
	s.k = (s.k or 0) + 1
	st[npcID] = s
end

function FL.CountItem(guid, npcID, itemID)
	local st = Stats()
	if not st or not npcID or not itemID then
		return
	end
	FL.CountKill(guid, npcID) -- a corpse we loot was a kill even if we missed it
	looted[guid] = looted[guid] or {}
	if looted[guid][itemID] then
		return
	end
	looted[guid][itemID] = true
	local s = st[npcID]
	s.i = s.i or {}
	s.i[itemID] = (s.i[itemID] or 0) + 1
end

local function Watch(unit)
	local guid = Read(UnitGUID, unit)
	local npc = FL.NpcIDFromGUID(guid)
	if not npc or counted[guid] then
		return
	end
	if Read(UnitIsDead, unit) then
		if watched[guid] then
			FL.CountKill(guid, npc)
			watched[guid] = nil
		end
		return
	end
	-- Alive: remember it if it is an enemy we (or the group) can loot.
	if Read(UnitCanAttack, "player", unit) and not Read(UnitIsTapDenied, unit) and Read(UnitAffectingCombat, unit) then
		watched[guid] = npc
	end
end

local function ScanUnits()
	Watch("target")
	Watch("mouseover")
	for i = 1, 40 do
		local unit = "nameplate" .. i
		if Read(UnitExists, unit) then
			Watch(unit)
		end
	end
end

-- Called from FastLoot.lua on LOOT_READY, before any slot is looted.
function FL.RecordLoot()
	local okN, n = pcall(GetNumLootItems)
	if not okN or type(n) ~= "number" or IsSecret(n) then
		return
	end
	for slot = 1, n do
		local okL, link = pcall(GetLootSlotLink, slot)
		local item = okL and type(link) == "string" and not IsSecret(link) and tonumber(link:match("item:(%d+)"))
		if item and GetLootSourceInfo then
			local sources = { pcall(GetLootSourceInfo, slot) }
			if sources[1] then
				for k = 2, #sources, 2 do
					local guid = sources[k]
					local npc = FL.NpcIDFromGUID(guid)
					if npc then
						FL.CountItem(guid, npc, item)
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Tooltip
------------------------------------------------------------------------

local function ItemName(item)
	local name = Read(C_Item and C_Item.GetItemNameByID, item) or Read(GetItemInfo, item)
	if not name and C_Item and C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, item)
	end
	return name
end

local function ItemColor(item)
	local q = Read(C_Item and C_Item.GetItemQualityByID, item)
	if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
		local c = ITEM_QUALITY_COLORS[q]
		return c.r, c.g, c.b
	end
	return 0.9, 0.9, 0.9
end

local function ItemIcon(item)
	return Read(C_Item and C_Item.GetItemIconByID, item) or 134400
end

local function Pct(v)
	if v >= 10 then
		return string.format("%d%%", math.floor(v + 0.5))
	end
	if v < 0.1 then
		return string.format("%.2f%%", v) -- boss world drops, e.g. 0.08%
	end
	return string.format("%.1f%%", v)
end

local tooltipNpc -- npc shown in GameTooltip right now (for refreshes)

local function AddDrops(tooltip, unit)
	if not (FastLootDB and FastLootDB.drops ~= false) then
		return
	end
	local guid = Read(UnitGUID, unit)
	local npc = FL.NpcIDFromGUID(guid)
	if not npc then
		return
	end
	local rows, kills = FL.DropRows(npc, FastLootDropData, Stats())
	if #rows == 0 then
		return
	end
	tooltipNpc = npc
	local killText = kills > 0 and string.format(", you killed %d", kills) or ""
	if not Read(IsShiftKeyDown) then
		tooltip:AddLine(string.format("|cff7fd4ffDrops:|r %d item%s%s  |cff888888(Shift)|r", #rows, #rows == 1 and "" or "s", killText), 0.85, 0.85, 0.85)
		tooltip:Show()
		return
	end
	tooltip:AddLine(" ")
	tooltip:AddDoubleLine("|cff7fd4ffDrops|r", "|cff888888classic DB" .. (kills > 0 and string.format(" · you %d kills", kills) or "") .. "|r")
	for i = 1, math.min(#rows, MAX_LINES) do
		local r = rows[i]
		local name = ItemName(r.item) or ("item " .. r.item)
		local left = string.format("|T%s:0|t %s%s", tostring(ItemIcon(r.item)), name, r.quest and " |cffffd100(quest)|r" or "")
		local right = r.chance and Pct(r.chance) or "?"
		if kills > 0 then
			right = right .. string.format("  |cff9fd3ff%d/%d|r", r.seen or 0, kills)
		end
		local cr, cg, cb = ItemColor(r.item)
		tooltip:AddDoubleLine(left, right, cr, cg, cb, 1, 1, 1)
	end
	if #rows > MAX_LINES then
		tooltip:AddLine(string.format("+%d more", #rows - MAX_LINES), 0.6, 0.6, 0.6)
	end
	tooltip:Show()
end

local function OnUnitTooltip(tooltip)
	if tooltip ~= GameTooltip then
		return
	end
	local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
	if not ok or type(unit) ~= "string" or IsSecret(unit) then
		unit = "mouseover"
	end
	pcall(AddDrops, tooltip, unit)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
elseif GameTooltip and GameTooltip.HookScript then
	GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip)
end

-- Redraw the tooltip when Shift is pressed or item names arrive.
local function RefreshTooltip()
	if tooltipNpc and GameTooltip and GameTooltip:IsShown() and Read(UnitExists, "mouseover") then
		local npc = FL.NpcIDFromGUID(Read(UnitGUID, "mouseover"))
		if npc == tooltipNpc then
			pcall(GameTooltip.SetUnit, GameTooltip, "mouseover")
		end
	end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local acc = 0
frame:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.5 then
		return
	end
	acc = 0
	if next(watched) or Read(UnitAffectingCombat, "player") then
		ScanUnits()
	end
end)
frame:SetScript("OnEvent", function(_, event, arg)
	if event == "MODIFIER_STATE_CHANGED" then
		if type(arg) == "string" and arg:find("SHIFT") then
			RefreshTooltip()
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		RefreshTooltip()
	elseif event == "PLAYER_TARGET_CHANGED" or event == "UPDATE_MOUSEOVER_UNIT" then
		ScanUnits()
	end
end)
frame:RegisterEvent("MODIFIER_STATE_CHANGED")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
pcall(frame.RegisterEvent, frame, "GET_ITEM_INFO_RECEIVED")
