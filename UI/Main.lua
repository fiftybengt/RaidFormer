-- Main window: title bar (Start/Stop, Post), pages, footer (tabs, raid groups mode), minimap button.
-- Redraws are throttled: Refresh() only marks the UI dirty, a driver frame redraws the visible page
-- (and the mini bar) at most every REDRAW_GAP seconds. UpdateStatus() (every Core tick) only
-- touches countdowns, bars and timers.
local _, RF = ...

local UI = { pages = {}, dirty = true, redraws = 0 }
RF.UI = UI

local WIDTH, HEIGHT = 640, 560
local REDRAW_GAP = 0.2

-- Tab files call this at load time; pages are built on PLAYER_LOGIN.
-- status(frame) is the cheap per-tick update (optional).
function UI:RegisterPage(index, title, build, refresh, status)
	self.pages[index] = { title = title, build = build, refresh = refresh, status = status }
end

function UI:Init()
	if self.frame then return end
	local W, Skin = RF.W, RF.Skin
	local C = Skin.C
	local db = RF.db

	local f = CreateFrame("Frame", "RaidFormerFrame", UIParent)
	self.frame = f
	f:SetWidth(WIDTH)
	f:SetHeight(HEIGHT)
	f:SetFrameStrata("HIGH") -- below popups (Save preset) and dropdown lists
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	Skin.Backdrop(f, C.bg)
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
	f:SetScale(db.ui.scale or 1)
	f:Hide()
	tinsert(UISpecialFrames, "RaidFormerFrame")

	-- title bar
	local titleBg = W.Solid(f, C.panel, "BACKGROUND")
	titleBg:SetPoint("TOPLEFT", 1, -1)
	titleBg:SetPoint("TOPRIGHT", -1, -1)
	titleBg:SetHeight(32)
	local title = W.Label(f, "RaidFormer", "RaidFormerFontTitle")
	title:SetPoint("TOPLEFT", 12, -10)
	W.SetColor(title, C.accent)
	self.tag = W.Label(f, "", "RaidFormerFontBig")
	self.tag:SetPoint("LEFT", title, "RIGHT", 8, 0)
	W.SetColor(self.tag, C.muted)

	local close = W.Button(f, "x", 22, 20, function() f:Hide() end)
	close:SetPoint("TOPRIGHT", -6, -6)
	local post = W.Button(f, "Post now", 70, 20, function() RF.Core:Post(true) end)
	post:SetPoint("RIGHT", close, "LEFT", -8, 0)
	W.Tip(post, "Post now", { "Posts the LFM line to your channels right away." })
	self.startButton = W.Button(f, "Start", 70, 20, function()
		if RF.Core.running then RF.Core:Stop() else RF.Core:Start() end
	end, "good")
	self.startButton:SetPoint("RIGHT", post, "LEFT", -4, 0)

	-- pages
	for _, page in ipairs(self.pages) do
		local content = CreateFrame("Frame", nil, f)
		content:SetPoint("TOPLEFT", 12, -42)
		content:SetPoint("BOTTOMRIGHT", -12, 40)
		content:SetWidth(WIDTH - 24)
		content:SetHeight(HEIGHT - 82)
		content:Hide()
		page.frame = content
		page.build(content)
	end

	-- footer: tabs left, raid groups mode right
	local footer = W.Solid(f, C.line)
	footer:SetHeight(1)
	footer:SetPoint("BOTTOMLEFT", 1, 34)
	footer:SetPoint("BOTTOMRIGHT", -1, 34)
	local tabs = {}
	for i, page in ipairs(self.pages) do tabs[i] = { text = page.title, value = i, width = 84 } end
	self.tabs = W.Segmented(f, tabs, 84, function(i) UI:SelectTab(i) end)
	self.tabs:SetPoint("BOTTOMLEFT", 12, 8)

	self.groups = W.Segmented(f, {
		{ text = "Forming", value = "forming", width = 66, tip = { "Forming groups", {
			"RaidFormer takes control of the raid groups: you and uninspected players in the uninspected group, everyone else in the other groups.",
			"Also puts back players you moved yourself." } } },
		{ text = "Final", value = "final", width = 50, tip = { "Final groups", {
			"Sorts the raid once: tanks with melee, then ranged, then healers, with party-only effects spread (Vampiric Embrace, Honor Among Thieves, Prayer of Healing, Healing Stream).",
			"After that the raid groups are yours." } } },
		{ text = "Manual", value = "manual", width = 62, tip = { "Manual groups", {
			"Full control: RaidFormer never moves anyone in the raid - not even when you press Insp - until you press Forming or Final again.",
			"Kept over /reload." } } },
	}, 60, function(mode)
		if mode == "forming" then RF.Groups:SetForming()
		elseif mode == "final" then RF.Groups:SetFinal()
		else RF.Groups:SetManual() end
	end)
	self.groups:SetPoint("BOTTOMRIGHT", -12, 8)
	local groupsLabel = W.Label(f, "Raid groups", "RaidFormerFontMuted")
	groupsLabel:SetPoint("RIGHT", self.groups, "LEFT", -8, 0)

	f:SetScript("OnShow", function() UI:Redraw() end)
	f:SetScript("OnHide", function()
		RF.W.CloseMenus() -- no menu left floating without its window
		UI:Redraw()      -- mini bar takes over
	end)

	-- throttled redraws; runs while the window is closed too (mini bar)
	self.driver = CreateFrame("Frame", nil, UIParent)
	local since = 0
	self.driver:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if UI.dirty and since >= REDRAW_GAP then
			since = 0
			UI:Redraw()
		end
	end)

	if self.InitMiniBar then self:InitMiniBar() end
	self:SelectTab(1)
	self:CreateMinimapButton()
end

function UI:SelectTab(index)
	RF.W.CloseMenus()
	self.current = index
	for i, page in ipairs(self.pages) do
		if i == index then page.frame:Show() else page.frame:Hide() end
	end
	self.tabs:SetValue(index)
	self:Redraw()
end

function UI:Toggle()
	if not self.frame then self:Init() end
	if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

-- Something changed: redraw soon (many calls in a row cost one redraw).
function UI:Refresh()
	self.dirty = true
end

-- Redraw now: the visible page, the title bar and the mini bar.
function UI:Redraw()
	if not self.frame then return end
	self.dirty = false
	self.redraws = self.redraws + 1
	if self.frame:IsShown() then
		local page = self.pages[self.current]
		if page and page.refresh then page.refresh(page.frame) end
	end
	self:UpdateStatus()
end

-- Every Core tick: only cheap things (texts, bars, timers), no list rebuilds.
function UI:UpdateStatus()
	if not self.frame then return end
	local core, C = RF.Core, RF.Skin.C
	if self.frame:IsShown() then
		self.startButton:SetText(core.running and "Stop" or "Start")
		self.startButton:SetKind(core.running and "bad" or "good")
		local p = RF.profile
		self.tag:SetText(RF.RaidTag(p.raid, p.size, p.heroic, p.customName))
		local mode = RF.Groups.mode or (RF.Groups:IsManual() and "manual") or nil
		self.groups:SetValue(mode)
		local page = self.pages[self.current]
		if page and page.status then page.status(page.frame) end
	end
	if self.UpdateMiniBar then self:UpdateMiniBar() end
end

-- Text for "what's happening": Stopped / next post in 23s / Raid full
function UI:StateText()
	local core, C = RF.Core, RF.Skin.C
	local hex = RF.Skin.Hex
	if not core.running then return hex(C.muted) .. "Stopped|r" end
	if core:IsFull() then return hex(C.good) .. "Raid full|r" end
	return hex(C.good) .. "Running|r - next post " .. math.max(0, math.floor(core.nextPost - GetTime())) .. "s"
end

-- Minimap button: click toggles the window, drag moves it around the minimap.
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

	b:RegisterForClicks("LeftButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnClick", function() UI:Toggle() end)
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
		local core, p = RF.Core, RF.profile
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("RaidFormer")
		GameTooltip:AddLine(string.format("%s  %d/%d", RF.RaidTag(p.raid, p.size, p.heroic, p.customName), #core:Holders(), p.size), 1, 1, 1)
		GameTooltip:AddLine(UI:StateText(), 1, 1, 1)
		local need = core:NeedText()
		if need ~= "" then GameTooltip:AddLine("Need: " .. need, 1, 0.82, 0.4, true) end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Click: open window", 0.7, 0.7, 0.7)
		GameTooltip:AddLine("Drag: move button", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	if db.hide then b:Hide() end
	self.minimapButton = b
end
