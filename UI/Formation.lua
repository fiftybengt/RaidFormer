-- Formation tab: role counts, class/spec needs and caps (as chips, added from a class-icon grid),
-- presets.
local _, RF = ...

local w = {}
local sel = { mode = "need", preset = nil }

local function P() return RF.profile end
local function Changed() RF.UI:Redraw() end
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
function RF.UI.AddNeed(class, spec, count)
	local needs = P().needs
	for _, need in ipairs(needs) do
		if need.class == class and need.spec == spec then
			need.count = math.min(40, (need.count or 1) + (count or 1))
			return Edited()
		end
	end
	needs[#needs + 1] = { class = class, spec = spec, count = count or 1 }
	Edited()
end

-- Adds a cap (max 1 to start, raise it with +), or raises an identical one.
function RF.UI.AddCap(class, spec)
	local caps = P().caps
	for _, cap in ipairs(caps) do
		if cap.class == class and cap.spec == spec then
			cap.max = math.min(40, (cap.max or 0) + 1)
			return Edited()
		end
	end
	caps[#caps + 1] = { class = class, spec = spec, max = 1 }
	Edited()
end

local function Remove(list, item)
	for i, x in ipairs(list) do
		if x == item then table.remove(list, i); return end
	end
end

-- Class icon clicked: pick the spec (or any) to add as a need or a cap.
local classMenu
local function ShowClassMenu(class, anchor)
	classMenu = classMenu or RF.W.NewMenuFrame()
	local isCap = sel.mode == "cap"
	local menu = { { text = (isCap and "Cap: " or "Need: ") .. RF.CLASS_NAMES[class], isTitle = true, notCheckable = true } }
	menu[#menu + 1] = {
		text = isCap and "Any spec (class cap)" or ("Any " .. RF.CLASS_NAMES[class]), notCheckable = true,
		func = function() if isCap then RF.UI.AddCap(class, nil) else RF.UI.AddNeed(class, nil, 1) end end,
	}
	for _, key in ipairs(RF.CLASS_SPECS[class]) do
		local spec = RF.SPECS[key]
		menu[#menu + 1] = {
			text = spec.name .. " (" .. spec.short .. ")", notCheckable = true,
			func = function() if isCap then RF.UI.AddCap(class, key) else RF.UI.AddNeed(class, key, 1) end end,
		}
	end
	EasyMenu(menu, classMenu, anchor, 0, 0, "MENU")
end

local function Build(page)
	local W, Skin = RF.W, RF.Skin
	local C = Skin.C

	----------------------------------------------------------------- roles
	local h = W.Header(page, "Roles", 616)
	h:SetPoint("TOPLEFT", 0, 0)
	w.roles = {}
	local layout = {
		{ "tank", "Tank", 0, -20 }, { "heal", "Healer", 150, -20 }, { "mdps", "Melee", 300, -20 },
		{ "rdps", "Ranged", 0, -44 }, { "flex", "Any DPS", 150, -44 },
	}
	for _, l in ipairs(layout) do
		local role = l[1]
		local s = W.Spinner(page, l[2], 50, 0, 40, function(v) P().roles[role] = v; Edited() end, role)
		s:SetPoint("TOPLEFT", l[3], l[4])
		w.roles[role] = s
	end
	W.Tip(w.roles.flex, "Any DPS", { "Spots for melee or ranged, whoever comes first - for when you don't mind which.",
		"Shown as 'dps' in the LFM line." })
	w.total = W.Label(page, "", "RaidFormerFontBig")
	w.total:SetPoint("TOPLEFT", 470, -22)
	w.loadDefault = W.Button(page, "Load recommended", 130, 20, function()
		RF.Core:LoadRecommended() -- follows the raid again from now on
		Changed()
	end)
	w.loadDefault:SetPoint("TOPLEFT", 300, -44)
	W.Tip(w.loadDefault, "Load recommended", { "The recommended setup for this raid and size; it follows raid changes again." })
	w.baseline = W.Label(page, "", "RaidFormerFontMuted")
	w.baseline:SetPoint("TOPLEFT", 470, -40)
	w.baseline:SetWidth(146)

	----------------------------------------------------------------- needs & caps
	h = W.Header(page, "Class / spec needs and caps", 616)
	h:SetPoint("TOPLEFT", 0, -76)
	w.mode = W.Segmented(page, {
		{ text = "Need", value = "need", width = 52, tip = { "Add a need", { "Reserves a spot for that class or spec." } } },
		{ text = "Cap", value = "cap", width = 52, tip = { "Add a cap", { "Maximum of a class, or of one spec (e.g. max 1 rdru)." } } },
	}, 52, function(v) sel.mode = v; Changed() end)
	w.mode:SetPoint("TOPLEFT", 0, -96)
	w.addHint = W.Label(page, "", "RaidFormerFontMuted")
	w.addHint:SetPoint("TOPLEFT", 114, -100)
	for i, class in ipairs(RF.CLASSES) do
		local b = W.Button(page, "", 22, 22, function(self) ShowClassMenu(class, self) end)
		b:SetPoint("TOPLEFT", 238 + (i - 1) * 25, -95)
		local icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", -2, 2)
		Skin.SetClassIcon(icon, class)
		W.Tip(b, W.ClassColor(class) .. RF.CLASS_NAMES[class] .. "|r", { "Click to pick the spec." })
	end

	w.needsLabel = W.Label(page, "Needs", "RaidFormerFontMuted")
	w.needsLabel:SetPoint("TOPLEFT", 0, -128)
	w.needSummary = W.Label(page, "", "RaidFormerFontMuted")
	w.needSummary:SetPoint("TOPRIGHT", page, "TOPLEFT", 616, -128)
	w.needSummary:SetJustifyH("RIGHT")
	w.needChips = {}
	w.needEmpty = W.Label(page, "None - every spot is open to any class.", "RaidFormerFontSmall")
	w.needEmpty:SetPoint("TOPLEFT", 0, -144)
	W.SetColor(w.needEmpty, C.muted)

	w.warning = W.Banner(page, 616)
	w.warning:SetPoint("TOPLEFT", 0, -228)

	w.capsLabel = W.Label(page, "Caps", "RaidFormerFontMuted")
	w.capsLabel:SetPoint("TOPLEFT", 0, -252)
	w.capChips = {}
	w.capEmpty = W.Label(page, "None.", "RaidFormerFontSmall")
	w.capEmpty:SetPoint("TOPLEFT", 0, -268)
	W.SetColor(w.capEmpty, C.muted)

	----------------------------------------------------------------- presets
	h = W.Header(page, "Presets", 616)
	h:SetPoint("TOPLEFT", 0, -324)
	w.presetDrop = W.Dropdown(page, 180, function()
		local items, names = {}, {}
		for name in pairs(RF.db.presets) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do items[#items + 1] = { text = name, value = name } end
		if #items == 0 then items[1] = { text = "(none saved)", value = nil, disabled = true } end
		return items
	end, function(value) sel.preset = value end)
	w.presetDrop:SetPoint("TOPLEFT", 0, -344)
	local load = W.Button(page, "Load", 60, 20, function() if sel.preset then LoadPreset(sel.preset) end end)
	load:SetPoint("LEFT", w.presetDrop, "RIGHT", 6, 0)
	local save = W.Button(page, "Save as...", 80, 20, function() StaticPopup_Show("RAIDFORMER_SAVE_PRESET") end)
	save:SetPoint("LEFT", load, "RIGHT", 4, 0)
	local del = W.Button(page, "Delete", 60, 20, function()
		if sel.preset and RF.db.presets[sel.preset] then
			RF.db.presets[sel.preset] = nil
			RF.Print("Preset deleted: " .. sel.preset)
			sel.preset = nil
			Changed()
		end
	end)
	del:SetPoint("LEFT", save, "RIGHT", 4, 0)
	W.Tip(load, "Load preset", { "Your baseline: changing raid, size or difficulty afterwards keeps it." })

	local hint = W.Label(page, "Shift-click - / + to step by 5.  Needs are named in the LFM line only once they're all that's left.", "RaidFormerFontMuted")
	hint:SetPoint("BOTTOMLEFT", 0, 4)
end

local function Refresh(page)
	local W, C = RF.W, RF.Skin.C
	local p = P()
	for role, s in pairs(w.roles) do s:SetValue(p.roles[role] or 0) end
	local total = RF.Comp.RoleTotal(p)
	w.total:SetText(string.format("Total  %s%d|r / %d", RF.Skin.Hex(total == p.size and C.good or C.bad), total, p.size))
	w.baseline:SetText(RF.Core:BaselineText())

	w.mode:SetValue(sel.mode)
	w.addHint:SetText(sel.mode == "cap" and "Add a cap - click a class:" or "Add a need - click a class:")

	-- need chips: "2x hpal" [-][+][x]
	for i, need in ipairs(p.needs) do
		local chip = w.needChips[i]
		if not chip then
			chip = W.Chip(page, {
				{ text = "-", onClick = function(c) c.item.count = math.max(1, (c.item.count or 1) - 1); Edited() end },
				{ text = "+", onClick = function(c) c.item.count = math.min(40, (c.item.count or 1) + 1); Edited() end },
				{ text = "x", onClick = function(c) Remove(P().needs, c.item); Edited() end },
			})
			w.needChips[i] = chip
		end
		chip.item = need
		local count = need.count or 1
		local role = need.spec and RF.SPECS[need.spec] and RF.SPECS[need.spec].role
		chip:Set(W.ClassColor(need.class) .. (count > 1 and (count .. "x ") or "") .. RF.Comp.NeedLabel(need) .. "|r", C.button,
			role and function(tex) RF.Skin.SetRoleIcon(tex, role) end or function(tex) RF.Skin.SetClassIcon(tex, need.class) end)
	end
	W.Flow(w.needChips, #p.needs, page, 0, -144, 616, 4)
	if #p.needs == 0 then w.needEmpty:Show() else w.needEmpty:Hide() end
	local players = 0
	for _, need in ipairs(p.needs) do players = players + (need.count or 1) end
	w.needSummary:SetText(string.format("%d need%s, %d player%s", #p.needs, #p.needs == 1 and "" or "s", players, players == 1 and "" or "s"))
	w.warning:SetMessages(RF.Comp.NeedsOverflow(p))

	-- cap chips: "Druid max 3", "rdru max 1"
	for i, cap in ipairs(p.caps) do
		local chip = w.capChips[i]
		if not chip then
			chip = W.Chip(page, {
				{ text = "-", onClick = function(c) c.item.max = math.max(0, (c.item.max or 0) - 1); Edited() end },
				{ text = "+", onClick = function(c) c.item.max = math.min(40, (c.item.max or 0) + 1); Edited() end },
				{ text = "x", onClick = function(c) Remove(P().caps, c.item); Edited() end },
			})
			w.capChips[i] = chip
		end
		chip.item = cap
		local what = cap.spec and RF.SPECS[cap.spec] and RF.SPECS[cap.spec].short or RF.CLASS_NAMES[cap.class]
		chip:Set(W.ClassColor(cap.class) .. what .. "|r max " .. (cap.max or 0), C.button,
			function(tex) RF.Skin.SetClassIcon(tex, cap.class) end)
	end
	W.Flow(w.capChips, #p.caps, page, 0, -268, 616, 2)
	if #p.caps == 0 then w.capEmpty:Show() else w.capEmpty:Hide() end

	w.presetDrop:SetValue(sel.preset, sel.preset or "Select preset")
end

RF.UI:RegisterPage(2, "Formation", Build, Refresh)
