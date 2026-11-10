--[[
  FastLoot: group loot roll results on screen.

  A small "ROLLS" panel lists the items being rolled on in your group. Under
  each item, everyone's choice and number:

      [icon] Item name                       (timer bar while rolling)
        ★ Saz Zy        Need     87          winner, gold
          Milk Tsu      Greed    54
          Cirilha       Pass

  Next to each item, and as a colored frame around the game's own roll
  window, a verdict for your character:
    UPGRADE +6   green  - you can wear it and its item level beats what you
                          wear in that slot (or the slot is empty)
    you can use  white  - you can wear it, not higher item level
    needs level  yellow - you can wear it later
    can't use    red    - your character has not learned that armor/weapon
  Proficiencies are read from the spells your character knows (Plate Mail,
  One-Handed Swords, ...), so trainer visits and Forever's class changes
  count. Item level is a rough measure: stats are not weighed.

  The data comes from the game's own loot roll messages in the loot chat,
  matched with the client's localized strings (works on any language).
  An item stays 30 seconds after the roll ends; the panel hides when empty.
  Right-click the panel to clear it at once.

  /fastloot rolls       turn the panel on or off
  /fastloot rollsmove   keep the panel shown while empty, to place it
  (the panel can be dragged with the mouse at any time)
  /fastloot rollstest   show a sample roll
]]

local FL = _G.FastLoot
if not FL then
	return
end

local R = {}
FL.Rolls = R

local KEEP = 30     -- seconds an item stays after its roll ends
local MAX_ITEMS = 4
local MAX_PLAYERS = 8

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
-- Message patterns built from the client's own strings
------------------------------------------------------------------------

-- "Need Roll - %d for %s by %s" -> pattern, list of arg indexes in order.
-- Handles positional args like "%2$s".
function R.FormatToPattern(fmt)
	if type(fmt) ~= "string" then
		return nil
	end
	local order, n = {}, 0
	-- Escape magic characters except "%" (the format specifiers start with it).
	local pat = fmt:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
	-- "%s", "%d", and positional "%2$s" (its "$" is now "%$").
	pat = pat:gsub("%%(%d?)%%?%$?([sd])", function(pos, kind)
		n = n + 1
		order[#order + 1] = tonumber(pos) or n
		return kind == "d" and "(%d+)" or "(.+)"
	end)
	return "^" .. pat .. "$", order
end

-- kind -> { global string name, field names in argument order }
local MESSAGES = {
	{ "choice", "need", "LOOT_ROLL_NEED", { "player", "item" } },
	{ "choice", "greed", "LOOT_ROLL_GREED", { "player", "item" } },
	{ "choice", "disenchant", "LOOT_ROLL_DISENCHANT", { "player", "item" } },
	{ "choice", "pass", "LOOT_ROLL_PASSED", { "player", "item" } },
	{ "choice", "pass", "LOOT_ROLL_PASSED_AUTO", { "player", "item" } },
	{ "choice", "pass", "LOOT_ROLL_PASSED_AUTO_FEMALE", { "player", "item" } },
	{ "choice", "need", "LOOT_ROLL_NEED_SELF", { "item" } },
	{ "choice", "greed", "LOOT_ROLL_GREED_SELF", { "item" } },
	{ "choice", "disenchant", "LOOT_ROLL_DISENCHANT_SELF", { "item" } },
	{ "choice", "pass", "LOOT_ROLL_PASSED_SELF", { "item" } },
	{ "choice", "pass", "LOOT_ROLL_PASSED_SELF_AUTO", { "item" } },
	{ "roll", "need", "LOOT_ROLL_ROLLED_NEED", { "roll", "item", "player" } },
	{ "roll", "greed", "LOOT_ROLL_ROLLED_GREED", { "roll", "item", "player" } },
	{ "roll", "disenchant", "LOOT_ROLL_ROLLED_DE", { "roll", "item", "player" } },
	{ "won", nil, "LOOT_ROLL_WON", { "player", "item" } },
	{ "won", nil, "LOOT_ROLL_YOU_WON", { "item" } },
	{ "allpass", nil, "LOOT_ROLL_ALL_PASSED", { "item" } },
}

local compiled

local function Compile()
	compiled = {}
	for _, m in ipairs(MESSAGES) do
		local fmt = _G[m[3]]
		local pat, order = R.FormatToPattern(fmt)
		if pat then
			-- Modern clients start these lines with a hidden loot history link,
			-- "|HlootHistory:%d|h[Loot]|h: ...": one extra leading argument.
			local fields = m[4]
			local extra = #order - #fields
			if extra > 0 then
				local shifted = {}
				for i = 1, extra do
					shifted[i] = "_history"
				end
				for _, f in ipairs(fields) do
					shifted[#shifted + 1] = f
				end
				fields = shifted
			end
			compiled[#compiled + 1] = { kind = m[1], choice = m[2], pat = pat, order = order, fields = fields, self = m[3]:find("SELF") or m[3] == "LOOT_ROLL_YOU_WON" }
		end
	end
	-- The most fixed text first: "You won: %s" must win over "%s won: %s",
	-- and "Everyone passed on: %s" over "%s passed on: %s".
	local function literal(p)
		return #(p:gsub("%(%.%+%)", ""):gsub("%(%%d%+%)", ""))
	end
	for _, c in ipairs(compiled) do
		c.literal = literal(c.pat)
	end
	table.sort(compiled, function(a, b)
		return a.literal > b.literal
	end)
end

R.Recompile = function()
	compiled = nil
end

-- Returns { kind, choice, player, item, roll } or nil.
function R.ParseMessage(msg, selfName)
	if type(msg) ~= "string" or IsSecret(msg) then
		return nil
	end
	if not compiled then
		Compile()
	end
	for _, c in ipairs(compiled) do
		local caps = { msg:match(c.pat) }
		if #caps > 0 then
			local out = { kind = c.kind, choice = c.choice }
			-- caps come in text order; order[k] says which format argument it is.
			local args = {}
			for k, argIndex in ipairs(c.order) do
				args[argIndex] = caps[k]
			end
			for i, field in ipairs(c.fields) do
				out[field] = args[i]
			end
			if c.self then
				out.player = selfName
			end
			out._history = nil
			if out.roll then
				out.roll = tonumber(out.roll)
			end
			-- Sanity: the item is always an item link.
			if type(out.item) ~= "string" or not out.item:find("|Hitem:", 1, true) then
				return nil
			end
			return out
		end
	end
	return nil
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------

R.items = {} -- list of { link, players = { [name] = {choice, roll} }, winner, done, started, ends, doneAt }

local function ItemKey(link)
	return type(link) == "string" and (link:match("item:[%-%d:]+") or link) or tostring(link)
end

-- The open entry for this item, or a new one.
function R.Entry(link, now)
	local key = ItemKey(link)
	for _, e in ipairs(R.items) do
		if e.key == key and not e.done then
			return e
		end
	end
	local e = { key = key, link = link, players = {}, started = now }
	table.insert(R.items, 1, e)
	while #R.items > MAX_ITEMS * 2 do
		table.remove(R.items)
	end
	return e
end

function R.Apply(ev, now)
	if not ev or not ev.item then
		return nil
	end
	local e = R.Entry(ev.item, now)
	if ev.kind == "choice" or ev.kind == "roll" then
		if ev.player then
			local p = e.players[ev.player] or {}
			p.choice = ev.choice or p.choice
			p.roll = ev.roll or p.roll
			e.players[ev.player] = p
		end
	elseif ev.kind == "won" then
		e.winner = ev.player
		e.done, e.doneAt = true, now
	elseif ev.kind == "allpass" then
		e.allPassed = true
		e.done, e.doneAt = true, now
	end
	return e
end

local CHOICE_ORDER = { need = 1, greed = 2, disenchant = 3, pass = 4 }

-- Players of an entry, winner first, then by choice and roll.
function R.Sorted(e)
	local list = {}
	for name, p in pairs(e.players) do
		list[#list + 1] = { name = name, choice = p.choice, roll = p.roll, winner = name == e.winner }
	end
	table.sort(list, function(a, b)
		if a.winner ~= b.winner then
			return a.winner
		end
		local ca, cb = CHOICE_ORDER[a.choice] or 5, CHOICE_ORDER[b.choice] or 5
		if ca ~= cb then
			return ca < cb
		end
		if (a.roll or -1) ~= (b.roll or -1) then
			return (a.roll or -1) > (b.roll or -1)
		end
		return a.name < b.name
	end)
	return list
end

local GRACE = 10 -- seconds after the roll timer for the result to arrive

function R.Prune(now)
	for i = #R.items, 1, -1 do
		local e = R.items[i]
		-- The roll timer ran out but no result line came: treat it as finished.
		if not e.done and e.ends and now > e.ends + GRACE then
			e.done, e.doneAt = true, e.ends + GRACE
		end
		if (e.done and now - e.doneAt > KEEP) or (not e.done and now - e.started > 300) then
			table.remove(R.items, i)
		end
	end
end

------------------------------------------------------------------------
-- Is this item for you?
------------------------------------------------------------------------

-- Proficiency spells the character must know, by item class and subclass.
-- Checked with IsPlayerSpell, so it follows what this character trained.
local ARMOR, WEAPON = 4, 2
local NEEDS = {
	[ARMOR] = { [1] = 9078, [2] = 9077, [3] = 8737, [4] = 750, [6] = 9116 },
	[WEAPON] = {
		[0] = 196, [1] = 197, [2] = 264, [3] = 266, [4] = 198, [5] = 199, [6] = 200,
		[7] = 201, [8] = 202, [10] = 227, [13] = 15590, [15] = 1180, [16] = 2567,
		[18] = 5011, [19] = 5009,
	},
}
-- Relics belong to one class: libram, idol, totem.
local RELIC_CLASS = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }

local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}

local function ItemLevelOf(link)
	if not link then
		return nil
	end
	local lvl = Read(C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo, link)
	if type(lvl) == "number" then
		return lvl
	end
	local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	local ok, _, _, _, ilvl = pcall(getInfo, link)
	return ok and not IsSecret(ilvl) and ilvl or nil
end

-- info: { classID, subclassID, equipLoc, minLevel, ilvl }
-- me:   { level, class, knows = function(spellID) -> bool,
--         equipped = function(slot) -> ilvl or nil (empty) }
-- Returns verdict ("upgrade", "usable", "level", "unusable") and a detail number,
-- or nil when the item is not something you wear.
function R.Judge(info, me)
	if not info or not info.equipLoc or info.equipLoc == "" or not SLOTS[info.equipLoc] then
		return nil
	end
	local need = NEEDS[info.classID] and NEEDS[info.classID][info.subclassID]
	if info.equipLoc == "INVTYPE_CLOAK" then
		need = nil -- every class wears cloaks (cloth subclass)
	end
	if need and not me.knows(need) then
		return "unusable"
	end
	if info.classID == ARMOR and RELIC_CLASS[info.subclassID] and RELIC_CLASS[info.subclassID] ~= me.class then
		return "unusable"
	end
	if info.minLevel and me.level and info.minLevel > me.level then
		return "level", info.minLevel
	end
	if info.ilvl then
		local worst
		for _, slot in ipairs(SLOTS[info.equipLoc]) do
			local have = me.equipped(slot)
			if have == nil then
				return "upgrade", nil -- empty slot
			end
			worst = worst and math.min(worst, have) or have
		end
		if worst and info.ilvl > worst then
			return "upgrade", info.ilvl - worst
		end
	end
	return "usable"
end

local function Me()
	return {
		level = Read(UnitLevel, "player"),
		class = select(2, pcall(function()
			local _, c = UnitClass("player")
			return not IsSecret(c) and c or nil
		end)),
		knows = function(id)
			return Read(IsPlayerSpell, id) == true or Read(IsSpellKnown, id) == true
		end,
		equipped = function(slot)
			local link = Read(GetInventoryItemLink, "player", slot)
			if not link then
				return nil
			end
			return ItemLevelOf(link) or 0
		end,
	}
end

-- The verdict for an item link, or nil while item data is not loaded.
function R.Suitability(link)
	if type(link) ~= "string" then
		return nil
	end
	local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	local ok, _, _, _, _, minLevel, _, _, _, equipLoc, _, _, classID, subclassID = pcall(getInfo, link)
	if not ok or classID == nil or IsSecret(classID) then
		return nil
	end
	return R.Judge({
		classID = classID,
		subclassID = subclassID,
		equipLoc = equipLoc,
		minLevel = minLevel,
		ilvl = ItemLevelOf(link),
	}, Me())
end

local VERDICT = {
	upgrade = { 0.2, 1, 0.3 },
	usable = { 0.95, 0.95, 0.95 },
	level = { 1, 0.82, 0.2 },
	unusable = { 1, 0.25, 0.2 },
}

function R.VerdictText(verdict, detail)
	if verdict == "upgrade" then
		return detail and string.format("|cff33ff4dUPGRADE +%d|r", detail) or "|cff33ff4dUPGRADE (empty slot)|r"
	elseif verdict == "usable" then
		return "|cffddddddyou can use|r"
	elseif verdict == "level" then
		return string.format("|cffffd133needs level %d|r", detail or 0)
	elseif verdict == "unusable" then
		return "|cffff4033can't use|r"
	end
	return ""
end

------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local WIDTH = 250
local LINE = 14

local ICONS = {
	need = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
	greed = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
	disenchant = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
	pass = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}
local LABEL = { need = "Need", greed = "Greed", disenchant = "DE", pass = "Pass" }

local panel = CreateFrame("Frame", "FastLootRollsPanel", UIParent, BACKDROP)
panel:SetSize(WIDTH, 40)
panel:SetFrameStrata("MEDIUM")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
-- Always draggable: grab the panel anywhere and move it; the spot is saved.
-- Right-click clears it.
panel:EnableMouse(true)
panel:SetScript("OnMouseUp", function(_, button)
	if button == "RightButton" then
		R.Clear()
	end
end)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	if type(FastLootDB) == "table" then
		local _, _, _, x, y = self:GetPoint(1)
		local point = select(1, self:GetPoint(1))
		FastLootDB.rollsPos = { point, x, y }
	end
end)
panel:Hide()
if panel.SetBackdrop then
	panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	panel:SetBackdropColor(0.05, 0.05, 0.07, 0.72)
	panel:SetBackdropBorderColor(0, 0, 0, 0.9)
end

local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
header:SetPoint("TOPLEFT", 8, -6)
header:SetText("|cff7fd4ffROLLS|r")

local lines = {}
local bars = {}
local function Line(i)
	local fs = lines[i]
	if not fs then
		fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		fs:SetWidth(WIDTH - 60)
		fs.right = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs.right:SetJustifyH("RIGHT")
		lines[i] = fs
	end
	return fs
end

local function Bar(i)
	local b = bars[i]
	if not b then
		b = panel:CreateTexture(nil, "ARTWORK")
		b:SetHeight(2)
		b:SetColorTexture(0.5, 0.83, 1, 0.8)
		bars[i] = b
	end
	return b
end

local function ClassColored(name)
	local ok, _, class = pcall(UnitClass, name)
	local c = ok and type(class) == "string" and not IsSecret(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if c and c.colorStr then
		return "|c" .. c.colorStr .. name .. "|r"
	end
	return name
end

local unlocked = false

function R.Render(now)
	local db = FastLootDB
	R.Prune(now)
	if not (db and db.rolls ~= false) or (#R.items == 0 and not unlocked) then
		panel:Hide()
		return
	end
	local y, li, bi = -22, 0, 0
	for _, fs in ipairs(lines) do
		fs:Hide()
		fs.right:Hide()
	end
	for _, b in ipairs(bars) do
		b:Hide()
	end
	for n, e in ipairs(R.items) do
		if n > MAX_ITEMS then
			break
		end
		li = li + 1
		local head = Line(li)
		head:ClearAllPoints()
		head:SetPoint("TOPLEFT", 8, y)
		local itemID = type(e.link) == "string" and tonumber(e.link:match("item:(%d+)"))
		local icon = itemID and Read(C_Item and C_Item.GetItemIconByID, itemID)
		head:SetText((icon and ("|T" .. icon .. ":14|t ") or "") .. tostring(e.link))
		head:SetWidth(WIDTH - 110)
		head:SetAlpha(e.done and 0.85 or 1)
		head:Show()
		head.right:ClearAllPoints()
		head.right:SetPoint("TOPRIGHT", -8, y)
		if e.allPassed then
			head.right:SetText("|cff888888all passed|r")
		else
			e.verdict, e.verdictDetail = R.Suitability(e.link)
			head.right:SetText(R.VerdictText(e.verdict, e.verdictDetail))
		end
		head.right:Show()
		y = y - LINE - 1
		if not e.done and e.ends and e.ends > now then
			bi = bi + 1
			local b = Bar(bi)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", 8, y + 1)
			local frac = (e.ends - now) / math.max(1, e.ends - e.started)
			b:SetWidth(math.max(1, (WIDTH - 16) * frac))
			b:Show()
			y = y - 3
		end
		local players = R.Sorted(e)
		for k = 1, math.min(#players, MAX_PLAYERS) do
			local p = players[k]
			li = li + 1
			local fs = Line(li)
			fs:ClearAllPoints()
			fs:SetPoint("TOPLEFT", 18, y)
			local mark = p.winner and "|cffffd100★|r " or "   "
			local ic = ICONS[p.choice] and ("|T" .. ICONS[p.choice] .. ":12|t ") or ""
			fs:SetText(mark .. ic .. ClassColored(p.name))
			fs:SetAlpha(p.choice == "pass" and 0.55 or 1)
			fs:Show()
			fs.right:ClearAllPoints()
			fs.right:SetPoint("TOPRIGHT", -8, y)
			local num = p.roll and tostring(p.roll) or (LABEL[p.choice] or "")
			fs.right:SetText(p.winner and ("|cffffd100" .. num .. "|r") or num)
			fs.right:Show()
			y = y - LINE
		end
		y = y - 4
	end
	if #R.items == 0 then
		li = li + 1
		local fs = Line(li)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", 8, y)
		fs:SetText("|cff888888drag to move, /fastloot rollsmove to hide|r")
		fs:Show()
		y = y - LINE
	end
	panel:SetHeight(-y + 4)
	panel:Show()
end

function R.Clear()
	for i = #R.items, 1, -1 do
		R.items[i] = nil
	end
	R.Render(GetTime())
end

local function ApplyPosition()
	panel:ClearAllPoints()
	local pos = type(FastLootDB) == "table" and FastLootDB.rollsPos
	if type(pos) == "table" and pos[1] then
		panel:SetPoint(pos[1], UIParent, pos[1], pos[2] or 0, pos[3] or 0)
	else
		panel:SetPoint("RIGHT", UIParent, "RIGHT", -260, 80)
	end
end

-- The panel can always be dragged; "unlocked" only keeps it visible while
-- empty, so it can be placed before any roll happens.
function R.SetUnlocked(on)
	unlocked = on
	R.Render(GetTime())
end

function R.Test()
	local now = GetTime()
	local link = "|cff1eff00|Hitem:2232::::::::|h[Dark Runner Boots]|h|r"
	local e = R.Entry(link, now)
	e.ends = now + 20
	e.players = {
		[UnitName and Read(UnitName, "player") or "You"] = { choice = "need", roll = 87 },
		["Milk"] = { choice = "greed", roll = 54 },
		["Cirilha"] = { choice = "pass" },
		["Tejonmelero"] = { choice = "need", roll = 31 },
	}
	R.Render(now)
end

------------------------------------------------------------------------
-- Colored frame around the game's own roll windows
------------------------------------------------------------------------

-- The roll windows are not protected; Bulwark-style, FastLoot only puts its
-- own frame around them and never changes them.
local function RollFrames()
	local out = {}
	for i = 1, 8 do
		local f = _G["GroupLootFrame" .. i]
		if type(f) == "table" then
			out[#out + 1] = f
		end
	end
	local container = _G.GroupLootContainer
	if type(container) == "table" and type(container.rollFrames) == "table" then
		for _, f in pairs(container.rollFrames) do
			out[#out + 1] = f
		end
	end
	return out
end

local glows = {}
local function GlowFor(f)
	local g = glows[f]
	if not g then
		g = CreateFrame("Frame", nil, UIParent, BACKDROP)
		g:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
		g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
		g:SetFrameStrata("DIALOG")
		if g.SetBackdrop then
			g:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
		end
		g.text = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		g.text:SetPoint("BOTTOM", g, "TOP", 0, 2)
		glows[f] = g
	end
	return g
end

function R.UpdateRollFrames()
	local on = FastLootDB and FastLootDB.rolls ~= false
	for _, f in ipairs(RollFrames()) do
		local shown = on and Read(f.IsShown, f)
		local rollID = shown and f.rollID
		local link = rollID and not IsSecret(rollID) and Read(GetLootRollItemLink, rollID)
		local verdict, detail
		if link then
			verdict, detail = R.Suitability(link)
		end
		local g = glows[f]
		if verdict and VERDICT[verdict] then
			g = GlowFor(f)
			local c = VERDICT[verdict]
			if g.SetBackdropBorderColor then
				g:SetBackdropBorderColor(c[1], c[2], c[3], verdict == "usable" and 0.5 or 0.95)
			end
			g.text:SetText(R.VerdictText(verdict, detail))
			g:Show()
		elseif g then
			g:Hide()
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
	if acc < 0.2 then
		return
	end
	acc = 0
	if #R.items > 0 or unlocked then
		R.Render(GetTime())
	end
	pcall(R.UpdateRollFrames)
end)
frame:SetScript("OnEvent", function(_, event, a, b)
	local now = GetTime()
	if event == "PLAYER_LOGIN" then
		ApplyPosition()
		return
	end
	if not (FastLootDB and FastLootDB.rolls ~= false) then
		return
	end
	if event == "START_LOOT_ROLL" then
		local link = Read(GetLootRollItemLink, a)
		local ms = type(b) == "number" and not IsSecret(b) and b or 60000
		if link then
			local e = R.Entry(link, now)
			e.ends = now + ms / 1000
		end
	elseif event == "CHAT_MSG_LOOT" then
		local selfName = Read(UnitName, "player")
		R.Apply(R.ParseMessage(a, selfName), now)
	end
	R.Render(now)
end)
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_LOOT")
pcall(frame.RegisterEvent, frame, "START_LOOT_ROLL")
