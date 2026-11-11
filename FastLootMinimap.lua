--[[
  FastLoot: round button on the minimap ring, like the other addon buttons.

  Left click:  open the FastLoot window
  Right click: filter mode on/off
  Drag:        move it around the minimap

  /fastloot minimap   show or hide the button
]]

local FL = _G.FastLoot
if not FL then
	return
end

local ICON = "Interface\\AddOns\\FastLoot\\Media\\icon"

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) and true or false
end

local function Num(v)
	return type(v) == "number" and not IsSecret(v) and v or nil
end

local btn

-- Position on the ring for an angle in degrees, in UIParent coordinates.
function FL.MinimapPoint(angle, mx, my, width, ms, us)
	local a = math.rad(angle or 200)
	local r = width / 2 + 8
	local x, y = mx + math.cos(a) * r, my + math.sin(a) * r
	if ms and us and ms > 0 and us > 0 then
		x, y = x * ms / us, y * ms / us
	end
	return x, y
end

local function Place()
	if not btn then
		return
	end
	local db = FastLootDB
	if not db or db.minimap == false or not Minimap then
		btn:Hide()
		return
	end
	local ok, mx, my = pcall(Minimap.GetCenter, Minimap)
	local okW, width = pcall(Minimap.GetWidth, Minimap)
	mx, my, width = ok and Num(mx), ok and Num(my), okW and Num(width)
	if not mx or not my or not width or width < 20 then
		btn:Hide()
		return
	end
	local okS, ms = pcall(Minimap.GetEffectiveScale, Minimap)
	local okU, us = pcall(UIParent.GetEffectiveScale, UIParent)
	local x, y = FL.MinimapPoint(db.minimapAngle, mx, my, width, okS and Num(ms), okU and Num(us))
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
	btn:Show()
end
FL.PlaceMinimapButton = Place

local function Create()
	if btn or not Minimap then
		return
	end
	-- Same layout as LibDBIcon's classic buttons; parented to UIParent.
	btn = CreateFrame("Button", "FastLootMinimapButton", UIParent)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(40)
	btn:SetClampedToScreen(true)
	btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	if icon.SetMask then
		pcall(icon.SetMask, icon, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
	end
	btn.icon = icon

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	local dragging = false
	btn:SetScript("OnClick", function(_, button)
		if dragging then
			return
		end
		if button == "RightButton" then
			FL.SetFilter(not (FastLootDB and FastLootDB.filter))
			print("|cff7fd4ffFastLoot|r filter mode " .. ((FastLootDB and FastLootDB.filter) and "on" or "off"))
			if FL.RefreshWindow then
				FL.RefreshWindow()
			end
		else
			FL.ToggleWindow()
		end
	end)
	btn:SetScript("OnDragStart", function(self)
		dragging = true
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			mx, my, px, py, scale = Num(mx), Num(my), Num(px), Num(py), Num(scale)
			if mx and my and px and py and scale and scale > 0 and FastLootDB then
				FastLootDB.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
				Place()
			end
		end)
	end)
	btn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		C_Timer.After(0, function()
			dragging = false
		end)
	end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("|cff7fd4ffFastLoot|r")
		local db = FastLootDB or {}
		GameTooltip:AddLine("mode: " .. (db.filter and "filter" or "take everything"), 1, 1, 1)
		GameTooltip:AddLine("Left click: open the window", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Right click: filter mode on/off", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Drag: move around the minimap", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)
	Place()
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function()
	if type(FastLootDB) == "table" then
		if FastLootDB.minimap == nil then
			FastLootDB.minimap = true
		end
		if FastLootDB.minimapAngle == nil then
			FastLootDB.minimapAngle = 200
		end
	end
	-- One second later, like Bulwark: the minimap has its final size then.
	C_Timer.After(1, function()
		Create()
		Place()
	end)
end)
frame:RegisterEvent("PLAYER_LOGIN")
