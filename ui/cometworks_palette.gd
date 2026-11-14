class_name CwPalette
extends RefCounted
## Cometworks UI tokens: the "Cometling sticker" look. Cream polka-dot paper panels with a navy
## ink outline and a chunky lip, candy keys, Fredoka for titles and numbers, Nunito for text.
## Text is navy ink on paper; the accents are candy colours deep enough to read as text on the
## paper too (bold, >= 3.5:1), and light enough to read as fills. The four quality bars always
## use the same colours (ENG, SCI, OPS, REL). The theme (ui/cometworks_theme.tres) is the source
## of truth for every control; these constants are for scripts that colour data at runtime.

## ink: text and outlines on paper
const INK := Color("#2b2a5c")
const INK_SOFT := Color("#5d5b8c")
## paper: panel faces, wells (insets, tracks) and the line between them
const PAPER := Color("#fff9ef")
const WELL := Color("#f6ead6")
const WELL_LINE := Color("#e6d3b3")
## text on the 3D world or a dark backdrop (with an ink outline)
const CREAM := Color("#fff6e6")
## candy fills (keys, chips, highlights)
const PEACH := Color("#ff9a5c")
const BUTTER := Color("#ffd25c")
const MINT := Color("#6fe0be")
const ICE := Color("#7cc8ff")
const LILAC := Color("#b39cff")
const PINK := Color("#ff8fb8")
const LILAC_LIGHT := Color("#eee8ff")
const MINT_LIGHT := Color("#ddf7ee")

## legacy names, now mapped onto the paper look
const SPACE := Color("#1e1d4a")
const PANEL := PAPER
const PANEL_DEEP := WELL
const PANEL_RAISED := Color("#fffdf8")
const LINE := WELL_LINE
const HAIRLINE := Color("#c9b48f")
const TEXT := INK
const TEXT_DIM := INK_SOFT
## accents: readable as bold text on paper, still candy as fills
const AURORA_TEAL := Color("#0e9077")
const AURORA_GREEN := Color("#1e9a63")
const AURORA_VIOLET := Color("#7652e8")
const AURORA_PINK := Color("#d6407e")
const IGNITION := Color("#e5651c")
const IGNITION_HI := Color("#ff9a5c")
const COMET_ICE := Color("#2f78cc")
const WARNING := Color("#c27400")
const DANGER := Color("#d93a5c")
const SUCCESS := Color("#178a57")
## money: positive balances in green, negative in coral
const MONEY_POS := SUCCESS
const MONEY_NEG := DANGER
const SHADOW := Color(0.1, 0.09, 0.27, 0.32)

## quality bars (candy fills)
const ENG := Color("#ff8f50")
const SCI := Color("#4fa9f0")
const OPS := Color("#2fc4a0")
const REL := Color("#9b7cff")
const BARS := {"eng": ENG, "sci": SCI, "ops": OPS, "rel": REL}

## the comet tail, left to right (mint -> lilac -> peach)
const AURORA: Array[Color] = [MINT, LILAC, PEACH]


## Colour of the comet-tail ribbon at x in 0..1.
static func aurora_at(x: float) -> Color:
	x = clampf(x, 0.0, 1.0) * 2.0
	if x < 1.0:
		return MINT.lerp(LILAC, x)
	return LILAC.lerp(PEACH, x - 1.0)


## A version of `c` dark enough to read as text on the paper panels (agency colours, bar
## colours and other light candy tones get darker, keeping their hue; dark colours pass).
static func ink(c: Color) -> Color:
	var out := c
	for i in 8:
		if out.get_luminance() <= 0.42:
			break
		out = out.darkened(0.14)
	return Color(out, c.a)
