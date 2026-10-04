-- Composition engine: counts, accept decisions with slot reservation, need string.
-- Pure logic, no WoW API calls, so it can be tested outside the game.
local _, RF = ...

local Comp = {}
RF.Comp = Comp

-- SendChatMessage errors with "Invalid escape code" on a bare "|" (e.g. from a custom raid name).
function RF.SafeChat(msg)
	return (tostring(msg or ""):gsub("|", "/"))
end

local floor = math.floor

-- Human readable label for a "need" entry {class=, spec=, count=}
function Comp.NeedLabel(need)
	if need.spec and RF.SPECS[need.spec] then return RF.SPECS[need.spec].short end
	return RF.CLASS_SHORT[need.class] or tostring(need.class)
end

local function MatchesNeed(holder, need)
	if need.spec then return holder.spec == need.spec end
	return holder.class == need.class
end

-- holders: array of { class=, spec= } (everyone holding a slot, including the leader)
function Comp.Count(profile, holders)
	local c = { total = #holders, role = { tank = 0, heal = 0, mdps = 0, rdps = 0 }, class = {}, need = {}, buff = {} }
	for _, h in ipairs(holders) do
		local spec = RF.SPECS[h.spec]
		if spec then c.role[spec.role] = c.role[spec.role] + 1 end
		if h.class then c.class[h.class] = (c.class[h.class] or 0) + 1 end
		for i, need in ipairs(profile.needs or {}) do
			if MatchesNeed(h, need) then c.need[i] = (c.need[i] or 0) + 1 end
		end
		for buff in pairs(profile.buffs or {}) do
			if h.spec and RF.SpecHasBuff(h.spec, buff) then c.buff[buff] = (c.buff[buff] or 0) + 1 end
		end
	end
	return c
end

-- Roles that could still satisfy a requirement.
local function RolesForNeed(need)
	local roles = {}
	if need.spec then
		roles[RF.SPECS[need.spec].role] = true
	else
		for _, key in ipairs(RF.CLASS_SPECS[need.class] or {}) do roles[RF.SPECS[key].role] = true end
	end
	return roles
end

local function RolesForBuff(buff)
	local roles = {}
	for key, spec in pairs(RF.SPECS) do
		if RF.SpecHasBuff(key, buff) then roles[spec.role] = true end
	end
	return roles
end

-- Unmet requirements: list of { label=, missing=, roles={role=true} }
function Comp.Unmet(profile, counts)
	local list = {}
	for i, need in ipairs(profile.needs or {}) do
		local missing = (need.count or 1) - (counts.need[i] or 0)
		if missing > 0 then
			list[#list + 1] = { label = Comp.NeedLabel(need), missing = missing, roles = RolesForNeed(need) }
		end
	end
	for _, buff in ipairs(RF.BUFFS) do
		local want = profile.buffs and profile.buffs[buff] or 0
		local missing = want - (counts.buff[buff] or 0)
		if want > 0 and missing > 0 then
			list[#list + 1] = { label = RF.BUFF_SHORT[buff], missing = missing, roles = RolesForBuff(buff), buff = buff }
		end
	end
	return list
end

local function CapFor(profile, class)
	for _, cap in ipairs(profile.caps or {}) do
		if cap.class == class then return cap.max end
	end
end

-- Can a player with specKey join given current slot holders?
-- Returns ok (bool), reason (string, for the whisper when refused)
function Comp.CanAccept(profile, holders, specKey)
	local spec = RF.SPECS[specKey]
	if not spec then return false, "unknown spec" end
	local counts = Comp.Count(profile, holders)
	if counts.total >= profile.size then return false, "raid is full" end

	local roleMax = profile.roles[spec.role] or 0
	if counts.role[spec.role] >= roleMax then
		return false, RF.ROLE_NAMES[spec.role] .. " spots are full"
	end

	local cap = CapFor(profile, spec.class)
	if cap and (counts.class[spec.class] or 0) >= cap then
		return false, "max " .. cap .. " " .. RF.CLASS_NAMES[spec.class] .. "s"
	end

	-- Simulate the join and make sure every unmet requirement can still be filled
	-- by the remaining open role slots (reservation).
	local after = {}
	for i, h in ipairs(holders) do after[i] = h end
	after[#after + 1] = { class = spec.class, spec = specKey }
	local counts2 = Comp.Count(profile, after)
	local roleFree = {}
	for _, r in ipairs(RF.ROLES) do roleFree[r] = math.max(0, (profile.roles[r] or 0) - counts2.role[r]) end

	local exclusive = {} -- role -> largest missing count among requirements only that role can fill
	for _, req in ipairs(Comp.Unmet(profile, counts2)) do
		local free, onlyRole, n = 0, nil, 0
		for r in pairs(req.roles) do free = free + roleFree[r]; onlyRole = r; n = n + 1 end
		if free < req.missing then
			return false, "remaining spots are reserved for " .. req.label
		end
		if n == 1 then exclusive[onlyRole] = math.max(exclusive[onlyRole] or 0, req.missing) end
	end
	for r, missing in pairs(exclusive) do
		if missing > roleFree[r] then return false, "remaining spots are reserved" end
	end
	return true
end

-- "rsham, 1 tank, 2 heal, 4 rdps" / "rsham, 2 heal, 7 dps" / "rsham, all"
function Comp.NeedString(profile, holders)
	local counts = Comp.Count(profile, holders)
	local parts = {}
	-- spec/class needs that can only be one role already use up that role's open slots,
	-- so "rsham, 5 heal" is shown as "rsham, 4 heal"
	local reserved = {}
	for _, req in ipairs(Comp.Unmet(profile, counts)) do
		parts[#parts + 1] = (req.missing > 1 and (req.missing .. "x ") or "") .. req.label
		local onlyRole, n = nil, 0
		for r in pairs(req.roles) do onlyRole = r; n = n + 1 end
		if n == 1 then reserved[onlyRole] = (reserved[onlyRole] or 0) + req.missing end
	end
	local open = {}
	for _, r in ipairs(RF.ROLES) do
		open[r] = math.max(0, (profile.roles[r] or 0) - counts.role[r] - (reserved[r] or 0))
	end
	if open.tank > 0 and open.heal > 0 and open.mdps > 0 and open.rdps > 0 then
		parts[#parts + 1] = "all" -- every role still open
	else
		if open.tank > 0 then parts[#parts + 1] = open.tank .. " " .. RF.ROLE_SHORT.tank end
		if open.heal > 0 then parts[#parts + 1] = open.heal .. " " .. RF.ROLE_SHORT.heal end
		if open.mdps > 0 and open.rdps > 0 then
			parts[#parts + 1] = (open.mdps + open.rdps) .. " dps" -- melee and ranged both open
		elseif open.mdps > 0 then
			parts[#parts + 1] = open.mdps .. " " .. RF.ROLE_SHORT.mdps
		elseif open.rdps > 0 then
			parts[#parts + 1] = open.rdps .. " " .. RF.ROLE_SHORT.rdps
		end
	end
	return table.concat(parts, ", "), counts
end

function Comp.FormatGS(gs)
	gs = tonumber(gs) or 0
	if gs >= 1000 then
		local k = floor(gs / 100) / 10
		if k == floor(k) then return string.format("%dk", k) end
		return string.format("%.1fk", k)
	end
	return tostring(gs)
end

-- Full LFM line, kept within the 255 character chat limit.
function Comp.BuildAnnouncement(profile, holders)
	local tag = RF.RaidTag(profile.raid, profile.size, profile.heroic, profile.customName)
	local need, counts = Comp.NeedString(profile, holders)
	-- optional "23/25": everyone holding a spot against the raid size
	local spots = profile.showCount and string.format(" %d/%d", counts.total, profile.size) or ""
	local head = string.format("LFM %s%s GS %s+", tag, spots, Comp.FormatGS(profile.minGS))
	local suffix = " - /w spec+gs"
	local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
	-- never use "|" in chat: WoW treats it as an escape code and rejects the message (SafeChat)
	local extras = trim(profile.extras)
	local extrasPart = (extras ~= "") and (" / " .. extras) or ""
	local freeText = trim(profile.freeText)
	local body = (need ~= "") and (" need: " .. need) or " last spot!"
	-- need list / reserves / your free text - /w spec+gs
	local function build(b, f)
		return RF.SafeChat(head .. b .. extrasPart .. ((f ~= "") and (" / " .. f) or "") .. suffix)
	end
	local msg = build(body, freeText)
	if #msg > 255 then
		-- over the chat limit: shorten the need list first (the free text box holds 80 chars) ...
		body = body:sub(1, math.max(0, #body - (#msg - 255) - 3)) .. "..."
		msg = build(body, freeText)
	end
	if #msg > 255 then
		-- ... and only if that still isn't enough, the free text; "/w spec+gs" always stays
		local room = 255 - #build(body, "") - 3
		freeText = (room > 0) and freeText:sub(1, room) or ""
		msg = build(body, freeText)
	end
	return msg:sub(1, 255), counts
end

local function RoleFits(specRole, role)
	return not role or specRole == role or (role == "dps" and (specRole == "mdps" or specRole == "rdps"))
end

-- Spec for a whisper that only named a class and/or role: the first spec the composition can
-- still take, preferring specs that fill an open spec need. The inspect decides the real one.
-- Returns specKey or nil, reason
function Comp.GuessSpec(profile, holders, class, role)
	local candidates = {}
	for _, c in ipairs(RF.CLASSES) do
		if not class or c == class then
			for _, key in ipairs(RF.CLASS_SPECS[c]) do
				if RoleFits(RF.SPECS[key].role, role) then candidates[#candidates + 1] = key end
			end
		end
	end
	local counts = Comp.Count(profile, holders)
	local wanted = {}
	for i, need in ipairs(profile.needs or {}) do
		if need.spec and (counts.need[i] or 0) < (need.count or 1) then wanted[need.spec] = true end
	end
	local firstReason
	for pass = 1, 2 do
		for _, key in ipairs(candidates) do
			if pass == 2 or wanted[key] then
				local ok, why = Comp.CanAccept(profile, holders, key)
				if ok then return key end
				firstReason = firstReason or why
			end
		end
	end
	return nil, firstReason or "no matching spec"
end

-- How much the raid wants this spec right now: an open spec need beats an open class need beats
-- a plain role slot; between roles, the one with the bigger share of its spots still open wins.
function Comp.NeedScore(profile, holders, specKey)
	local spec = RF.SPECS[specKey]
	if not spec then return -1 end
	local counts = Comp.Count(profile, holders)
	local bonus = 0
	for i, need in ipairs(profile.needs or {}) do
		if (counts.need[i] or 0) < (need.count or 1) then
			if need.spec == specKey then
				bonus = math.max(bonus, 200)
			elseif not need.spec and need.class == spec.class then
				bonus = math.max(bonus, 100)
			end
		end
	end
	local slots = profile.roles[spec.role] or 0
	local open = math.max(0, slots - counts.role[spec.role])
	return bonus + ((slots > 0) and (open / slots * 10) or 0)
end

-- Formation tab warnings: spec needs that can't fit their role slots, or more needs than players.
function Comp.NeedsOverflow(profile)
	local perRole, total = {}, 0
	for _, need in ipairs(profile.needs or {}) do
		local count = need.count or 1
		total = total + count
		if need.spec and RF.SPECS[need.spec] then
			local role = RF.SPECS[need.spec].role
			perRole[role] = (perRole[role] or 0) + count
		end
	end
	local problems = {}
	for _, role in ipairs(RF.ROLES) do
		local want, slots = perRole[role] or 0, profile.roles[role] or 0
		if want > slots then
			problems[#problems + 1] = string.format("%s needs %d but only %d slots", RF.ROLE_NAMES[role], want, slots)
		end
	end
	if total > profile.size then
		problems[#problems + 1] = string.format("%d needed players > raid size %d", total, profile.size)
	end
	return problems
end

-- Sanity check for the Formation tab: role counts must add up to the raid size.
function Comp.RoleTotal(profile)
	local t = 0
	for _, r in ipairs(RF.ROLES) do t = t + (profile.roles[r] or 0) end
	return t
end
