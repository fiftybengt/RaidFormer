-- Settings tab: raid, recruiting, inspect & kick, raid chat & groups, interface, announcement.
local _, RF = ...

local w = {}
local LEFT, RIGHT, FIELD = 0, 316, 74

local function P() return RF.profile end
local function Changed() RF.UI:Redraw() end

-- Raid/size/difficulty changed: the recommended setup follows (a preset or your own edits are
-- kept, with role counts fitted to a new size).
local function RaidChanged(oldSize)
	RF.Core:RaidSettingsChanged(oldSize)
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

local function MiniDB() return RF.db.ui.mini end

local function Build(page)
	local W = RF.W
	local function Field(text, x, y)
		local l = W.Label(page, text, "RaidFormerFontMuted")
		l:SetPoint("TOPLEFT", x, y - 4)
		return l
	end
	local function Tip(frame, title, ...) W.Tip(frame, title, { ... }) end

	----------------------------------------------------------------- Raid
	W.Header(page, "Raid", 300):SetPoint("TOPLEFT", LEFT, 0)
	w.raid = W.Dropdown(page, 226, function()
		local items = {}
		for _, r in ipairs(RF.RAIDS) do items[#items + 1] = { text = r.name, value = r.key } end
		return items
	end, function(value)
		local p = P()
		local oldSize = p.size
		p.raid = value
		local r = RF.RAID_BY_KEY[value]
		if not r.heroic then p.heroic = false end
		if not r.custom and p.size ~= 10 and p.size ~= 25 then p.size = 25 end
		RaidChanged(oldSize)
	end)
	Field("Raid", LEFT, -20)
	w.raid:SetPoint("TOPLEFT", LEFT + FIELD, -20)

	Field("Size", LEFT, -46)
	w.size = W.Segmented(page, { { text = "10", value = 10 }, { text = "25", value = 25 } }, 40, function(v)
		local old = P().size
		P().size = v
		RaidChanged(old)
	end)
	w.size:SetPoint("TOPLEFT", LEFT + FIELD, -46)
	w.customName = W.EditBox(page, 60, false, function(text)
		P().customName = text:gsub("%s", ""):upper()
		Changed()
	end, 8)
	w.customName:SetPoint("TOPLEFT", LEFT + FIELD + 90, -46)
	Tip(w.customName, "Raid name", "Shown in the LFM line, e.g. VOA or ONY.")
	w.customSize = W.EditBox(page, 30, true, function(text)
		local n = tonumber(text)
		if n and n >= 2 and n <= 40 then local old = P().size; P().size = n; RaidChanged(old) else Changed() end
	end, 2)
	w.customSize:SetPoint("LEFT", w.customName, "RIGHT", 4, 0)
	Tip(w.customSize, "Raid size", "2 to 40.")

	Field("Difficulty", LEFT, -70)
	w.difficulty = W.Segmented(page, { { text = "Normal", value = false }, { text = "Heroic", value = true } }, 60, function(v)
		P().heroic = v
		RaidChanged()
	end)
	w.difficulty:SetPoint("TOPLEFT", LEFT + FIELD, -70)

	Field("My role", LEFT, -94)
	w.myRole = W.Segmented(page, {
		{ text = "Auto", value = "auto", width = 46, tip = { "Auto", { "From your talents." } } },
		{ text = "Tank", value = "tank", width = 46 }, { text = "Healer", value = "heal", width = 54 },
		{ text = "DPS", value = "dps", width = 44 },
	}, 46, function(v)
		P().myRole = (v ~= "auto") and v or nil
		Changed()
	end)
	w.myRole:SetPoint("TOPLEFT", LEFT + FIELD, -94)

	w.autoDefaults = W.Check(page, "Follow the recommended formation", function(v) P().autoDefaults = v end)
	w.autoDefaults:SetPoint("TOPLEFT", LEFT, -122)
	Tip(w.autoDefaults, "Follow the recommended formation",
		"While you're on the recommended setup, changing raid, size or difficulty loads the new one. A preset or your own edits are always kept.")
	w.baseline = W.Label(page, "", "RaidFormerFontMuted")
	w.baseline:SetPoint("TOPLEFT", LEFT + 19, -138)
	w.baseline:SetWidth(280)

	----------------------------------------------------------------- Recruiting
	W.Header(page, "Recruiting", 300):SetPoint("TOPLEFT", LEFT, -160)
	Field("Min GS", LEFT, -180)
	w.minGS = W.EditBox(page, 48, true, function(text)
		local n = tonumber(text)
		if n then P().minGS = n; RF.Core:MarkEdited() end
		Changed()
	end, 4)
	w.minGS:SetPoint("TOPLEFT", LEFT + FIELD, -180)
	w.gsSlider = W.Slider(page, 168, 3000, 6500, 50, function(v) P().minGS = v; RF.Core:MarkEdited(); Changed() end)
	w.gsSlider:SetPoint("LEFT", w.minGS, "RIGHT", 8, 0)

	Field("Channels", LEFT, -204)
	w.channels = W.MultiDropdown(page, 226, function()
		local items = {}
		for _, c in ipairs(RF.Core:ChannelList()) do
			items[#items + 1] = { text = c.id .. ". " .. c.name, value = c.name }
		end
		-- keep selected channels visible even if not joined right now
		for _, ch in ipairs(P().channels) do
			local found = false
			for _, item in ipairs(items) do if item.value == ch then found = true end end
			if not found then
				items[#items + 1] = { text = ch .. (RF.Core:ChannelId(ch) and "" or " (not joined)"), value = ch }
			end
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
	w.channels:SetPoint("TOPLEFT", LEFT + FIELD, -204)
	Tip(w.channels, "Channels", "Posted to each in turn, 0.8-1.2s apart.")
	w.guild = W.Check(page, "Guild", function(v) P().postGuild = v; Changed() end)
	w.guild:SetPoint("TOPLEFT", LEFT + FIELD, -232)
	w.yell = W.Check(page, "Yell", function(v) P().postYell = v; Changed() end)
	w.yell:SetPoint("TOPLEFT", LEFT + FIELD + 80, -232)

	Field("Post every", LEFT, -252)
	w.interval = W.EditBox(page, 40, true, function(text)
		local n = tonumber(text)
		if n then P().interval = math.max(30, n) end
		Changed()
	end, 4)
	w.interval:SetPoint("TOPLEFT", LEFT + FIELD, -252)
	local sec = W.Label(page, "seconds (min 30)", "RaidFormerFontMuted")
	sec:SetPoint("LEFT", w.interval, "RIGHT", 6, 0)

	----------------------------------------------------------------- Inspect & kick
	W.Header(page, "Inspect & kick", 300):SetPoint("TOPLEFT", RIGHT, 0)
	w.requireInspect = W.Check(page, "Require inspect", function(v) P().requireInspect = v; Changed() end)
	w.requireInspect:SetPoint("TOPLEFT", RIGHT, -22)
	Tip(w.requireInspect, "Require inspect", "Off: whoever joins is accepted at their whispered word - no inspect, no GS check, no timeout.")
	w.remindInspect = W.Check(page, "Remind to inspect", function(v) P().remindInspect = v end)
	w.remindInspect:SetPoint("TOPLEFT", RIGHT + 150, -22)
	Tip(w.remindInspect, "Remind to inspect", "Warn players to come to you, and remove them after the timeout.")

	Field("Timeout", RIGHT, -42)
	w.timeout = W.EditBox(page, 44, true, function(text)
		local n = tonumber(text)
		if n then P().inspectTimeout = math.max(60, n) end
		Changed()
	end, 4)
	w.timeout:SetPoint("TOPLEFT", RIGHT + 60, -42)
	Field("Warn before", RIGHT + 150, -42)
	w.warn = W.EditBox(page, 36, true, function(text)
		local n = tonumber(text)
		if n then P().warnBefore = math.max(0, math.min(n, P().inspectTimeout - 10)) end
		Changed()
	end, 3)
	w.warn:SetPoint("TOPLEFT", RIGHT + 226, -42)
	Tip(w.timeout, "Inspect timeout (seconds)", "How long players get to come to you.")
	Tip(w.warn, "Warn before (seconds)", "0 = no warning.")

	w.autoKick = W.Check(page, "Auto kick", function(v) P().autoKick = v end)
	w.autoKick:SetPoint("TOPLEFT", RIGHT, -68)
	Tip(w.autoKick, "Auto kick", "Off: players who fail stay in the raid, you're told in chat - Kick or Accept them on the Raid tab.")
	w.strict = W.Check(page, "Kick wrong spec claims", function(v) P().rejectWrongSpec = v end)
	w.strict:SetPoint("TOPLEFT", RIGHT + 150, -68)
	Tip(w.strict, "Kick wrong spec claims", "Remove players whose talents don't match what they whispered, even if they'd fit.")

	----------------------------------------------------------------- Raid chat & groups
	W.Header(page, "Raid chat & groups", 300):SetPoint("TOPLEFT", RIGHT, -92)
	w.raidUpdates = W.Check(page, "Post \"still need\" in /raid", function(v) P().raidUpdates = v end)
	w.raidUpdates:SetPoint("TOPLEFT", RIGHT, -114)
	w.rwOnJoin = W.Check(page, "RW on join", function(v) P().raidWarnOnJoin = v end)
	w.rwOnJoin:SetPoint("TOPLEFT", RIGHT, -138)
	w.rwText = W.EditBox(page, 150, false, function(text)
		P().raidWarnText = RF.SafeChat(text)
		Changed()
	end, 40)
	w.rwText:SetPoint("TOPLEFT", RIGHT + 100, -134)
	Tip(w.rwText, "Raid warning on join", "e.g. g1 vh - joins within 10s share one warning.")

	Field("Uninspected group", RIGHT, -160)
	w.pendingGroup = W.EditBox(page, 22, true, function(text)
		local n = tonumber(text)
		if n and n >= 1 and n <= 8 then P().pendingGroup = n end
		Changed()
	end, 1)
	w.pendingGroup:SetPoint("TOPLEFT", RIGHT + 108, -160)
	Field("Others from", RIGHT + 150, -160)
	w.acceptedGroup = W.EditBox(page, 22, true, function(text)
		local n = tonumber(text)
		if n and n >= 1 and n <= 8 then P().acceptedGroup = n end
		Changed()
	end, 1)
	w.acceptedGroup:SetPoint("TOPLEFT", RIGHT + 226, -160)

	----------------------------------------------------------------- Interface
	W.Header(page, "Interface", 300):SetPoint("TOPLEFT", RIGHT, -188)
	Field("Scale", RIGHT, -208)
	local dragging = false
	local function ApplyScale(v)
		RF.db.ui.scale = v
		if RF.UI.frame then RF.UI.frame:SetScale(v) end
		if RF.UI.mini then RF.UI.mini:SetScale(v) end
	end
	w.scale = W.Slider(page, 150, 0.7, 1.4, 0.05, function(v)
		w.scaleText:SetText(string.format("%d%%", v * 100 + 0.5))
		if not dragging then ApplyScale(v) end
	end)
	w.scale:SetPoint("TOPLEFT", RIGHT + 60, -212)
	w.scale:SetScript("OnMouseDown", function() dragging = true end)
	w.scale:SetScript("OnMouseUp", function(self)
		dragging = false
		ApplyScale(math.floor(self:GetValue() / 0.05 + 0.5) * 0.05)
	end)
	w.scaleText = W.Label(page, "", "RaidFormerFontMuted")
	w.scaleText:SetPoint("LEFT", w.scale, "RIGHT", 8, 0)

	Field("Mini bar", RIGHT, -232)
	w.miniMode = W.Segmented(page, {
		{ text = "Running", value = "running", width = 62, tip = { "Mini bar", { "Shown while RaidFormer is running and this window is closed." } } },
		{ text = "Always", value = "always", width = 58, tip = { "Mini bar", { "Shown whenever this window is closed." } } },
		{ text = "Never", value = "never", width = 52 },
	}, 58, function(v) MiniDB().mode = v; Changed() end)
	w.miniMode:SetPoint("TOPLEFT", RIGHT + 60, -232)
	w.miniLock = W.Check(page, "Lock mini bar", function(v) MiniDB().locked = v end)
	w.miniLock:SetPoint("TOPLEFT", RIGHT, -260)
	w.minimap = W.Check(page, "Minimap button", function(v)
		RF.db.minimap.hide = not v
		local b = RF.UI.minimapButton
		if b then if v then b:Show() else b:Hide() end end
	end)
	w.minimap:SetPoint("TOPLEFT", RIGHT + 150, -260)

	----------------------------------------------------------------- Announcement
	W.Header(page, "Announcement", 616):SetPoint("TOPLEFT", LEFT, -282)
	w.count = W.Label(page, "", "RaidFormerFontMuted")
	w.count:SetPoint("TOPRIGHT", page, "TOPLEFT", 616, -282)
	w.count:SetJustifyH("RIGHT")

	Field("Style", LEFT, -302)
	w.lfmStyle = W.Dropdown(page, 120, function()
		local items = {}
		for _, s in ipairs(RF.LFM_STYLES) do items[#items + 1] = { text = s.name, value = s.key } end
		return items
	end, function(value) P().lfmStyle = value; Changed() end)
	w.lfmStyle:SetPoint("TOPLEFT", LEFT + 44, -302)
	w.lfmIcon = W.Dropdown(page, 76, function()
		local items = {}
		for _, icon in ipairs(RF.LFM_ICONS) do items[#items + 1] = { text = icon, value = icon } end
		return items
	end, function(value) P().lfmIcon = value; Changed() end)
	w.lfmIcon:SetPoint("LEFT", w.lfmStyle, "RIGHT", 4, 0)

	-- extras: toggle buttons, right-aligned on the style row
	w.extraButtons = {}
	local x = 616
	for i = #RF.EXTRA_PRESETS, 1, -1 do
		local label = RF.EXTRA_PRESETS[i]
		local b = W.Button(page, label, 10, 20, function() ToggleExtra(label) end)
		local width = b:GetFontString():GetStringWidth() + 16
		b:SetWidth(width)
		x = x - width
		b:SetPoint("TOPLEFT", x, -302)
		x = x - 4
		b.label = label
		w.extraButtons[#w.extraButtons + 1] = b
	end
	W.Tip(w.extraButtons[#w.extraButtons], "Extras", { "Toggle what goes in the LFM line." })

	Field("Free text", LEFT, -328)
	w.freeText = W.EditBox(page, 616 - FIELD, false, function(text)
		P().freeText = RF.SafeChat(text)
		Changed()
	end, 80)
	w.freeText:SetPoint("TOPLEFT", LEFT + FIELD, -328)
	Tip(w.freeText, "Free text", "Up to 80 characters, right before /w spec + GS.")

	w.previewBox = CreateFrame("Frame", nil, page)
	w.previewBox:SetPoint("TOPLEFT", LEFT, -356)
	w.previewBox:SetWidth(616)
	w.previewBox:SetHeight(40)
	RF.Skin.Backdrop(w.previewBox, RF.Skin.C.input)
	w.preview = W.Label(w.previewBox, "", "RaidFormerFontSmall")
	w.preview:SetPoint("TOPLEFT", 6, -5)
	w.preview:SetPoint("BOTTOMRIGHT", -6, 5)
	w.preview:SetJustifyV("TOP")
end

local function Refresh(page)
	local p = P()
	local r = RF.RAID_BY_KEY[p.raid] or RF.RAIDS[1]
	w.raid:SetValue(p.raid, r.name)

	w.size:SetValue(p.size)
	if r.custom then
		w.customName:Show(); w.customSize:Show()
		if not w.customName:HasFocus() then w.customName:SetText(p.customName or "") end
		if not w.customSize:HasFocus() then w.customSize:SetText(p.size) end
	else
		w.customName:Hide(); w.customSize:Hide()
	end
	w.difficulty:SetValue(p.heroic and true or false)
	w.difficulty:SetEnabled(r.heroic and true or false)
	w.myRole:SetValue(p.myRole or "auto")
	for _, b in ipairs(w.myRole.buttons) do
		if b.value == "auto" or RF.Core:RoleAvailable(b.value) then b:Enable() else b:Disable() end
		b:Paint()
	end
	local mySpec = RF.SPECS[RF.Core:MySpec()]
	w.autoDefaults:SetChecked(p.autoDefaults)
	w.baseline:SetText(RF.Core:BaselineText() .. (mySpec and ("   You count as " .. mySpec.short .. ".") or ""))

	if not w.minGS:HasFocus() then w.minGS:SetText(p.minGS) end
	w.gsSlider:SetSilent(math.max(3000, math.min(6500, p.minGS)))
	local names = {}
	for _, ch in ipairs(p.channels) do names[#names + 1] = (ch:gsub(" %- .*", "")) end
	w.channels:SetText(#names > 0 and table.concat(names, ", ") or "None")
	w.guild:SetChecked(p.postGuild)
	w.yell:SetChecked(p.postYell)
	if not w.interval:HasFocus() then w.interval:SetText(p.interval) end

	w.requireInspect:SetChecked(p.requireInspect)
	w.remindInspect:SetChecked(p.remindInspect)
	if p.requireInspect then w.remindInspect:Enable() else w.remindInspect:Disable() end
	if not w.timeout:HasFocus() then w.timeout:SetText(p.inspectTimeout) end
	if not w.warn:HasFocus() then w.warn:SetText(p.warnBefore) end
	w.autoKick:SetChecked(p.autoKick)
	w.strict:SetChecked(p.rejectWrongSpec)

	w.raidUpdates:SetChecked(p.raidUpdates)
	w.rwOnJoin:SetChecked(p.raidWarnOnJoin)
	if not w.rwText:HasFocus() then w.rwText:SetText(p.raidWarnText or "") end
	if not w.pendingGroup:HasFocus() then w.pendingGroup:SetText(p.pendingGroup) end
	if not w.acceptedGroup:HasFocus() then w.acceptedGroup:SetText(p.acceptedGroup) end

	local scale = RF.db.ui.scale or 1
	w.scale:SetSilent(scale)
	w.scaleText:SetText(string.format("%d%%", scale * 100 + 0.5))
	w.miniMode:SetValue(MiniDB().mode or "running")
	w.miniLock:SetChecked(MiniDB().locked)
	w.minimap:SetChecked(not RF.db.minimap.hide)

	local styleName = "Clean dashes"
	for _, s in ipairs(RF.LFM_STYLES) do if s.key == p.lfmStyle then styleName = s.name end end
	w.lfmStyle:SetValue(p.lfmStyle, styleName)
	w.lfmIcon:SetValue(p.lfmIcon, p.lfmIcon)
	if p.lfmStyle == "icons" then w.lfmIcon:Show() else w.lfmIcon:Hide() end
	for _, b in ipairs(w.extraButtons) do b:SetActive(HasExtra(b.label)) end
	if not w.freeText:HasFocus() then w.freeText:SetText(p.freeText or "") end

	local msg = RF.Core:Announcement()
	w.preview:SetText(msg)
	w.count:SetText((#msg > 255 and RF.Skin.Hex(RF.Skin.C.bad) or "") .. #msg .. "/255")
end

RF.UI:RegisterPage(3, "Settings", Build, Refresh)
