-- Core: saved variables, events, whisper handling, invites, verdicts, announcements, slash commands.
local ADDON, RF = ...

local Core = { running = false, nextPost = 0, lastRaidUpdate = 0, replyThrottle = {} }
RF.Core = Core
RF.members = {}

local TICK = 0.5
local INVITE_EXPIRE = 90        -- seconds before an unanswered invite frees its slot
local REPLY_THROTTLE = 8        -- don't answer the same player more often than this
local RAID_UPDATE_THROTTLE = 30
local ARRIVED_GRACE = 120       -- seconds out of range before an arrived player's timeout applies again
local CONFIRM_DELAY = 2         -- seconds before re-inspecting a failing reading
local MAX_READINGS = 3          -- readings before a final verdict (5 while item data is incomplete)
local MAX_INCOMPLETE_READINGS = 5
local RW_DELAY = 1              -- seconds after a join before the raid warning (they see it once in the raid)
local RW_THROTTLE = 10          -- joins close together share one raid warning
local REAPPLY_COOLDOWN = 300    -- removed for low GS: no new invite + inspect for this long
local REJOINABLE = { left = true, timeout = true, rejected = true, refused = true }

RF.STATUS = {
	invited = "Invited", waiting = "Waiting for inspect", accepted = "Accepted", rejected = "Rejected",
	timeout = "Timed out", refused = "Refused", left = "Left raid", expired = "Invite expired",
	declined = "Declined invite",
}
RF.HOLDING = { invited = true, waiting = true, accepted = true }

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99RaidFormer|r: " .. tostring(msg))
end
RF.Print = Print

function RF.CopyTable(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = RF.CopyTable(v) end
	return c
end

-- Announcement extras only come from the preset buttons: drop anything else, keep button order.
function RF.SanitizeExtras(profile)
	local have = {}
	for part in (profile.extras or ""):gmatch("[^,]+") do
		have[part:gsub("^%s+", ""):gsub("%s+$", ""):lower()] = true
	end
	local parts = {}
	for _, label in ipairs(RF.EXTRA_PRESETS) do
		if have[label:lower()] then parts[#parts + 1] = label end
	end
	profile.extras = table.concat(parts, ", ")
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

function Core:DefaultProfile()
	local roles, needs, buffs, caps = RF.DefaultFormation("TOC", 25, false)
	return {
		raid = "TOC", size = 25, heroic = false, customName = "",
		minGS = RF.DefaultMinGS("TOC", 25, false),
		channels = {}, postGuild = false, postYell = false,
		interval = 90, extras = "", freeText = "",
		roles = roles, needs = needs, buffs = buffs, caps = caps,
		autoDefaults = true, warnBefore = 60, -- myRole: nil = detect from talents
		pendingGroup = 1, acceptedGroup = 2, -- raid group control: Forming / Final buttons (Roster tab)
		raidWarnOnJoin = false, raidWarnText = "g1 vh",
		inspectTimeout = 180, autoKick = true, raidUpdates = true, rejectWrongSpec = false,
		requireInspect = true, remindInspect = true, showCount = false,
		formationSource = "default", -- "default" (recommended), "preset:<name>" or "edited"
	}
end

local function MergeDefaults(dst, defaults)
	for k, v in pairs(defaults) do
		if dst[k] == nil then dst[k] = RF.CopyTable(v) end
	end
end

function Core:InitDB()
	RaidFormerDB = RaidFormerDB or {}
	local db = RaidFormerDB
	db.profile = db.profile or {}
	local p = db.profile
	-- migrate settings from older versions
	if p.channels == nil and type(p.channel) == "string" and p.channel ~= "" then p.channels = { p.channel } end
	if p.myRole == nil and type(p.mySpec) == "string" and RF.SPECS[p.mySpec] then
		local role = RF.SPECS[p.mySpec].role
		p.myRole = (role == "tank" or role == "heal") and role or "dps"
	end
	p.channel, p.mySpec, p.strictTalents = nil, nil, nil
	p.organizeGroups, p.sortByRole = nil, nil -- replaced by the Forming / Final buttons
	p.buffs = {} -- buff/utility requirements were removed from the UI; don't keep hidden ones
	MergeDefaults(p, self:DefaultProfile())
	RF.SanitizeExtras(p)
	db.presets = db.presets or {}
	db.aliases = db.aliases or {}           -- word -> spec key / class key / role (/rf alias)
	db.unknownWords = db.unknownWords or {} -- words from whispers nothing matched (/rf unknown)
	db.ui = db.ui or {}
	db.minimap = db.minimap or { angle = 200, hide = false }
	-- keep applicant state across /reload, but not across long breaks
	if db.members and db.membersSavedAt and time() - db.membersSavedAt < 3600 then
		RF.members = db.members
	else
		RF.members = {}
	end
	db.members = RF.members
	-- restored applicants: an inspect in flight doesn't survive a reload (a stale flag would block
	-- timeouts forever), and timers use GetTime, which restarts with the computer: fresh clock
	local now = GetTime()
	for _, m in pairs(RF.members) do
		m.inspecting, m.nextInspect, m.verifiedLowAt, m.warned = nil, nil, nil, nil
		m.movingTo, m.moveFor, m.moveAt, m.placedFor, m.lastGroup, m.groupLocked = nil, nil, nil, nil, nil, nil -- old group logic
		m.arrivedAt, m.lastSeenNear = nil, nil
		if m.invitedAt then m.invitedAt = now end
		if m.joinedAt then m.joinedAt = now end
	end
	RF.db = db
	RF.profile = db.profile
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Spec from the player's own talents.
function Core:AutoSpec()
	local _, class = UnitClass("player")
	local best, bestPoints = 1, -1
	for tab = 1, 3 do
		local _, _, points = GetTalentTabInfo(tab)
		if (points or 0) > bestPoints then best, bestPoints = tab, points or 0 end
	end
	if class == "DEATHKNIGHT" then return "DK_DPS" end
	if class == "DRUID" and best == 2 then return "DRUID_CAT" end
	return RF.SpecFromTab(class, best)
end

-- role: "tank" | "heal" | "dps"
local function SpecHasRole(specKey, role)
	local r = RF.SPECS[specKey] and RF.SPECS[specKey].role
	return r == role or (role == "dps" and (r == "mdps" or r == "rdps"))
end

function Core:RoleAvailable(role)
	local _, class = UnitClass("player")
	for _, key in ipairs(RF.CLASS_SPECS[class] or {}) do
		if SpecHasRole(key, role) then return true end
	end
	return false
end

-- The leader's spec for composition counting: the chosen role (Tank/Healer/DPS), using the
-- talent spec when it already fits that role; talents when no role is chosen.
function Core:MySpec()
	local auto = self:AutoSpec()
	local role = RF.profile.myRole
	if not role or SpecHasRole(auto, role) then return auto end
	local _, class = UnitClass("player")
	for _, key in ipairs(RF.CLASS_SPECS[class] or {}) do
		if SpecHasRole(key, role) then return key end
	end
	return auto
end

-- Everyone holding a slot, including the leader. exclude = name to leave out.
function Core:Holders(exclude)
	local _, myClass = UnitClass("player")
	local list = { { class = myClass, spec = self:MySpec(), name = UnitName("player") } }
	for name, m in pairs(RF.members) do
		-- anyone actually in the raid takes a slot, whatever the addon thought of them
		if (RF.HOLDING[m.status] or m.inGroup) and name ~= exclude then
			list[#list + 1] = { class = m.class, spec = m.spec, name = name }
		end
	end
	return list
end

function Core:Whisper(name, msg)
	-- automatic whispers are marked so players can tell it's an addon talking, not you
	SendChatMessage(RF.SafeChat("[RaidFormer] " .. msg), "WHISPER", nil, name)
end

function Core:CanInvite()
	if GetNumRaidMembers() > 0 then return IsRaidLeader() or IsRaidOfficer() end
	if GetNumPartyMembers() > 0 then return IsPartyLeader() end
	return true
end

function Core:NeedText()
	return (RF.Comp.NeedString(RF.profile, self:Holders()))
end

function Core:Refresh()
	if RF.UI and RF.UI.Refresh then RF.UI:Refresh() end
end

---------------------------------------------------------------------------
-- Whispers
---------------------------------------------------------------------------

-- Whispers carry no addon name, so recognise our own automatic replies by how they start.
-- Another leader running RaidFormer would otherwise make the two addons answer each other forever.
local OWN_REPLIES = {
	"^sorry, ", "^invited as ", "^please whisper your gs", "^got you %- you're #", "^gs %d+ verified",
	"^please come to me for inspect", "^removed: ", "^your inspected gs was", "^you're invited %- come to me",
	"^you're already in a group",
}
local function IsOwnReply(lowerMsg)
	for _, pattern in ipairs(OWN_REPLIES) do
		if lowerMsg:find(pattern) then return true end
	end
	return false
end

function Core:OnWhisper(msg, sender)
	if not self.running then return end
	sender = sender and sender:gsub("%-.*", "") -- strip realm
	if not sender or sender == UnitName("player") then return end
	local lower = msg:lower()
	if lower:find("lfm") or lower:find("%[raidformer%]") or IsOwnReply(lower) then return end

	local now = GetTime()
	local m = RF.members[sender]
	if m and m.inGroup and not RF.HOLDING[m.status] then return end -- already in the raid (kept by you)
	if m and RF.HOLDING[m.status] then return end -- already invited / in the raid: nothing to answer

	-- every spec they offer is an option ("enh 6,3 / resto 5,7"); the raid's needs pick one
	local options, unknown = RF.ParseOptions(msg)
	local gs, spec, class, role
	for _, o in ipairs(options) do
		gs, spec, class, role = gs or o.gs, spec or o.spec, class or o.class, role or o.role
	end
	if not gs and not spec and not class and not role then return end -- not an application

	if self.replyThrottle[sender] and now - self.replyThrottle[sender] < REPLY_THROTTLE then return end
	self.replyThrottle[sender] = now

	local p = RF.profile
	-- inspected below the minimum a moment ago: don't invite and inspect them all over again
	if m and m.status == "rejected" and m.verifiedLowAt and m.gs and m.gs < p.minGS
		and now - m.verifiedLowAt < REAPPLY_COOLDOWN then
		self:Whisper(sender, string.format("Your inspected GS was %d (min %d) - try again in %d min.",
			m.gs, p.minGS, math.ceil((REAPPLY_COOLDOWN - (now - m.verifiedLowAt)) / 60)))
		return
	end
	if not spec and not class and not role then
		self:NoteUnknown(unknown, msg)
		self:Whisper(sender, "Sorry, I didn't catch your class/spec - e.g. '5.6k rsham' or '5.6k ret pala'.")
		return
	end
	if not gs then
		self:Whisper(sender, "Please whisper your GS too, e.g. '5.6k " .. self:ClaimLabel(spec, class, role) .. "'.")
		return
	end

	local holders = self:Holders(sender)
	local choice, reason, allLowGS = self:ChooseOption(options, holders, gs)
	local main = choice and choice.option or options[1]

	-- the whisper is only a claim; the inspect decides the real class and spec
	local entry = {
		name = sender, claimedGS = main.gs or gs, appliedAt = now, whisper = msg,
		claimedSpec = main.spec, claimedClass = main.class, claimedRole = main.role, class = main.class, spec = main.spec,
	}
	-- the other spec they offered: shown in the roster, and fine if they're still in its talents
	for _, o in ipairs(options) do
		if o ~= main and not entry.offLabel then
			entry.offSpec, entry.offGS, entry.offLabel = o.spec, o.gs or gs, self:ClaimLabel(o.spec, o.class, o.role)
		end
	end
	RF.members[sender] = entry

	if not choice then
		entry.status, entry.reason = "refused", reason
		if allLowGS then
			self:Whisper(sender, "Sorry, min GS is " .. RF.Comp.FormatGS(p.minGS) .. ".")
		else
			local need = self:NeedText()
			self:Whisper(sender, "Sorry, " .. reason .. "." .. (need ~= "" and (" Still need: " .. need) or ""))
		end
		self:Refresh()
		return
	end
	entry.spec, entry.class, entry.specGuessed = choice.spec, RF.SPECS[choice.spec].class, choice.guessed

	if not self:CanInvite() then
		entry.status, entry.reason = "refused", "not raid leader/assist"
		Print("Can't invite " .. sender .. ": you need to be leader or assist.")
		self:Refresh()
		return
	end

	self:Invite(entry)
end

-- Pick the spec the raid needs most among what a player offered (one or more options).
-- Returns { option=, spec=, guessed= } or nil, reason, allBelowMinGS
function Core:ChooseOption(options, holders, fallbackGS)
	local p = RF.profile
	local best, bestScore, gsReason, fitReason, allLow = nil, nil, nil, nil, true
	for i, o in ipairs(options) do
		local gs = o.gs or fallbackGS
		if gs < p.minGS then
			gsReason = gsReason or ("GS " .. gs .. " < " .. p.minGS)
		else
			allLow = false
			local spec, why, guessed = o.spec, nil, false
			if not spec then
				-- only class and/or role known: take a spec the raid can still use
				spec, why = RF.Comp.GuessSpec(p, holders, o.class, o.role)
				guessed = spec ~= nil
			end
			if spec then
				local ok, whyNot = RF.Comp.CanAccept(p, holders, spec)
				if not ok then spec, why = nil, whyNot end
			end
			if spec then
				local score = RF.Comp.NeedScore(p, holders, spec) - i * 0.001 -- a tie goes to the spec said first
				if not best or score > bestScore then
					best, bestScore = { option = o, spec = spec, guessed = guessed }, score
				end
			else
				fitReason = fitReason or why
			end
		end
	end
	if best then return best end
	return nil, (allLow and gsReason) or fitReason or gsReason, allLow
end

function Core:Invite(entry)
	if GetNumRaidMembers() == 0 and GetNumPartyMembers() >= 4 then ConvertToRaid() end
	entry.status, entry.invitedAt, entry.reason = "invited", GetTime(), nil
	entry.warned, entry.joinedAt, entry.gs, entry.nextInspect = nil, nil, nil, nil
	entry.arrivedAt, entry.readings, entry.confirming = nil, nil, nil
	-- no whisper: the invite itself says enough (use "RW on join" to send them to inspect)
	InviteUnit(entry.name)
	self:Refresh()
end

-- Short text for what a player claimed: "rsham", "sham", "heal".
function Core:ClaimLabel(spec, class, role)
	if spec and RF.SPECS[spec] then return RF.SPECS[spec].short end
	if class and RF.CLASS_SHORT[class] then return RF.CLASS_SHORT[class] end
	return role or "spec"
end

---------------------------------------------------------------------------
-- Abbreviations: unknown words and your own aliases
---------------------------------------------------------------------------

local MAX_UNKNOWN = 100

function Core:NoteUnknown(words, msg)
	local list = RF.db.unknownWords
	for _, w in ipairs(words or {}) do
		local e = list[w] or { count = 0 }
		e.count, e.example, e.last = e.count + 1, (msg or ""):sub(1, 80), time()
		list[w] = e
	end
	-- keep the list small: drop the rarest, oldest words
	local all = {}
	for w, e in pairs(list) do all[#all + 1] = { w = w, count = e.count, last = e.last or 0 } end
	if #all > MAX_UNKNOWN then
		table.sort(all, function(a, b)
			if a.count ~= b.count then return a.count < b.count end
			return a.last < b.last
		end)
		for i = 1, #all - MAX_UNKNOWN do list[all[i].w] = nil end
	end
end

local function AliasLabel(value)
	if RF.SPECS[value] then return RF.SPECS[value].name .. " " .. RF.CLASS_NAMES[RF.SPECS[value].class] end
	if RF.CLASS_NAMES[value] then return RF.CLASS_NAMES[value] end
	return tostring(value)
end

-- /rf alias rpal ret  ->  "rpal" means Retribution Paladin from now on
function Core:AddAlias(word, target)
	word = (word or ""):lower():gsub("[^%a]", "")
	local kind, value = RF.ResolveAliasTarget(target)
	if word == "" or not kind then
		Print("Usage: /rf alias <word> <spec|class|role>, e.g. /rf alias rpal ret  or  /rf alias healz heal")
		return nil
	end
	RF.db.aliases[word] = value
	RF.db.unknownWords[word] = nil
	Print(string.format("'%s' now means %s.", word, AliasLabel(value)))
	return value
end

function Core:RemoveAlias(word)
	word = (word or ""):lower()
	if RF.db.aliases[word] then
		RF.db.aliases[word] = nil
		Print("Alias removed: " .. word)
	else
		Print("No alias '" .. word .. "'.")
	end
end

function Core:ListAliases()
	local words = {}
	for w in pairs(RF.db.aliases) do words[#words + 1] = w end
	table.sort(words)
	if #words == 0 then Print("No custom aliases. Add one with /rf alias <word> <spec>.") return end
	for _, w in ipairs(words) do Print(w .. " = " .. AliasLabel(RF.db.aliases[w])) end
end

function Core:ListUnknown()
	local all = {}
	for w, e in pairs(RF.db.unknownWords) do all[#all + 1] = { w = w, e = e } end
	table.sort(all, function(a, b) return a.e.count > b.e.count end)
	if #all == 0 then Print("No unrecognised words so far.") return end
	Print("Unrecognised words (teach one with /rf alias <word> <spec>):")
	for i = 1, math.min(10, #all) do
		Print(string.format("  %s x%d  e.g. \"%s\"", all[i].w, all[i].e.count, all[i].e.example or ""))
	end
end

---------------------------------------------------------------------------
-- Roster
---------------------------------------------------------------------------

function Core:OnRosterUpdate(fromLogin)
	local inGroup = {}
	local numRaid = GetNumRaidMembers()
	if numRaid == 0 and GetNumPartyMembers() > 0 and self.running and IsPartyLeader() then
		ConvertToRaid()
	end
	local count = numRaid > 0 and numRaid or GetNumPartyMembers()
	local prefix = numRaid > 0 and "raid" or "party"
	local me = UnitName("player")
	for i = 1, count do
		local unit = prefix .. i
		local name = UnitName(unit)
		if name and name ~= me and name ~= UNKNOWNOBJECT then
			inGroup[name] = true
			local m = RF.members[name]
			if not m then
				-- joined without the addon inviting them: you (or an assist) let them in -> trusted
				m = { name = name, status = "waiting", joinedAt = GetTime(), manualJoin = true, manual = true }
				RF.members[name] = m
				self:QueueJoinWarning()
			elseif m.status == "invited" or m.status == "expired" or m.status == "declined" then
				m.status, m.joinedAt = "waiting", GetTime()
				m.arrivedAt, m.readings, m.confirming = nil, nil, nil
				self:QueueJoinWarning()
			elseif not m.inGroup and REJOINABLE[m.status] then
				-- refused / removed / left and now back in the raid: someone invited them by hand -> trusted
				m.status, m.joinedAt, m.manualJoin, m.manual, m.reason = "waiting", GetTime(), true, true, nil
				m.arrivedAt, m.readings, m.confirming, m.warned, m.nextInspect = nil, nil, nil, nil, nil
				self:QueueJoinWarning()
			end
			m.inGroup = true
			if not m.class then
				local _, class = UnitClass(unit)
				m.class = class
			end
			if m.manual then self:ProvisionalSpec(m) end
			if self:PromoteIfNoInspect(m) then self:RaidUpdate() end
		end
	end
	-- right after logging in the roster can still be empty: don't mark everyone as left
	if not (fromLogin and count == 0) then
		for name, m in pairs(RF.members) do
			if not inGroup[name] then
				m.inGroup = nil
				if m.status == "waiting" or m.status == "accepted" then
					m.status = "left"
					self:RaidUpdate()
				end
			end
		end
	end
	RF.Groups:OnRosterUpdate()
	self:Refresh()
end

-- system messages about invites
local function FormatToPattern(fmt)
	if not fmt then return nil end
	local escaped = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	escaped = escaped:gsub("%%s", "(.+)")
	return "^" .. escaped .. "$"
end

function Core:OnSystemMessage(msg)
	-- "You have invited X to join your group." for an invite the addon didn't send: you invited
	-- them by hand, so they hold a slot right away and are trusted
	local invitePattern = FormatToPattern(_G.ERR_INVITE_PLAYER_S)
	local invited = invitePattern and msg:match(invitePattern)
	if invited then
		local m = RF.members[invited]
		if not (m and (RF.HOLDING[m.status] or m.inGroup)) then
			m = m or { name = invited }
			RF.members[invited] = m
			m.status, m.invitedAt, m.reason = "invited", GetTime(), nil
			m.manual, m.manualInvite = true, true
			self:Refresh()
		end
		return
	end
	for _, key in ipairs({ "ERR_DECLINE_GROUP_S", "ERR_ALREADY_IN_GROUP_S", "ERR_BAD_PLAYER_NAME_S" }) do
		local pattern = FormatToPattern(_G[key])
		local name = pattern and msg:match(pattern)
		if name then
			local m = RF.members[name]
			if m and m.status == "invited" then
				m.status = "declined"
				m.reason = (key == "ERR_ALREADY_IN_GROUP_S") and "already in a group" or
					(key == "ERR_BAD_PLAYER_NAME_S") and "player not found" or "declined invite"
				if key == "ERR_ALREADY_IN_GROUP_S" then
					self:Whisper(name, "You're already in a group - leave it and whisper me again.")
				end
				self:Refresh()
			end
			return
		end
	end
end

---------------------------------------------------------------------------
-- Inspect verdicts
---------------------------------------------------------------------------

function Core:WarnBefore()
	local p = RF.profile
	return math.max(0, math.min(p.warnBefore or 60, p.inspectTimeout - 10))
end

-- A failing reading is only final once it has been confirmed: the first inspect can show
-- transmog / stale item links with lower item levels.
local function NeedsConfirmation(m)
	local n = #m.readings
	local last, prev = m.readings[n], m.readings[n - 1]
	if n >= MAX_INCOMPLETE_READINGS then return false end
	if last.incomplete or (prev and prev.incomplete) then return true end
	if n < 2 then return true end
	if n >= MAX_READINGS then return false end
	return last.sig ~= prev.sig -- gear changed between readings: take another look
end

-- First spec of the class that fits a whispered role ("tank" for a druid -> bear).
local function RoleHint(class, role)
	if not class or not role then return nil end
	for _, key in ipairs(RF.CLASS_SPECS[class] or {}) do
		if SpecHasRole(key, role) then return key end
	end
end

function Core:OnInspected(name, class, gs, ilvl, tab, incomplete, signature)
	local m = RF.members[name]
	if not m or m.status ~= "waiting" then return end
	m.class = class or m.class
	local p = RF.profile

	-- every reading is kept; the highest GS counts (stale readings are only ever lower)
	m.readings = m.readings or {}
	table.insert(m.readings, { gs = gs, ilvl = ilvl, tab = tab, sig = signature, incomplete = incomplete })
	local best = m.readings[1]
	for _, r in ipairs(m.readings) do
		if r.gs > best.gs then best = r end
	end
	m.gs, m.ilvl, m.tab = best.gs, best.ilvl, tab

	-- the inspect decides: real class from the character, real spec from the talents. Only a real
	-- claim settles what talents can't show (bear/cat, dk tank/dps) - never our own guess.
	local hint = m.specByLeader or m.claimedSpec or RoleHint(m.class, m.claimedRole) or (not m.specGuessed and m.spec) or nil
	local actual = RF.SpecFromInspect(m.class, tab, hint)
	-- a spec you set yourself always counts (e.g. the fury warrior who offered to tank)
	if m.specByLeader and RF.SPECS[m.specByLeader] and RF.SPECS[m.specByLeader].class == m.class then
		actual = m.specByLeader
	end
	-- still in the talents of the other spec they offered: they'll switch, count the one we picked
	if actual and m.offSpec and actual == m.offSpec and RF.SPECS[m.spec] and RF.SPECS[m.spec].class == m.class then
		m.inOffSpec, actual = true, m.spec
	end

	if m.manual then
		-- trusted: only their spec is learned; a spec you set yourself wins over talents
		m.spec, m.specGuessed = m.specByLeader or actual or m.spec, nil
		m.status, m.confirming = "accepted", nil
		for _, r in ipairs(m.readings) do r.sig = nil end
		self:Refresh()
		return
	end

	local claimedWrong = actual and not m.specByLeader and ((m.claimedSpec and m.claimedSpec ~= actual)
		or (m.claimedClass and m.claimedClass ~= m.class)
		or (m.claimedRole and not SpecHasRole(actual, m.claimedRole)))
	local lowGS = m.gs < p.minGS
	local reason
	if lowGS then
		reason = string.format("GS %d is below %d", m.gs, p.minGS)
	elseif not actual then
		reason = "couldn't determine spec"
	elseif claimedWrong and p.rejectWrongSpec then
		reason = string.format("whispered %s but you are %s",
			self:ClaimLabel(m.claimedSpec, m.claimedClass, m.claimedRole), RF.SPECS[actual].short)
	else
		local ok, why = RF.Comp.CanAccept(p, self:Holders(name), actual)
		if not ok then reason = (claimedWrong and ("as " .. RF.SPECS[actual].short .. " ") or "") .. why end
	end

	-- talents/gear can be stale on the first look: confirm before removing anyone
	if reason and NeedsConfirmation(m) then
		m.confirming = true
		m.nextInspect = GetTime() + CONFIRM_DELAY
		self:Refresh()
		return
	end
	m.confirming = nil
	-- the verdict is final: gear signatures were only needed for confirming (keeps SavedVariables small)
	for _, r in ipairs(m.readings) do r.sig = nil end

	if reason then
		if lowGS then m.verifiedLowAt = GetTime() end
		-- if you keep them in the raid anyway they count with their real spec
		if actual then m.spec, m.specGuessed = actual, nil end
		self:Reject(m, reason)
	else
		-- no whisper: being moved to the accepted groups tells them they're in
		m.spec, m.specGuessed = actual, nil
		m.status, m.reason = "accepted", nil
		self:RaidUpdate()
	end
	self:Refresh()
end

function Core:Reject(m, reason, manual)
	m.status, m.reason = "rejected", reason
	self:Whisper(m.name, "Sorry, removed: " .. reason .. ".")
	if RF.profile.autoKick or manual then UninviteUnit(m.name) end
	self:RaidUpdate()
	self:Refresh()
end

-- Trusted players count right away: until they are inspected (or you set their spec) they get
-- a spec that fits their class and the raid, shown with "?" in the roster.
function Core:ProvisionalSpec(m)
	if m.spec or not m.class or not RF.CLASS_SPECS[m.class] then return end
	m.spec = RF.Comp.GuessSpec(RF.profile, self:Holders(m.name), m.class, nil) or RF.CLASS_SPECS[m.class][1]
	m.specGuessed = true
end

-- "Require inspect" off: whoever joins is taken at their whispered word - no inspect, no GS
-- check, no timeout. They are counted with the spec they gave (or the one you set).
function Core:PromoteIfNoInspect(m)
	if RF.profile.requireInspect or m.status ~= "waiting" then return false end
	m.status, m.reason, m.confirming = "accepted", nil, nil
	return true
end

-- Roster tab spec menu: set a player's spec yourself (friends who never come to inspect, bear/cat ...)
function Core:SetSpec(name, specKey)
	local m = RF.members[name]
	if not m or not RF.SPECS[specKey] then return end
	m.spec, m.class, m.specGuessed, m.specByLeader = specKey, RF.SPECS[specKey].class, nil, specKey
	local need = self:NeedText()
	Print(string.format("%s now counted as %s. Still need: %s", name, RF.SPECS[specKey].short, need ~= "" and need or "nothing"))
	self:Refresh()
end

---------------------------------------------------------------------------
-- Formation baseline: recommended, a preset, or your own edits
---------------------------------------------------------------------------

-- Changing raid/size/difficulty only reloads the recommended setup while you're still on it.
-- A loaded preset or your own edits are your baseline and stay as they are.
function Core:MarkEdited()
	if (RF.profile.formationSource or "default") == "default" then RF.profile.formationSource = "edited" end
end

function Core:LoadRecommended()
	local p = RF.profile
	p.roles, p.needs, p.buffs, p.caps = RF.DefaultFormation(p.raid, p.size, p.heroic)
	p.minGS = RF.DefaultMinGS(p.raid, p.size, p.heroic)
	p.formationSource = "default"
end

-- Raid, size or difficulty changed in the Setup tab.
function Core:RaidSettingsChanged()
	local p = RF.profile
	if p.autoDefaults and (p.formationSource or "default") == "default" then self:LoadRecommended() end
end

function Core:LoadPreset(name)
	local preset = RF.db.presets[name]
	if not preset then return false end
	local p = RF.profile
	for k, v in pairs(RF.CopyTable(preset)) do p[k] = v end
	p.buffs = {}
	RF.SanitizeExtras(p)
	p.formationSource = "preset:" .. name
	Print("Preset loaded: " .. name .. " - changing raid/size now keeps it.")
	return true
end

function Core:BaselineText()
	local src = RF.profile.formationSource or "default"
	if src == "default" then return "Based on: recommended for this raid" end
	if src == "edited" then return "Based on: your edits (kept on raid change)" end
	return "Based on: preset '" .. src:sub(8) .. "' (kept on raid change)"
end

-- Manual overrides from the Roster tab
function Core:ManualAccept(name)
	local m = RF.members[name]
	if not m then return end
	m.manual = true
	if RF.UnitForName(name) then
		m.status = "accepted"
	elseif m.spec then
		self:Invite(m)
	else
		Print(name .. " has no spec yet - whisper-invite them manually.")
	end
	self:Refresh()
end

function Core:ManualKick(name)
	local m = RF.members[name]
	if not m then return end
	m.manual = nil
	if RF.UnitForName(name) then
		self:Reject(m, "removed by leader", true)
	else
		m.status, m.reason = "rejected", "removed by leader"
		self:Refresh()
	end
end

function Core:Reinspect(name)
	local m = RF.members[name]
	if m and RF.UnitForName(name) then
		m.status, m.nextInspect, m.warned, m.joinedAt = "waiting", nil, nil, GetTime()
		m.arrivedAt, m.readings, m.confirming = nil, nil, nil
		self:Refresh()
	end
end

---------------------------------------------------------------------------
-- Announcements
---------------------------------------------------------------------------

function Core:Announcement()
	return RF.Comp.BuildAnnouncement(RF.profile, self:Holders())
end

function Core:IsFull()
	return #self:Holders() >= RF.profile.size
end

function Core:ChannelId(ch)
	if not ch or ch == "" then return nil end
	local id = GetChannelName(ch)
	if (not id or id == 0) and tonumber(ch) then id = GetChannelName(tonumber(ch)) end
	if id and id > 0 then return id end
end

local SEND_DELAY_MIN, SEND_DELAY_MAX = 0.8, 1.2 -- random pause between channels

-- Queues the announcement for every selected channel (+ guild/yell); the first goes out
-- immediately, the rest one by one with a random 0.8-1.2s pause.
function Core:Post(manual)
	local p = RF.profile
	if self:IsFull() and not manual then return end
	local msg = self:Announcement()
	local queue = {}
	for _, ch in ipairs(p.channels or {}) do
		local id = self:ChannelId(ch)
		if id then
			queue[#queue + 1] = { msg = msg, chatType = "CHANNEL", id = id }
		else
			Print("You are not in channel '" .. ch .. "'.")
		end
	end
	if p.postGuild and IsInGuild() then queue[#queue + 1] = { msg = msg, chatType = "GUILD" } end
	if p.postYell then queue[#queue + 1] = { msg = msg, chatType = "YELL" } end
	self.nextPost = GetTime() + math.max(30, p.interval or 90)
	if #queue == 0 then
		Print("No announcement target set - pick channels in the Setup tab.")
		return
	end
	self.sendQueue, self.nextSendAt = queue, 0
	self:ProcessSendQueue()
end

-- Called every frame.
function Core:ProcessSendQueue()
	local queue = self.sendQueue
	if not queue or #queue == 0 then return end
	local now = GetTime()
	if now < self.nextSendAt then return end
	local item = table.remove(queue, 1)
	SendChatMessage(RF.SafeChat(item.msg), item.chatType, nil, item.id)
	self.nextSendAt = now + SEND_DELAY_MIN + math.random() * (SEND_DELAY_MAX - SEND_DELAY_MIN)
end

-- "/rw g1 vh" once new players are in the raid; joins close together share one warning.
function Core:QueueJoinWarning()
	local p = RF.profile
	if not self.running or not p.raidWarnOnJoin then return end
	if not self.rwAt then self.rwAt = GetTime() + RW_DELAY end
end

function Core:SendJoinWarning()
	if not self.rwAt then return end
	local now = GetTime()
	if now < self.rwAt or now - (self.lastRW or -RW_THROTTLE) < RW_THROTTLE then return end
	self.rwAt = nil
	local p = RF.profile
	local text = RF.SafeChat((p.raidWarnText or ""):gsub("^%s+", ""):gsub("%s+$", ""))
	if not self.running or not p.raidWarnOnJoin or text == "" then return end
	local chatType
	if GetNumRaidMembers() > 0 then
		chatType = (IsRaidLeader() or IsRaidOfficer()) and "RAID_WARNING" or "RAID"
	elseif GetNumPartyMembers() > 0 then
		chatType = "PARTY"
	else
		return
	end
	SendChatMessage(text, chatType)
	self.lastRW = now
end

function Core:RaidUpdate()
	if not self.running or not RF.profile.raidUpdates or GetNumRaidMembers() == 0 then return end
	local now = GetTime()
	if self:IsFull() then
		local allDone = true
		for _, m in pairs(RF.members) do
			if m.status == "waiting" or m.status == "invited" then allDone = false end
		end
		if allDone and not self.announcedFull then
			self.announcedFull = true
			SendChatMessage("Raid is full - thanks everyone!", (IsRaidLeader() or IsRaidOfficer()) and "RAID_WARNING" or "RAID")
			Print("Raid full! Announcements paused.")
		end
		return
	end
	self.announcedFull = false
	if now - self.lastRaidUpdate < RAID_UPDATE_THROTTLE then return end
	self.lastRaidUpdate = now
	SendChatMessage(RF.SafeChat(string.format("%d/%d - still need: %s", #self:Holders(), RF.profile.size, self:NeedText())), "RAID")
end

---------------------------------------------------------------------------
-- Ticker
---------------------------------------------------------------------------

function Core:Tick()
	local now = GetTime()
	local p = RF.profile
	local changed = false

	for name, m in pairs(RF.members) do
		if m.status == "invited" and m.invitedAt and now - m.invitedAt > INVITE_EXPIRE then
			m.status, m.reason, changed = "expired", "didn't accept invite", true
		elseif m.status == "waiting" and not p.requireInspect then
			if self:PromoteIfNoInspect(m) then changed = true end
		elseif m.status == "waiting" and m.joinedAt and self.running and not m.manual and p.remindInspect then
			-- arrived players can't time out, unless they walked away again for a while
			if m.arrivedAt and not m.inspecting and now - (m.lastSeenNear or m.arrivedAt) > ARRIVED_GRACE then
				m.arrivedAt, m.warned = nil, nil
				m.joinedAt = math.max(m.joinedAt, now - p.inspectTimeout + 60)
			end
			if not m.arrivedAt then
				local waited = now - m.joinedAt
				local warnBefore = self:WarnBefore()
				if warnBefore > 0 and not m.warned and waited > p.inspectTimeout - warnBefore then
					m.warned = true
					self:Whisper(name, string.format("Please come to me for inspect - you'll be removed in %d seconds.", warnBefore))
				elseif waited > p.inspectTimeout and not m.inspecting then
					m.status, m.reason, changed = "timeout", "didn't come for inspect", true
					self:Whisper(name, "Removed: didn't come for inspect in time. Whisper again when you're nearby.")
					if p.autoKick then UninviteUnit(name) end
				end
			end
		end
	end

	RF.Inspect:Tick(RF.members)
	RF.Groups:Tick()
	self:SendJoinWarning()

	if self.running and now >= self.nextPost and not self:IsFull() then self:Post() end
	if changed then self:Refresh() end
	if RF.UI and RF.UI.UpdateStatus then RF.UI:UpdateStatus() end
end

function Core:Start()
	self.running = true
	self.nextPost = GetTime() + 1
	self.announcedFull = false
	Print("Started: " .. RF.RaidTag(RF.profile.raid, RF.profile.size, RF.profile.heroic, RF.profile.customName))
	if RF.Comp.RoleTotal(RF.profile) ~= RF.profile.size then
		Print("|cffff4040Warning:|r role counts (" .. RF.Comp.RoleTotal(RF.profile) .. ") don't match raid size (" .. RF.profile.size .. ").")
	end
	self:Refresh()
end

function Core:Stop()
	self.running = false
	Print("Stopped.")
	RF.Groups:Release() -- raid groups are yours again
	self:Refresh()
end

function Core:ClearApplicants()
	for name, m in pairs(RF.members) do
		if not RF.HOLDING[m.status] then RF.members[name] = nil end
	end
	self:Refresh()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
Core.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
frame:RegisterEvent("INSPECT_TALENT_READY")

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		Core:InitDB()
	elseif event == "PLAYER_LOGIN" then
		if RF.UI and RF.UI.Init then RF.UI:Init() end
		Core:OnRosterUpdate(true)
	elseif event == "PLAYER_LOGOUT" then
		if RF.db then RF.db.membersSavedAt = time() end
	elseif not RF.db then
		return
	elseif event == "CHAT_MSG_WHISPER" then
		Core:OnWhisper(arg1, arg2)
	elseif event == "CHAT_MSG_SYSTEM" then
		Core:OnSystemMessage(arg1)
	elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
		Core:OnRosterUpdate()
	elseif event == "INSPECT_TALENT_READY" then
		RF.Inspect:OnTalentReady(RF.members)
	end
end)

local elapsedSince = 0
frame:SetScript("OnUpdate", function(_, elapsed)
	if RF.db then Core:ProcessSendQueue() end
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < TICK or not RF.db then return end
	elapsedSince = 0
	Core:Tick()
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_RAIDFORMER1 = "/rf"
SLASH_RAIDFORMER2 = "/raidformer"
SlashCmdList["RAIDFORMER"] = function(input)
	local cmd, rest = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "alias" then
		local word, target = rest:match("^(%S+)%s+(.+)$")
		if word then Core:AddAlias(word, target)
		elseif rest ~= "" then Core:AddAlias(rest, nil)
		else Core:ListAliases() end
	elseif cmd == "unalias" then Core:RemoveAlias(rest)
	elseif cmd == "unknown" then Core:ListUnknown()
	elseif cmd == "start" then Core:Start()
	elseif cmd == "stop" then Core:Stop()
	elseif cmd == "post" then Core:Post(true)
	elseif cmd == "status" then
		Print(string.format("%s | %d/%d | need: %s", Core.running and "running" or "stopped",
			#Core:Holders(), RF.profile.size, Core:NeedText()))
		Print(Core:Announcement())
	elseif cmd == "clear" then Core:ClearApplicants()
	elseif cmd == "help" then
		Print("/rf - toggle window | /rf start | /rf stop | /rf post | /rf status | /rf clear")
		Print("/rf alias [word spec] - list/add abbreviations | /rf unalias word | /rf unknown - unrecognised words")
	else
		if RF.UI and RF.UI.Toggle then RF.UI:Toggle() end
	end
end
