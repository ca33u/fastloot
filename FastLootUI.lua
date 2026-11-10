--[[
  FastLoot window: /fastloot (or the addon button next to the minimap).

  Top: the rules as checkboxes plus the quality threshold.
  Below: two item grids, like a small bank:
    NEVER LOOT   - drag an item from your bags here
    ALWAYS LOOT  - drag an item from your bags here
  Hover an icon for the tooltip, right-click it to take it off the list.
  Dropping an item on one list moves it off the other.
]]

local FL = _G.FastLoot
if not FL then
	return
end

local COLS = 9
local SLOT = 30
local GAP = 4
local ROWS = 4
local PAD = 12
local WIDTH = PAD * 2 + COLS * SLOT + (COLS - 1) * GAP
local GRID_H = ROWS * SLOT + (ROWS - 1) * GAP
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
win:SetSize(WIDTH, 120 + 2 * (GRID_H + 34))
win:SetPoint("CENTER", 0, 60)
win:SetFrameStrata("DIALOG")
win:SetClampedToScreen(true)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
Flat(win, 0.05, 0.05, 0.07, 0.94)
win:Hide()
if UISpecialFrames then
	table.insert(UISpecialFrames, "FastLootWindow") -- Esc closes it
end

local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOPLEFT", PAD, -10)
title:SetText("|cff7fd4ffFastLoot|r")

local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", 2, 2)

------------------------------------------------------------------------
-- Rules
------------------------------------------------------------------------

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
	checks[key] = cb
	return cb
end

local col1, col2, col3 = PAD - 4, PAD + 96, PAD + 196
Check("filter", "Filter mode", col1, -30, function(on)
	FL.SetFilter(on)
end)
Check("enabled", "FastLoot on", col2, -30)
Check("close", "Close window", col3, -30)
Check("quest", "Quest items", col1, -52)
Check("prof", "Profession mats", col2, -52)
Check("grey", "Grey", col1, -74)
Check("white", "White", col2, -74)
Check("drops", "Mob drops tip", col3, -74)

local qual = CreateFrame("Button", nil, win, BACKDROP)
qual:SetSize(96, 20)
qual:SetPoint("TOPLEFT", col3 + 4, -54)
Flat(qual, 0.15, 0.15, 0.18, 1)
qual.text = qual:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", PAD, -100)
hint:SetPoint("RIGHT", -PAD, 0)
hint:SetJustifyH("LEFT")

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
	return { list = list, buttons = buttons, count = count, empty = empty }
end

local NEVER = MakeGrid("ignore", "NEVER LOOT", { 1, 0.35, 0.3 }, -118)
local ALWAYS = MakeGrid("always", "ALWAYS LOOT", { 0.35, 0.9, 0.45 }, -118 - GRID_H - 34)

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
	local q = QUALITY[FastLootDB.minQuality or 2] or QUALITY[2]
	qual.text:SetText(q[1] .. "+")
	qual.text:SetTextColor(q[2], q[3], q[4])
	if FastLootDB.filter then
		hint:SetText("Filter on: game auto loot is off. Hold Shift while looting to take everything.")
	else
		hint:SetText("Filter off: everything is looted. The lists and rules apply in filter mode.")
	end
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
