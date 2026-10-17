-- Mini bar: a small movable strip for forming without the big window - raid count, what's still
-- needed, next post, Start/Stop, Post and a button to open the window.
-- Shown while running (or always / never, Settings > Interface) and only while the window is closed.
local _, RF = ...

local UI = RF.UI
local WIDTH, HEIGHT = 300, 42

function UI:InitMiniBar()
	if self.mini then return end
	local W, Skin = RF.W, RF.Skin
	local C = Skin.C
	local db = RF.db.ui.mini

	local f = CreateFrame("Frame", "RaidFormerMiniBar", UIParent)
	self.mini = f
	f:SetWidth(WIDTH)
	f:SetHeight(HEIGHT)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	Skin.Backdrop(f, C.bg)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
	end)
	if db.point then
		f:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
	else
		f:SetPoint("TOP", UIParent, "TOP", 0, -120)
	end
	f:SetScale(RF.db.ui.scale or 1)
	f:Hide()

	f.bar = W.Bar(f, WIDTH - 8, 16)
	f.bar:SetPoint("TOPLEFT", 4, -4)
	f.bar.text:ClearAllPoints()
	f.bar.text:SetPoint("LEFT", 5, 0)
	f.state = W.Label(f.bar.bar, "", "RaidFormerFontSmall")
	f.state:SetPoint("RIGHT", -5, 0)

	f.open = W.Button(f, "Open", 40, 16, function() UI:Toggle() end)
	f.open:SetPoint("BOTTOMRIGHT", -4, 4)
	f.post = W.Button(f, "Post", 36, 16, function() RF.Core:Post(true) end)
	f.post:SetPoint("RIGHT", f.open, "LEFT", -3, 0)
	f.start = W.Button(f, "Start", 40, 16, function()
		if RF.Core.running then RF.Core:Stop() else RF.Core:Start() end
	end, "good")
	f.start:SetPoint("RIGHT", f.post, "LEFT", -3, 0)

	f.need = W.Label(f, "", "RaidFormerFontSmall")
	f.need:SetPoint("BOTTOMLEFT", 6, 6)
	f.need:SetPoint("RIGHT", f.start, "LEFT", -6, 0)
	f.need:SetHeight(12)
	f:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("RaidFormer")
		GameTooltip:AddLine(RF.Core:Announcement(), 1, 1, 1, true)
		GameTooltip:AddLine(db.locked and "Locked (Settings > Interface)" or "Drag to move", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI:MiniBarWanted()
	local mode = RF.db.ui.mini.mode or "running"
	if mode == "never" then return false end
	if self.frame and self.frame:IsShown() then return false end
	return mode == "always" or RF.Core.running
end

-- Cheap: called on every redraw and Core tick.
function UI:UpdateMiniBar()
	local f = self.mini
	if not f then return end
	if not self:MiniBarWanted() then f:Hide() return end
	f:Show()
	local p, core, C = RF.profile, RF.Core, RF.Skin.C
	local holders = #core:Holders()
	f.bar:Set(holders, p.size, holders >= p.size and C.good or C.warn,
		string.format("%s  %d/%d", RF.RaidTag(p.raid, p.size, p.heroic, p.customName), holders, p.size))
	f.state:SetText(self:StateText())
	local need = core:NeedText()
	f.need:SetText(need ~= "" and ("Need: " .. need) or RF.Skin.Hex(C.good) .. "Nothing needed|r")
	f.start:SetText(core.running and "Stop" or "Start")
	f.start:SetKind(core.running and "bad" or "good")
end
