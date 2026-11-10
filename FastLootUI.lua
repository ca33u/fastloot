--[[
  FastLoot window: /fastloot or the round button at the minimap.

  Laid out top to bottom by what depends on what:
    title bar         FastLoot on/off (master switch)
    HOW TO LOOT       Take everything  |  Filter by rules below
    FILTER TAKES      quest items, profession mats, grey, white, quality,
                      close the loot window -- dimmed while not filtering
    EXTRAS            mob drops in tooltip, roll results panel (always work)
    NEVER / ALWAYS    two item grids for filter mode: drag items from bags,
                      right-click an icon to remove it
]]

local FL = _G.FastLoot
if not FL then
	return
end

local COLS = 9
local SLOT = 30
local GAP = 4
local ROWS = 4
local PAD = 18 -- room for the dialog border
local WIDTH = PAD * 2 + COLS * SLOT + (COLS - 1) * GAP
local GRID_H = ROWS * SLOT + (ROWS - 1) * GAP
local COL1, COL2 = PAD - 4, PAD + 156
local Y0 = -26 -- everything below the title header moves down by this
local GRIDS_TOP = -284 + Y0 -- first grid header
local QUALITY = {
	[0] = { "grey", 0.62, 0.62, 0.62 },
	[1] = { "white", 1, 1, 1 },
	[2] = { "green", 0.12, 1, 0 },
	[3] = { "blue", 0, 0.44, 0.87 },
	[4] = { "epic", 0.64, 0.21, 0.93 },
	[5] = { "legendary", 1, 0.5, 0 },
}

local function Flat(frame, r, g, b, a)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		frame:SetBackdropColor(r, g, b, a)
		frame:SetBackdropBorderColor(0, 0, 0, 0.9)
	end
end

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

local win = CreateFrame("Frame", "FastLootWindow", UIParent, BACKDROP)
local FOOTER_H = 18 -- "by addicted" line at the bottom
win:SetSize(WIDTH, -GRIDS_TOP + 2 * (GRID_H + 34) + 14 + FOOTER_H)
win:SetPoint("CENTER", 0, 60)
win:SetFrameStrata("DIALOG")
win:SetClampedToScreen(true)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
-- Classic Warcraft dialog look: the game's own dialog border and background.
if win.SetBackdrop then
	win:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	win:SetBackdropColor(1, 1, 1, 0.95)
end
win:Hide()
if UISpecialFrames then
	table.insert(UISpecialFrames, "FastLootWindow") -- Esc closes it
end

-- Title on the classic dialog header plate.
local header = win:CreateTexture(nil, "ARTWORK")
header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
header:SetSize(256, 64)
header:SetPoint("TOP", 0, 12)
local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", header, "TOP", 0, -14)
title:SetText("FastLoot")

local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -5, -5)

------------------------------------------------------------------------
-- Footer: studio credit and website. The game cannot open web pages, so
-- clicking the address shows it selected, ready for Cmd+C / Ctrl+C.
------------------------------------------------------------------------

FL.WEBSITE = "addicted.sh"
FL.WEBSITE_URL = "https://addicted.sh"
local RU = GetLocale and GetLocale() == "ruRU"

local copy
function FL.ShowCopy(url)
	if not copy then
		copy = CreateFrame("Frame", "FastLootCopyDialog", UIParent, BACKDROP)
		copy:SetSize(330, 104)
		copy:SetPoint("CENTER", 0, 120)
		copy:SetFrameStrata("FULLSCREEN_DIALOG")
		copy:SetToplevel(true)
		copy:EnableMouse(true)
		if copy.SetBackdrop then
			copy:SetBackdrop({
				bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
				edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
				tile = true, tileSize = 32, edgeSize = 32,
				insets = { left = 11, right = 12, top = 12, bottom = 11 },
			})
		end
		local hint = copy:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		hint:SetPoint("TOP", 0, -22)
		hint:SetText(RU and "Нажмите Cmd+C (Ctrl+C), чтобы скопировать адрес" or "Press Cmd+C (Ctrl+C) to copy the address")
		local eb = CreateFrame("EditBox", nil, copy, "InputBoxTemplate")
		eb:SetSize(250, 22)
		eb:SetPoint("TOP", 0, -44)
		eb:SetAutoFocus(true)
		eb:SetJustifyH("CENTER")
		eb:SetScript("OnEscapePressed", function() copy:Hide() end)
		eb:SetScript("OnEnterPressed", function() copy:Hide() end)
		eb:SetScript("OnTextChanged", function(self, user)
			if user then -- keep the address intact
				self:SetText(copy.url or "")
				self:HighlightText()
			end
		end)
		eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
		copy.eb = eb
		local x = CreateFrame("Button", nil, copy, "UIPanelCloseButton")
		x:SetPoint("TOPRIGHT", -5, -5)
		local done = CreateFrame("Button", nil, copy, "UIPanelButtonTemplate")
		done:SetSize(90, 20)
		done:SetPoint("BOTTOM", 0, 16)
		done:SetText(OKAY or "OK")
		done:SetScript("OnClick", function() copy:Hide() end)
		if UISpecialFrames then
			table.insert(UISpecialFrames, "FastLootCopyDialog")
		end
	end
	copy.url = url
	copy.eb:SetText(url)
	copy:Show()
	copy.eb:SetFocus()
	copy.eb:HighlightText()
end

local footer = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
footer:SetPoint("BOTTOMLEFT", PAD, 16)
local version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)
local okV, ver = pcall(version or function() end, "FastLoot", "Version")
footer:SetText(string.format("FastLoot %s  ·  by addicted  ·  GPL-3.0  · ", okV and ver or ""))
local link = CreateFrame("Button", nil, win)
link.text = link:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
link.text:SetPoint("LEFT")
link.text:SetText(FL.WEBSITE)
link.text:SetTextColor(0.5, 0.83, 1)
local linkW = link.text:GetStringWidth()
link:SetSize((type(linkW) == "number" and linkW > 0 and linkW or 60) + 2, 14)
link:SetPoint("LEFT", footer, "RIGHT", 2, 0)
link:SetScript("OnEnter", function(self)
	link.text:SetTextColor(0.75, 0.92, 1)
	if GameTooltip then
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(FL.WEBSITE_URL)
		GameTooltip:AddLine(RU and "Щёлкните, чтобы скопировать адрес" or "Click to copy the address", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end
end)
link:SetScript("OnLeave", function()
	link.text:SetTextColor(0.5, 0.83, 1)
	if GameTooltip then
		GameTooltip:Hide()
	end
end)
link:SetScript("OnClick", function()
	FL.ShowCopy(FL.WEBSITE_URL)
end)

------------------------------------------------------------------------
-- Building blocks
------------------------------------------------------------------------

local function Section(text, y, note)
	local fs = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("TOPLEFT", PAD, y)
	fs:SetText(text)
	local line = win:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.18)
	line:SetHeight(1)
	line:SetPoint("LEFT", fs, "RIGHT", 6, 0)
	line:SetPoint("RIGHT", win, "RIGHT", -PAD, 0)
	local n
	if note then
		n = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		n:SetPoint("TOPLEFT", PAD, y - 13)
		n:SetWidth(WIDTH - 2 * PAD)
		n:SetJustifyH("LEFT")
		n:SetWordWrap(false)
		n:SetText(note)
	end
	return fs, n
end

local checks = {}
local function Check(key, label, x, y, onClick)
	local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
	cb:SetSize(22, 22)
	cb:SetPoint("TOPLEFT", x, y)
	local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	text:SetText(label)
	cb:SetScript("OnClick", function(self)
		if onClick then
			onClick(self:GetChecked() and true or false)
		else
			FastLootDB[key] = self:GetChecked() and true or false
		end
		FL.RefreshWindow()
	end)
	if key then
		checks[key] = cb
	end
	return cb
end

------------------------------------------------------------------------
-- Title bar: master switch
------------------------------------------------------------------------

Check("enabled", "FastLoot on", COL1, -30)

------------------------------------------------------------------------
-- HOW TO LOOT (two choices, one is always on)
------------------------------------------------------------------------

Section("HOW TO LOOT", -36 + Y0)
local takeAll = Check(nil, "Take everything", COL1, -50 + Y0, function()
	FL.SetFilter(false)
end)
local takeFiltered = Check(nil, "Filter by rules below", COL2, -50 + Y0, function()
	FL.SetFilter(true)
end)

------------------------------------------------------------------------
-- FILTER TAKES (only in filter mode)
------------------------------------------------------------------------

local filterWidgets = {}
local _, filterNote = Section("FILTER TAKES", -82 + Y0, "Only in filter mode. Shift while looting takes all.")
filterWidgets[#filterWidgets + 1] = Check("quest", "Quest items", COL1, -108 + Y0)
filterWidgets[#filterWidgets + 1] = Check("prof", "Profession materials", COL2, -108 + Y0)
filterWidgets[#filterWidgets + 1] = Check("grey", "Grey items", COL1, -130 + Y0)
filterWidgets[#filterWidgets + 1] = Check("white", "White items", COL2, -130 + Y0)

local qualLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
qualLabel:SetPoint("TOPLEFT", COL1 + 4, -158 + Y0)
qualLabel:SetText("Any item of quality")
-- The game's red panel button, like the buttons in Blizzard dialogs.
local qual = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
qual:SetSize(120, 22)
qual:SetPoint("LEFT", qualLabel, "RIGHT", 6, 0)
qual.text = qual:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
qual.text:SetPoint("CENTER")
qual:SetScript("OnClick", function(_, button)
	local q = FastLootDB.minQuality or 2
	q = button == "RightButton" and q - 1 or q + 1
	if q > 4 then q = 0 end
	if q < 0 then q = 4 end
	FastLootDB.minQuality = q
	FL.RefreshWindow()
end)
qual:RegisterForClicks("LeftButtonUp", "RightButtonUp")
qual:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine("Take this quality and better")
	GameTooltip:AddLine("Left click: higher. Right click: lower.", 1, 1, 1)
	GameTooltip:Show()
end)
qual:SetScript("OnLeave", GameTooltip_Hide)
filterWidgets[#filterWidgets + 1] = qualLabel
filterWidgets[#filterWidgets + 1] = qual
filterWidgets[#filterWidgets + 1] = Check("close", "Leave the rest and close the loot window", COL1, -176 + Y0)

------------------------------------------------------------------------
-- EXTRAS (work in both modes)
------------------------------------------------------------------------

Section("EXTRAS", -204 + Y0)
Check("drops", "Drops in mob tooltip", COL1, -218 + Y0)
Check("rolls", "Group roll results", COL2, -218 + Y0)

------------------------------------------------------------------------
-- ITEM LISTS (filter mode)
------------------------------------------------------------------------

Section("ITEM LISTS", -250 + Y0, "Drag items here from bags. Right-click to remove.")

------------------------------------------------------------------------
-- Item grids
------------------------------------------------------------------------

local function ItemIcon(key)
	if type(key) ~= "number" then
		return 134400 -- question mark: a list entry saved by name
	end
	if C_Item and C_Item.GetItemIconByID then
		local ok, icon = pcall(C_Item.GetItemIconByID, key)
		if ok and icon then
			return icon
		end
	end
	local getInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	local ok, _, _, _, _, icon = pcall(getInstant, key)
	return ok and icon or 134400
end

local function MakeGrid(list, label, color, top)
	local head = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	head:SetPoint("TOPLEFT", PAD, top)
	head:SetText(label)
	head:SetTextColor(color[1], color[2], color[3])

	local count = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	count:SetPoint("TOPRIGHT", -PAD, top)

	local zone = CreateFrame("Frame", nil, win, BACKDROP)
	zone:SetPoint("TOPLEFT", PAD - 3, top - 14)
	zone:SetSize(WIDTH - 2 * PAD + 6, GRID_H + 6)
	Flat(zone, color[1] * 0.12, color[2] * 0.12, color[3] * 0.12, 0.9)
	zone:EnableMouse(true)

	local empty = zone:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("CENTER")
	empty:SetText("drag items from your bags here")

	local function Drop()
		if FL.AddFromCursor(list) then
			FL.RefreshWindow()
		end
	end
	zone:SetScript("OnReceiveDrag", Drop)
	zone:SetScript("OnMouseUp", Drop)

	local buttons = {}
	for i = 1, COLS * ROWS do
		local b = CreateFrame("Button", nil, zone, BACKDROP)
		b:SetSize(SLOT, SLOT)
		local c, r = (i - 1) % COLS, math.floor((i - 1) / COLS)
		b:SetPoint("TOPLEFT", 3 + c * (SLOT + GAP), -3 - r * (SLOT + GAP))
		Flat(b, 0, 0, 0, 1)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("TOPLEFT", 1, -1)
		b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b:RegisterForClicks("RightButtonUp", "LeftButtonUp")
		b:SetScript("OnReceiveDrag", Drop)
		b:SetScript("OnClick", function(self, button)
			local ok, kind = pcall(GetCursorInfo)
			if ok and kind == "item" then
				Drop()
			elseif button == "RightButton" and self.key ~= nil then
				FL.RemoveFromList(self.key)
				GameTooltip:Hide()
				FL.RefreshWindow()
			end
		end)
		b:SetScript("OnEnter", function(self)
			if self.key == nil then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if type(self.key) == "number" and GameTooltip.SetItemByID then
				GameTooltip:SetItemByID(self.key)
			else
				GameTooltip:AddLine(tostring(self.label))
			end
			GameTooltip:AddLine("Right click: remove from the list", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		b:Hide()
		buttons[i] = b
	end
	return { list = list, buttons = buttons, count = count, empty = empty, zone = zone }
end

local NEVER = MakeGrid("ignore", "NEVER LOOT", { 1, 0.35, 0.3 }, GRIDS_TOP)
local ALWAYS = MakeGrid("always", "ALWAYS LOOT", { 0.35, 0.9, 0.45 }, GRIDS_TOP - GRID_H - 34)

local function FillGrid(grid)
	local entries = {}
	for key, label in pairs(FastLootDB[grid.list]) do
		entries[#entries + 1] = { key = key, label = label }
	end
	table.sort(entries, function(a, b)
		return tostring(a.label) < tostring(b.label)
	end)
	for i, b in ipairs(grid.buttons) do
		local e = entries[i]
		if e then
			b.key, b.label = e.key, e.label
			b.icon:SetTexture(ItemIcon(e.key))
			b:Show()
		else
			b.key, b.label = nil, nil
			b:Hide()
		end
	end
	local extra = #entries > #grid.buttons and string.format(" (+%d not shown)", #entries - #grid.buttons) or ""
	grid.count:SetText(#entries .. extra)
	grid.empty:SetShown(#entries == 0)
end

function FL.RefreshWindow()
	if not win:IsShown() or type(FastLootDB) ~= "table" then
		return
	end
	for key, cb in pairs(checks) do
		cb:SetChecked(FastLootDB[key] and true or false)
	end
	local filtering = FastLootDB.filter and true or false
	takeAll:SetChecked(not filtering)
	takeFiltered:SetChecked(filtering)
	local q = QUALITY[FastLootDB.minQuality or 2] or QUALITY[2]
	qual.text:SetText(q[1] .. " and better")
	qual.text:SetTextColor(q[2], q[3], q[4])
	-- The filter rules and lists only matter in filter mode: dim them otherwise.
	local a = filtering and 1 or 0.4
	for _, w in ipairs(filterWidgets) do
		w:SetAlpha(a)
	end
	filterNote:SetAlpha(filtering and 1 or 0.7)
	NEVER.zone:SetAlpha(filtering and 1 or 0.55)
	ALWAYS.zone:SetAlpha(filtering and 1 or 0.55)
	-- Everything is off while FastLoot itself is off.
	local all = FastLootDB.enabled and 1 or 0.45
	takeAll:SetAlpha(all)
	takeFiltered:SetAlpha(all)
	FillGrid(NEVER)
	FillGrid(ALWAYS)
end

FL.OnListsChanged = FL.RefreshWindow

function FL.ToggleWindow()
	FL.InitDB()
	if win:IsShown() then
		win:Hide()
	else
		win:Show()
		FL.RefreshWindow()
	end
end

-- The addon button next to the minimap (addon compartment).
function FastLoot_OnAddonCompartmentClick()
	FL.ToggleWindow()
end
