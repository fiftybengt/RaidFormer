-- Main window, tabs, bottom bar and minimap button.
local _, RF = ...

local UI = { pages = {} }
RF.UI = UI

local WIDTH, HEIGHT = 600, 500

-- Tab files call this at load time; pages are built on PLAYER_LOGIN.
function UI:RegisterPage(index, title, build, refresh)
	self.pages[index] = { title = title, build = build, refresh = refresh }
end

function UI:Init()
	if self.frame then return end
	local W = RF.W
	local db = RF.db

	local f = CreateFrame("Frame", "RaidFormerFrame", UIParent)
	self.frame = f
	f:SetWidth(WIDTH)
	f:SetHeight(HEIGHT)
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		db.ui.point, db.ui.relPoint, db.ui.x, db.ui.y = point, relPoint, x, y
	end)
	if db.ui.point then
		f:SetPoint(db.ui.point, UIParent, db.ui.relPoint, db.ui.x, db.ui.y)
	else
		f:SetPoint("CENTER")
	end
	f:Hide()
	tinsert(UISpecialFrames, "RaidFormerFrame")

	local title = W.Label(f, "RaidFormer", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -18)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	-- pages + tabs
	self.tabs = {}
	for i, page in ipairs(self.pages) do
		local content = CreateFrame("Frame", nil, f)
		content:SetPoint("TOPLEFT", 20, -44)
		content:SetPoint("BOTTOMRIGHT", -20, 50)
		content:Hide()
		page.frame = content
		page.build(content)

		local tab = CreateFrame("Button", "RaidFormerFrameTab" .. i, f, "CharacterFrameTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(page.title)
		tab:SetScript("OnClick", function() UI:SelectTab(i) end)
		if i == 1 then
			tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 14, 8)
		else
			tab:SetPoint("LEFT", self.tabs[i - 1], "RIGHT", -16, 0)
		end
		self.tabs[i] = tab
	end
	PanelTemplates_SetNumTabs(f, #self.pages)

	-- bottom bar
	self.startButton = W.Button(f, "Start", 90, 24, function()
		if RF.Core.running then RF.Core:Stop() else RF.Core:Start() end
	end)
	self.startButton:SetPoint("BOTTOMLEFT", 20, 18)
	local post = W.Button(f, "Post now", 90, 24, function() RF.Core:Post(true) end)
	post:SetPoint("LEFT", self.startButton, "RIGHT", 6, 0)
	self.statusText = W.Label(f, "", "GameFontHighlightSmall")
	self.statusText:SetPoint("LEFT", post, "RIGHT", 12, 0)
	self.statusText:SetPoint("RIGHT", f, "RIGHT", -20, 0)

	f:SetScript("OnShow", function() UI:Refresh() end)
	self:SelectTab(1)
	self:CreateMinimapButton()
end

function UI:SelectTab(index)
	self.current = index
	PanelTemplates_SetTab(self.frame, index)
	for i, page in ipairs(self.pages) do
		if i == index then page.frame:Show() else page.frame:Hide() end
	end
	self:Refresh()
end

function UI:Toggle()
	if not self.frame then self:Init() end
	if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

function UI:Refresh()
	if not self.frame or not self.frame:IsShown() then return end
	local page = self.pages[self.current]
	if page and page.refresh then page.refresh(page.frame) end
	self:UpdateStatus()
end

function UI:UpdateStatus()
	if not self.frame or not self.frame:IsShown() then return end
	local core = RF.Core
	self.startButton:SetText(core.running and "Stop" or "Start")
	local holders = #core:Holders()
	local text
	if core.running then
		if core:IsFull() then
			text = string.format("|cff40ff40Running|r: %d/%d - raid full", holders, RF.profile.size)
		else
			text = string.format("|cff40ff40Running|r: %d/%d, next post in %ds", holders, RF.profile.size,
				math.max(0, math.floor(core.nextPost - GetTime())))
		end
	else
		text = string.format("|cffff8040Stopped|r: %d/%d", holders, RF.profile.size)
	end
	self.statusText:SetText(text)
	-- roster changes over time (timeouts, inspects), keep that tab live
	if self.current == 3 and self.pages[3] and self.pages[3].refresh then
		self.pages[3].refresh(self.pages[3].frame)
	end
end

-- Minimap button: left click toggles window, drag moves it around the minimap.
function UI:CreateMinimapButton()
	local db = RF.db.minimap
	local b = CreateFrame("Button", "RaidFormerMinimapButton", Minimap)
	b:SetWidth(31)
	b:SetHeight(31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local icon = b:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture("Interface\\Icons\\Ability_Warrior_BattleShout")
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetPoint("TOPLEFT", 7, -5)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetPoint("TOPLEFT")

	local function Place()
		local angle = math.rad(db.angle or 200)
		b:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(angle), 80 * math.sin(angle))
	end
	Place()

	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			if RF.Core.running then RF.Core:Stop() else RF.Core:Start() end
		else
			UI:Toggle()
		end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			db.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
			b:ClearAllPoints()
			Place()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("RaidFormer")
		GameTooltip:AddLine("Left-click: open window", 1, 1, 1)
		GameTooltip:AddLine("Right-click: start/stop", 1, 1, 1)
		GameTooltip:AddLine("Drag: move button", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	if db.hide then b:Hide() end
	self.minimapButton = b
end
