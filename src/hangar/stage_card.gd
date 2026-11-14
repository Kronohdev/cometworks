class_name StageCard
extends PanelContainer
## One stage in the hangar's stage list (layout lives in scenes/ui/stage_card.tscn).
## Compact by default (stage, mass, Δv, TWR chip); click it, or use the panel's
## "detailed" toggle, to show SL/vac Δv, burn time and the TWR bar.

signal detail_toggled(on: bool)

## Shows the detail rows (SL/vac Δv, burn time, TWR bar).
@export var detailed := false:
	set(v):
		detailed = v
		if is_node_ready():
			_detail.visible = v

@onready var _swatch: ColorRect = %Swatch
@onready var _title: Label = %Title
@onready var _mass: Label = %Mass
@onready var _dv: Label = %Dv
@onready var _twr: MarginChip = %TwrChip
@onready var _detail: Control = %Detail
@onready var _dv_detail: Label = %DvDetail
@onready var _burn: Label = %Burn
@onready var _twr_bar: ProgressBar = %TwrBar


func _ready() -> void:
	_detail.visible = detailed


## st: one entry of VesselMath.analyze()["stages"]; first: true for stage 1 (sea-level TWR);
## color: the stage's data colour (same as its segment in the Δv bar).
func setup(st: Dictionary, first: bool, color: Color = MarginPalette.DATA_1) -> void:
	var twr: float = st["twr_sl"] if first else st["twr_vac"]
	_swatch.color = color
	_title.text = tr("UI_STAGE_N") % st["stage"]
	_mass.text = "%s t" % HangarUI.numk(st["m0_kg"] / 1000.0, 1)
	_dv.text = "%s m/s" % HangarUI.numk(st["dv_vac"])
	var tone := MarginChip.Tone.OK
	if first and twr < 1.0:
		tone = MarginChip.Tone.DANGER
	elif first and twr < 1.2:
		tone = MarginChip.Tone.WARN
	_twr.set_chip("%s %s" % [tr("STAT_TWR"), HangarUI.num(twr, 2)], tone,
		tr("UI_TWR_SL_TIP") if first else tr("UI_TWR_VAC_TIP"))
	_dv_detail.text = "%s %s · %s %s m/s" % [tr("STAT_SL"), HangarUI.numk(st["dv_sl"]), tr("STAT_VAC"), HangarUI.numk(st["dv_vac"])]
	_burn.text = "%s %s s" % [tr("STAT_BURN"), HangarUI.numk(st["burn_s"])]
	_twr_bar.value = minf(twr, _twr_bar.max_value)
	var fill := _twr_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	fill.bg_color = MarginChip.tone_color(tone)
	_twr_bar.add_theme_stylebox_override("fill", fill)


func set_detailed(on: bool) -> void:
	detailed = on
	_detail.visible = on


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		set_detailed(not detailed)
		detail_toggled.emit(detailed)
		accept_event()
