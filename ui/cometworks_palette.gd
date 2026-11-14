class_name CwPalette
extends RefCounted
## Cometworks UI tokens ("Aurora de observatório", docs/GDD_Cometworks.pdf section 22).
## Opaque night-instrument panels, engraved hairlines, the comet-tail aurora only as thin
## lines. The four quality bars always use the same colours (ENG, SCI, OPS, REL).

const SPACE := Color("#070b14")
const PANEL := Color("#0e1524")
const PANEL_RAISED := Color("#152036")
const LINE := Color("#24324d")
const HAIRLINE := Color("#3a4d72")
const TEXT := Color("#e9eef7")
const TEXT_DIM := Color("#8c9ab5")
const AURORA_TEAL := Color("#3fe0c5")
const AURORA_VIOLET := Color("#8e7cff")
const IGNITION := Color("#ff8a3d")
const IGNITION_HI := Color("#ffa766")
const COMET_ICE := Color("#bfe8ff")
const WARNING := Color("#ffc547")
const DANGER := Color("#ff5c6c")
const SUCCESS := Color("#5bd68e")
## hard 2 px drop shadow under panels (no blur)
const SHADOW := Color(0.0, 0.0, 0.0, 0.45)

## quality bars
const ENG := IGNITION
const SCI := COMET_ICE
const OPS := AURORA_TEAL
const REL := AURORA_VIOLET
const BARS := {"eng": ENG, "sci": SCI, "ops": OPS, "rel": REL}

## the aurora thread, left to right
const AURORA: Array[Color] = [AURORA_TEAL, AURORA_VIOLET, IGNITION]


## Colour of the aurora thread at x in 0..1.
static func aurora_at(x: float) -> Color:
	x = clampf(x, 0.0, 1.0) * 2.0
	if x < 1.0:
		return AURORA_TEAL.lerp(AURORA_VIOLET, x)
	return AURORA_VIOLET.lerp(IGNITION, x - 1.0)
