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

-- What the LFM line asks for. Classes from the formation list are only named once they are all
-- that's left, so the line stays short while the raid is open to anyone:
--  * roles are counted with their reserved needs included ("6 heal", not "rsham, 5 heal");
--  * a role's count becomes its need names ("rsham") once every open spot of that role is reserved;
--  * when every open spot in the raid is reserved, exactly the remaining needs are listed
--    (that's also the only time needs fitting several roles, e.g. "any shaman", are named);
--  * "all" / "N dps" bundle roles that are still shown as counts.
-- Over a raid: "all" -> "6 heal, 17 dps" -> "rsham, 17 dps" -> "rsham, rog"
function Comp.NeedString(profile, holders)
	local counts = Comp.Count(profile, holders)
	local open, totalOpen = {}, 0
	for _, r in ipairs(RF.ROLES) do
		open[r] = math.max(0, (profile.roles[r] or 0) - counts.role[r])
		totalOpen = totalOpen + open[r]
	end

	local byRole, reserved, multi, totalMissing = {}, {}, {}, 0
	for _, req in ipairs(Comp.Unmet(profile, counts)) do
		local label = (req.missing > 1 and (req.missing .. "x ") or "") .. req.label
		totalMissing = totalMissing + req.missing
		local onlyRole, n = nil, 0
		for r in pairs(req.roles) do onlyRole = r; n = n + 1 end
		if n == 1 then
			byRole[onlyRole] = byRole[onlyRole] or {}
			table.insert(byRole[onlyRole], label)
			reserved[onlyRole] = (reserved[onlyRole] or 0) + req.missing
		else
			multi[#multi + 1] = label
		end
	end

	local parts = {}
	local function add(list)
		for _, label in ipairs(list or {}) do parts[#parts + 1] = label end
	end

	if totalOpen > 0 and totalMissing >= totalOpen then
		-- every open spot is reserved: name exactly who we still need
		for _, r in ipairs(RF.ROLES) do add(byRole[r]) end
		add(multi)
		return table.concat(parts, ", "), counts
	end

	local named = {}
	for _, r in ipairs(RF.ROLES) do
		named[r] = open[r] > 0 and (reserved[r] or 0) >= open[r]
	end
	if open.tank > 0 and open.heal > 0 and open.mdps > 0 and open.rdps > 0
		and not (named.tank or named.heal or named.mdps or named.rdps) then
		return "all", counts -- every role still open to anyone
	end
	local function role(r)
		if open[r] == 0 then return end
		if named[r] then add(byRole[r]) else parts[#parts + 1] = open[r] .. " " .. RF.ROLE_SHORT[r] end
	end
	role("tank")
	role("heal")
	if open.mdps > 0 and open.rdps > 0 and not named.mdps and not named.rdps then
		parts[#parts + 1] = (open.mdps + open.rdps) .. " dps" -- melee and ranged both open
	else
		role("mdps")
		role("rdps")
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

-- Announcement styles (Setup tab). The default is "dashes".
RF.LFM_STYLES = {
	{ key = "dashes", name = "Clean dashes" },
	{ key = "icons", name = "Raid icons" },
	{ key = "brackets", name = "Brackets" },
	{ key = "needfirst", name = "Need first" },
}
-- raid target icons the client draws in chat when written as {name}
RF.LFM_ICONS = { "star", "circle", "diamond", "triangle", "moon", "square", "cross", "skull" }

local function Join(list, sep)
	local out = {}
	for _, part in ipairs(list) do
		if part and part ~= "" then out[#out + 1] = part end
	end
	return table.concat(out, sep)
end

-- One LFM line in the chosen style. n = need text, f = free text (both may be shortened).
local function Format(profile, tag, count, gs, n, extras, f)
	local style = profile.lfmStyle
	local suffix = "/w spec + GS"
	local needSeg = (n ~= "") and ("Need: " .. n) or "Last spot!"
	if style == "icons" then
		local icon = "{" .. (profile.lfmIcon or "skull") .. "}"
		return icon .. " " .. Join({ Join({ "LFM", tag, count }, " "), needSeg, gs, extras, f, suffix }, " " .. icon .. " ")
	elseif style == "brackets" then
		return Join({ Join({ "[" .. tag .. "] LFM", count }, " "), "[" .. needSeg .. "]", gs, Join({ extras, f }, ", "), suffix }, " - ")
	elseif style == "needfirst" then
		local wants = (n == "all") and "ALL" or ((n ~= "") and n or "a last spot")
		return Join({ Join({ tag .. " needs " .. wants, count and ("(" .. count .. ")") }, " "), gs, extras, f, suffix }, " - ")
	end
	-- "dashes"
	return Join({ Join({ "LFM", tag, count }, " "), gs, needSeg, extras, f, suffix }, " - ")
end

-- Full LFM line, kept within the 255 character chat limit.
function Comp.BuildAnnouncement(profile, holders)
	local tag = RF.RaidTag(profile.raid, profile.size, profile.heroic, profile.customName)
	local need, counts = Comp.NeedString(profile, holders)
	-- optional "23/25": everyone holding a spot against the raid size
	local count = profile.showCount and string.format("%d/%d", counts.total, profile.size) or nil
	local gs = "GS " .. Comp.FormatGS(profile.minGS) .. "+"
	local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
	local extras = trim(profile.extras)
	local freeText = trim(profile.freeText)
	-- never use "|" in chat: WoW treats it as an escape code and rejects the message (SafeChat)
	local function build(n, f) return RF.SafeChat(Format(profile, tag, count, gs, n, extras, f)) end
	local msg = build(need, freeText)
	if #msg > 255 then
		-- over the chat limit: shorten the need list first (the free text box holds 80 chars) ...
		need = need:sub(1, math.max(0, #need - (#msg - 255) - 3)) .. "..."
		msg = build(need, freeText)
	end
	if #msg > 255 then
		-- ... and only if that still isn't enough, the free text; "/w spec + GS" always stays
		local room = math.max(0, #freeText - (#msg - 255))
		freeText = freeText:sub(1, room)
		msg = build(need, freeText)
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
