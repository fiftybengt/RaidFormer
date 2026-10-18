-- Flat widget kit (see Skin.lua for colours/fonts). Built from plain frames, so the look is the
-- same everywhere; lists still use FrameXML's faux scroll frame and menus its dropdown lists.
local _, RF = ...

local W = {}
RF.W = W
local Skin = RF.Skin
local C = Skin.C

local uid = 0
local function NextName(prefix)
	uid = uid + 1
	return "RaidFormer" .. prefix .. uid
end
W.NextName = NextName

local function SetColor(fs, color) fs:SetTextColor(color[1], color[2], color[3]) end
W.SetColor = SetColor

function W.Label(parent, text, font)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "RaidFormerFont")
	fs:SetText(text or "")
	fs:SetJustifyH("LEFT")
	return fs
end

-- Thin solid texture (lines, highlights).
function W.Solid(parent, color, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(color[1], color[2], color[3], color[4] or 1)
	return t
end

---------------------------------------------------------------------------
-- Tooltips: W.Tip(frame, "Title", { "line", ... }) - buttons show it on hover as well
---------------------------------------------------------------------------

local function ShowTip(self)
	if not self.tipTitle then return end
	GameTooltip:SetOwner(self, self.tipAnchor or "ANCHOR_TOP")
	GameTooltip:AddLine(self.tipTitle, 1, 1, 1)
	for _, line in ipairs(self.tipLines or {}) do GameTooltip:AddLine(line, 1, 0.82, 0.4, true) end
	GameTooltip:Show()
end
W.ShowTip = ShowTip

function W.Tip(frame, title, lines, anchor)
	frame.tipTitle, frame.tipLines, frame.tipAnchor = title, lines, anchor
	if not frame.isFlatButton then
		frame:EnableMouse(true)
		frame:SetScript("OnEnter", ShowTip)
		frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

local KIND_COLOR = { normal = C.button, good = C.goodBg, bad = C.badBg, accent = C.active }

-- kind: nil/"normal", "good", "bad" (Start/Stop) or "accent"; :SetActive(on) for toggles
function W.Button(parent, text, width, height, onClick, kind)
	local b = CreateFrame("Button", NextName("Button"), parent)
	b.isFlatButton = true
	b:SetWidth(width or 80)
	b:SetHeight(height or 20)
	Skin.Backdrop(b, C.button)
	local fs = b:CreateFontString(nil, "OVERLAY")
	fs:SetPoint("CENTER", 0, 0)
	b:SetFontString(fs)
	b:SetNormalFontObject(Skin.Font)
	b:SetDisabledFontObject(Skin.FontDisabled)
	b:SetText(text or "")
	b.kind = kind or "normal"
	local function Paint(self)
		local base = self.active and C.active or KIND_COLOR[self.kind] or C.button
		self:SetBackdropColor(base[1], base[2], base[3], base[4] or 1)
		local edge = (self.hover and self:IsEnabled() == 1) and C.accent or C.border
		self:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
	end
	b.Paint = Paint
	b:SetScript("OnEnter", function(self)
		self.hover = true
		Paint(self)
		ShowTip(self)
		if self.onEnter then self.onEnter(self) end
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = false
		Paint(self)
		GameTooltip:Hide()
		if self.onLeave then self.onLeave(self) end
	end)
	if onClick then b:SetScript("OnClick", onClick) end
	function b:SetActive(on)
		self.active = on and true or false
		Paint(self)
	end
	function b:SetKind(k)
		self.kind = k or "normal"
		Paint(self)
	end
	Paint(b)
	return b
end

-- Text-only button (chip actions, links)
function W.TextButton(parent, text, onClick, font)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(16)
	local fs = b:CreateFontString(nil, "OVERLAY")
	fs:SetPoint("CENTER", 0, 0)
	b:SetFontString(fs)
	b:SetNormalFontObject(font or Skin.FontMuted)
	b:SetHighlightFontObject(Skin.FontHeader)
	b:SetText(text or "")
	b:SetWidth(math.max(12, fs:GetStringWidth() + 6))
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

-- One-of-N buttons. items: { { text=, value=, width=, tip={ title, { lines } } } }
function W.Segmented(parent, items, width, onSelect)
	local f = CreateFrame("Frame", nil, parent)
	f.buttons = {}
	local x = 0
	for i, it in ipairs(items) do
		local bw = it.width or width or 60
		local b = W.Button(f, it.text, bw, 20, function() onSelect(it.value) end)
		b:SetPoint("LEFT", x, 0)
		b.value = it.value
		if it.tip then W.Tip(b, it.tip[1], it.tip[2]) end
		f.buttons[i] = b
		x = x + bw - 1 -- borders overlap
	end
	f:SetWidth(x + 1)
	f:SetHeight(20)
	function f:SetValue(v)
		self.value = v
		for _, b in ipairs(self.buttons) do b:SetActive(b.value == v) end
	end
	function f:SetEnabled(on)
		for _, b in ipairs(self.buttons) do if on then b:Enable() else b:Disable() end b:Paint() end
	end
	return f
end

---------------------------------------------------------------------------
-- Inputs
---------------------------------------------------------------------------

-- onCommit(text) fires on Enter, Tab or focus loss
function W.EditBox(parent, width, numeric, onCommit, maxLetters)
	local e = CreateFrame("EditBox", NextName("Edit"), parent)
	e:SetWidth(width or 100)
	e:SetHeight(20)
	Skin.Backdrop(e, C.input)
	e:SetFontObject(Skin.Font)
	e:SetTextInsets(5, 5, 0, 0)
	e:SetAutoFocus(false)
	if numeric then e:SetNumeric(true) end
	e:SetMaxLetters(maxLetters or 255)
	local function commit(self)
		if self.committing then return end
		self.committing = true
		if onCommit then onCommit(self:GetText()) end
		self.committing = false
	end
	e:SetScript("OnEnterPressed", function(self) commit(self); self:ClearFocus() end)
	e:SetScript("OnTabPressed", function(self) commit(self); self:ClearFocus() end)
	e:SetScript("OnEditFocusLost", function(self)
		self:SetBackdropBorderColor(0, 0, 0, 1)
		commit(self)
	end)
	e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return e
end

-- Checkbox with its label; the label is clickable too.
function W.Check(parent, label, onClick)
	local c = CreateFrame("CheckButton", NextName("Check"), parent)
	c:SetWidth(14)
	c:SetHeight(14)
	Skin.Backdrop(c, C.input)
	c:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
	c:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
	local fs = W.Label(c, label, "RaidFormerFont")
	fs:SetPoint("LEFT", c, "RIGHT", 5, 0)
	c.label = fs
	c:SetHitRectInsets(0, -(fs:GetStringWidth() + 8), 0, 0)
	c:SetScript("OnClick", function(self)
		if onClick then onClick(self:GetChecked() and true or false) end
	end)
	c:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
		ShowTip(self)
	end)
	c:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(0, 0, 0, 1)
		GameTooltip:Hide()
	end)
	local enable, disable = c.Enable, c.Disable
	function c:Enable() enable(self); SetColor(fs, C.text) end
	function c:Disable() disable(self); SetColor(fs, C.muted) end
	return c
end

function W.Slider(parent, width, minV, maxV, step, onChange)
	local s = CreateFrame("Slider", NextName("Slider"), parent)
	s:SetOrientation("HORIZONTAL")
	s:SetWidth(width or 160)
	s:SetHeight(10)
	Skin.Backdrop(s, C.input)
	s:SetThumbTexture(Skin.WHITE)
	local thumb = s:GetThumbTexture()
	if thumb then
		thumb:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
		thumb:SetWidth(8)
		thumb:SetHeight(14)
	end
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step or 1)
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self:GetValue() + delta * (step or 1)) end)
	s:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value / (step or 1) + 0.5) * (step or 1)
		if self.silent then return end
		if onChange then onChange(value) end
	end)
	function s:SetSilent(value)
		self.silent = true
		self:SetValue(value)
		self.silent = false
	end
	return s
end

---------------------------------------------------------------------------
-- Menus and dropdowns (native dropdown list, flat trigger button)
---------------------------------------------------------------------------

-- Shows an EasyMenu list under anchor. items: UIDropDownMenu info tables.
function W.ShowMenu(menuFrame, items, anchor)
	EasyMenu(items, menuFrame, anchor, 0, 0, "MENU")
end

local function NewMenuFrame()
	return CreateFrame("Frame", NextName("Menu"), UIParent, "UIDropDownMenuTemplate")
end
W.NewMenuFrame = NewMenuFrame

local function DropButton(parent, width, onClick)
	local b = W.Button(parent, "", width, 20, onClick)
	local fs = b:GetFontString()
	fs:ClearAllPoints()
	fs:SetPoint("LEFT", 6, 0)
	fs:SetPoint("RIGHT", -16, 0)
	fs:SetJustifyH("LEFT")
	local arrow = b:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	arrow:SetWidth(12)
	arrow:SetHeight(12)
	arrow:SetPoint("RIGHT", -3, -3)
	return b
end

-- getItems() -> { { text=, value=, disabled= }, ... }; onSelect(value, text)
function W.Dropdown(parent, width, getItems, onSelect)
	local menu = NewMenuFrame()
	local dd
	dd = DropButton(parent, width, function(self)
		local list = {}
		for _, item in ipairs(getItems()) do
			list[#list + 1] = {
				text = item.text, checked = (item.value == dd.value), disabled = item.disabled,
				func = function()
					dd:SetValue(item.value, item.text)
					if onSelect then onSelect(item.value, item.text) end
				end,
			}
		end
		W.ShowMenu(menu, list, self)
	end)
	function dd:SetValue(value, text)
		self.value = value
		if not text then
			for _, item in ipairs(getItems()) do
				if item.value == value then text = item.text end
			end
		end
		self:SetText(text or "")
	end
	return dd
end

-- Multi-select that stays open while ticking entries.
-- getItems() -> { { text=, value= } }; isChecked(value) -> bool; onToggle(value)
function W.MultiDropdown(parent, width, getItems, isChecked, onToggle)
	local menu = NewMenuFrame()
	return DropButton(parent, width, function(self)
		local list = {}
		for _, item in ipairs(getItems()) do
			list[#list + 1] = {
				text = item.text, checked = isChecked(item.value), keepShownOnClick = 1, disabled = item.disabled,
				func = function() onToggle(item.value) end,
			}
		end
		W.ShowMenu(menu, list, self)
	end)
end

---------------------------------------------------------------------------
-- Display pieces
---------------------------------------------------------------------------

-- Progress bar with a centered text: bar:Set(value, max, color[, text])
function W.Bar(parent, width, height)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(width)
	f:SetHeight(height)
	Skin.Backdrop(f, C.input)
	local bar = CreateFrame("StatusBar", nil, f)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("BOTTOMRIGHT", -1, 1)
	bar:SetStatusBarTexture(Skin.WHITE)
	bar:SetMinMaxValues(0, 1)
	f.bar = bar
	f.text = W.Label(bar, "", "RaidFormerFont")
	f.text:SetPoint("CENTER", 0, 0)
	f.text:SetJustifyH("CENTER")
	function f:Set(value, max, color, text)
		self.bar:SetMinMaxValues(0, math.max(1, max))
		self.bar:SetValue(math.min(value, max))
		self.bar:SetStatusBarColor(color[1] * 0.75, color[2] * 0.75, color[3] * 0.75, 1)
		self.text:SetText(text or (value .. "/" .. max))
	end
	return f
end

-- Small pill: label + optional action buttons (e.g. "-", "+", "x").
-- actions: { { text=, onClick=function(chip) end, tip= }, ... }
function W.Chip(parent, actions)
	local c = CreateFrame("Frame", nil, parent)
	c:SetHeight(18)
	Skin.Backdrop(c, C.button)
	c.icon = c:CreateTexture(nil, "OVERLAY")
	c.icon:SetWidth(14)
	c.icon:SetHeight(14)
	c.icon:SetPoint("LEFT", 3, 0)
	c.icon:Hide()
	c.text = W.Label(c, "", "RaidFormerFontSmall")
	c.text:SetPoint("LEFT", 6, 0)
	c.actions = {}
	for i, a in ipairs(actions or {}) do
		local b = W.TextButton(c, a.text, function() a.onClick(c) end)
		b:SetWidth(13)
		if a.tip then W.Tip(b, a.tip) end
		c.actions[i] = b
	end
	-- label, background tint and optional icon setter(tex)
	function c:Set(label, tint, setIcon)
		local left = 6
		if setIcon then
			setIcon(self.icon)
			self.icon:Show()
			left = 20
		else
			self.icon:Hide()
		end
		self.text:ClearAllPoints()
		self.text:SetPoint("LEFT", left, 0)
		self.text:SetText(label)
		local width = left + self.text:GetStringWidth() + 6
		local x = width - 2
		for _, b in ipairs(self.actions) do
			b:ClearAllPoints()
			b:SetPoint("LEFT", x, 0)
			x = x + 13
		end
		self:SetWidth(x + (#self.actions > 0 and 3 or 0))
		local t = tint or C.button
		self:SetBackdropColor(t[1], t[2], t[3], t[4] or 1)
	end
	return c
end

-- Lays out the first `count` chips left to right, wrapping; hides the rest and the ones that don't
-- fit in maxRows (nil = no limit). Returns the rows used and how many chips didn't fit.
function W.Flow(chips, count, parent, x0, y0, maxWidth, maxRows)
	local x, y, rows, hidden = 0, 0, (count > 0) and 1 or 0, 0
	for i = 1, #chips do
		local c = chips[i]
		if i > count then
			c:Hide()
		else
			local w = c:GetWidth()
			if x > 0 and x + w > maxWidth then
				x, y, rows = 0, y + 20, rows + 1
			end
			if maxRows and rows > maxRows then
				c:Hide()
				hidden = hidden + 1
			else
				c:ClearAllPoints()
				c:SetPoint("TOPLEFT", parent, "TOPLEFT", x0 + x, y0 - y)
				c:Show()
				x = x + w + 4
			end
		end
	end
	return maxRows and math.min(rows, maxRows) or rows, hidden
end

-- Scrolling area: put content on area.child, then call area:SetContentHeight(h). Mouse wheel
-- scrolls; a slim scrollbar shows only when the content is taller than the area.
function W.ScrollArea(parent, width, height)
	local area = CreateFrame("ScrollFrame", NextName("Area"), parent)
	area:SetWidth(width)
	area:SetHeight(height)
	local child = CreateFrame("Frame", nil, area)
	child:SetWidth(width - 10)
	child:SetHeight(height)
	area:SetScrollChild(child)
	area.child = child

	local bar = CreateFrame("Slider", nil, area)
	bar:SetOrientation("VERTICAL")
	bar:SetWidth(6)
	bar:SetPoint("TOPRIGHT", 0, 0)
	bar:SetPoint("BOTTOMRIGHT", 0, 0)
	Skin.Backdrop(bar, C.input)
	bar:SetThumbTexture(Skin.WHITE)
	local thumb = bar:GetThumbTexture()
	if thumb then
		thumb:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 0.7)
		thumb:SetWidth(6)
		thumb:SetHeight(24)
	end
	bar:SetMinMaxValues(0, 0)
	bar:SetValue(0)
	bar:SetScript("OnValueChanged", function(_, value) area:SetVerticalScroll(value) end)
	bar:Hide()
	area.bar = bar

	area:EnableMouseWheel(true)
	area:SetScript("OnMouseWheel", function(self, delta)
		self:ScrollTo(self.offset - delta * 20)
	end)
	area.offset, area.range = 0, 0

	function area:ScrollTo(value)
		self.offset = math.max(0, math.min(self.range, value))
		self.bar:SetValue(self.offset)
		self:SetVerticalScroll(self.offset)
	end
	function area:SetContentHeight(h)
		self.child:SetHeight(math.max(h, height))
		self.range = math.max(0, h - height)
		self.bar:SetMinMaxValues(0, self.range)
		if self.range > 0 then self.bar:Show() else self.bar:Hide() end
		self:ScrollTo(self.offset) -- stays in range after content shrinks
	end
	return area
end

-- [icon] Label  [-] n [+]   onChange(newValue); shift-click steps by 5
function W.Spinner(parent, label, labelWidth, minV, maxV, onChange, role)
	local f = CreateFrame("Frame", nil, parent)
	local iconW = role and 18 or 0
	f:SetWidth(iconW + (labelWidth or 90) + 74)
	f:SetHeight(20)
	if role then
		f.icon = f:CreateTexture(nil, "ARTWORK")
		f.icon:SetWidth(16)
		f.icon:SetHeight(16)
		f.icon:SetPoint("LEFT", 0, 0)
		Skin.SetRoleIcon(f.icon, role)
	end
	f.label = W.Label(f, label, "RaidFormerFont")
	f.label:SetPoint("LEFT", iconW, 0)
	f.label:SetWidth(labelWidth or 90)
	f.value = 0
	f.minus = W.Button(f, "-", 20, 18, function() f:Change(-1) end)
	f.minus:SetPoint("LEFT", f.label, "RIGHT", 2, 0)
	f.text = W.Label(f, "0", "RaidFormerFontBig")
	f.text:SetWidth(26)
	f.text:SetJustifyH("CENTER")
	f.text:SetPoint("LEFT", f.minus, "RIGHT", 2, 0)
	f.plus = W.Button(f, "+", 20, 18, function() f:Change(1) end)
	f.plus:SetPoint("LEFT", f.text, "RIGHT", 2, 0)
	function f:SetValue(v)
		self.value = v
		self.text:SetText(v)
	end
	function f:Change(delta)
		local step = IsShiftKeyDown() and 5 or 1
		local v = math.max(minV, math.min(maxV, self.value + delta * step))
		if v ~= self.value then
			self:SetValue(v)
			if onChange then onChange(v) end
		end
	end
	return f
end

-- Faux scroll list with pooled rows. createRow(row, index) builds row widgets; updateRow(row, data)
-- fills them. Rows are Buttons (left/right click).
function W.ScrollList(parent, width, numRows, rowHeight, createRow, updateRow)
	local name = NextName("Scroll")
	local list = CreateFrame("Frame", nil, parent)
	list:SetWidth(width)
	list:SetHeight(numRows * rowHeight)
	list.data = {}
	list.rows = {}
	local scroll = CreateFrame("ScrollFrame", name, list, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", -22, 0)
	-- slim the scrollbar: flat thumb, no arrow buttons (mouse wheel / drag)
	local bar = _G[name .. "ScrollBar"]
	if bar then
		local up, down = _G[name .. "ScrollBarScrollUpButton"], _G[name .. "ScrollBarScrollDownButton"]
		if up then up:SetAlpha(0); up:SetWidth(1) end
		if down then down:SetAlpha(0); down:SetWidth(1) end
		bar:SetThumbTexture(Skin.WHITE)
		local thumb = bar:GetThumbTexture()
		if thumb then
			thumb:SetVertexColor(C.muted[1], C.muted[2], C.muted[3], 0.6)
			thumb:SetWidth(5)
		end
	end
	for i = 1, numRows do
		local row = CreateFrame("Button", nil, list)
		row:SetWidth(width - 24)
		row:SetHeight(rowHeight)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.hl = W.Solid(row, { 1, 1, 1, 0.05 }, "BACKGROUND")
		row.hl:SetAllPoints()
		row.hl:Hide()
		createRow(row, i)
		list.rows[i] = row
	end
	function list:Update()
		local offset = FauxScrollFrame_GetOffset(scroll)
		FauxScrollFrame_Update(scroll, #self.data, numRows, rowHeight)
		for i = 1, numRows do
			local item = self.data[i + offset]
			local row = self.rows[i]
			if item then
				row.data = item
				updateRow(row, item)
				row:Show()
			else
				row.data = nil
				row:Hide()
			end
		end
	end
	function list:SetData(data)
		self.data = data or {}
		self:Update()
	end
	-- rows currently on screen (for cheap per-row updates)
	function list:VisibleRows()
		local out = {}
		for _, row in ipairs(self.rows) do
			if row.data and row:IsShown() then out[#out + 1] = row end
		end
		return out
	end
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, rowHeight, function() list:Update() end)
	end)
	return list
end

-- Section header: accent label with a hairline under it.
function W.Header(parent, text, width)
	local fs = W.Label(parent, text, "RaidFormerFontHeader")
	local line = W.Solid(parent, C.line)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
	line:SetWidth(width or 290)
	fs.line = line
	return fs
end

-- Inline warning line (hidden when empty).
function W.Banner(parent, width)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth(width)
	f:SetHeight(18)
	Skin.Backdrop(f, C.warnBg, { C.warn[1], C.warn[2], C.warn[3], 0.6 })
	f.text = W.Label(f, "", "RaidFormerFontSmall")
	f.text:SetPoint("LEFT", 6, 0)
	f.text:SetPoint("RIGHT", -6, 0)
	SetColor(f.text, C.warn)
	-- shows the first message, the rest in the tooltip
	function f:SetMessages(list)
		if not list or #list == 0 then self:Hide() return end
		self.text:SetText(list[1] .. (#list > 1 and string.format("  (+%d more)", #list - 1) or ""))
		W.Tip(self, "Check", list)
		self:Show()
	end
	f:Hide()
	return f
end

function W.ClassColor(class)
	local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if not c then return "|cffffffff" end
	return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

-- Items for class/spec dropdowns
function W.ClassItems(withAny)
	local items = {}
	if withAny then items[1] = { text = "Any", value = "ANY" } end
	for _, class in ipairs(RF.CLASSES) do
		items[#items + 1] = { text = W.ClassColor(class) .. RF.CLASS_NAMES[class] .. "|r", value = class }
	end
	return items
end

function W.SpecItems(class, withAny)
	local items = {}
	if withAny then items[1] = { text = "Any spec", value = "ANY" } end
	for _, key in ipairs(RF.CLASS_SPECS[class] or {}) do
		items[#items + 1] = { text = RF.SPECS[key].name, value = key }
	end
	return items
end
