-- Embedded GearScore calculation.
-- Formula and tables taken from GearScoreLite 3x04 by Mirrikat45, renamed into a
-- private namespace so it never clashes with GearScoreLite when both are loaded.
local _, RF = ...

local floor = math.floor

local GS = {}
RF.GS = GS

local ItemTypes = {
	INVTYPE_RELIC          = { SlotMOD = 0.3164, Enchantable = false },
	INVTYPE_TRINKET        = { SlotMOD = 0.5625, Enchantable = false },
	INVTYPE_2HWEAPON       = { SlotMOD = 2.0000, Enchantable = true },
	INVTYPE_WEAPONMAINHAND = { SlotMOD = 1.0000, Enchantable = true },
	INVTYPE_WEAPONOFFHAND  = { SlotMOD = 1.0000, Enchantable = true },
	INVTYPE_RANGED         = { SlotMOD = 0.3164, Enchantable = true },
	INVTYPE_THROWN         = { SlotMOD = 0.3164, Enchantable = false },
	INVTYPE_RANGEDRIGHT    = { SlotMOD = 0.3164, Enchantable = false },
	INVTYPE_SHIELD         = { SlotMOD = 1.0000, Enchantable = true },
	INVTYPE_WEAPON         = { SlotMOD = 1.0000, Enchantable = true },
	INVTYPE_HOLDABLE       = { SlotMOD = 1.0000, Enchantable = false },
	INVTYPE_HEAD           = { SlotMOD = 1.0000, Enchantable = true },
	INVTYPE_NECK           = { SlotMOD = 0.5625, Enchantable = false },
	INVTYPE_SHOULDER       = { SlotMOD = 0.7500, Enchantable = true },
	INVTYPE_CHEST          = { SlotMOD = 1.0000, Enchantable = true },
	INVTYPE_ROBE           = { SlotMOD = 1.0000, Enchantable = true },
	INVTYPE_WAIST          = { SlotMOD = 0.7500, Enchantable = false },
	INVTYPE_LEGS           = { SlotMOD = 1.0000, Enchantable = true },
	INVTYPE_FEET           = { SlotMOD = 0.7500, Enchantable = true },
	INVTYPE_WRIST          = { SlotMOD = 0.5625, Enchantable = true },
	INVTYPE_HAND           = { SlotMOD = 0.7500, Enchantable = true },
	INVTYPE_FINGER         = { SlotMOD = 0.5625, Enchantable = false },
	INVTYPE_CLOAK          = { SlotMOD = 0.5625, Enchantable = true },
	INVTYPE_BODY           = { SlotMOD = 0,      Enchantable = false },
}

local Formula = {
	A = {
		[4] = { A = 91.4500, B = 0.6500 },
		[3] = { A = 81.3750, B = 0.8125 },
		[2] = { A = 73.0000, B = 1.0000 },
	},
	B = {
		[4] = { A = 26.0000, B = 1.2000 },
		[3] = { A = 0.7500,  B = 1.8000 },
		[2] = { A = 8.0000,  B = 2.0000 },
		[1] = { A = 0.0000,  B = 2.2500 },
	},
}

-- Unenchanted enchantable items lose a small percentage, like GearScoreLite.
local function EnchantFactor(link, equipLoc)
	local enchant = link:match("item:%d+:(%d+)")
	if enchant == "0" and ItemTypes[equipLoc] and ItemTypes[equipLoc].Enchantable then
		local percent = floor((-2 * ItemTypes[equipLoc].SlotMOD) * 100) / 100
		return 1 + (percent / 100)
	end
	return 1
end

function GS.GetItemScore(link)
	if not link then return 0, 0 end
	local _, _, rarity, level, _, _, _, _, equipLoc = GetItemInfo(link)
	if not rarity or not level then return 0, 0, true end -- not cached yet
	local qualityScale, scale = 1, 1.8618
	if rarity == 5 then qualityScale = 1.3; rarity = 4
	elseif rarity == 1 or rarity == 0 then qualityScale = 0.005; rarity = 2 end
	if rarity == 7 then rarity = 3; level = 187.05 end
	local slot = ItemTypes[equipLoc]
	if slot and rarity >= 2 and rarity <= 4 then
		local tbl = (level > 120) and Formula.A or Formula.B
		local score = floor(((level - tbl[rarity].A) / tbl[rarity].B) * slot.SlotMOD * scale * qualityScale)
		if level == 187.05 then level = 0 end
		if score < 0 then score = 0 end
		score = floor(score * EnchantFactor(link, equipLoc))
		return score, level
	end
	return -1, level or 0 -- GearScoreLite counts unscorable items as -1
end

-- Returns gearScore, averageItemLevel, incomplete
-- incomplete = true when some equipped items are not in the item cache yet (retry later).
function GS.GetScore(unit)
	if not UnitIsPlayer(unit) then return 0, 0, true end
	local _, class = UnitClass(unit)
	local total, count, levels, incomplete = 0, 0, 0, false
	local titanGrip = 1

	local function info(slot)
		local link = GetInventoryItemLink(unit, slot)
		if not link then return nil end
		local equipLoc = select(9, GetItemInfo(link))
		return link, equipLoc
	end

	local mh, mhLoc = info(16)
	local oh, ohLoc = info(17)
	if (mh and oh and mhLoc == "INVTYPE_2HWEAPON") or (oh and ohLoc == "INVTYPE_2HWEAPON") then
		titanGrip = 0.5
	end

	if oh then
		local s, lvl, missing = GS.GetItemScore(oh)
		incomplete = incomplete or missing
		if class == "HUNTER" then s = s * 0.3164 end
		total = total + s * titanGrip; count = count + 1; levels = levels + (lvl or 0)
	end

	for slot = 1, 18 do
		if slot ~= 4 and slot ~= 17 then
			local link = GetInventoryItemLink(unit, slot)
			if link then
				local s, _, missing = GS.GetItemScore(link)
				incomplete = incomplete or missing
				if slot == 16 and class == "HUNTER" then s = s * 0.3164 end
				if slot == 18 and class == "HUNTER" then s = s * 5.3224 end
				if slot == 16 then s = s * titanGrip end
				-- like GearScoreLite, the average uses the raw item level here
				local lvl = select(4, GetItemInfo(link))
				total = total + s; count = count + 1; levels = levels + (lvl or 0)
			end
		end
	end

	if count == 0 then return 0, 0, true end
	if total <= 0 then return 0, 0, incomplete end
	return floor(total), floor(levels / count), incomplete
end
