-- Look of the UI: flat dark theme, fonts and the role/class icons (all textures ship with 3.3.5).
local _, RF = ...

local Skin = {}
RF.Skin = Skin

local WHITE = "Interface\\Buttons\\WHITE8X8"
Skin.WHITE = WHITE

-- colour tokens { r, g, b, a }
local C = {
	bg      = { 0.06, 0.06, 0.08, 0.94 },
	panel   = { 0.10, 0.10, 0.13, 0.95 },
	input   = { 0.04, 0.04, 0.05, 0.90 },
	button  = { 0.15, 0.15, 0.19, 1 },
	hover   = { 0.21, 0.21, 0.27, 1 },
	active  = { 0.16, 0.36, 0.52, 1 },
	border  = { 0, 0, 0, 1 },
	line    = { 1, 1, 1, 0.08 },
	text    = { 0.92, 0.92, 0.92, 1 },
	muted   = { 0.58, 0.58, 0.64, 1 },
	accent  = { 0.25, 0.72, 1.00, 1 },
	good    = { 0.30, 0.82, 0.40, 1 },
	warn    = { 1.00, 0.76, 0.22, 1 },
	bad     = { 1.00, 0.32, 0.32, 1 },
	goodBg  = { 0.14, 0.34, 0.18, 1 },
	badBg   = { 0.42, 0.12, 0.12, 1 },
	warnBg  = { 0.30, 0.22, 0.05, 0.95 },
}
Skin.C = C

-- "|cffrrggbb" for a colour token
function Skin.Hex(color)
	return string.format("|cff%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

-- Flat panel with a 1px border.
function Skin.Backdrop(frame, color, border)
	frame:SetBackdrop({
		bgFile = WHITE, edgeFile = WHITE, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	local c, b = color or C.panel, border or C.border
	frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 1)
	frame:SetBackdropBorderColor(b[1], b[2], b[3], b[4] or 1)
end

-- Fonts: one family, a few sizes.
local FONT = "Fonts\\FRIZQT__.TTF"
local function MakeFont(name, size, color)
	local f = CreateFont(name)
	f:SetFont(FONT, size, "")
	f:SetShadowColor(0, 0, 0, 1)
	f:SetShadowOffset(1, -1)
	f:SetTextColor(color[1], color[2], color[3])
	return f
end
Skin.Font = MakeFont("RaidFormerFont", 11, C.text)
Skin.FontSmall = MakeFont("RaidFormerFontSmall", 10, C.text)
Skin.FontMuted = MakeFont("RaidFormerFontMuted", 10, C.muted)
Skin.FontHeader = MakeFont("RaidFormerFontHeader", 11, C.accent)
Skin.FontTitle = MakeFont("RaidFormerFontTitle", 14, C.text)
Skin.FontBig = MakeFont("RaidFormerFontBig", 12, C.text)
Skin.FontDisabled = MakeFont("RaidFormerFontDisabled", 11, { 0.42, 0.42, 0.46 })

-- Role icons from the 3.3 Dungeon Finder (small portrait set): tank / healer / damage.
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = {
	tank = { 0, 19 / 64, 22 / 64, 41 / 64 },
	heal = { 20 / 64, 39 / 64, 1 / 64, 20 / 64 },
	dps  = { 20 / 64, 39 / 64, 22 / 64, 41 / 64 },
}
function Skin.SetRoleIcon(tex, role)
	local key = (role == "tank" or role == "heal") and role or "dps"
	tex:SetTexture(ROLE_TEXTURE)
	tex:SetTexCoord(ROLE_COORDS[key][1], ROLE_COORDS[key][2], ROLE_COORDS[key][3], ROLE_COORDS[key][4])
end

-- Class icons from character creation (same coords as FrameXML's CLASS_ICON_TCOORDS).
local CLASS_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CLASS_COORDS = {
	WARRIOR = { 0, 0.25, 0, 0.25 },          MAGE = { 0.25, 0.49609375, 0, 0.25 },
	ROGUE = { 0.49609375, 0.7421875, 0, 0.25 }, DRUID = { 0.7421875, 0.98828125, 0, 0.25 },
	HUNTER = { 0, 0.25, 0.25, 0.5 },         SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
	PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
	PALADIN = { 0, 0.25, 0.5, 0.75 },        DEATHKNIGHT = { 0.25, 0.49609375, 0.5, 0.75 },
}
function Skin.SetClassIcon(tex, class)
	local c = class and CLASS_COORDS[class]
	if not c then tex:Hide() return end
	tex:SetTexture(CLASS_TEXTURE)
	tex:SetTexCoord(c[1], c[2], c[3], c[4])
	tex:Show()
end
