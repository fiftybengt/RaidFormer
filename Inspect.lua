-- Inspect queue: first come first served, one inspect at a time, retries while item data
-- is not cached, and protection against other addons inspecting in the middle of ours.
local _, RF = ...

local Inspect = { pending = nil, lastSend = 0, foreign = false, sending = false }
RF.Inspect = Inspect

local SEND_TIMEOUT = 4        -- seconds to wait for INSPECT_TALENT_READY
local CACHE_RETRY_DELAY = 1.5
local MAX_CACHE_RETRIES = 4
local FOREIGN_RETRY_DELAY = 1
local MAX_FOREIGN_RETRIES = 10
local MIN_GAP = 1.0           -- seconds between our NotifyInspect calls

local function UnitForName(name)
	for i = 1, GetNumRaidMembers() do
		local unit = "raid" .. i
		if UnitName(unit) == name then return unit end
	end
	for i = 1, GetNumPartyMembers() do
		local unit = "party" .. i
		if UnitName(unit) == name then return unit end
	end
end
RF.UnitForName = UnitForName

local function InRange(unit)
	return UnitIsConnected(unit) and UnitIsVisible(unit) and CheckInteractDistance(unit, 1) and CanInspect(unit)
end
Inspect.InRange = InRange

-- Anyone else calling NotifyInspect (GearScoreLite mouseover, the player's own inspect)
-- while ours is pending overwrites the server's inspect data.
hooksecurefunc("NotifyInspect", function()
	if Inspect.sending then return end
	if Inspect.pending then Inspect.foreign = true end
end)

local function Notify(unit)
	Inspect.sending = true
	Inspect.foreign = false
	NotifyInspect(unit)
	Inspect.sending = false
	Inspect.lastSend = GetTime()
end

-- Gear signature: all equipped item links, used to spot stale / transmog readings.
function Inspect.GearSignature(unit)
	local links = {}
	for slot = 1, 19 do links[slot] = GetInventoryItemLink(unit, slot) or "" end
	return table.concat(links, ";")
end

-- Members who have come into range and wait for inspect, in arrival order.
function Inspect:Queue(members)
	local queue = {}
	for _, m in pairs(members) do
		if m.status == "waiting" and m.arrivedAt then queue[#queue + 1] = m end
	end
	table.sort(queue, function(a, b)
		if a.arrivedAt ~= b.arrivedAt then return a.arrivedAt < b.arrivedAt end
		if (a.joinedAt or 0) ~= (b.joinedAt or 0) then return (a.joinedAt or 0) < (b.joinedAt or 0) end
		return a.name < b.name
	end)
	return queue
end

function Inspect:QueuePosition(name)
	for i, m in ipairs(self:Queue(RF.members)) do
		if m.name == name then return i end
	end
end

function Inspect:IsBusy() return self.pending ~= nil end

function Inspect:Send(member, unit)
	self.pending = { name = member.name, unit = unit, sentAt = GetTime(), retries = 0, foreignRetries = 0 }
	member.inspecting = true
	Notify(unit)
end

-- Called from the Core ticker. members: RF.members table.
function Inspect:Tick(members)
	local now = GetTime()

	-- arrival tracking (first time each waiting member is seen in range)
	local arrived = {}
	for name, m in pairs(members) do
		if m.status == "waiting" then
			local unit = UnitForName(name)
			if unit and InRange(unit) then
				if not m.arrivedAt then
					m.arrivedAt = now
					arrived[#arrived + 1] = m
				end
				m.lastSeenNear = now
			end
		end
	end
	if #arrived > 0 then RF.Core:Refresh() end -- roster shows "In queue #N"

	local p = self.pending
	if p then
		if p.retryAt and now >= p.retryAt then
			p.retryAt = nil
			local unit = UnitForName(p.name)
			if unit and InRange(unit) then
				p.unit, p.sentAt = unit, now
				Notify(unit)
			else
				self:Finish(members, false)
			end
		elseif not p.retryAt and now - p.sentAt > SEND_TIMEOUT then
			self:Finish(members, false) -- server never answered, try again later
		end
		return
	end
	if now - self.lastSend < MIN_GAP then return end
	-- Don't fight with the player's own inspect window.
	if InspectFrame and InspectFrame:IsShown() then return end

	for _, m in ipairs(self:Queue(members)) do
		if not m.nextInspect or now >= m.nextInspect then
			local unit = UnitForName(m.name)
			if unit and InRange(unit) then
				self:Send(m, unit)
				return
			end
		end
	end
end

function Inspect:Finish(members, done)
	local p = self.pending
	self.pending = nil
	self.foreign = false
	if p and members[p.name] then
		members[p.name].inspecting = nil
		if not done then members[p.name].nextInspect = GetTime() + 3 end
	end
	ClearInspectPlayer()
end

-- INSPECT_TALENT_READY handler
function Inspect:OnTalentReady(members)
	local p = self.pending
	if not p then return end
	if self.foreign then
		-- data may belong to someone else; ask again without using up cache retries
		self.foreign = false
		p.foreignRetries = p.foreignRetries + 1
		if p.foreignRetries > MAX_FOREIGN_RETRIES then return self:Finish(members, false) end
		p.retryAt = GetTime() + FOREIGN_RETRY_DELAY
		return
	end
	if UnitName(p.unit) ~= p.name then
		-- raid indexes shifted; re-resolve and retry
		p.retryAt = GetTime() + 0.2
		return
	end
	local gs, ilvl, incomplete = RF.GS.GetScore(p.unit)
	if incomplete and p.retries < MAX_CACHE_RETRIES then
		p.retries = p.retries + 1
		p.retryAt = GetTime() + CACHE_RETRY_DELAY
		return
	end
	local _, class = UnitClass(p.unit)
	local tab = RF.GetInspectedPrimaryTab()
	local signature = Inspect.GearSignature(p.unit)
	local name = p.name
	self:Finish(members, true)
	RF.Core:OnInspected(name, class, gs, ilvl, tab, incomplete, signature)
end
