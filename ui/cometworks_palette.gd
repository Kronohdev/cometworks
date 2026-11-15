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


# ------------------------------------------------------------ colour-blind friendly mode
## On (CwAccess, the Accessibility options): agency and briefing-kind colours come from the
## Okabe-Ito palette (told apart under protan, deutan and tritan vision) and every marker and
## swatch of one of those colours draws its shape cue on top, so no two are told apart by hue
## alone. A shape belongs to a colour, so the same cue means the same colour everywhere.
static var colorblind := false

enum Cue { NONE = -1, CIRCLE, TRIANGLE, SQUARE, DIAMOND, STAR, CROSS }

## Okabe-Ito colours (html) -> their shape cue
const CB_CUES := {"e69f00": Cue.STAR, "0072b2": Cue.TRIANGLE, "56b4e9": Cue.SQUARE, "cc79a7": Cue.DIAMOND,
	"009e73": Cue.CROSS, "d55e00": Cue.CIRCLE}
## agencies in colour-blind mode (the player, then the rivals of data/tycoon/rules.json)
const CB_AGENCY := {"player": Color("#e69f00"), "aurora": Color("#0072b2"), "nimbo": Color("#56b4e9"),
	"quietude": Color("#cc79a7")}
## agencies the table does not know take these in turn
const CB_SPARE: Array[Color] = [Color("#009e73"), Color("#d55e00")]
## briefing kinds in colour-blind mode (BriefingsScreen.KIND_COLORS)
const CB_KIND := {"science": Color("#56b4e9"), "contract": Color("#e69f00"), "space_apps": Color("#009e73"),
	"dream": Color("#cc79a7"), "race": Color("#d55e00")}


## An agency's colour: `normal` (its own) or, in colour-blind mode, its Okabe-Ito colour.
static func agency(id: String, normal: Color) -> Color:
	if not colorblind:
		return normal
	if CB_AGENCY.has(id):
		return CB_AGENCY[id]
	return CB_SPARE[absi(hash(id)) % CB_SPARE.size()]


## A briefing kind's colour: `normal` or, in colour-blind mode, its Okabe-Ito colour.
static func kind(id: String, normal: Color) -> Color:
	if colorblind and CB_KIND.has(id):
		return CB_KIND[id]
	return normal


## The shape cue of a colour in colour-blind mode (Cue.NONE when off or not a cue colour).
static func cue_of(c: Color) -> int:
	if not colorblind or c.a <= 0.0:
		return Cue.NONE
	return int(CB_CUES.get(c.to_html(false).to_lower(), Cue.NONE))


## Draws shape `cue` centred at `at` with radius `r` on `ci`, in ink or cream (whichever reads
## on `under`).
static func draw_cue(ci: CanvasItem, cue: int, at: Vector2, r: float, under: Color) -> void:
	if cue == Cue.NONE or r < 1.5:
		return
	var col := INK if under.get_luminance() > 0.45 else CREAM
	match cue:
		Cue.CIRCLE:
			ci.draw_circle(at, r * 0.8, col)
		Cue.SQUARE:
			ci.draw_rect(Rect2(at - Vector2.ONE * r * 0.72, Vector2.ONE * r * 1.44), col)
		Cue.CROSS:
			var t := r * 0.36
			ci.draw_rect(Rect2(at - Vector2(r, t), Vector2(r * 2.0, t * 2.0)), col)
			ci.draw_rect(Rect2(at - Vector2(t, r), Vector2(t * 2.0, r * 2.0)), col)
		_:
			ci.draw_colored_polygon(cue_points(cue, at, r), col)


## The outline of a polygon cue (triangle, diamond, star).
static func cue_points(cue: int, at: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match cue:
		Cue.TRIANGLE:
			for i in 3:
				var a := -PI / 2.0 + TAU * i / 3.0
				pts.append(at + Vector2(cos(a), sin(a)) * r * 1.05 + Vector2(0, r * 0.15))
		Cue.DIAMOND:
			pts = PackedVector2Array([at + Vector2(0, -r), at + Vector2(r * 0.8, 0), at + Vector2(0, r), at + Vector2(-r * 0.8, 0)])
		Cue.STAR:
			for i in 10:
				var a := -PI / 2.0 + PI * i / 5.0
				pts.append(at + Vector2(cos(a), sin(a)) * (r * 1.05 if i % 2 == 0 else r * 0.45))
	return pts
