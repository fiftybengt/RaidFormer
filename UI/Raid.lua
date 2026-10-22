-- Raid tab (dashboard): progress, roles, needs, the LFM line, problems, and the roster in sections
-- (In raid / Waiting for inspect / Invited / History). Rows: hover for Insp/Accept/Kick, right-click
-- for the full menu, click the spec to set it.
local _, RF = ...

local w = {}
RF.UI.widgets = RF.UI.widgets or {}
RF.UI.widgets.raid = w -- for tests and debugging
local ROWS, ROW_H = 15, 20
local ORDER = { accepted = 1, waiting = 2, invited = 3, refused = 4, rejected = 5, timeout = 6, declined = 7, expired = 8, left = 9 }

local SECTIONS = {
	{ key = "raid", title = "In raid" },
	{ key = "waiting", title = "Waiting for inspect" },
	{ key = "invited", title = "Invited" },
	{ key = "history", title = "History" },
}

local function SectionOf(m)
	if m.status == "waiting" then return "waiting" end
	if m.status == "invited" then return "invited" end
	if m.inGroup or m.status == "accepted" then return "raid" end
	return "history"
end
RF.UI.SectionOf = SectionOf

local function Collapsed(key)
	local c = RF.db.ui.collapsed
	if c[key] == nil then return key == "history" end -- history starts folded
	return c[key]
end

---------------------------------------------------------------------------
-- Status text
---------------------------------------------------------------------------

local STATUS_COLOR = {
	accepted = "good", waiting = "warn", invited = "accent", rejected = "bad", timeout = "bad",
	refused = "bad", left = "muted", expired = "muted", declined = "muted",
}

local function Clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- inspect queue places, rebuilt once per redraw / tick (not per row)
local queuePos = {}

local function StatusText(m)
	local C, hex = RF.Skin.C, RF.Skin.Hex
	if m.status == "waiting" then
		if m.confirming then return hex(C.warn) .. "Confirming GS...|r" end
		if m.inspecting then return hex(C.warn) .. "Inspecting...|r" end
		if m.arrivedAt then return hex(C.warn) .. "In queue #" .. (queuePos[m.name] or "?") .. "|r" end
		local p = RF.profile
		if m.joinedAt and not m.manual and p.requireInspect and p.remindInspect and RF.Core.running then
			return hex(C.warn) .. "Come for inspect|r " .. hex(C.muted) .. Clock(p.inspectTimeout - (GetTime() - m.joinedAt)) .. "|r"
		end
	end
	local text = hex(C[STATUS_COLOR[m.status] or "text"]) .. (RF.STATUS[m.status] or m.status or "") .. "|r"
	if m.reason and (m.status == "rejected" or m.status == "refused" or m.status == "timeout") then
		text = text .. hex(C.muted) .. " - " .. m.reason .. "|r"
	end
	if m.inGroup and not RF.HOLDING[m.status] then text = text .. hex(C.warn) .. " (in raid)|r" end
	return text
end

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------

-- Click on a player's spec: pick the right spec from their class.
local specMenu
function RF.UI.ShowSpecMenu(m, anchor)
	if not m then return end
	if not (m.class and RF.CLASS_SPECS[m.class]) then
		RF.Print("Class of " .. m.name .. " is not known until they are in the raid.")
		return
	end
	specMenu = specMenu or RF.W.NewMenuFrame()
	local menu = { { text = "Spec for " .. m.name, isTitle = true, notCheckable = true } }
	for _, key in ipairs(RF.CLASS_SPECS[m.class]) do
		local spec = RF.SPECS[key]
		menu[#menu + 1] = {
			text = spec.name .. " (" .. spec.short .. ")" .. (m.offSpec == key and " - 2nd spec" or ""),
			checked = (m.spec == key and not m.specGuessed),
			func = function() RF.Core:SetSpec(m.name, key) end,
		}
	end
	RF.W.ToggleMenu(specMenu, menu, anchor, nil, m.name)
end

-- Right-click on a row: everything you can do with that player.
local rowMenu
function RF.UI.ShowRowMenu(m, anchor)
	if not m then return end
	rowMenu = rowMenu or RF.W.NewMenuFrame()
	local core, name = RF.Core, m.name
	local menu = {
		{ text = name, isTitle = true, notCheckable = true },
		{ text = "Accept", notCheckable = true, disabled = (m.status == "accepted"), func = function() core:ManualAccept(name) end },
		{ text = "Inspect again", notCheckable = true, disabled = not RF.UnitForName(name), func = function() core:Reinspect(name) end },
		{ text = "Kick", notCheckable = true, func = function() core:ManualKick(name) end },
		{ text = "Whisper", notCheckable = true, func = function() if ChatFrame_SendTell then ChatFrame_SendTell(name) end end },
	}
	if m.class and RF.CLASS_SPECS[m.class] then
		menu[#menu + 1] = { text = "Set spec", isTitle = true, notCheckable = true }
		for _, key in ipairs(RF.CLASS_SPECS[m.class]) do
			local spec = RF.SPECS[key]
			menu[#menu + 1] = {
				text = spec.name .. " (" .. spec.short .. ")",
				checked = (m.spec == key and not m.specGuessed),
				func = function() core:SetSpec(name, key) end,
			}
		end
	end
	menu[#menu + 1] = { text = CANCEL or "Cancel", notCheckable = true, func = function() end }
	RF.W.ToggleMenu(rowMenu, menu, anchor, nil, m.name)
end

---------------------------------------------------------------------------
-- Problems worth a banner
---------------------------------------------------------------------------

function RF.UI.Alerts()
	local p, core, list = RF.profile, RF.Core, {}
	if not core:CanInvite() then list[#list + 1] = "You're not raid leader or assistant - RaidFormer can't invite or kick." end
	local total = RF.Comp.RoleTotal(p)
	if total ~= p.size then list[#list + 1] = string.format("Role counts add up to %d, the raid is %d - fix it on the Formation tab.", total, p.size) end
	for _, problem in ipairs(RF.Comp.NeedsOverflow(p)) do list[#list + 1] = "Formation: " .. problem .. "." end
	if #p.channels == 0 and not p.postGuild and not p.postYell then
		list[#list + 1] = "No channel to post in - pick one in Settings."
	else
		for _, ch in ipairs(p.channels) do
			if not core:ChannelId(ch) then list[#list + 1] = "You're not in channel '" .. ch .. "'." end
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

-- Only one row shows its highlight and Accept/Insp/Kick at a time: entering a row clears the last
-- one, redraws reset the others, and a check on the list clears it once the mouse is gone
-- (enter/leave events alone miss fast moves from a button onto the next row).
local hovered

local function SetHover(row, on)
	if on then row.hl:Show() else row.hl:Hide() end
	local buttons = on and row.data and not row.data.isHeader
	for _, b in ipairs({ row.insp, row.accept, row.kick }) do
		if buttons then b:Show() else b:Hide() end
	end
end

local function ClearHover()
	if hovered then SetHover(hovered, false) end
	hovered = nil
end
w.ClearHover = ClearHover
function w.Hovered() return hovered end

local function RowEnter(row)
	local m = row.data
	if not m then return end
	if hovered ~= row then ClearHover() end
	hovered = row
	SetHover(row, true)
	if m.isHeader then return end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:AddLine(RF.W.ClassColor(m.class) .. m.name .. "|r")
	if m.whisper then GameTooltip:AddLine("Whispered: " .. m.whisper, 0.8, 0.8, 1, true) end
	if m.claimedGS then GameTooltip:AddLine("Said GS: " .. m.claimedGS, 0.8, 0.8, 1) end
	if m.offLabel then
		GameTooltip:AddLine("Second spec: " .. m.offLabel .. (m.offGS and (" (" .. RF.Comp.FormatGS(m.offGS) .. ")") or ""), 0.8, 0.8, 1)
	end
	if m.inOffSpec then GameTooltip:AddLine("Inspected in their second spec's talents - counted as picked", 1, 0.82, 0, true) end
	if m.reason then GameTooltip:AddLine(m.reason, 1, 0.4, 0.4, true) end
	if m.ilvl then GameTooltip:AddLine("Avg item level: " .. m.ilvl, 1, 1, 1) end
	if m.manual then GameTooltip:AddLine("Let in by you - counted, never removed", 0.4, 1, 0.4) end
	if m.specByLeader then GameTooltip:AddLine("Spec set by you", 0.4, 1, 0.4) end
	if m.specGuessed then GameTooltip:AddLine("Spec is a guess until inspected - click the spec to set it", 1, 0.82, 0, true) end
	if m.readings and #m.readings > 1 then
		local gsList = {}
		for _, r in ipairs(m.readings) do gsList[#gsList + 1] = tostring(r.gs) end
		GameTooltip:AddLine("GS readings: " .. table.concat(gsList, ", "), 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine("Right-click for more", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function RowLeave(row)
	GameTooltip:Hide()
	if MouseIsOver and MouseIsOver(row) then return end -- moved onto one of its buttons
	if hovered == row then ClearHover() else SetHover(row, false) end
end

local function Build(page)
	local W, Skin = RF.W, RF.Skin
	local C = Skin.C

	-- progress + state
	w.bar = W.Bar(page, 380, 18)
	w.bar:SetPoint("TOPLEFT", 0, 0)
	w.bar:EnableMouse(true)
	w.bar:SetScript("OnEnter", function(self)
		local me = RF.SPECS[RF.Core:MySpec()]
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:AddLine("Raid spots taken")
		GameTooltip:AddLine("Counts everyone in the raid or invited, and you (as " .. (me and me.short or "?") .. ").", 1, 0.82, 0.4, true)
		GameTooltip:Show()
	end)
	w.bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
	w.state = W.Label(page, "", "RaidFormerFont")
	w.state:SetPoint("LEFT", w.bar, "RIGHT", 10, 0)

	-- role chips (tank, heal, melee, ranged, any dps)
	w.roleChips = {}
	for i, role in ipairs({ "tank", "heal", "mdps", "rdps", "flex" }) do
		local chip = W.Chip(page)
		chip.role = role
		W.Tip(chip, role == "flex" and "Any DPS" or RF.ROLE_NAMES[role], { role == "flex" and "Spots for melee or ranged, whoever comes first." or "In the raid / wanted." })
		w.roleChips[i] = chip
	end
	w.needChips = {}

	-- the LFM line, click to edit it
	w.lfm = CreateFrame("Button", nil, page)
	w.lfm:SetWidth(616)
	w.lfm:SetHeight(32)
	Skin.Backdrop(w.lfm, C.input)
	w.lfm.text = W.Label(w.lfm, "", "RaidFormerFontSmall")
	w.lfm.text:SetPoint("TOPLEFT", 6, -4)
	w.lfm.text:SetPoint("BOTTOMRIGHT", -6, 4)
	w.lfm.text:SetJustifyV("TOP")
	w.lfm:SetScript("OnClick", function() RF.UI:SelectTab(3) end)
	W.Tip(w.lfm, "LFM line", { "What gets posted, updated as the raid fills. Click to edit it (Settings)." })

	w.banner = W.Banner(page, 616)

	-- roster
	local cols = { { "Name", 22 }, { "Spec", 136 }, { "GS", 244 }, { "Status", 292 } }
	w.cols = {}
	for i, c in ipairs(cols) do
		local l = W.Label(page, c[1], "RaidFormerFontMuted")
		w.cols[i] = { label = l, x = c[2] }
	end

	w.list = W.ScrollList(page, 616, ROWS, ROW_H, function(row)
		-- section header widgets
		row.title = W.Label(row, "", "RaidFormerFontHeader")
		row.title:SetHeight(ROW_H)
		row.title:SetPoint("LEFT", 4, 0)
		row.fold = W.Label(row, "", "RaidFormerFontMuted")
		row.fold:SetPoint("RIGHT", -6, 0)
		row.line = W.Solid(row, C.line)
		row.line:SetHeight(1)
		row.line:SetPoint("BOTTOMLEFT", 0, 1)
		row.line:SetPoint("BOTTOMRIGHT", 0, 1)
		row.clear = W.TextButton(row, "clear", function() RF.Core:ClearApplicants() end)
		row.clear:SetPoint("RIGHT", row.fold, "LEFT", -10, 0)
		W.Tip(row.clear, "Clear history", { "Forget refused, removed and left players (everyone still in the raid stays)." })

		-- member widgets
		row.classIcon = row:CreateTexture(nil, "ARTWORK")
		row.classIcon:SetWidth(14)
		row.classIcon:SetHeight(14)
		row.classIcon:SetPoint("LEFT", 4, 0)
		row.name = W.Label(row, "", "RaidFormerFont"); row.name:SetPoint("LEFT", 22, 0); row.name:SetWidth(110); row.name:SetHeight(ROW_H)
		row.roleIcon = row:CreateTexture(nil, "ARTWORK")
		row.roleIcon:SetWidth(14)
		row.roleIcon:SetHeight(14)
		row.roleIcon:SetPoint("LEFT", 136, 0)
		row.spec = W.Label(row, "", "RaidFormerFont"); row.spec:SetPoint("LEFT", 154, 0); row.spec:SetWidth(86); row.spec:SetHeight(ROW_H)
		row.specButton = CreateFrame("Button", nil, row)
		row.specButton:SetWidth(104)
		row.specButton:SetHeight(ROW_H)
		row.specButton:SetPoint("LEFT", 136, 0)
		row.specButton:SetScript("OnClick", function(self) RF.UI.ShowSpecMenu(row.data, self) end)
		W.Tip(row.specButton, "Spec", { "Click to set this player's spec." }, "ANCHOR_RIGHT")
		row.gs = W.Label(row, "", "RaidFormerFont"); row.gs:SetPoint("LEFT", 244, 0); row.gs:SetWidth(44); row.gs:SetHeight(ROW_H)
		row.status = W.Label(row, "", "RaidFormerFontSmall"); row.status:SetPoint("LEFT", 292, 0); row.status:SetPoint("RIGHT", -4, 0)
		row.status:SetHeight(ROW_H) -- one line: a long reason is cut off instead of spilling into the next row

		-- hover actions
		row.kick = W.Button(row, "Kick", 36, 16, function() RF.Core:ManualKick(row.data.name) end, "bad")
		row.kick:SetPoint("RIGHT", -2, 0)
		row.insp = W.Button(row, "Insp", 36, 16, function() RF.Core:Reinspect(row.data.name) end)
		row.insp:SetPoint("RIGHT", row.kick, "LEFT", -2, 0)
		W.Tip(row.insp, "Inspect again", { "Confirms GS and talents; moves them to the uninspected group (not with Manual groups)." })
		row.accept = W.Button(row, "Accept", 46, 16, function() RF.Core:ManualAccept(row.data.name) end, "good")
		row.accept:SetPoint("RIGHT", row.insp, "LEFT", -2, 0)
		W.Tip(row.accept, "Accept", { "Let them in yourself: counted, never removed." })
		for _, b in ipairs({ row.kick, row.insp, row.accept }) do
			b:Hide()
			b.onLeave = function() RowLeave(row) end
		end

		row:SetScript("OnEnter", RowEnter)
		row:SetScript("OnLeave", RowLeave)
		row:SetScript("OnClick", function(self, button)
			local m = self.data
			if not m then return end
			if m.isHeader then
				RF.db.ui.collapsed[m.key] = not Collapsed(m.key)
				RF.UI:Redraw()
			elseif button == "RightButton" then
				RF.UI.ShowRowMenu(m, self)
			end
		end)
	end, function(row, m)
		local W, C, hex = RF.W, RF.Skin.C, RF.Skin.Hex
		local header = m.isHeader
		SetHover(row, row == hovered)
		for _, el in ipairs({ row.title, row.fold, row.line }) do if header then el:Show() else el:Hide() end end
		for _, el in ipairs({ row.classIcon, row.name, row.roleIcon, row.spec, row.specButton, row.gs, row.status }) do
			if header then el:Hide() else el:Show() end
		end
		if header then
			row.title:SetText(string.upper(m.title) .. hex(C.muted) .. "  " .. m.count .. "|r")
			row.fold:SetText(m.collapsed and "show" or "hide")
			if m.key == "history" and m.count > 0 then row.clear:Show() else row.clear:Hide() end
			return
		end
		row.clear:Hide()
		RF.Skin.SetClassIcon(row.classIcon, m.class)
		row.name:SetText(W.ClassColor(m.class) .. m.name .. "|r")
		local spec = m.spec and RF.SPECS[m.spec]
		if spec then
			RF.Skin.SetRoleIcon(row.roleIcon, spec.role)
			row.roleIcon:Show()
		else
			row.roleIcon:Hide()
		end
		-- a trailing "?" = spec guessed from class/role, the inspect will tell
		local off = m.offSpec ~= m.spec and (m.offSpec and RF.SPECS[m.offSpec] and RF.SPECS[m.offSpec].short or m.offLabel)
		row.spec:SetText((spec and spec.short or "?") .. (m.specGuessed and "?" or "") .. (off and (hex(C.muted) .. "/" .. off .. "|r") or ""))
		local gsText = m.gs and tostring(m.gs) or (m.inspecting and "..." or (hex(C.muted) .. (m.claimedGS or "-") .. "|r"))
		if m.gs and m.gs < RF.profile.minGS then gsText = hex(C.bad) .. gsText .. "|r" end
		row.gs:SetText(gsText)
		row.status:SetText(StatusText(m))
		if m.status == "accepted" then row.accept:Disable() else row.accept:Enable() end
		if RF.UnitForName(m.name) then row.insp:Enable() else row.insp:Disable() end
	end)

	-- safety net: whatever events were missed, the buttons go once the mouse has left that row
	local since = 0
	w.list:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < 0.1 then return end
		since = 0
		if hovered and not (hovered:IsShown() and MouseIsOver and MouseIsOver(hovered)) then ClearHover() end
	end)
end

---------------------------------------------------------------------------
-- Refresh (on changes) / Status (every tick)
---------------------------------------------------------------------------

-- Roster as one list: section headers followed by their members (folded sections: header only).
function RF.UI.RosterItems()
	local bySection = {}
	for _, s in ipairs(SECTIONS) do bySection[s.key] = {} end
	queuePos = RF.Inspect:QueuePositions()
	for _, m in pairs(RF.members) do table.insert(bySection[SectionOf(m)], m) end
	local items = {}
	for _, s in ipairs(SECTIONS) do
		local list = bySection[s.key]
		if #list > 0 then
			table.sort(list, function(a, b)
				if s.key == "waiting" then
					local qa, qb = queuePos[a.name] or 99, queuePos[b.name] or 99
					if qa ~= qb then return qa < qb end
				end
				local oa, ob = ORDER[a.status] or 99, ORDER[b.status] or 99
				if oa ~= ob then return oa < ob end
				return a.name < b.name
			end)
			local folded = Collapsed(s.key)
			items[#items + 1] = { isHeader = true, key = s.key, title = s.title, count = #list, collapsed = folded }
			if not folded then
				for _, m in ipairs(list) do items[#items + 1] = m end
			end
		end
	end
	return items
end

local function Status(page)
	local p, core, C = RF.profile, RF.Core, RF.Skin.C
	local holders = #core:Holders()
	w.bar:Set(holders, p.size, holders >= p.size and C.good or C.warn,
		string.format("%s  %d / %d", RF.RaidTag(p.raid, p.size, p.heroic, p.customName), holders, p.size))
	w.state:SetText(RF.UI:StateText())
	-- timers and queue positions change every tick: only touch the rows on screen
	queuePos = RF.Inspect:QueuePositions()
	for _, row in ipairs(w.list:VisibleRows()) do
		if not row.data.isHeader and row.data.status == "waiting" then row.status:SetText(StatusText(row.data)) end
	end
end

local function Refresh(page)
	local W, C = RF.W, RF.Skin.C
	local p = RF.profile
	local holders = RF.Core:Holders()
	local counts = RF.Comp.Count(p, holders)

	-- roles: icon + have/want (melee and ranged share the dps icon, so they get a letter)
	local PREFIX = { tank = "", heal = "", mdps = "M ", rdps = "R ", flex = "Any " }
	local x = 0
	for _, chip in ipairs(w.roleChips) do
		local want, have = p.roles[chip.role] or 0, nil
		if chip.role == "flex" then
			local _, flexFree = RF.Comp.Free(p, counts)
			have = want - flexFree
		else
			have = counts.role[chip.role]
		end
		if chip.role == "flex" and want == 0 then
			chip:Hide()
		else
			chip:Set(PREFIX[chip.role] .. have .. "/" .. want, have >= want and C.goodBg or C.button,
				function(tex) RF.Skin.SetRoleIcon(tex, chip.role) end)
			chip:ClearAllPoints()
			chip:SetPoint("TOPLEFT", page, "TOPLEFT", x, -26)
			chip:Show()
			x = x + chip:GetWidth() + 4
		end
	end

	-- needs: still missing first; what doesn't fit in two rows goes into a "+N more" chip
	local entries = {}
	for i, need in ipairs(p.needs) do
		local have, want = counts.need[i] or 0, need.count or 1
		entries[#entries + 1] = { text = W.ClassColor(need.class) .. RF.Comp.NeedLabel(need) .. (want > 1 and (" " .. have .. "/" .. want) or "") .. "|r",
			plain = RF.Comp.NeedLabel(need) .. " " .. have .. "/" .. want, met = have >= want, order = i }
	end
	for _, buff in ipairs(RF.BUFFS) do
		local want = p.buffs[buff]
		if want then
			local have = counts.buff[buff] or 0
			local text = RF.BUFF_SHORT[buff] .. " " .. have .. "/" .. want
			entries[#entries + 1] = { text = text, plain = text, met = have >= want, order = 100 + #entries }
		end
	end
	table.sort(entries, function(a, b)
		if a.met ~= b.met then return not a.met end
		return a.order < b.order
	end)
	for i, e in ipairs(entries) do
		local chip = w.needChips[i] or W.Chip(page)
		w.needChips[i] = chip
		chip:Set(e.text, e.met and C.goodBg or C.badBg)
	end
	if not w.moreChip then
		w.moreChip = W.Chip(page)
		w.moreChip:EnableMouse(true)
	end
	w.moreChip:Hide()
	local _, hidden = W.Flow(w.needChips, #entries, page, 0, -50, 616, 2)
	if hidden > 0 then
		-- room for the "+N more" chip: drop chips from the end until everything fits
		for shown = #entries - 1, 0, -1 do
			local list = {}
			for i = 1, shown do list[i] = w.needChips[i] end
			local rest = {}
			for i = shown + 1, #entries do rest[#rest + 1] = (entries[i].met and "in: " or "missing: ") .. entries[i].plain end
			w.moreChip:Set("+" .. (#entries - shown) .. " more", C.button)
			W.Tip(w.moreChip, "More needs", rest)
			list[#list + 1] = w.moreChip
			local _, left = W.Flow(list, #list, page, 0, -50, 616, 2)
			if left == 0 then
				for i = shown + 1, #w.needChips do w.needChips[i]:Hide() end
				break
			end
		end
	end

	-- LFM line, problems
	w.lfm:SetPoint("TOPLEFT", 0, -94)
	w.lfm.text:SetText(RF.Core:Announcement())
	w.banner:SetPoint("TOPLEFT", 0, -132)
	w.banner:SetMessages(RF.UI.Alerts())

	-- roster
	for _, c in ipairs(w.cols) do c.label:SetPoint("TOPLEFT", page, "TOPLEFT", c.x, -158) end
	w.list:SetPoint("TOPLEFT", 0, -172)
	w.list:SetData(RF.UI.RosterItems())
	if hovered and not (hovered:IsShown() and hovered.data) then ClearHover() end
	Status(page)
end

RF.UI:RegisterPage(1, "Raid", Build, Refresh, Status)
