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
	local c = { total = #holders, role = { tank = 0, heal = 0, mdps = 0, rdps = 0 }, class = {}, spec = {}, need = {}, buff = {} }
	for _, h in ipairs(holders) do
		local spec = RF.SPECS[h.spec]
		if spec then
			c.role[spec.role] = c.role[spec.role] + 1
			c.spec[h.spec] = (c.spec[h.spec] or 0) + 1
		end
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

-- "Any DPS" spots (profile.roles.flex): taken by melee or ranged once their own spots are full.
local DPS = { "mdps", "rdps" }
local IS_DPS = { mdps = true, rdps = true }
Comp.IS_DPS = IS_DPS

-- Free spots per role, plus the free "Any DPS" spots.
function Comp.Free(profile, counts)
	local free, over = {}, 0
	for _, r in ipairs(RF.ROLES) do free[r] = math.max(0, (profile.roles[r] or 0) - counts.role[r]) end
	for _, r in ipairs(DPS) do over = over + math.max(0, counts.role[r] - (profile.roles[r] or 0)) end
	return free, math.max(0, (profile.roles.flex or 0) - over)
end

-- Class caps ("max 3 Druids") and spec caps ("max 1 rdru"): the reason if specKey would go over one.
local function OverCap(profile, counts, specKey)
	local spec = RF.SPECS[specKey]
	for _, cap in ipairs(profile.caps or {}) do
		if cap.class == spec.class and (not cap.spec or cap.spec == specKey) then
			local have = cap.spec and (counts.spec[cap.spec] or 0) or (counts.class[spec.class] or 0)
			if have >= (cap.max or 0) then
				return "max " .. (cap.max or 0) .. " " .. (cap.spec and RF.SPECS[cap.spec].short or (RF.CLASS_NAMES[spec.class] .. "s"))
			end
		end
	end
end

-- How many needed players can't get a spot any more (role spots and free raid spots), plus the
-- labels of those needs. Needs only one role can fill use that role's spots first; the others share
-- what's left over.
local function Shortfall(profile, counts)
	local free, flex = Comp.Free(profile, counts)
	local single, multi, missingTotal = {}, {}, 0
	for _, r in ipairs(RF.ROLES) do single[r] = {} end
	for _, req in ipairs(Comp.Unmet(profile, counts)) do
		missingTotal = missingTotal + req.missing
		local onlyRole, n = nil, 0
		for r in pairs(req.roles) do onlyRole, n = r, n + 1 end
		if n == 1 then table.insert(single[onlyRole], req) else multi[#multi + 1] = req end
	end
	local short, labels, left, def = 0, {}, {}, {}
	for _, r in ipairs(RF.ROLES) do
		local want = 0
		for _, req in ipairs(single[r]) do want = want + req.missing end
		left[r] = math.max(0, free[r] - want)
		def[r] = math.max(0, want - free[r])
	end
	-- melee/ranged needs beyond their own spots can use "Any DPS" spots
	for _, r in ipairs(DPS) do
		local take = math.min(flex, def[r])
		flex, def[r] = flex - take, def[r] - take
	end
	for _, r in ipairs(RF.ROLES) do
		if def[r] > 0 then
			short = short + def[r]
			for _, req in ipairs(single[r]) do labels[#labels + 1] = req.label end
		end
	end
	for _, req in ipairs(multi) do
		local m = req.missing
		for _, r in ipairs(RF.ROLES) do
			if req.roles[r] then
				local take = math.min(left[r], m)
				left[r], m = left[r] - take, m - take
			end
		end
		if m > 0 and (req.roles.mdps or req.roles.rdps) then
			local take = math.min(flex, m)
			flex, m = flex - take, m - take
		end
		if m > 0 then
			short = short + m
			labels[#labels + 1] = req.label
		end
	end
	local raidShort = missingTotal - math.max(0, profile.size - counts.total)
	return math.max(short, raidShort), labels
end

-- Can a player with specKey join given current slot holders?
-- Returns ok (bool), reason (string, for the whisper when refused)
function Comp.CanAccept(profile, holders, specKey)
	local spec = RF.SPECS[specKey]
	if not spec then return false, "unknown spec" end
	local counts = Comp.Count(profile, holders)
	if counts.total >= profile.size then return false, "raid is full" end

	local free, flex = Comp.Free(profile, counts)
	if free[spec.role] == 0 and not (IS_DPS[spec.role] and flex > 0) then
		if IS_DPS[spec.role] and (profile.roles.flex or 0) > 0 then return false, "DPS spots are full" end
		return false, RF.ROLE_NAMES[spec.role] .. " spots are full"
	end

	local capped = OverCap(profile, counts, specKey)
	if capped then return false, capped end

	-- Reservation: simulate the join; refused if it leaves more needed players without a spot than
	-- before. When the needs already don't all fit (2 healer specs needed, 1 heal spot) any of them
	-- may take the spot, but nobody else.
	local after = {}
	for i, h in ipairs(holders) do after[i] = h end
	after[#after + 1] = { class = spec.class, spec = specKey }
	local before = Shortfall(profile, counts)
	local short, labels = Shortfall(profile, Comp.Count(profile, after))
	if short > before then
		return false, labels[1] and ("remaining spots are reserved for " .. labels[1]) or "remaining spots are reserved"
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
	local open, flexOpen = Comp.Free(profile, counts)
	local totalOpen = flexOpen
	for _, r in ipairs(RF.ROLES) do totalOpen = totalOpen + open[r] end
	-- never ask for more than the raid still has room for: the role counts can add up to more than
	-- the free spots (e.g. 25-man role counts in a 10-man raid, or players whose spec isn't known yet)
	local remaining = math.max(0, (profile.size or 0) - counts.total)
	for _, r in ipairs(RF.ROLES) do open[r] = math.min(open[r], remaining) end
	flexOpen = math.min(flexOpen, remaining)
	totalOpen = math.min(totalOpen, remaining)

	local byRole, reserved, multi, multiMissing = {}, {}, {}, 0
	for _, req in ipairs(Comp.Unmet(profile, counts)) do
		local entry = { label = req.label, missing = req.missing }
		local onlyRole, n, anyOpen = nil, 0, false
		for r in pairs(req.roles) do
			onlyRole, n = r, n + 1
			anyOpen = anyOpen or open[r] > 0
		end
		if n == 1 then
			byRole[onlyRole] = byRole[onlyRole] or {}
			table.insert(byRole[onlyRole], entry)
			reserved[onlyRole] = (reserved[onlyRole] or 0) + req.missing
		elseif anyOpen then
			multi[#multi + 1] = entry
			multiMissing = multiMissing + req.missing
		end
	end

	-- Needs for `spots` places: "rsham, 2x hpal" when they all fit; when there are more needs than
	-- spots any of them will do: "hpal/rdru" (1 spot) or "2 of hpal/rdru/disc".
	local function names(list, spots)
		local missing, full, short = 0, {}, {}
		for _, e in ipairs(list) do
			missing = missing + e.missing
			full[#full + 1] = (e.missing > 1 and (e.missing .. "x ") or "") .. e.label
			short[#short + 1] = e.label
		end
		if missing <= spots then return table.concat(full, ", ") end
		if spots == 1 then return table.concat(short, "/") end
		return spots .. " of " .. table.concat(short, "/")
	end

	local parts = {}
	-- melee/ranged needs beyond their own open spots take "Any DPS" spots
	local spots, flexLeft = {}, flexOpen
	for _, r in ipairs(RF.ROLES) do spots[r] = open[r] end
	for _, r in ipairs(DPS) do
		local take = math.min(flexLeft, math.max(0, (reserved[r] or 0) - open[r]))
		spots[r], flexLeft = spots[r] + take, flexLeft - take
	end

	local fillable = multiMissing -- reserved spots that can actually be taken
	for _, r in ipairs(RF.ROLES) do fillable = fillable + math.min(spots[r], reserved[r] or 0) end
	if totalOpen > 0 and fillable >= totalOpen then
		-- every open spot is reserved: name exactly who we still need (needs for full roles can't join)
		local groups, spotSum, all = {}, 0, {}
		for _, r in ipairs(RF.ROLES) do
			if spots[r] > 0 and byRole[r] then
				groups[#groups + 1] = { list = byRole[r], spots = math.min(spots[r], reserved[r]) }
			end
		end
		if #multi > 0 then groups[#groups + 1] = { list = multi, spots = multiMissing } end
		for _, g in ipairs(groups) do
			spotSum = spotSum + g.spots
			for _, e in ipairs(g.list) do all[#all + 1] = e end
		end
		if spotSum > totalOpen then
			groups = { { list = all, spots = totalOpen } } -- more names than places left: any of them
		end
		for _, g in ipairs(groups) do parts[#parts + 1] = names(g.list, g.spots) end
		return table.concat(parts, ", "), counts
	end

	local named = {}
	for _, r in ipairs(RF.ROLES) do
		named[r] = spots[r] > 0 and (reserved[r] or 0) >= open[r]
	end
	if open.tank > 0 and open.heal > 0 and open.mdps > 0 and open.rdps > 0
		and not (named.tank or named.heal or named.mdps or named.rdps) then
		return "all", counts -- every role still open to anyone
	end
	local function role(r)
		if spots[r] == 0 then return end
		if named[r] then
			parts[#parts + 1] = names(byRole[r], spots[r])
		else
			parts[#parts + 1] = open[r] .. " " .. RF.ROLE_SHORT[r]
		end
	end
	role("tank")
	role("heal")
	if open.mdps > 0 and open.rdps > 0 and not named.mdps and not named.rdps then
		parts[#parts + 1] = math.min(open.mdps + open.rdps + flexLeft, remaining) .. " dps" -- melee and ranged both open
	else
		role("mdps")
		role("rdps")
		if flexLeft > 0 then parts[#parts + 1] = flexLeft .. " dps" end -- "Any DPS" spots: melee or ranged
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

-- The LFM line shows "[n/size]" once this many spots are taken (any raid size).
Comp.COUNT_FROM = 5

-- Announcement styles (Settings tab). The default is "dashes".
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
		return Join({ Join({ tag .. " needs " .. wants, count }, " "), gs, extras, f, suffix }, " - ")
	end
	-- "dashes"
	return Join({ Join({ "LFM", tag, count }, " "), gs, needSeg, extras, f, suffix }, " - ")
end

-- Full LFM line, kept within the 255 character chat limit.
function Comp.BuildAnnouncement(profile, holders)
	local tag = RF.RaidTag(profile.raid, profile.size, profile.heroic, profile.customName)
	local need, counts = Comp.NeedString(profile, holders)
	-- "[18/25]": everyone holding a spot against the raid size, once there are enough to be worth saying
	local count = (counts.total >= Comp.COUNT_FROM) and string.format("[%d/%d]", counts.total, profile.size) or nil
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
	local free, flex = Comp.Free(profile, counts)
	local slots, open = profile.roles[spec.role] or 0, free[spec.role]
	if IS_DPS[spec.role] then slots, open = slots + (profile.roles.flex or 0), open + flex end
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
	local flex = profile.roles.flex or 0
	local dpsWant = (perRole.mdps or 0) + (perRole.rdps or 0)
	local dpsSlots = (profile.roles.mdps or 0) + (profile.roles.rdps or 0) + flex
	for _, role in ipairs(RF.ROLES) do
		local want, slots = perRole[role] or 0, profile.roles[role] or 0
		if IS_DPS[role] then slots = slots + flex end -- can use the "Any DPS" spots
		if want > slots then
			problems[#problems + 1] = string.format("%s needs %d but only %d slots", RF.ROLE_NAMES[role], want, slots)
		end
	end
	if flex > 0 and dpsWant > dpsSlots and (perRole.mdps or 0) <= (profile.roles.mdps or 0) + flex
		and (perRole.rdps or 0) <= (profile.roles.rdps or 0) + flex then
		problems[#problems + 1] = string.format("DPS needs %d but only %d slots", dpsWant, dpsSlots)
	end
	-- needs above a cap can never be met
	for _, need in ipairs(profile.needs or {}) do
		for _, cap in ipairs(profile.caps or {}) do
			if cap.class == need.class and (not cap.spec or cap.spec == need.spec) and (need.count or 1) > (cap.max or 0) then
				problems[#problems + 1] = string.format("%s needed %d but max %d", Comp.NeedLabel(need), need.count or 1, cap.max or 0)
			end
		end
	end
	if total > profile.size then
		problems[#problems + 1] = string.format("%d needed players > raid size %d", total, profile.size)
	end
	return problems
end

-- Role counts for a new raid size, keeping the shape of your setup: the tank count stays, the
-- other spots are shared out in the same proportions (largest remainder). Always adds up to newSize.
-- With needs given, every role then keeps room for the needs only it can fill (3 healer specs on
-- the list -> at least 3 heal), taking spots from the role with most to spare.
function Comp.ScaleRoles(roles, newSize, needs)
	local out = { tank = math.min(roles.tank or 0, newSize) }
	local rest, oldRest = newSize - out.tank, 0
	local others = { "heal", "mdps", "rdps", "flex" }
	for _, r in ipairs(others) do oldRest = oldRest + (roles[r] or 0) end
	local used, fracs = 0, {}
	for _, r in ipairs(others) do
		local exact = (oldRest > 0) and ((roles[r] or 0) * rest / oldRest) or (r ~= "flex" and rest / 3 or 0)
		out[r] = math.floor(exact)
		used = used + out[r]
		fracs[#fracs + 1] = { r = r, f = exact - out[r] }
	end
	table.sort(fracs, function(a, b)
		if a.f ~= b.f then return a.f > b.f end
		return a.r < b.r
	end)
	local i = 0
	while used < rest do
		local r = fracs[(i % #fracs) + 1].r
		out[r], used, i = out[r] + 1, used + 1, i + 1
	end

	local min, minTotal = {}, 0
	for _, r in ipairs(RF.ROLES) do min[r] = 0 end
	min.flex = 0
	for _, need in ipairs(needs or {}) do
		local only, n = nil, 0
		for r in pairs(RolesForNeed(need)) do only, n = r, n + 1 end
		if n == 1 then min[only] = min[only] + (need.count or 1) end
	end
	for _, r in ipairs(RF.ROLES) do minTotal = minTotal + min[r] end
	if minTotal > newSize then return out end -- can't all fit; the Formation tab warns
	for _, r in ipairs(RF.ROLES) do
		while out[r] < min[r] do
			local donor, spare = nil, 0
			for _, d in ipairs({ "flex", "mdps", "rdps", "heal", "tank" }) do
				if out[d] - min[d] > spare then donor, spare = d, out[d] - min[d] end
			end
			if not donor then break end
			out[donor], out[r] = out[donor] - 1, out[r] + 1
		end
	end
	return out
end

-- Sanity check for the Formation tab: role counts must add up to the raid size.
function Comp.RoleTotal(profile)
	local t = 0
	for _, r in ipairs(RF.ROLES) do t = t + (profile.roles[r] or 0) end
	t = t + (profile.roles.flex or 0) -- "Any DPS"
	return t
end
