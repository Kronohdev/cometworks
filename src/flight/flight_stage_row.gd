class_name FlightStageRow
extends PanelContainer
## One sticker of the flight stage stack (layout in scenes/flight/flight_stage_row.tscn):
## a candy stripe in the stage's colour, the stage number, its state (burning / empty /
## waiting), engines (lit / total), core fuel gauge, booster fuel gauge and the Δv left.

@onready var _num: Label = %Num
@onready var _title: Label = %Title
@onready var _state: Label = %State
@onready var _dv: Label = %Dv
@onready var _engines: Label = %Engines
@onready var _fuel: CwSegmentBar = %Fuel
@onready var _booster: CwSegmentBar = %Booster
@onready var _booster_row: Control = %BoosterRow
@onready var _engine_icon: TextureRect = %EngineIcon
@onready var _stripe: ColorRect = %Stripe


## state: "active" / "idle" / "spent"; fuel: FlightVessel.stage_fuel() [core, core0, boost, boost0];
## color: the stage's candy colour (the HUD's stage_colors)
func set_data(stage_no: int, state: String, engines: int, lit: int, fuel: PackedFloat64Array, dv: float,
		color := CwPalette.PEACH) -> void:
	_num.text = str(stage_no)
	_title.text = tr("UI_STAGE_N") % stage_no
	_dv.text = FlightHUD.fmt_speed(dv) if state != "spent" else "—"
	_engines.text = "%d / %d" % [lit, engines] if state == "active" else "× %d" % engines
	var empty := fuel[0] + fuel[2] <= 1.0
	var st := "FL_CW_STAGE_WAITING"
	if state == "active":
		st = "FL_CW_STAGE_BURNING" if lit > 0 else ("FL_CW_STAGE_EMPTY" if empty else "FL_CW_STAGE_READY")
	elif state == "spent":
		st = "FL_CW_STAGE_EMPTY"
	_state.text = tr(st)
	_state.add_theme_color_override("font_color", CwPalette.IGNITION if st == "FL_CW_STAGE_BURNING" else (
		CwPalette.DANGER if st == "FL_CW_STAGE_EMPTY" else CwPalette.TEXT_DIM))
	_engine_icon.modulate = Color.WHITE if lit > 0 else Color(1, 1, 1, 0.45)
	_stripe.color = color
	_fuel.color = color
	_fuel.value = fuel[0] / fuel[1] if fuel[1] > 0.0 else 0.0
	_booster_row.visible = fuel[3] > 0.0
	_booster.value = fuel[2] / fuel[3] if fuel[3] > 0.0 else 0.0
	modulate.a = 1.0 if state == "active" else (0.78 if state == "idle" else 0.4)
	_num.add_theme_color_override("font_color", CwPalette.ink(color) if state == "active" else CwPalette.TEXT_DIM)
