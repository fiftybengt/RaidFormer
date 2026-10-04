-- Whisper parsing: GearScore, class, spec and role from free-form text.
-- Exact abbreviation table first, then your own aliases (/rf alias), then typo tolerance.
-- The result is only a claim: the inspect decides the real class and spec.
local _, RF = ...

local CLASS_WORDS = {
	warrior = "WARRIOR", warr = "WARRIOR", war = "WARRIOR", warri = "WARRIOR", warrio = "WARRIOR", wari = "WARRIOR",
	paladin = "PALADIN", pala = "PALADIN", pally = "PALADIN", pal = "PALADIN", pali = "PALADIN", paly = "PALADIN", palla = "PALADIN", pld = "PALADIN",
	hunter = "HUNTER", hunt = "HUNTER", hunta = "HUNTER", hunti = "HUNTER", hun = "HUNTER", hntr = "HUNTER",
	rogue = "ROGUE", rog = "ROGUE", rouge = "ROGUE", rogu = "ROGUE",
	priest = "PRIEST", pri = "PRIEST", pr = "PRIEST", prst = "PRIEST", prist = "PRIEST",
	dk = "DEATHKNIGHT", deathknight = "DEATHKNIGHT", death = "DEATHKNIGHT", dknight = "DEATHKNIGHT",
	shaman = "SHAMAN", sham = "SHAMAN", shammy = "SHAMAN", shamy = "SHAMAN", shamie = "SHAMAN", shm = "SHAMAN", shammi = "SHAMAN",
	mage = "MAGE", mag = "MAGE",
	warlock = "WARLOCK", lock = "WARLOCK", wl = "WARLOCK", wlock = "WARLOCK", lok = "WARLOCK",
	druid = "DRUID", dudu = "DRUID", dru = "DRUID", drood = "DRUID", drud = "DRUID",
}

-- Words that identify a spec on their own ("mm hunt" is also found as the joined pair "mmhunt").
local SPEC_WORDS = {
	-- paladin
	ret = "PALADIN_RET", retri = "PALADIN_RET", retr = "PALADIN_RET", retribution = "PALADIN_RET", retadin = "PALADIN_RET",
	retpal = "PALADIN_RET", retpala = "PALADIN_RET", retpally = "PALADIN_RET", rpal = "PALADIN_RET", rpala = "PALADIN_RET", rpally = "PALADIN_RET",
	hpal = "PALADIN_HOLY", hpala = "PALADIN_HOLY", hpally = "PALADIN_HOLY", hpaladin = "PALADIN_HOLY", holypal = "PALADIN_HOLY", holypala = "PALADIN_HOLY", holypally = "PALADIN_HOLY",
	ppal = "PALADIN_PROT", ppala = "PALADIN_PROT", ppally = "PALADIN_PROT", protpal = "PALADIN_PROT", protpala = "PALADIN_PROT", protpally = "PALADIN_PROT", tankadin = "PALADIN_PROT",
	-- priest
	spriest = "PRIEST_SHADOW", sp = "PRIEST_SHADOW", shadow = "PRIEST_SHADOW", shadowpriest = "PRIEST_SHADOW", shp = "PRIEST_SHADOW", spr = "PRIEST_SHADOW", spri = "PRIEST_SHADOW",
	disc = "PRIEST_DISC", disco = "PRIEST_DISC", discipline = "PRIEST_DISC", discpriest = "PRIEST_DISC", dpriest = "PRIEST_DISC",
	hpriest = "PRIEST_HOLY", holypriest = "PRIEST_HOLY", hpr = "PRIEST_HOLY", hpri = "PRIEST_HOLY",
	-- shaman
	rsham = "SHAMAN_RESTO", rshaman = "SHAMAN_RESTO", rshammy = "SHAMAN_RESTO", rshm = "SHAMAN_RESTO", restosham = "SHAMAN_RESTO", restoshaman = "SHAMAN_RESTO",
	ele = "SHAMAN_ELE", elemental = "SHAMAN_ELE", elesham = "SHAMAN_ELE", eleshaman = "SHAMAN_ELE", esham = "SHAMAN_ELE",
	enh = "SHAMAN_ENH", enha = "SHAMAN_ENH", enhance = "SHAMAN_ENH", enhancement = "SHAMAN_ENH", enhsham = "SHAMAN_ENH", enhshaman = "SHAMAN_ENH",
	-- druid
	rdruid = "DRUID_RESTO", rdudu = "DRUID_RESTO", rdru = "DRUID_RESTO", tree = "DRUID_RESTO", restodruid = "DRUID_RESTO", restodudu = "DRUID_RESTO",
	boomkin = "DRUID_BALANCE", moonkin = "DRUID_BALANCE", boomy = "DRUID_BALANCE", boomie = "DRUID_BALANCE", boomi = "DRUID_BALANCE", boom = "DRUID_BALANCE",
	balance = "DRUID_BALANCE", bala = "DRUID_BALANCE", owl = "DRUID_BALANCE", moonk = "DRUID_BALANCE",
	bear = "DRUID_BEAR", beartank = "DRUID_BEAR", feraltank = "DRUID_BEAR",
	cat = "DRUID_CAT", kitty = "DRUID_CAT", feral = "DRUID_CAT", fdruid = "DRUID_CAT", catdruid = "DRUID_CAT",
	-- death knight
	bdk = "DK_DPS", fdk = "DK_DPS", udk = "DK_DPS", unholy = "DK_DPS", frostdk = "DK_DPS", dkdps = "DK_DPS", dpsdk = "DK_DPS",
	tankdk = "DK_TANK", dktank = "DK_TANK",
	-- warrior
	fury = "WARRIOR_FURY", fwarr = "WARRIOR_FURY", fwar = "WARRIOR_FURY", furywarr = "WARRIOR_FURY", furywar = "WARRIOR_FURY", fwarrior = "WARRIOR_FURY",
	arms = "WARRIOR_ARMS", awarr = "WARRIOR_ARMS", awar = "WARRIOR_ARMS", armswarr = "WARRIOR_ARMS", armswar = "WARRIOR_ARMS",
	pwarr = "WARRIOR_PROT", pwar = "WARRIOR_PROT", protwar = "WARRIOR_PROT", protwarr = "WARRIOR_PROT", protwarrior = "WARRIOR_PROT",
	-- hunter
	mm = "HUNTER_MM", mmh = "HUNTER_MM", mmhunt = "HUNTER_MM", mmhunter = "HUNTER_MM", mmhun = "HUNTER_MM",
	marks = "HUNTER_MM", marksman = "HUNTER_MM", marksmanship = "HUNTER_MM",
	bm = "HUNTER_BM", bmh = "HUNTER_BM", bmhunt = "HUNTER_BM", bmhunter = "HUNTER_BM", beastmaster = "HUNTER_BM", beastmastery = "HUNTER_BM",
	sv = "HUNTER_SV", svh = "HUNTER_SV", svhunt = "HUNTER_SV", surv = "HUNTER_SV", survhunt = "HUNTER_SV", survival = "HUNTER_SV",
	-- rogue
	combat = "ROGUE_COMBAT", crog = "ROGUE_COMBAT", combatrog = "ROGUE_COMBAT",
	assa = "ROGUE_ASSA", assassination = "ROGUE_ASSA", mut = "ROGUE_ASSA", muti = "ROGUE_ASSA", mutilate = "ROGUE_ASSA", mrog = "ROGUE_ASSA",
	sub = "ROGUE_SUB", subtlety = "ROGUE_SUB", srog = "ROGUE_SUB",
	-- mage
	arcane = "MAGE_ARCANE", amage = "MAGE_ARCANE", arcmage = "MAGE_ARCANE",
	fire = "MAGE_FIRE", fmage = "MAGE_FIRE", firemage = "MAGE_FIRE",
	frmage = "MAGE_FROST", frostmage = "MAGE_FROST",
	-- warlock
	affli = "WARLOCK_AFFLI", aff = "WARLOCK_AFFLI", affliction = "WARLOCK_AFFLI", afflock = "WARLOCK_AFFLI",
	demo = "WARLOCK_DEMO", demonology = "WARLOCK_DEMO", demolock = "WARLOCK_DEMO",
	destro = "WARLOCK_DESTRO", destru = "WARLOCK_DESTRO", destruction = "WARLOCK_DESTRO", destrolock = "WARLOCK_DESTRO",
}

-- Words whose meaning depends on the class.
local CLASS_SPEC_WORDS = {
	resto = { SHAMAN = "SHAMAN_RESTO", DRUID = "DRUID_RESTO" },
	restoration = { SHAMAN = "SHAMAN_RESTO", DRUID = "DRUID_RESTO" },
	holy = { PALADIN = "PALADIN_HOLY", PRIEST = "PRIEST_HOLY" },
	prot = { WARRIOR = "WARRIOR_PROT", PALADIN = "PALADIN_PROT" },
	protection = { WARRIOR = "WARRIOR_PROT", PALADIN = "PALADIN_PROT" },
	frost = { MAGE = "MAGE_FROST", DEATHKNIGHT = "DK_DPS" },
	blood = { DEATHKNIGHT = "DK_DPS" },
}

-- role: tank | heal | dps | mdps | rdps
local ROLE_WORDS = {
	tank = "tank", tanking = "tank", tnk = "tank", mt = "tank", ot = "tank",
	heal = "heal", healer = "heal", heals = "heal", healing = "heal", heali = "heal", healz = "heal", hps = "heal",
	dps = "dps", dd = "dps",
	melee = "mdps", mdps = "mdps",
	caster = "rdps", ranged = "rdps", range = "rdps", rdps = "rdps",
}

-- When class + role leave several specs, these don't change anything for the raid.
local DEFAULT_DPS = { WARRIOR = "WARRIOR_FURY", HUNTER = "HUNTER_MM", ROGUE = "ROGUE_COMBAT", MAGE = "MAGE_FROST", WARLOCK = "WARLOCK_AFFLI" }

-- Classes that can only DPS: "hunt 5.6k" is fine as mm, but "warr 5.6k" might be a tank.
local ONLY_DPS = {}
for class, specs in pairs(RF.CLASS_SPECS) do
	local only = true
	for _, key in ipairs(specs) do
		local role = RF.SPECS[key].role
		if role == "tank" or role == "heal" then only = false end
	end
	ONLY_DPS[class] = only
end

-- Common words in applications that are not unknown abbreviations.
local IGNORE = {}
for w in ([[k gs ilvl inv invite invit pls plz please lf lfm lfg me im iam am my can you hi hey hello yo for the
	and or with spot spots still need raid toc icc rs voa uld ulduar naxx ony os eoe ok thx ty got have has spec
	offspec ms main dual achiev achi ach done exp link sure yes no lol hc nm heroic normal gear score full run
	man pve bis both also ready of in on to is it bro gearscore xp hm here near come coming omw sec wait]]):gmatch("%a+") do
	IGNORE[w] = true
end

-- "5", "62" -> 5620 ; "5", "6" -> 5600 ; "5", "625" -> 5625
local function Thousands(whole, decimals)
	decimals = decimals:sub(1, 3)
	return tonumber(whole) * 1000 + math.floor(tonumber(decimals) * 10 ^ (3 - #decimals) + 0.5)
end

local function ParseGS(text)
	local gs
	-- 5.8k / 5,8k / 5.62k / 5.8 k
	local a, b = text:match("(%d)[%.,](%d+)%s*k")
	if a then gs = Thousands(a, b) end
	-- 5k8
	if not gs then
		a, b = text:match("(%d)k(%d)")
		if a then gs = tonumber(a) * 1000 + tonumber(b) * 100 end
	end
	-- 5800
	if not gs then
		for num in text:gmatch("%d+") do
			local n = tonumber(num)
			if #num == 4 and n >= 1000 and n <= 7500 then gs = n; break end
		end
	end
	-- 5k
	if not gs then
		a = text:match("(%d)%s*k")
		if a then gs = tonumber(a) * 1000 end
	end
	-- "gs 5.8" / "5,8" / "5,62"
	if not gs then
		a, b = text:match("(%d)[%.,](%d+)")
		if a and tonumber(a) >= 1 and tonumber(a) <= 7 then gs = Thousands(a, b) end
	end
	return gs
end
RF.ParseGS = ParseGS

-- Edit distance, stops early once it exceeds max.
local function Distance(a, b, max)
	if math.abs(#a - #b) > max then return max + 1 end
	local prev = {}
	for j = 0, #b do prev[j] = j end
	for i = 1, #a do
		local cur, rowMin = { [0] = i }, i
		for j = 1, #b do
			local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
			cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
			if cur[j] < rowMin then rowMin = cur[j] end
		end
		if rowMin > max then return max + 1 end
		prev = cur
	end
	return prev[#b]
end

-- Long table words used for typo matching ("shamman", "paladn", "warlok" ...).
local FUZZY = {}
for _, tbl in ipairs({ CLASS_WORDS, SPEC_WORDS, ROLE_WORDS }) do
	for word in pairs(tbl) do
		if #word >= 5 then FUZZY[#FUZZY + 1] = word end
	end
end
table.sort(FUZZY)

local function RoleFits(specRole, role)
	return specRole == role or (role == "dps" and (specRole == "mdps" or specRole == "rdps"))
end

-- Returns gs, specKey, class, role, unknownWords
-- Any of them can be nil; unknownWords lists words that matched nothing.
-- classHint: class named elsewhere in the whisper (the other half of "enh 6,3 / resto 5,7")
function RF.ParseWhisper(msg, classHint)
	local text = (msg or ""):lower()
	-- WoW links / raid icons would confuse the tokenizer
	text = text:gsub("|c%x+", ""):gsub("|h.-|h", " "):gsub("|r", ""):gsub("{.-}", " ")
	local gs = ParseGS(text)
	local aliases = RF.db and RF.db.aliases

	local tokens = {}
	for w in text:gmatch("%a+") do tokens[#tokens + 1] = w end
	local words, source = {}, {}
	for i, w in ipairs(tokens) do words[#words + 1] = w; source[#words] = { i } end
	-- joined pairs: "mm hunt" -> "mmhunt", "prot warr" -> "protwarr"
	for i = 1, #tokens - 1 do
		words[#words + 1] = tokens[i] .. tokens[i + 1]
		source[#words] = { i, i + 1 }
	end

	local known = {}
	local class, spec, role
	local function take(kind, value, idx)
		if kind == "spec" then spec = spec or value
		elseif kind == "class" then class = class or value
		elseif kind == "role" then role = role or value end
		for _, t in ipairs(source[idx]) do known[t] = true end
	end
	local function lookup(w, idx)
		local a = aliases and aliases[w]
		if a then
			if RF.SPECS[a] then take("spec", a, idx)
			elseif RF.CLASS_NAMES[a] then take("class", a, idx)
			else take("role", a, idx) end
			return true
		end
		local hit = false
		if SPEC_WORDS[w] then take("spec", SPEC_WORDS[w], idx); hit = true end
		if CLASS_WORDS[w] then take("class", CLASS_WORDS[w], idx); hit = true end
		if ROLE_WORDS[w] then take("role", ROLE_WORDS[w], idx); hit = true end
		if CLASS_SPEC_WORDS[w] then for _, t in ipairs(source[idx]) do known[t] = true end; hit = true end
		return hit
	end
	for idx, w in ipairs(words) do lookup(w, idx) end

	-- plurals / trailing letters: "shamans", "paladins", "pallys"
	if not class then
		for i, w in ipairs(tokens) do
			for word, c in pairs(CLASS_WORDS) do
				if #word >= 4 and w:sub(1, #word) == word then take("class", c, i); break end
			end
			if class then break end
		end
	end

	-- typos: one wrong/missing/extra letter in a long word
	for i, w in ipairs(tokens) do
		if not known[i] and #w >= 5 and not IGNORE[w] then
			for _, word in ipairs(FUZZY) do
				if Distance(w, word, 1) <= 1 then
					lookup(word, i)
					break
				end
			end
		end
	end

	if not class and not spec and classHint then class = classHint end

	-- class-dependent spec words ("resto" + druid)
	local classSpec
	if class then
		for _, w in ipairs(words) do
			local map = CLASS_SPEC_WORDS[w]
			if map and map[class] then classSpec = map[class]; break end
		end
	end

	-- a spec word that contradicts the stated class loses (e.g. "shadow" for a DK)
	if spec and class and RF.SPECS[spec].class ~= class then spec = nil end
	spec = spec or classSpec
	if not class and spec then class = RF.SPECS[spec].class end

	if class then
		-- role words settle specs that share a talent tree
		if class == "DRUID" and role == "tank" and (spec == "DRUID_CAT" or not spec) then spec = "DRUID_BEAR" end
		if class == "DEATHKNIGHT" and role == "tank" and (spec == "DK_DPS" or not spec) then spec = "DK_TANK" end
		if not spec then
			local fits = {}
			for _, key in ipairs(RF.CLASS_SPECS[class]) do
				if not role or RoleFits(RF.SPECS[key].role, role) then fits[#fits + 1] = key end
			end
			if #fits == 1 then
				spec = fits[1]
			elseif DEFAULT_DPS[class] and (role == "dps" or RF.SPECS[DEFAULT_DPS[class]].role == role
				or (not role and ONLY_DPS[class])) then
				spec = DEFAULT_DPS[class]
			end
			-- otherwise ambiguous (priest healer, shaman dps, druid): the raid composition picks
		end
	end

	local unknown = {}
	for i, w in ipairs(tokens) do
		if not known[i] and #w >= 2 and not IGNORE[w] then unknown[#unknown + 1] = w end
	end
	return gs, spec, class, role, unknown
end

-- Splits a whisper that offers more than one spec: "enh 6,3/ resto 5,7", "resto 5.7 or enh 6.3",
-- "ret 5.8k prot 5.2k". Returns the parts as text.
local function SplitSpecs(text)
	local t = text:gsub("%s+or%s+", "/")
	t = t:gsub("%s+and%s+", "/")
	t = t:gsub("%s+os%s+", "/")
	t = t:gsub("offspec", "/")
	t = t:gsub("[\\;&]", "/")
	local parts = {}
	for part in t:gmatch("[^/]+") do
		if part:find("%a") then parts[#parts + 1] = part end
	end
	if #parts < 2 then
		-- no separator: split before a second spec word that comes after a GS number
		local aliases = RF.db and RF.db.aliases
		local starts = {}
		for pos, word in text:gmatch("()(%a+)") do
			if SPEC_WORDS[word] or CLASS_SPEC_WORDS[word] or (aliases and aliases[word] and RF.SPECS[aliases[word]]) then
				starts[#starts + 1] = pos
			end
		end
		if #starts >= 2 and text:sub(1, starts[2] - 1):find("%d") then
			parts = { text:sub(1, starts[2] - 1), text:sub(starts[2]) }
		else
			parts = { text }
		end
	end
	return parts
end

-- Every spec a player offers, in the order they wrote them.
-- Returns options = { { gs=, spec=, class=, role= }, ... } (at least one), unknownWords
function RF.ParseOptions(msg)
	local gsAll, specAll, classAll, roleAll, unknown = RF.ParseWhisper(msg)
	local text = (msg or ""):lower()
	text = text:gsub("|c%x+", ""):gsub("|h.-|h", " "):gsub("|r", ""):gsub("{.-}", " ")
	local single = { { gs = gsAll, spec = specAll, class = classAll, role = roleAll } }
	local parts = SplitSpecs(text)
	if #parts < 2 then return single, unknown end

	local parsed, classHint = {}, nil
	for i, part in ipairs(parts) do
		local gs, spec, class, role = RF.ParseWhisper(part)
		parsed[i] = { gs = gs, spec = spec, class = class, role = role, text = part }
		classHint = classHint or class
	end
	local options, seen = {}, {}
	for _, o in ipairs(parsed) do
		if not o.class and classHint then
			-- "resto" in "enh 6,3 / resto 5,7" belongs to the shaman
			local _, spec, class, role = RF.ParseWhisper(o.text, classHint)
			o.spec, o.class, o.role = spec, class, role or o.role
		end
		o.gs = o.gs or gsAll
		local key = o.spec or ((o.class or "") .. ":" .. (o.role or ""))
		if (o.spec or o.class or o.role) and not seen[key] then
			seen[key] = true
			options[#options + 1] = { gs = o.gs, spec = o.spec, class = o.class, role = o.role }
		end
	end
	if #options == 0 then return single, unknown end
	return options, unknown
end

-- Target for /rf alias: a spec key, class key, role, or any text the parser understands.
-- Returns kind ("spec" | "class" | "role"), value
function RF.ResolveAliasTarget(text)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then return nil end
	local up = text:upper()
	if RF.SPECS[up] then return "spec", up end
	if RF.CLASS_NAMES[up] then return "class", up end
	local low = text:lower()
	if low == "tank" or low == "heal" or low == "dps" or low == "mdps" or low == "rdps" then return "role", low end
	local _, spec, class, role = RF.ParseWhisper(text)
	if spec then return "spec", spec end
	if class then return "class", class end
	if role then return "role", role end
end
