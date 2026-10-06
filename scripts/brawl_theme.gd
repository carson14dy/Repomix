class_name BrawlTheme
extends RefCounted
## BrawlCrypt palette and the two colour rules shared by HUD, VFX and stage art.
## Bone whites over teal-grey shadows (the Wyrm's Ossuary), cyan for Kage, crimson for Ignis.

const P1_COLOR := Color("#38bdf8")
const P2_COLOR := Color("#ef4444")
const BONE := Color("#dfe6e9")
const BONE_SHADOW := Color("#93a9b3")
const BONE_DARK := Color("#5f7681")
const OUTLINE := Color("#1b2a33")
const MIST := Color("#4f7f8c")
const SLATE := Color("#14202a")
const PERCENT_WHITE := Color("#f1f5f9")
const PERCENT_YELLOW := Color("#facc15")
const PERCENT_ORANGE := Color("#f97316")
const PERCENT_RED := Color("#f43f5e")


static func player_color(index: int) -> Color:
	return P2_COLOR if index == 2 else P1_COLOR


static func player_name(index: int) -> String:
	return "Ignis" if index == 2 else "Kage"


## Damage read-out colour: white < 35, yellow < 75, orange < 120, red above.
static func percent_color(percentage: float) -> Color:
	if percentage < 35.0:
		return PERCENT_WHITE
	if percentage < 75.0:
		return PERCENT_YELLOW
	if percentage < 120.0:
		return PERCENT_ORANGE
	return PERCENT_RED
