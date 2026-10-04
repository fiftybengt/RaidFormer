-- Class/spec data, roles, raid buffs and inspect helpers. Whisper parsing lives in Parse.lua.
local _, RF = ...

RF.ROLES = { "tank", "heal", "mdps", "rdps" }
RF.ROLE_NAMES = { tank = "Tank", heal = "Healer", mdps = "Melee DPS", rdps = "Ranged DPS" }
RF.ROLE_SHORT = { tank = "tank", heal = "heal", mdps = "mdps", rdps = "rdps" }

RF.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
RF.CLASS_NAMES = {
	WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	DEATHKNIGHT = "Death Knight", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
-- Abbreviations used in announcements, whispers and the roster.
RF.CLASS_SHORT = {
	WARRIOR = "warr", PALADIN = "pal", HUNTER = "hunt", ROGUE = "rog", PRIEST = "priest",
	DEATHKNIGHT = "dk", SHAMAN = "sham", MAGE = "mage", WARLOCK = "lock", DRUID = "dru",
}

-- tab = primary talent tab used to verify on inspect (nil = can't tell from talents)
RF.SPECS = {
	WARRIOR_ARMS    = { class = "WARRIOR", tab = 1, name = "Arms",          short = "arms",      role = "mdps" },
	WARRIOR_FURY    = { class = "WARRIOR", tab = 2, name = "Fury",          short = "fury",      role = "mdps" },
	WARRIOR_PROT    = { class = "WARRIOR", tab = 3, name = "Protection",    short = "pwarr",     role = "tank" },
	PALADIN_HOLY    = { class = "PALADIN", tab = 1, name = "Holy",          short = "hpal",      role = "heal" },
	PALADIN_PROT    = { class = "PALADIN", tab = 2, name = "Protection",    short = "ppal",      role = "tank" },
	PALADIN_RET     = { class = "PALADIN", tab = 3, name = "Retribution",   short = "ret",       role = "mdps", buffs = { REPLENISHMENT = true } },
	HUNTER_BM       = { class = "HUNTER",  tab = 1, name = "Beast Mastery", short = "bm hunt",   role = "rdps" },
	HUNTER_MM       = { class = "HUNTER",  tab = 2, name = "Marksmanship",  short = "mm hunt",   role = "rdps" },
	HUNTER_SV       = { class = "HUNTER",  tab = 3, name = "Survival",      short = "sv hunt",   role = "rdps", buffs = { REPLENISHMENT = true } },
	ROGUE_ASSA      = { class = "ROGUE",   tab = 1, name = "Assassination", short = "mut rog",   role = "mdps" },
	ROGUE_COMBAT    = { class = "ROGUE",   tab = 2, name = "Combat",        short = "combat rog", role = "mdps" },
	ROGUE_SUB       = { class = "ROGUE",   tab = 3, name = "Subtlety",      short = "sub rog",   role = "mdps" },
	PRIEST_DISC     = { class = "PRIEST",  tab = 1, name = "Discipline",    short = "disc",      role = "heal" },
	PRIEST_HOLY     = { class = "PRIEST",  tab = 2, name = "Holy",          short = "hpriest",   role = "heal" },
	PRIEST_SHADOW   = { class = "PRIEST",  tab = 3, name = "Shadow",        short = "SPriest",   role = "rdps", buffs = { REPLENISHMENT = true } },
	DK_TANK         = { class = "DEATHKNIGHT", tab = nil, name = "Tank",    short = "tank dk",   role = "tank" },
	DK_DPS          = { class = "DEATHKNIGHT", tab = nil, name = "DPS",     short = "dps dk",    role = "mdps" },
	SHAMAN_ELE      = { class = "SHAMAN",  tab = 1, name = "Elemental",     short = "ele",       role = "rdps" },
	SHAMAN_ENH      = { class = "SHAMAN",  tab = 2, name = "Enhancement",   short = "enh",       role = "mdps" },
	SHAMAN_RESTO    = { class = "SHAMAN",  tab = 3, name = "Restoration",   short = "rsham",     role = "heal" },
	MAGE_ARCANE     = { class = "MAGE",    tab = 1, name = "Arcane",        short = "amage",     role = "rdps" },
	MAGE_FIRE       = { class = "MAGE",    tab = 2, name = "Fire",          short = "fmage",     role = "rdps" },
	MAGE_FROST      = { class = "MAGE",    tab = 3, name = "Frost",         short = "frmage",    role = "rdps", buffs = { REPLENISHMENT = true } },
	WARLOCK_AFFLI   = { class = "WARLOCK", tab = 1, name = "Affliction",    short = "affli",     role = "rdps" },
	WARLOCK_DEMO    = { class = "WARLOCK", tab = 2, name = "Demonology",    short = "demo",      role = "rdps" },
	WARLOCK_DESTRO  = { class = "WARLOCK", tab = 3, name = "Destruction",   short = "destro",    role = "rdps", buffs = { REPLENISHMENT = true } },
	DRUID_BALANCE   = { class = "DRUID",   tab = 1, name = "Balance",       short = "boomy",     role = "rdps" },
	DRUID_BEAR      = { class = "DRUID",   tab = 2, name = "Feral (Bear)",  short = "bear",      role = "tank" },
	DRUID_CAT       = { class = "DRUID",   tab = 2, name = "Feral (Cat)",   short = "cat",       role = "mdps" },
	DRUID_RESTO     = { class = "DRUID",   tab = 3, name = "Restoration",   short = "rdru",      role = "heal" },
}

-- Ordered spec list per class, for dropdowns.
RF.CLASS_SPECS = {}
do
	local order = {
		"WARRIOR_ARMS", "WARRIOR_FURY", "WARRIOR_PROT", "PALADIN_HOLY", "PALADIN_PROT", "PALADIN_RET",
		"HUNTER_BM", "HUNTER_MM", "HUNTER_SV", "ROGUE_ASSA", "ROGUE_COMBAT", "ROGUE_SUB",
		"PRIEST_DISC", "PRIEST_HOLY", "PRIEST_SHADOW", "DK_TANK", "DK_DPS",
		"SHAMAN_ELE", "SHAMAN_ENH", "SHAMAN_RESTO", "MAGE_ARCANE", "MAGE_FIRE", "MAGE_FROST",
		"WARLOCK_AFFLI", "WARLOCK_DEMO", "WARLOCK_DESTRO", "DRUID_BALANCE", "DRUID_BEAR", "DRUID_CAT", "DRUID_RESTO",
	}
	for _, key in ipairs(order) do
		local class = RF.SPECS[key].class
		RF.CLASS_SPECS[class] = RF.CLASS_SPECS[class] or {}
		table.insert(RF.CLASS_SPECS[class], key)
	end
end

-- Raid utility a class brings regardless of spec.
local CLASS_BUFFS = {
	SHAMAN = { BLOODLUST = true },
	DRUID = { BATTLE_REZ = true, MARK_OF_WILD = true },
	DEATHKNIGHT = { BATTLE_REZ = true },
	PALADIN = { BLESSINGS = true },
	PRIEST = { FORTITUDE = true },
	MAGE = { ARCANE_INT = true },
	ROGUE = { TRICKS = true },
	HUNTER = { MISDIRECTION = true },
	WARLOCK = { SOULSTONE = true },
}

RF.BUFFS = { "BLOODLUST", "REPLENISHMENT", "BATTLE_REZ", "BLESSINGS", "FORTITUDE", "MARK_OF_WILD", "ARCANE_INT", "TRICKS", "MISDIRECTION", "SOULSTONE" }
RF.BUFF_NAMES = {
	BLOODLUST = "Bloodlust/Heroism", REPLENISHMENT = "Replenishment", BATTLE_REZ = "Battle Rez",
	BLESSINGS = "Blessings", FORTITUDE = "Fortitude", MARK_OF_WILD = "Mark of the Wild",
	ARCANE_INT = "Arcane Intellect", TRICKS = "Tricks of the Trade", MISDIRECTION = "Misdirection",
	SOULSTONE = "Soulstone",
}
RF.BUFF_SHORT = {
	BLOODLUST = "BL", REPLENISHMENT = "replenish", BATTLE_REZ = "brez", BLESSINGS = "pala buffs",
	FORTITUDE = "fort", MARK_OF_WILD = "motw", ARCANE_INT = "int", TRICKS = "tricks",
	MISDIRECTION = "MD", SOULSTONE = "SS",
}

function RF.SpecHasBuff(specKey, buff)
	local spec = RF.SPECS[specKey]
	if not spec then return false end
	if spec.buffs and spec.buffs[buff] then return true end
	local cb = CLASS_BUFFS[spec.class]
	return cb and cb[buff] or false
end

---------------------------------------------------------------------------
-- Inspect helpers
---------------------------------------------------------------------------

-- Primary talent tab from inspected talents (call after INSPECT_TALENT_READY).
function RF.GetInspectedPrimaryTab()
	local best, bestPoints = nil, -1
	for tab = 1, 3 do
		local _, _, points = GetTalentTabInfo(tab, true)
		points = points or 0
		if points > bestPoints then best, bestPoints = tab, points end
	end
	if bestPoints <= 0 then return nil end
	return best
end

-- Spec for a class given its primary tab.
function RF.SpecFromTab(class, tab)
	for _, key in ipairs(RF.CLASS_SPECS[class] or {}) do
		if RF.SPECS[key].tab == tab then return key end
	end
	return RF.CLASS_SPECS[class] and RF.CLASS_SPECS[class][1]
end

-- Real spec after an inspect. The talents decide; the whispered/guessed spec (hint) only
-- settles what talents can't show: bear vs cat and death knight tank vs dps.
function RF.SpecFromInspect(class, tab, hint)
	if not class or not RF.CLASS_SPECS[class] then return nil end
	local hinted = hint and RF.SPECS[hint] and RF.SPECS[hint].class == class and hint or nil
	if class == "DEATHKNIGHT" then return hinted or "DK_DPS" end
	if not tab then return hinted or RF.CLASS_SPECS[class][1] end
	if class == "DRUID" and tab == 2 then
		return (hinted and RF.SPECS[hinted].role == "tank") and "DRUID_BEAR" or "DRUID_CAT"
	end
	return RF.SpecFromTab(class, tab)
end
