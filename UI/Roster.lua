-- Roster tab: live applicants/members with manual overrides.
local _, RF = ...

local w = {}
local showAll = true

local STATUS_COLOR = {
	accepted = "|cff40ff40", waiting = "|cffffd100", invited = "|cff66ccff",
	rejected = "|cffff4040", timeout = "|cffff4040", refused = "|cffff7070",
	left = "|cff999999", expired = "|cff999999", declined = "|cff999999",
}
local ORDER = { accepted = 1, waiting = 2, invited = 3, refused = 4, rejected = 5, timeout = 6, declined = 7, expired = 8, left = 9 }

local function StatusText(m)
	if m.status == "waiting" then
		if m.confirming then return "|cffff9900Confirming GS...|r" end
		if m.inspecting then return STATUS_COLOR.waiting .. "Inspecting...|r" end
		if m.arrivedAt then
			return STATUS_COLOR.waiting .. "In queue #" .. (RF.Inspect:QueuePosition(m.name) or "?") .. "|r"
		end
	end
	local text = (STATUS_COLOR[m.status] or "") .. (RF.STATUS[m.status] or m.status or "") .. "|r"
	if m.inGroup and not RF.HOLDING[m.status] then text = text .. " |cffffd100(in raid)|r" end
	return text
end

-- Click on a player's spec: pick the right spec from their class.
local specMenu
function RF.UI.ShowSpecMenu(m, anchor)
	if not m then return end
	if not (m.class and RF.CLASS_SPECS[m.class]) then
		RF.Print("Class of " .. m.name .. " is not known until they are in the raid.")
		return
	end
	specMenu = specMenu or CreateFrame("Frame", "RaidFormerSpecMenu", UIParent, "UIDropDownMenuTemplate")
	local menu = { { text = "Spec for " .. m.name, isTitle = true, notCheckable = true } }
	for _, key in ipairs(RF.CLASS_SPECS[m.class]) do
		local spec = RF.SPECS[key]
		menu[#menu + 1] = {
			text = spec.name .. " (" .. spec.short .. ")" .. (m.offSpec == key and " - 2nd spec" or ""),
			checked = (m.spec == key and not m.specGuessed),
			func = function() RF.Core:SetSpec(m.name, key) end,
		}
	end
	EasyMenu(menu, specMenu, anchor, 0, 0, "MENU")
end

local function Build(page)
	local W = RF.W

	w.roles = W.Label(page, "", "GameFontHighlight")
	w.roles:SetPoint("TOPLEFT", 0, 0)
	w.roles:SetWidth(560)
	w.needs = W.Label(page, "", "GameFontHighlightSmall")
	w.needs:SetPoint("TOPLEFT", 0, -18)
	w.needs:SetWidth(560)

	w.showAll = W.Check(page, "Show refused / left", function(v) showAll = v; RF.UI:Refresh() end)
	w.showAll:SetPoint("TOPLEFT", -4, -36)
	local clear = W.Button(page, "Clear history", 90, 20, function() RF.Core:ClearApplicants() end)
	clear:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -38)
	local function tip(button, lines)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			for i, line in ipairs(lines) do GameTooltip:AddLine(line, 1, 1, i == 1 and 1 or 0.8, true) end
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	w.manualButton = W.Button(page, "Manual", 62, 20, function() RF.Groups:SetManual() end)
	w.manualButton:SetPoint("RIGHT", clear, "LEFT", -10, 0)
	tip(w.manualButton, { "Manual groups", "Full control: RaidFormer never moves anyone in the raid - not even when you press Insp - until you press Forming or Final again. Kept over /reload." })
	w.finalButton = W.Button(page, "Final", 50, 20, function() RF.Groups:SetFinal() end)
	w.finalButton:SetPoint("RIGHT", w.manualButton, "LEFT", -4, 0)
	tip(w.finalButton, { "Final groups", "Sorts the raid once: tanks with melee, then ranged, then healers, with party-only effects spread (Vampiric Embrace, Honor Among Thieves, Prayer of Healing, Healing Stream). After that the raid groups are yours." })
	w.formingButton = W.Button(page, "Forming", 66, 20, function() RF.Groups:SetForming() end)
	w.formingButton:SetPoint("RIGHT", w.finalButton, "LEFT", -4, 0)
	tip(w.formingButton, { "Forming groups", "RaidFormer takes control of the raid groups: you and uninspected players in the uninspected group, everyone else in the other groups. Also puts back players you moved yourself." })
	w.groupMode = W.Label(page, "", "GameFontHighlightSmall")
	w.groupMode:SetPoint("RIGHT", w.formingButton, "LEFT", -6, 0)

	-- column headers
	local cols = { { "Name", 4 }, { "Spec", 104 }, { "Said", 194 }, { "GS", 234 }, { "Status", 276 } }
	for _, c in ipairs(cols) do
		local l = W.Label(page, c[1], "GameFontNormalSmall")
		l:SetPoint("TOPLEFT", c[2], -64)
	end

	w.list = W.ScrollList(page, 560, 14, 22, function(row)
		row:EnableMouse(true)
		row.name = W.Label(row, "", "GameFontHighlightSmall"); row.name:SetPoint("LEFT", 4, 0); row.name:SetWidth(96)
		row.spec = W.Label(row, "", "GameFontHighlightSmall"); row.spec:SetPoint("LEFT", 104, 0); row.spec:SetWidth(86)
		row.specButton = CreateFrame("Button", nil, row)
		row.specButton:SetWidth(86)
		row.specButton:SetHeight(22)
		row.specButton:SetPoint("LEFT", 104, 0)
		row.specButton:SetScript("OnClick", function(self) RF.UI.ShowSpecMenu(row.data, self) end)
		row.specButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine("Click to set this player's spec")
			GameTooltip:Show()
		end)
		row.specButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row.said = W.Label(row, "", "GameFontHighlightSmall"); row.said:SetPoint("LEFT", 194, 0); row.said:SetWidth(40)
		row.gs = W.Label(row, "", "GameFontHighlightSmall"); row.gs:SetPoint("LEFT", 234, 0); row.gs:SetWidth(40)
		row.status = W.Label(row, "", "GameFontHighlightSmall"); row.status:SetPoint("LEFT", 276, 0); row.status:SetWidth(120)
		row.kick = W.Button(row, "Kick", 40, 18, function() RF.Core:ManualKick(row.data.name) end)
		row.kick:SetPoint("RIGHT", -2, 0)
		row.insp = W.Button(row, "Insp", 40, 18, function() RF.Core:Reinspect(row.data.name) end)
		row.insp:SetPoint("RIGHT", row.kick, "LEFT", -2, 0)
		row.accept = W.Button(row, "Accept", 50, 18, function() RF.Core:ManualAccept(row.data.name) end)
		row.accept:SetPoint("RIGHT", row.insp, "LEFT", -2, 0)
		row:SetScript("OnEnter", function(self)
			local m = self.data
			if not m then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(m.name)
			if m.whisper then GameTooltip:AddLine("Whispered: " .. m.whisper, 0.8, 0.8, 1, true) end
			if m.offLabel then
				GameTooltip:AddLine("Second spec: " .. m.offLabel .. (m.offGS and (" (" .. RF.Comp.FormatGS(m.offGS) .. ")") or ""), 0.8, 0.8, 1)
			end
			if m.inOffSpec then GameTooltip:AddLine("Inspected in their second spec's talents - counted as picked", 1, 0.82, 0, true) end
			if m.reason then GameTooltip:AddLine(m.reason, 1, 0.4, 0.4, true) end
			if m.ilvl then GameTooltip:AddLine("Avg item level: " .. m.ilvl, 1, 1, 1) end
			if m.manual then GameTooltip:AddLine("Let in by you - counted, never removed", 0.4, 1, 0.4) end
			if m.specByLeader then GameTooltip:AddLine("Spec set by you", 0.4, 1, 0.4) end
			if m.specGuessed then GameTooltip:AddLine("Spec is a guess until inspected - click the spec to set it", 1, 0.82, 0, true) end
			if m.status == "waiting" and not m.arrivedAt and m.joinedAt and not m.manual then
				local left = math.max(0, math.floor(RF.profile.inspectTimeout - (GetTime() - m.joinedAt)))
				GameTooltip:AddLine(string.format("Time left to come for inspect: %ds", left), 1, 1, 1)
			end
			if m.readings and #m.readings > 1 then
				local gsList = {}
				for _, r in ipairs(m.readings) do gsList[#gsList + 1] = tostring(r.gs) end
				GameTooltip:AddLine("GS readings: " .. table.concat(gsList, ", "), 0.8, 0.8, 0.8)
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end, function(row, m)
		local W = RF.W
		row.name:SetText(W.ClassColor(m.class) .. m.name .. "|r")
		-- a trailing "?" = spec guessed from class/role, the inspect will tell
		local off = m.offSpec ~= m.spec and (m.offSpec and RF.SPECS[m.offSpec] and RF.SPECS[m.offSpec].short or m.offLabel)
		row.spec:SetText((m.spec and RF.SPECS[m.spec].short or "?") .. (m.specGuessed and "?" or "") .. (off and ("/" .. off) or ""))
		row.said:SetText(m.claimedGS or "-")
		local gsText = m.gs and tostring(m.gs) or (m.inspecting and "..." or "-")
		if m.gs and m.gs < RF.profile.minGS then gsText = "|cffff4040" .. gsText .. "|r" end
		row.gs:SetText(gsText)
		row.status:SetText(StatusText(m))
		if m.status == "accepted" then row.accept:Disable() else row.accept:Enable() end
		if RF.UnitForName(m.name) then row.insp:Enable() else row.insp:Disable() end
	end)
	w.list:SetPoint("TOPLEFT", 0, -80)
end

local function Refresh(page)
	local p = RF.profile
	local holders = RF.Core:Holders()
	local counts = RF.Comp.Count(p, holders)

	local parts = {}
	for _, role in ipairs(RF.ROLES) do
		local have, want = counts.role[role], p.roles[role] or 0
		local color = (have >= want) and "|cff40ff40" or "|cffffd100"
		parts[#parts + 1] = string.format("%s: %s%d/%d|r", RF.ROLE_NAMES[role], color, have, want)
	end
	local flex = p.roles.flex or 0
	if flex > 0 then
		local _, flexFree = RF.Comp.Free(p, counts)
		parts[#parts + 1] = string.format("Any DPS: %s%d/%d|r", flexFree == 0 and "|cff40ff40" or "|cffffd100", flex - flexFree, flex)
	end
	w.roles:SetText(string.format("%d/%d   ", #holders, p.size) .. table.concat(parts, "   "))

	local needParts = {}
	for i, need in ipairs(p.needs) do
		local have, want = counts.need[i] or 0, need.count or 1
		needParts[#needParts + 1] = string.format("%s%s %d/%d|r", have >= want and "|cff40ff40" or "|cffff7070", RF.Comp.NeedLabel(need), have, want)
	end
	for _, buff in ipairs(RF.BUFFS) do
		local want = p.buffs[buff]
		if want then
			local have = counts.buff[buff] or 0
			needParts[#needParts + 1] = string.format("%s%s %d/%d|r", have >= want and "|cff40ff40" or "|cffff7070", RF.BUFF_SHORT[buff], have, want)
		end
	end
	local me = RF.SPECS[RF.Core:MySpec()]
	w.needs:SetText((#needParts > 0 and ("Needs: " .. table.concat(needParts, ", ") .. "   ") or "") ..
		"|cff999999(includes you as " .. (me and me.short or "?") .. ")|r")
	w.showAll:SetChecked(showAll)
	local mode = RF.Groups.mode
	if mode == "forming" then w.formingButton:LockHighlight() else w.formingButton:UnlockHighlight() end
	if mode == "final" then w.finalButton:LockHighlight() else w.finalButton:UnlockHighlight() end
	local manual = RF.Groups:IsManual()
	if manual then w.manualButton:LockHighlight() else w.manualButton:UnlockHighlight() end
	w.groupMode:SetText(mode == "forming" and "|cff40ff40Groups:|r" or mode == "final" and "|cffffd100Groups (sorting):|r" or "Groups:")

	local data = {}
	for _, m in pairs(RF.members) do
		if showAll or RF.HOLDING[m.status] or m.inGroup then data[#data + 1] = m end
	end
	table.sort(data, function(a, b)
		local oa, ob = ORDER[a.status] or 99, ORDER[b.status] or 99
		if oa ~= ob then return oa < ob end
		return a.name < b.name
	end)
	w.list:SetData(data)
end

RF.UI:RegisterPage(3, "Roster", Build, Refresh)
