@tool
class_name MarginChip
extends PanelContainer
## Small pill used for stats ("1.2 t", "TWR 2.03") and status badges ("⚠ Low TWR").
## Layout lives in scenes/ui/chip.tscn; the look comes from the Chip* theme variations
## of ui/margin_theme.tres. Scripts only pick the text, tone, icon and tooltip.

enum Tone { NEUTRAL, OK, WARN, DANGER, INFO, ACCENT }

const VARIATIONS := [&"Chip", &"ChipOk", &"ChipWarn", &"ChipDanger", &"ChipInfo", &"ChipAccent"]

@export var icon: Texture2D:
	set(v):
		icon = v
		_apply()
@export var text := "":
	set(v):
		text = v
		_apply()
@export var tone: Tone = Tone.NEUTRAL:
	set(v):
		tone = v
		_apply()


func _ready() -> void:
	_apply()


## One call to fill the chip. `tip` becomes the tooltip (keys are translated by Godot).
func set_chip(chip_text: String, chip_tone: Tone = Tone.NEUTRAL, tip := "", chip_icon: Texture2D = null) -> void:
	text = chip_text
	tone = chip_tone
	if tip != "":
		tooltip_text = tip
	if chip_icon:
		icon = chip_icon


static func tone_color(t: Tone) -> Color:
	match t:
		Tone.OK:
			return MarginPalette.SUCCESS
		Tone.WARN:
			return MarginPalette.WARNING
		Tone.DANGER:
			return MarginPalette.DANGER
		Tone.INFO:
			return MarginPalette.ACCENT_2_HI
		Tone.ACCENT:
			return MarginPalette.ACCENT_HI
	return MarginPalette.TEXT


func _apply() -> void:
	if not is_node_ready():
		return
	theme_type_variation = VARIATIONS[tone]
	var c := tone_color(tone)
	var label := $HBox/Text as Label
	var tex := $HBox/Icon as TextureRect
	label.text = text
	label.add_theme_color_override("font_color", c)
	tex.texture = icon
	tex.visible = icon != null
	tex.modulate = MarginPalette.TEXT_DIM if tone == Tone.NEUTRAL else c
