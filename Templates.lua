-- Raid list and default formations.
local _, RF = ...

RF.RAIDS = {
	{ key = "TOC",    name = "Trial of the Crusader", tag = "TOC",  sizes = { 10, 25 }, heroic = true,  minGS = { [10] = 4500, [25] = 5000 }, minGSH = { [10] = 5200, [25] = 5500 } },
	{ key = "ICC",    name = "Icecrown Citadel",      tag = "ICC",  sizes = { 10, 25 }, heroic = true,  minGS = { [10] = 5200, [25] = 5400 }, minGSH = { [10] = 5800, [25] = 6000 } },
	{ key = "RS",     name = "Ruby Sanctum",          tag = "RS",   sizes = { 10, 25 }, heroic = true,  minGS = { [10] = 5500, [25] = 5700 }, minGSH = { [10] = 6000, [25] = 6200 } },
	{ key = "VOA",    name = "Vault of Archavon",     tag = "VOA",  sizes = { 10, 25 }, heroic = false, minGS = { [10] = 4000, [25] = 4500 } },
	{ key = "ULDUAR", name = "Ulduar",                tag = "ULDU", sizes = { 10, 25 }, heroic = false, minGS = { [10] = 4000, [25] = 4500 } },
	{ key = "NAXX",   name = "Naxxramas",             tag = "NAXX", sizes = { 10, 25 }, heroic = false, minGS = { [10] = 3500, [25] = 4000 } },
	{ key = "ONY",    name = "Onyxia's Lair",         tag = "ONY",  sizes = { 10, 25 }, heroic = false, minGS = { [10] = 4000, [25] = 4500 } },
	{ key = "OS",     name = "Obsidian Sanctum",      tag = "OS",   sizes = { 10, 25 }, heroic = false, minGS = { [10] = 3500, [25] = 4000 } },
	{ key = "EOE",    name = "Eye of Eternity",       tag = "EOE",  sizes = { 10, 25 }, heroic = false, minGS = { [10] = 3500, [25] = 4000 } },
	{ key = "CUSTOM", name = "Custom",                tag = "RAID", sizes = { 10, 25 }, heroic = true,  custom = true, minGS = { [10] = 4000, [25] = 4500 } },
}

RF.RAID_BY_KEY = {}
for _, r in ipairs(RF.RAIDS) do RF.RAID_BY_KEY[r.key] = r end

-- Quick-add reserve buttons on the Setup tab.
RF.EXTRA_PRESETS = { "B+O+P RES", "BOE RES", "BOE+P RES", "Link best achiev" }

local function round(x) return math.floor(x + 0.5) end

-- Returns roles, needs, buffs, caps for a raid/size/difficulty.
function RF.DefaultFormation(raidKey, size, heroic)
	size = math.max(2, math.min(40, size or 25))
	local tank, heal
	if size <= 5 then tank, heal = 1, 1
	elseif size <= 15 then tank, heal = 2, (size >= 10) and 3 or 2
	else tank, heal = 2, round(size * 0.24) end

	-- raid specific tweaks
	if raidKey == "ICC" and size >= 25 then heal = heroic and 7 or 6 end
	if raidKey == "ICC" and size == 10 and heroic then heal = 3 end
	if raidKey == "TOC" and size >= 25 and heroic then heal = 7 end
	if raidKey == "RS" and size >= 25 then tank = 3 end
	if raidKey == "ONY" and size == 10 then tank = 1 end
	if raidKey == "VOA" and size >= 25 then heal = 5 end

	local dps = size - tank - heal
	local mdps = math.floor(dps / 2)
	local rdps = dps - mdps

	-- no buff/utility requirements any more; Bloodlust/Heroism comes from a shaman need
	local buffs = {}
	local needs = { { class = "SHAMAN", count = 1 } }
	local caps = {}
	if size >= 20 then
		table.insert(caps, { class = "DEATHKNIGHT", max = 5 })
	end
	return { tank = tank, heal = heal, mdps = mdps, rdps = rdps }, needs, buffs, caps
end

function RF.DefaultMinGS(raidKey, size, heroic)
	local r = RF.RAID_BY_KEY[raidKey]
	if not r then return 4500 end
	local t = (heroic and r.minGSH) or r.minGS
	return t[size] or t[25] or 4500
end

-- "TOC25N", "ICC10H", "NAXX25"
function RF.RaidTag(raidKey, size, heroic, customName)
	local r = RF.RAID_BY_KEY[raidKey]
	local tag = (r and r.custom and customName and customName ~= "") and customName or (r and r.tag or "RAID")
	tag = tag .. tostring(size)
	if r and r.heroic then tag = tag .. (heroic and "H" or "N") end
	return tag
end
