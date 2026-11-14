class_name FlightStageRow
extends PanelContainer
## One row of the flight stage stack (layout in scenes/flight/flight_stage_row.tscn):
## stage number, engines (lit / total), core fuel bar, booster fuel bar, Δv left.

@onready var _num: Label = %Num
@onready var _title: Label = %Title
@onready var _dv: Label = %Dv
@onready var _engines: Label = %Engines
@onready var _fuel: ProgressBar = %Fuel
@onready var _booster: ProgressBar = %Booster
@onready var _booster_row: Control = %BoosterRow
@onready var _engine_icon: TextureRect = %EngineIcon


## state: "active" / "idle" / "spent"; fuel: FlightVessel.stage_fuel() [core, core0, boost, boost0]
func set_data(stage_no: int, state: String, engines: int, lit: int, fuel: PackedFloat64Array, dv: float) -> void:
	_num.text = str(stage_no)
	_title.text = tr("UI_STAGE_N") % stage_no
	_dv.text = FlightHUD.fmt_speed(dv) if state != "spent" else "—"
	_engines.text = "%d / %d" % [lit, engines] if state == "active" else "× %d" % engines
	_engines.add_theme_color_override("font_color", MarginPalette.ACCENT if lit > 0 else MarginPalette.TEXT_DIM)
	_engine_icon.modulate = MarginPalette.ACCENT if lit > 0 else MarginPalette.TEXT_DIM
	_fuel.value = 100.0 * fuel[0] / fuel[1] if fuel[1] > 0.0 else 0.0
	_booster_row.visible = fuel[3] > 0.0
	_booster.value = 100.0 * fuel[2] / fuel[3] if fuel[3] > 0.0 else 0.0
	modulate.a = 1.0 if state == "active" else (0.62 if state == "idle" else 0.35)
	_num.add_theme_color_override("font_color", MarginPalette.ACCENT if state == "active" else MarginPalette.TEXT_DIM)
