-- Small widget helpers on top of stock 3.3.5 FrameXML templates.
local _, RF = ...

local W = {}
RF.W = W

local uid = 0
local function NextName(prefix)
	uid = uid + 1
	return "RaidFormer" .. prefix .. uid
end

function W.Label(parent, text, font)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
	fs:SetText(text or "")
	fs:SetJustifyH("LEFT")
	return fs
end

function W.Button(parent, text, width, height, onClick)
	local b = CreateFrame("Button", NextName("Button"), parent, "UIPanelButtonTemplate")
	b:SetWidth(width or 80)
	b:SetHeight(height or 22)
	b:SetText(text)
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

-- onCommit(text) fires on Enter, Tab or focus loss
function W.EditBox(parent, width, numeric, onCommit, maxLetters)
	local e = CreateFrame("EditBox", NextName("Edit"), parent, "InputBoxTemplate")
	e:SetWidth(width or 100)
	e:SetHeight(20)
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
	e:SetScript("OnEditFocusLost", commit)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	return e
end

function W.Check(parent, label, onClick)
	local c = CreateFrame("CheckButton", NextName("Check"), parent, "UICheckButtonTemplate")
	c:SetWidth(24)
	c:SetHeight(24)
	_G[c:GetName() .. "Text"]:SetText(label)
	_G[c:GetName() .. "Text"]:SetFontObject("GameFontHighlightSmall")
	c:SetScript("OnClick", function(self)
		if onClick then onClick(self:GetChecked() and true or false) end
	end)
	return c
end

function W.Radio(parent, label, onClick)
	local r = CreateFrame("CheckButton", NextName("Radio"), parent, "UIRadioButtonTemplate")
	_G[r:GetName() .. "Text"]:SetText(label)
	r:SetScript("OnClick", function(self)
		self:SetChecked(true)
		if onClick then onClick() end
	end)
	return r
end

-- Multi-select dropdown that stays open while ticking entries.
-- getItems() -> { { text=, value= } }; isChecked(value) -> bool; onToggle(value)
function W.MultiDropdown(parent, width, getItems, isChecked, onToggle)
	local dd = CreateFrame("Frame", NextName("MultiDropdown"), parent, "UIDropDownMenuTemplate")
	UIDropDownMenu_SetWidth(dd, width or 120)
	UIDropDownMenu_Initialize(dd, function(self, level)
		for _, item in ipairs(getItems()) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = item.text
			info.value = item.value
			info.checked = isChecked(item.value)
			info.keepShownOnClick = 1
			info.disabled = item.disabled
			info.func = function() onToggle(item.value) end
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	return dd
end

-- getItems() -> { { text=, value= }, ... }; onSelect(value, text)
function W.Dropdown(parent, width, getItems, onSelect)
	local dd = CreateFrame("Frame", NextName("Dropdown"), parent, "UIDropDownMenuTemplate")
	UIDropDownMenu_SetWidth(dd, width or 120)
	UIDropDownMenu_Initialize(dd, function(self, level)
		for _, item in ipairs(getItems()) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = item.text
			info.value = item.value
			info.checked = (item.value == dd.value)
			info.disabled = item.disabled
			info.func = function()
				dd:SetValue(item.value, item.text)
				if onSelect then onSelect(item.value, item.text) end
			end
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	function dd:SetValue(value, text)
		self.value = value
		if not text then
			for _, item in ipairs(getItems()) do
				if item.value == value then text = item.text end
			end
		end
		UIDropDownMenu_SetText(self, text or "")
	end
	return dd
end

function W.Slider(parent, width, minV, maxV, step, onChange)
	local name = NextName("Slider")
	local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
	s:SetWidth(width or 160)
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step or 1)
	_G[name .. "Low"]:SetText(minV)
	_G[name .. "High"]:SetText(maxV)
	_G[name .. "Text"]:SetText("")
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

-- [-] n [+] with a label on the left; onChange(newValue)
function W.Spinner(parent, label, labelWidth, minV, maxV, onChange)
	local f = CreateFrame("Frame", nil, parent)
	f:SetWidth((labelWidth or 90) + 90)
	f:SetHeight(22)
	f.label = W.Label(f, label, "GameFontHighlight")
	f.label:SetPoint("LEFT", 0, 0)
	f.label:SetWidth(labelWidth or 90)
	f.value = 0
	f.minus = W.Button(f, "-", 22, 20, function() f:Change(-1) end)
	f.minus:SetPoint("LEFT", f.label, "RIGHT", 4, 0)
	f.text = W.Label(f, "0", "GameFontHighlight")
	f.text:SetWidth(30)
	f.text:SetJustifyH("CENTER")
	f.text:SetPoint("LEFT", f.minus, "RIGHT", 2, 0)
	f.plus = W.Button(f, "+", 22, 20, function() f:Change(1) end)
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

-- Faux scroll list. createRow(row, index) builds row widgets; updateRow(row, data) fills them.
function W.ScrollList(parent, width, numRows, rowHeight, createRow, updateRow)
	local name = NextName("Scroll")
	local list = CreateFrame("Frame", nil, parent)
	list:SetWidth(width)
	list:SetHeight(numRows * rowHeight)
	list.data = {}
	list.rows = {}
	local scroll = CreateFrame("ScrollFrame", name, list, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, 0)
	scroll:SetPoint("BOTTOMRIGHT", -26, 0)
	for i = 1, numRows do
		local row = CreateFrame("Frame", nil, list)
		row:SetWidth(width - 28)
		row:SetHeight(rowHeight)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
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
				row:Hide()
			end
		end
	end
	function list:SetData(data)
		self.data = data or {}
		self:Update()
	end
	scroll:SetScript("OnVerticalScroll", function(self, offset)
		FauxScrollFrame_OnVerticalScroll(self, offset, rowHeight, function() list:Update() end)
	end)
	return list
end

-- Thin section header with a line under it.
function W.Header(parent, text)
	local fs = W.Label(parent, text, "GameFontNormal")
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetTexture(1, 1, 1, 0.15)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -2)
	line:SetWidth(250)
	fs.line = line
	return fs
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
