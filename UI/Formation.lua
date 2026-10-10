-- Formation tab: role counts, class/spec needs, class caps, presets.
local _, RF = ...

local w = {}
local sel = { needClass = "SHAMAN", needSpec = "ANY", needCount = 1, capClass = "DEATHKNIGHT", capMax = 4, preset = nil }

-- one-click needs for the specs raid leaders ask for most
local QUICK_NEEDS = {
	{ "Resto Shaman", "SHAMAN", "SHAMAN_RESTO" }, { "Holy Paladin", "PALADIN", "PALADIN_HOLY" },
	{ "Disc Priest", "PRIEST", "PRIEST_DISC" },   { "Resto Druid", "DRUID", "DRUID_RESTO" },
	{ "Prot Paladin", "PALADIN", "PALADIN_PROT" }, { "Prot Warrior", "WARRIOR", "WARRIOR_PROT" },
	{ "DK Tank", "DEATHKNIGHT", "DK_TANK" },       { "Bear Tank", "DRUID", "DRUID_BEAR" },
	{ "Any Shaman", "SHAMAN", nil },               { "Ret Paladin", "PALADIN", "PALADIN_RET" },
}

local function P() return RF.profile end
local function Changed() RF.UI:Refresh() end
-- your own change: the formation becomes your baseline (kept when the raid changes)
local function Edited() RF.Core:MarkEdited(); Changed() end

StaticPopupDialogs["RAIDFORMER_SAVE_PRESET"] = {
	text = "Save formation as preset:",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = 1,
	maxLetters = 32,
	OnAccept = function(self)
		local eb = self.editBox or _G[self:GetName() .. "EditBox"]
		RF.UI.SavePreset(eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self)
		RF.UI.SavePreset(self:GetText())
		self:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

function RF.UI.SavePreset(name)
	name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then return end
	local p = P()
	RF.db.presets[name] = RF.CopyTable({
		raid = p.raid, size = p.size, heroic = p.heroic, customName = p.customName, minGS = p.minGS,
		roles = p.roles, needs = p.needs, caps = p.caps, extras = p.extras, freeText = p.freeText,
	})
	sel.preset = name
	p.formationSource = "preset:" .. name
	RF.Print("Preset saved: " .. name)
	Changed()
end

local function LoadPreset(name)
	if RF.Core:LoadPreset(name) then Changed() end
end

-- Adds a need, or raises the count of an identical one.
local function AddNeed(class, spec, count, setCount)
	local needs = P().needs
	for _, need in ipairs(needs) do
		if need.class == class and need.spec == spec then
			need.count = setCount and count or math.min(40, (need.count or 1) + count)
			return Edited()
		end
	end
	needs[#needs + 1] = { class = class, spec = spec, count = count }
	Edited()
end

local function RoleOfNeed(need)
	if need.spec and RF.SPECS[need.spec] then return RF.ROLE_NAMES[RF.SPECS[need.spec].role] end
	return "any role"
end

local function Build(page)
	local W = RF.W

	----------------------------------------------------------------- roles
	local h = W.Header(page, "Roles")
	h:SetPoint("TOPLEFT", 0, 0)
	w.roles = {}
	for i, role in ipairs(RF.ROLES) do
		local s = W.Spinner(page, RF.ROLE_NAMES[role], 75, 0, 40, function(v) P().roles[role] = v; Edited() end)
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		s:SetPoint("TOPLEFT", col * 180, -20 - row * 24)
		w.roles[role] = s
	end
	w.total = W.Label(page, "", "GameFontNormal")
	w.total:SetPoint("TOPLEFT", 370, -24)

	w.loadDefault = W.Button(page, "Load recommended", 130, 20, function()
		RF.Core:LoadRecommended() -- follows the raid again from now on
		Changed()
	end)
	w.loadDefault:SetPoint("TOPLEFT", 370, -44)
	w.baseline = W.Label(page, "", "GameFontDisableSmall")
	w.baseline:SetPoint("TOPLEFT", 370, -66)
	w.baseline:SetWidth(190)

	----------------------------------------------------------------- class/spec needs
	h = W.Header(page, "Class / spec needs")
	h:SetPoint("TOPLEFT", 0, -76)
	h.line:SetWidth(350)
	w.needSummary = W.Label(page, "", "GameFontHighlightSmall")
	w.needSummary:SetPoint("TOPRIGHT", page, "TOPLEFT", 350, -78)
	w.needSummary:SetJustifyH("RIGHT")

	w.needClass = W.Dropdown(page, 90, function() return W.ClassItems() end, function(value)
		sel.needClass, sel.needSpec = value, "ANY"
		w.needSpec:SetValue("ANY", "Any spec")
	end)
	w.needClass:SetPoint("TOPLEFT", -16, -92)
	w.needSpec = W.Dropdown(page, 90, function() return W.SpecItems(sel.needClass, true) end, function(value)
		sel.needSpec = value
	end)
	w.needSpec:SetPoint("LEFT", w.needClass, "RIGHT", -28, 0)
	w.needCount = W.EditBox(page, 20, true, function(text) sel.needCount = math.max(1, tonumber(text) or 1) end, 2)
	w.needCount:SetPoint("LEFT", w.needSpec, "RIGHT", -6, 2)
	w.needAdd = W.Button(page, "Add", 40, 20, function()
		sel.needCount = math.max(1, tonumber(w.needCount:GetText()) or 1)
		AddNeed(sel.needClass, (sel.needSpec ~= "ANY") and sel.needSpec or nil, sel.needCount, true)
	end)
	w.needAdd:SetPoint("LEFT", w.needCount, "RIGHT", 4, 0)

	local cols = { { "Class", 4 }, { "Spec", 100 }, { "Role", 196 }, { "Count", 268 } }
	for _, c in ipairs(cols) do
		local l = W.Label(page, c[1], "GameFontNormalSmall")
		l:SetPoint("TOPLEFT", c[2], -126)
	end

	w.needList = W.ScrollList(page, 360, 10, 20, function(row)
		row.class = W.Label(row, "", "GameFontHighlightSmall"); row.class:SetPoint("LEFT", 4, 0); row.class:SetWidth(94)
		row.spec = W.Label(row, "", "GameFontHighlightSmall"); row.spec:SetPoint("LEFT", 100, 0); row.spec:SetWidth(94)
		row.role = W.Label(row, "", "GameFontHighlightSmall"); row.role:SetPoint("LEFT", 196, 0); row.role:SetWidth(70)
		row.minus = W.Button(row, "-", 18, 18, function()
			row.data.count = math.max(1, (row.data.count or 1) - 1)
			Edited()
		end)
		row.minus:SetPoint("LEFT", 262, 0)
		row.count = W.Label(row, "", "GameFontHighlight"); row.count:SetWidth(20); row.count:SetJustifyH("CENTER")
		row.count:SetPoint("LEFT", row.minus, "RIGHT", 0, 0)
		row.plus = W.Button(row, "+", 18, 18, function()
			row.data.count = math.min(40, (row.data.count or 1) + 1)
			Edited()
		end)
		row.plus:SetPoint("LEFT", row.count, "RIGHT", 0, 0)
		row.remove = W.Button(row, "x", 18, 18, function()
			for i, need in ipairs(P().needs) do
				if need == row.data then table.remove(P().needs, i); break end
			end
			Edited()
		end)
		row.remove:SetPoint("RIGHT", -2, 0)
	end, function(row, need)
		row.class:SetText(W.ClassColor(need.class) .. RF.CLASS_NAMES[need.class] .. "|r")
		row.spec:SetText(need.spec and RF.SPECS[need.spec].name or "|cff999999Any spec|r")
		row.role:SetText(RoleOfNeed(need))
		row.count:SetText(need.count or 1)
	end)
	w.needList:SetPoint("TOPLEFT", 0, -140)

	w.needWarning = W.Label(page, "", "GameFontHighlightSmall")
	w.needWarning:SetPoint("TOPLEFT", 0, -343)
	w.needWarning:SetWidth(350)

	----------------------------------------------------------------- class caps
	h = W.Header(page, "Class caps (max)")
	h:SetPoint("TOPLEFT", 370, -76)
	h.line:SetWidth(190)

	w.capClass = W.Dropdown(page, 80, function() return W.ClassItems() end, function(value) sel.capClass = value end)
	w.capClass:SetPoint("TOPLEFT", 354, -92)
	w.capMax = W.EditBox(page, 20, true, function(text) sel.capMax = tonumber(text) or 0 end, 2)
	w.capMax:SetPoint("LEFT", w.capClass, "RIGHT", -6, 2)
	w.capAdd = W.Button(page, "Add", 36, 20, function()
		sel.capMax = tonumber(w.capMax:GetText()) or sel.capMax
		local caps = P().caps
		for _, cap in ipairs(caps) do
			if cap.class == sel.capClass then cap.max = sel.capMax; return Edited() end
		end
		caps[#caps + 1] = { class = sel.capClass, max = sel.capMax }
		Edited()
	end)
	w.capAdd:SetPoint("LEFT", w.capMax, "RIGHT", 2, 0)

	w.capList = W.ScrollList(page, 190, 4, 20, function(row)
		row.text = W.Label(row, "", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 4, 0)
		row.text:SetWidth(130)
		row.remove = W.Button(row, "x", 18, 18, function()
			for i, cap in ipairs(P().caps) do
				if cap == row.data then table.remove(P().caps, i); break end
			end
			Edited()
		end)
		row.remove:SetPoint("RIGHT", -2, 0)
	end, function(row, cap)
		row.text:SetText(string.format("%s%s|r max %d", W.ClassColor(cap.class), RF.CLASS_NAMES[cap.class], cap.max))
	end)
	w.capList:SetPoint("TOPLEFT", 370, -126)

	----------------------------------------------------------------- quick add needs
	h = W.Header(page, "Quick add need (+1)")
	h:SetPoint("TOPLEFT", 370, -214)
	h.line:SetWidth(190)
	for i, q in ipairs(QUICK_NEEDS) do
		local label, class, spec = q[1], q[2], q[3]
		local b = W.Button(page, label, 93, 20, function() AddNeed(class, spec, 1) end)
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		b:SetPoint("TOPLEFT", 370 + col * 96, -232 - row * 22)
	end

	----------------------------------------------------------------- presets
	h = W.Header(page, "Presets")
	h:SetPoint("TOPLEFT", 0, -358)
	h.line:SetWidth(560)
	w.presetDrop = W.Dropdown(page, 150, function()
		local items = {}
		local names = {}
		for name in pairs(RF.db.presets) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do items[#items + 1] = { text = name, value = name } end
		if #items == 0 then items[1] = { text = "(none saved)", value = nil } end
		return items
	end, function(value) sel.preset = value end)
	w.presetDrop:SetPoint("TOPLEFT", -16, -372)
	local load = W.Button(page, "Load", 60, 22, function() if sel.preset then LoadPreset(sel.preset) end end)
	load:SetPoint("LEFT", w.presetDrop, "RIGHT", -6, 2)
	local save = W.Button(page, "Save as...", 80, 22, function() StaticPopup_Show("RAIDFORMER_SAVE_PRESET") end)
	save:SetPoint("LEFT", load, "RIGHT", 4, 0)
	local del = W.Button(page, "Delete", 60, 22, function()
		if sel.preset and RF.db.presets[sel.preset] then
			RF.db.presets[sel.preset] = nil
			RF.Print("Preset deleted: " .. sel.preset)
			sel.preset = nil
			Changed()
		end
	end)
	del:SetPoint("LEFT", save, "RIGHT", 4, 0)
end

local function Refresh(page)
	local p = P()
	for role, s in pairs(w.roles) do s:SetValue(p.roles[role] or 0) end
	w.baseline:SetText(RF.Core:BaselineText())
	local total = RF.Comp.RoleTotal(p)
	local color = (total == p.size) and "|cff40ff40" or "|cffff4040"
	w.total:SetText(string.format("Total: %s%d|r / %d", color, total, p.size))

	w.needClass:SetValue(sel.needClass)
	w.needSpec:SetValue(sel.needSpec, sel.needSpec == "ANY" and "Any spec" or RF.SPECS[sel.needSpec].name)
	if not w.needCount:HasFocus() then w.needCount:SetText(sel.needCount) end
	w.needList:SetData(p.needs)

	local players = 0
	for _, need in ipairs(p.needs) do players = players + (need.count or 1) end
	w.needSummary:SetText(string.format("%d need%s, %d player%s", #p.needs, #p.needs == 1 and "" or "s", players, players == 1 and "" or "s"))
	local problems = RF.Comp.NeedsOverflow(p)
	w.needWarning:SetText(#problems > 0 and ("|cffff4040" .. table.concat(problems, "; ") .. "|r") or "")

	w.capClass:SetValue(sel.capClass)
	if not w.capMax:HasFocus() then w.capMax:SetText(sel.capMax) end
	w.capList:SetData(p.caps)

	w.presetDrop:SetValue(sel.preset, sel.preset or "Select preset")
end

RF.UI:RegisterPage(2, "Formation", Build, Refresh)
