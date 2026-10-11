-- Setup tab: raid, size, difficulty, GS, channel, interval, extras, preview.
local _, RF = ...

local w = {}
local ROLE_CHOICES = { "tank", "heal", "dps" }
local ROLE_CHOICE_NAMES = { tank = "Tank", heal = "Healer", dps = "DPS" }

local function P() return RF.profile end

local function Changed()
	RF.UI:Refresh()
end

-- Raid/size/difficulty changed: optionally load the recommended formation and GS.
local function RaidChanged()
	-- only while on the recommended setup; a preset or your own edits are kept
	RF.Core:RaidSettingsChanged()
	Changed()
end

local function ExtrasParts(text)
	local parts = {}
	for part in (text or ""):gmatch("[^,]+") do
		part = part:gsub("^%s+", ""):gsub("%s+$", "")
		if part ~= "" then parts[#parts + 1] = part end
	end
	return parts
end

local function ToggleExtra(label)
	local parts = ExtrasParts(P().extras)
	for i, part in ipairs(parts) do
		if part:lower() == label:lower() then
			table.remove(parts, i)
			P().extras = table.concat(parts, ", ")
			return Changed()
		end
	end
	parts[#parts + 1] = label
	P().extras = table.concat(parts, ", ")
	Changed()
end

local function HasExtra(label)
	for _, part in ipairs(ExtrasParts(P().extras)) do
		if part:lower() == label:lower() then return true end
	end
	return false
end

local function Build(page)
	local W = RF.W
	local LEFT, RIGHT = 0, 290

	----------------------------------------------------------------- left column
	local h = W.Header(page, "Raid")
	h:SetPoint("TOPLEFT", LEFT, 0)

	w.raid = W.Dropdown(page, 150, function()
		local items = {}
		for _, r in ipairs(RF.RAIDS) do items[#items + 1] = { text = r.name, value = r.key } end
		return items
	end, function(value)
		local p = P()
		p.raid = value
		local r = RF.RAID_BY_KEY[value]
		if not r.heroic then p.heroic = false end
		if not r.custom and p.size ~= 10 and p.size ~= 25 then p.size = 25 end
		RaidChanged()
	end)
	w.raid:SetPoint("TOPLEFT", LEFT - 16, -18)

	w.size10 = W.Radio(page, "10 man", function() P().size = 10; RaidChanged() end)
	w.size10:SetPoint("TOPLEFT", LEFT, -54)
	w.size25 = W.Radio(page, "25 man", function() P().size = 25; RaidChanged() end)
	w.size25:SetPoint("LEFT", w.size10, "RIGHT", 60, 0)

	w.customLabel = W.Label(page, "Name / size:", "GameFontHighlightSmall")
	w.customLabel:SetPoint("TOPLEFT", LEFT, -80)
	w.customName = W.EditBox(page, 70, false, function(text)
		P().customName = text:gsub("%s", ""):upper()
		Changed()
	end, 8)
	w.customName:SetPoint("LEFT", w.customLabel, "RIGHT", 10, 0)
	w.customSize = W.EditBox(page, 30, true, function(text)
		local n = tonumber(text)
		if n and n >= 2 and n <= 40 then P().size = n; RaidChanged() else Changed() end
	end, 2)
	w.customSize:SetPoint("LEFT", w.customName, "RIGHT", 10, 0)

	w.normal = W.Radio(page, "Normal", function() P().heroic = false; RaidChanged() end)
	w.normal:SetPoint("TOPLEFT", LEFT, -104)
	w.heroic = W.Radio(page, "Heroic", function() P().heroic = true; RaidChanged() end)
	w.heroic:SetPoint("LEFT", w.normal, "RIGHT", 60, 0)

	w.autoDefaults = W.Check(page, "Load recommended formation on change", function(v) P().autoDefaults = v end)
	w.autoDefaults:SetPoint("TOPLEFT", LEFT - 4, -126)
	w.baseline = W.Label(page, "", "GameFontDisableSmall")
	w.baseline:SetPoint("TOPLEFT", LEFT + 24, -146)

	local myLabel = W.Label(page, "My spec:", "GameFontHighlightSmall")
	myLabel:SetPoint("TOPLEFT", LEFT, -160)
	w.mySpec = W.Dropdown(page, 100, function()
		local items = {}
		for _, role in ipairs(ROLE_CHOICES) do
			items[#items + 1] = { text = ROLE_CHOICE_NAMES[role], value = role, disabled = not RF.Core:RoleAvailable(role) }
		end
		return items
	end, function(value) P().myRole = value; Changed() end)
	w.mySpec:SetPoint("LEFT", myLabel, "RIGHT", -8, -2)

	local groupsLabel = W.Label(page, "Raid groups: Forming / Final buttons on the Roster tab", "GameFontHighlightSmall")
	groupsLabel:SetPoint("TOPLEFT", LEFT, -196)

	local pendLabel = W.Label(page, "Uninspected group:", "GameFontHighlightSmall")
	pendLabel:SetPoint("TOPLEFT", LEFT, -218)
	w.pendingGroup = W.EditBox(page, 16, true, function(text)
		local n = tonumber(text)
		if n and n >= 1 and n <= 8 then P().pendingGroup = n end
		Changed()
	end, 1)
	w.pendingGroup:SetPoint("LEFT", pendLabel, "RIGHT", 8, 0)
	local accLabel = W.Label(page, "Accepted from:", "GameFontHighlightSmall")
	accLabel:SetPoint("LEFT", w.pendingGroup, "RIGHT", 14, 0)
	w.acceptedGroup = W.EditBox(page, 16, true, function(text)
		local n = tonumber(text)
		if n and n >= 1 and n <= 8 then P().acceptedGroup = n end
		Changed()
	end, 1)
	w.acceptedGroup:SetPoint("LEFT", accLabel, "RIGHT", 8, 0)

	----------------------------------------------------------------- right column
	h = W.Header(page, "Requirements & announcing")
	h:SetPoint("TOPLEFT", RIGHT, 0)

	local gsLabel = W.Label(page, "Min GearScore:", "GameFontHighlightSmall")
	gsLabel:SetPoint("TOPLEFT", RIGHT, -26)
	w.minGS = W.EditBox(page, 50, true, function(text)
		local n = tonumber(text)
		if n then P().minGS = n; RF.Core:MarkEdited() end
		Changed()
	end, 4)
	w.minGS:SetPoint("LEFT", gsLabel, "RIGHT", 10, 0)
	w.gsSlider = W.Slider(page, 250, 3000, 6500, 50, function(v) P().minGS = v; RF.Core:MarkEdited(); Changed() end)
	w.gsSlider:SetPoint("TOPLEFT", RIGHT, -50)

	local chLabel = W.Label(page, "Channels:", "GameFontHighlightSmall")
	chLabel:SetPoint("TOPLEFT", RIGHT, -86)
	w.channels = W.MultiDropdown(page, 150, function()
		local items = {}
		local list = { GetChannelList() }
		for i = 1, #list, 2 do
			items[#items + 1] = { text = list[i] .. ". " .. list[i + 1], value = list[i + 1] }
		end
		-- keep selected channels visible even if not joined right now
		for _, ch in ipairs(P().channels) do
			local found = false
			for _, item in ipairs(items) do if item.value == ch then found = true end end
			if not found then items[#items + 1] = { text = ch .. " (not joined)", value = ch } end
		end
		return items
	end, function(value)
		for _, ch in ipairs(P().channels) do
			if ch == value then return true end
		end
		return false
	end, function(value)
		local channels = P().channels
		for i, ch in ipairs(channels) do
			if ch == value then
				table.remove(channels, i)
				return Changed()
			end
		end
		channels[#channels + 1] = value
		Changed()
	end)
	w.channels:SetPoint("LEFT", chLabel, "RIGHT", -8, -2)

	w.guild = W.Check(page, "Guild", function(v) P().postGuild = v; Changed() end)
	w.guild:SetPoint("TOPLEFT", RIGHT - 4, -110)
	w.yell = W.Check(page, "Yell", function(v) P().postYell = v; Changed() end)
	w.yell:SetPoint("LEFT", w.guild, "RIGHT", 60, 0)

	local intLabel = W.Label(page, "Seconds between posts:", "GameFontHighlightSmall")
	intLabel:SetPoint("TOPLEFT", RIGHT, -142)
	w.interval = W.EditBox(page, 40, true, function(text)
		local n = tonumber(text)
		if n then P().interval = math.max(30, n) end
		Changed()
	end, 4)
	w.interval:SetPoint("LEFT", intLabel, "RIGHT", 10, 0)

	local toLabel = W.Label(page, "Inspect timeout (sec):", "GameFontHighlightSmall")
	toLabel:SetPoint("TOPLEFT", RIGHT, -166)
	w.timeout = W.EditBox(page, 40, true, function(text)
		local n = tonumber(text)
		if n then P().inspectTimeout = math.max(60, n) end
		Changed()
	end, 4)
	w.timeout:SetPoint("LEFT", toLabel, "RIGHT", 10, 0)
	local warnLabel = W.Label(page, "Warn before (sec):", "GameFontHighlightSmall")
	warnLabel:SetPoint("LEFT", w.timeout, "RIGHT", 10, 0)
	w.warn = W.EditBox(page, 30, true, function(text)
		local n = tonumber(text)
		if n then P().warnBefore = math.max(0, math.min(n, P().inspectTimeout - 10)) end
		Changed()
	end, 3)
	w.warn:SetPoint("LEFT", warnLabel, "RIGHT", 8, 0)

	w.autoKick = W.Check(page, "Auto kick", function(v) P().autoKick = v end)
	w.autoKick:SetPoint("TOPLEFT", RIGHT - 4, -186)
	w.strict = W.Check(page, "Kick wrong spec claims", function(v) P().rejectWrongSpec = v end)
	w.strict:SetPoint("LEFT", w.autoKick, "RIGHT", 70, 0)
	w.raidUpdates = W.Check(page, "Still need in /raid", function(v) P().raidUpdates = v end)
	w.raidUpdates:SetPoint("TOPLEFT", RIGHT - 4, -208)
	w.rwOnJoin = W.Check(page, "RW on join:", function(v) P().raidWarnOnJoin = v end)
	w.rwOnJoin:SetPoint("LEFT", w.raidUpdates, "RIGHT", 104, 0)
	w.rwText = W.EditBox(page, 50, false, function(text)
		P().raidWarnText = RF.SafeChat(text)
		Changed()
	end, 40)
	w.rwText:SetPoint("LEFT", w.rwOnJoin, "RIGHT", 64, 0)

	w.requireInspect = W.Check(page, "Require inspect", function(v) P().requireInspect = v; Changed() end)
	w.requireInspect:SetPoint("TOPLEFT", RIGHT - 4, -228)
	w.remindInspect = W.Check(page, "Remind to inspect", function(v) P().remindInspect = v end)
	w.remindInspect:SetPoint("LEFT", w.requireInspect, "RIGHT", 96, 0)

	----------------------------------------------------------------- extras + preview
	h = W.Header(page, "Announcement extras")
	h:SetPoint("TOPLEFT", LEFT, -240)
	h.line:SetWidth(560)

	w.extraButtons = {}
	local x, y = LEFT, -260
	for _, label in ipairs(RF.EXTRA_PRESETS) do
		local b = W.Button(page, label, 10, 20, function() ToggleExtra(label) end)
		local width = b:GetFontString():GetStringWidth() + 20
		b:SetWidth(width)
		if x + width > 560 then x, y = LEFT, y - 22 end
		b:SetPoint("TOPLEFT", x, y)
		x = x + width + 4
		b.label = label
		w.extraButtons[#w.extraButtons + 1] = b
	end

	-- your own text, placed right before "/w spec + GS"
	local freeLabel = W.Label(page, "Free text:", "GameFontHighlightSmall")
	freeLabel:SetPoint("TOPLEFT", LEFT, -290)
	w.freeText = W.EditBox(page, 480, false, function(text)
		P().freeText = RF.SafeChat(text)
		Changed()
	end, 80)
	w.freeText:SetPoint("LEFT", freeLabel, "RIGHT", 12, 0)

	h = W.Header(page, "Preview")
	h:SetPoint("TOPLEFT", LEFT, -314)
	h.line:SetWidth(560)
	w.showCount = W.Check(page, "Show 23/25 in the LFM line", function(v) P().showCount = v; Changed() end)
	w.showCount:SetPoint("TOPLEFT", LEFT + 70, -310)
	w.lfmStyle = W.Dropdown(page, 95, function()
		local items = {}
		for _, s in ipairs(RF.LFM_STYLES) do items[#items + 1] = { text = s.name, value = s.key } end
		return items
	end, function(value) P().lfmStyle = value; Changed() end)
	w.lfmStyle:SetPoint("TOPLEFT", LEFT + 232, -304)
	w.lfmIcon = W.Dropdown(page, 70, function()
		local items = {}
		for _, icon in ipairs(RF.LFM_ICONS) do items[#items + 1] = { text = icon, value = icon } end
		return items
	end, function(value) P().lfmIcon = value; Changed() end)
	w.lfmIcon:SetPoint("LEFT", w.lfmStyle, "RIGHT", -28, 0)
	w.count = W.Label(page, "", "GameFontHighlightSmall")
	w.count:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -314)
	w.preview = W.Label(page, "", "GameFontHighlight")
	w.preview:SetPoint("TOPLEFT", LEFT, -332)
	w.preview:SetWidth(560)
	w.preview:SetJustifyV("TOP")
end

local function Refresh(page)
	local p = P()
	local r = RF.RAID_BY_KEY[p.raid] or RF.RAIDS[1]
	w.raid:SetValue(p.raid, r.name)

	w.size10:SetChecked(p.size == 10)
	w.size25:SetChecked(p.size == 25)
	if r.custom then
		w.customLabel:Show(); w.customName:Show(); w.customSize:Show()
		if not w.customName:HasFocus() then w.customName:SetText(p.customName or "") end
		if not w.customSize:HasFocus() then w.customSize:SetText(p.size) end
	else
		w.customLabel:Hide(); w.customName:Hide(); w.customSize:Hide()
	end

	w.normal:SetChecked(not p.heroic)
	w.heroic:SetChecked(p.heroic)
	if r.heroic then w.heroic:Enable(); w.normal:Enable() else w.heroic:Disable(); w.normal:Disable() end
	w.autoDefaults:SetChecked(p.autoDefaults)
	w.baseline:SetText(RF.Core:BaselineText())
	local mySpec = RF.SPECS[RF.Core:MySpec()]
	local myRole = mySpec and ((mySpec.role == "tank" or mySpec.role == "heal") and mySpec.role or "dps")
	w.mySpec:SetValue(p.myRole, (ROLE_CHOICE_NAMES[myRole] or "?") .. (p.myRole and "" or " (talents)"))

	if not w.minGS:HasFocus() then w.minGS:SetText(p.minGS) end
	w.gsSlider:SetSilent(math.max(3000, math.min(6500, p.minGS)))
	local names = {}
	for _, ch in ipairs(p.channels) do names[#names + 1] = (ch:gsub(" %- .*", "")) end
	UIDropDownMenu_SetText(w.channels, #names > 0 and table.concat(names, ", ") or "None")
	w.guild:SetChecked(p.postGuild)
	w.yell:SetChecked(p.postYell)
	if not w.interval:HasFocus() then w.interval:SetText(p.interval) end
	if not w.timeout:HasFocus() then w.timeout:SetText(p.inspectTimeout) end
	if not w.warn:HasFocus() then w.warn:SetText(p.warnBefore) end
	if not w.pendingGroup:HasFocus() then w.pendingGroup:SetText(p.pendingGroup) end
	if not w.acceptedGroup:HasFocus() then w.acceptedGroup:SetText(p.acceptedGroup) end
	w.autoKick:SetChecked(p.autoKick)
	w.strict:SetChecked(p.rejectWrongSpec)
	w.raidUpdates:SetChecked(p.raidUpdates)
	w.rwOnJoin:SetChecked(p.raidWarnOnJoin)
	w.showCount:SetChecked(p.showCount)
	local styleName = "Clean dashes"
	for _, s in ipairs(RF.LFM_STYLES) do if s.key == p.lfmStyle then styleName = s.name end end
	w.lfmStyle:SetValue(p.lfmStyle, styleName)
	w.lfmIcon:SetValue(p.lfmIcon, p.lfmIcon)
	if p.lfmStyle == "icons" then w.lfmIcon:Show() else w.lfmIcon:Hide() end
	w.requireInspect:SetChecked(p.requireInspect)
	w.remindInspect:SetChecked(p.remindInspect)
	if p.requireInspect then w.remindInspect:Enable() else w.remindInspect:Disable() end
	if not w.rwText:HasFocus() then w.rwText:SetText(p.raidWarnText or "") end

	if not w.freeText:HasFocus() then w.freeText:SetText(p.freeText or "") end
	for _, b in ipairs(w.extraButtons) do
		if HasExtra(b.label) then b:LockHighlight() else b:UnlockHighlight() end
	end

	local msg = RF.Core:Announcement()
	w.preview:SetText(msg)
	w.count:SetText((#msg > 255 and "|cffff4040" or "") .. #msg .. "/255")
end

RF.UI:RegisterPage(1, "Setup", Build, Refresh)
