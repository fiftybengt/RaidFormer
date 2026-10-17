-- Raid group control in two phases (buttons on the Roster tab):
--  * Forming groups: RaidFormer controls the raid groups. You and everyone still waiting for
--    inspect sit in the uninspected group (default 1); everyone else - inspected, or let in by
--    you - goes to the other groups. Pressing it takes control, also over your own hand moves.
--  * Final groups: one-off sort into WotLK groups by role and spec, then the raid groups are
--    yours: nothing is moved again until you press Forming groups.
--  * Manual groups: hands off - RaidFormer never moves anyone (not even for "Insp") until you
--    press Forming or Final again. Kept over /reload.
-- Stopping RaidFormer also hands the raid groups back to you (without sorting).
local _, RF = ...

local Groups = { mode = nil, lastMove = 0, waitingForRoster = false, finalUntil = 0, finalPlan = nil }
RF.Groups = Groups

local GROUP_SIZE, NUM_GROUPS = 5, 8
local MOVE_GAP = 0.5
local ROSTER_WAIT_TIMEOUT = 3   -- a move that hasn't shown up by then is retried
local FINAL_TIMEOUT = 30

-- In 3.3.5 almost every WotLK buff is raid-wide (totem stat buffs, Moonkin Aura, Leader of the
-- Pack, Bloodlust, auras, Trueshot Aura ...). These effects still only reach the caster's own
-- 5-man party, so the final sort spreads them to the groups that benefit:
local SPREAD = {
	{ specs = { PRIEST_SHADOW = true }, into = "rdps" },                     -- Vampiric Embrace heals the party
	{ specs = { ROGUE_SUB = true }, into = "mdps" },                         -- Honor Among Thieves: party crits
	{ specs = { PRIEST_HOLY = true, SHAMAN_RESTO = true }, into = "fight" }, -- Prayer of Healing, Healing Stream/Tremor/Cleansing totems
}
local SPREAD_SPEC = {}
for _, rule in ipairs(SPREAD) do
	for spec in pairs(rule.specs) do SPREAD_SPEC[spec] = true end
end
local BUCKETS = { "tank", "mdps", "rdps", "heal" }
local BUCKET_ORDER = { tank = 1, mdps = 2, rdps = 3, heal = 4 }

local function CanMove()
	return GetNumRaidMembers() > 0 and (IsRaidLeader() or IsRaidOfficer())
end

local function Roster()
	local list = {}
	for i = 1, GetNumRaidMembers() do
		local name, _, subgroup = GetRaidRosterInfo(i)
		if name then list[#list + 1] = { index = i, name = name, group = subgroup } end
	end
	return list
end

local function Settings()
	local p = RF.profile
	local pending = math.max(1, math.min(NUM_GROUPS, p.pendingGroup or 1))
	local acceptedFrom = math.max(1, math.min(NUM_GROUPS, p.acceptedGroup or 2))
	return pending, acceptedFrom
end

-- still to be inspected (players you let in yourself count as formed)
local function IsUninspected(m)
	-- a player you let in yourself counts as formed, unless you asked for an inspect ("Insp")
	return m and m.status == "waiting" and (not m.manual or m.forceInspect)
end

-- Roster "Insp": put the player in the uninspected group right away (needs leader/assist).
-- If it's full, swap with someone there who doesn't need inspecting - never you.
-- Returns true if a move was made.
function Groups:MoveToPending(name)
	if RF.profile.manualGroups or not CanMove() then return false end
	local pending = Settings()
	local roster, me, target, count = Roster(), UnitName("player"), nil, 0
	for _, r in ipairs(roster) do
		if r.group == pending then count = count + 1 end
		if r.name == name then target = r end
	end
	if not target or target.group == pending then return false end
	if count < GROUP_SIZE then
		SetRaidSubgroup(target.index, pending)
	else
		local other
		for _, r in ipairs(roster) do
			if r.group == pending and r.name ~= me and r.name ~= name and not IsUninspected(RF.members[r.name]) then
				other = r
				break
			end
		end
		if not other then return false end
		SwapRaidSubgroup(target.index, other.index)
	end
	self.lastMove, self.waitingForRoster = GetTime(), true
	return true
end

function Groups:OnRosterUpdate()
	self.waitingForRoster = false
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

function Groups:SetForming()
	if not CanMove() then
		RF.Print("You need to be raid leader or assistant to control raid groups.")
		return
	end
	self.mode, self.finalPlan, self.waitingForRoster = "forming", nil, false
	RF.profile.manualGroups = nil
	RF.Print("Forming groups: RaidFormer controls the raid groups (uninspected in group " .. Settings() .. ").")
	RF.Core:Refresh()
end

function Groups:SetFinal()
	if not CanMove() then
		RF.Print("You need to be raid leader or assistant to control raid groups.")
		return
	end
	self.mode, self.finalPlan, self.waitingForRoster = "final", nil, false
	RF.profile.manualGroups = nil
	self.finalUntil = GetTime() + FINAL_TIMEOUT
	RF.Print("Final groups: sorting the raid, then the groups are yours.")
	RF.Core:Refresh()
end

-- Manual: the raid groups are fully yours, nothing is moved until you press Forming or Final.
function Groups:SetManual()
	self:Release(true)
	RF.profile.manualGroups = true
	RF.Print("Manual groups: RaidFormer won't move anyone - the raid groups are all yours (Insp included). Press Forming or Final to hand them back.")
	RF.Core:Refresh()
end

function Groups:IsManual()
	return RF.profile.manualGroups and true or false
end

-- Hand the raid groups back to you (Stop, or when the final sort is done).
function Groups:Release(silent)
	local had = self.mode
	self.mode, self.finalPlan = nil, nil
	if had and not silent then RF.Print("The raid groups are yours now.") end
	RF.Core:Refresh()
end

---------------------------------------------------------------------------
-- Forming layout
---------------------------------------------------------------------------

-- desired[name] = group; people already sitting where they belong are kept (fewest moves)
function Groups:PlanForming(roster)
	local pending, acceptedFrom = Settings()
	local me = UnitName("player")
	local used, desired, formedGroups = {}, {}, {}
	for g = 1, NUM_GROUPS do used[g] = 0 end
	local function place(r, g)
		desired[r.name] = g
		used[g] = used[g] + 1
	end
	local function room(g) return used[g] < GROUP_SIZE end

	local uninspected, formed = {}, {}
	for _, r in ipairs(roster) do
		if r.name == me then
			place(r, pending) -- you stay with the uninspected group
		elseif IsUninspected(RF.members[r.name]) then
			uninspected[#uninspected + 1] = r
		else
			formed[#formed + 1] = r
		end
	end

	local restU, restF = {}, {}
	for _, r in ipairs(uninspected) do
		if r.group == pending and room(pending) then place(r, pending) else restU[#restU + 1] = r end
	end
	for _, r in ipairs(formed) do
		if r.group ~= pending and room(r.group) then
			place(r, r.group)
			formedGroups[r.group] = true
		else
			restF[#restF + 1] = r
		end
	end

	for _, r in ipairs(restF) do
		local target
		for g = acceptedFrom, NUM_GROUPS do
			if g ~= pending and room(g) then target = g; break end
		end
		if not target then
			for g = 1, NUM_GROUPS do
				if g ~= pending and room(g) then target = g; break end
			end
		end
		target = target or pending
		place(r, target)
		formedGroups[target] = true
	end

	for _, r in ipairs(restU) do
		local target
		if room(pending) then
			target = pending
		else
			-- uninspected group full: highest group without formed players
			for g = NUM_GROUPS, 1, -1 do
				if g ~= pending and not formedGroups[g] and room(g) then target = g; break end
			end
			if not target then
				for g = NUM_GROUPS, 1, -1 do
					if room(g) then target = g; break end
				end
			end
		end
		place(r, target or r.group)
	end
	return desired
end

---------------------------------------------------------------------------
-- Final layout: tanks + melee, ranged, healers; party-only effects spread
---------------------------------------------------------------------------

local function Wants(rule, kind)
	if rule.into == "fight" then return kind ~= "heal" end
	return kind == rule.into
end

function Groups:PlanFinal(roster)
	local me = UnitName("player")
	local entries = {}
	for _, r in ipairs(roster) do
		local m = RF.members[r.name]
		local spec = (r.name == me) and RF.Core:MySpec() or (m and m.spec)
		if not RF.SPECS[spec] and m and m.class and RF.CLASS_SPECS[m.class] then spec = RF.CLASS_SPECS[m.class][1] end
		local bucket = RF.SPECS[spec] and RF.SPECS[spec].role or "mdps"
		entries[#entries + 1] = { r = r, spec = spec, bucket = bucket }
	end
	table.sort(entries, function(a, b)
		if BUCKET_ORDER[a.bucket] ~= BUCKET_ORDER[b.bucket] then return BUCKET_ORDER[a.bucket] < BUCKET_ORDER[b.bucket] end
		return a.r.index < b.r.index
	end)

	local numGroups = math.min(NUM_GROUPS, math.max(1, math.ceil(#entries / GROUP_SIZE)))
	local groups, kinds = {}, {}
	for g = 1, numGroups do groups[g] = {} end
	for i, e in ipairs(entries) do
		local g = math.min(numGroups, math.floor((i - 1) / GROUP_SIZE) + 1)
		table.insert(groups[g], e)
	end
	for g = 1, numGroups do
		local count, best, bestN = {}, nil, -1
		for _, e in ipairs(groups[g]) do count[e.bucket] = (count[e.bucket] or 0) + 1 end
		for _, b in ipairs(BUCKETS) do
			if (count[b] or 0) > bestN then best, bestN = b, count[b] or 0 end
		end
		kinds[g] = best
	end

	local function found(list, rule)
		local first, n = nil, 0
		for i, e in ipairs(list) do
			if rule.specs[e.spec] then first, n = first or i, n + 1 end
		end
		return first, n
	end
	for _, rule in ipairs(SPREAD) do
		for g = 1, numGroups do
			if Wants(rule, kinds[g]) and not found(groups[g], rule) then
				-- take one from a group with two of them, or from a group that doesn't need one
				for d = 1, numGroups do
					local idx, n = found(groups[d], rule)
					if d ~= g and idx and (n >= 2 or not Wants(rule, kinds[d])) then
						local j
						for i = #groups[g], 1, -1 do
							if not SPREAD_SPEC[groups[g][i].spec] then j = i; break end
						end
						if j then groups[g][j], groups[d][idx] = groups[d][idx], groups[g][j] end
						break
					end
				end
			end
		end
	end

	local desired = {}
	for g = 1, numGroups do
		for _, e in ipairs(groups[g]) do desired[e.r.name] = g end
	end
	return desired
end

---------------------------------------------------------------------------
-- Moving (one move per call)
---------------------------------------------------------------------------

-- Returns true if a move was made.
function Groups:Step(roster, desired, now)
	local count = {}
	for g = 1, NUM_GROUPS do count[g] = 0 end
	for _, r in ipairs(roster) do count[r.group] = count[r.group] + 1 end

	for _, r in ipairs(roster) do
		local target = desired[r.name]
		if target and target ~= r.group then
			if count[target] < GROUP_SIZE then
				SetRaidSubgroup(r.index, target)
				self.lastMove, self.waitingForRoster = now, true
				return true
			end
			-- target full: swap with someone there who doesn't belong there
			for _, o in ipairs(roster) do
				if o.group == target and desired[o.name] ~= target then
					SwapRaidSubgroup(r.index, o.index)
					self.lastMove, self.waitingForRoster = now, true
					return true
				end
			end
		end
	end
	return false
end

function Groups:Tick()
	if not self.mode then return end
	local now = GetTime()
	if self.waitingForRoster and now - self.lastMove < ROSTER_WAIT_TIMEOUT then return end
	if now - self.lastMove < MOVE_GAP then return end
	self.waitingForRoster = false
	if not CanMove() then return end

	local roster = Roster()
	if self.mode == "forming" then
		self:Step(roster, self:PlanForming(roster), now)
		return
	end
	-- final: plan once, move until everyone is placed, then hand the groups back
	if now > self.finalUntil then
		RF.Print("Final groups: stopped after " .. FINAL_TIMEOUT .. "s.")
		return self:Release()
	end
	self.finalPlan = self.finalPlan or self:PlanFinal(roster)
	if not self:Step(roster, self.finalPlan, now) then
		RF.Print("Final groups are set.")
		self:Release()
	end
end
