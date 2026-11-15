class_name FlightCapturePanel
extends PanelContainer
## Map-view panel for the automatic orbit insertion (FlightCapture): shows the body the
## current plan arrives at, lets the player pick the orbit (periapsis, apoapsis or
## circular, optionally the inclination) and adds the correction + capture nodes.
## FlightHUD keeps it stacked right above the maneuver panel.

var world: FlightWorld
var map_view: FlightMap
var _body := -1
var _min_alt := 0.0
var _timer := 0.0
var _collapsed := false

@onready var _target: Label = %Target
@onready var _form: Control = %Form
@onready var _pe: SpinBox = %PeSpin
@onready var _ap: SpinBox = %ApSpin
@onready var _circular: CheckBox = %Circular
@onready var _inc_check: CheckBox = %IncCheck
@onready var _inc: SpinBox = %IncSpin
@onready var _inc_hint: Label = %IncHint
@onready var _result: Label = %Result


func _ready() -> void:
	%BtnPlan.pressed.connect(_plan)
	%BtnCollapse.pressed.connect(func() -> void: set_collapsed(not _collapsed))
	_circular.toggled.connect(func(_on: bool) -> void: _sync_form())
	_inc_check.toggled.connect(func(_on: bool) -> void: _sync_form())
	_pe.value_changed.connect(func(_v: float) -> void: _sync_form())
	_inc.value_changed.connect(func(_v: float) -> void: _sync_form())
	for sp: SpinBox in [_pe, _ap, _inc]:
		sp.get_line_edit().focus_mode = Control.FOCUS_CLICK
	_result.text = ""
	_result.visible = false
	_sync_form()


## Called by the HUD once the world is set: re-read the arrival whenever the plan changes.
func bind(w: FlightWorld, map: FlightMap) -> void:
	world = w
	map_view = map
	w.plan.changed.connect(func() -> void: _timer = minf(_timer, 0.1))


func set_collapsed(on: bool) -> void:
	_collapsed = on
	%BtnCollapse.text = "+" if on else "-"
	refresh(true)


## Re-reads the arrival (one prediction, a few ms) a couple of times per second.
func refresh(force := false, delta := 0.0) -> void:
	if world == null or not visible:
		return
	_timer -= delta
	if _timer > 0.0 and not force:
		return
	_timer = 0.5
	var tg := {}
	if world.launched and not world.sim.landed and not world.sim.crashed:
		tg = world.capture_planner().target()
	var has := not tg.is_empty()
	_form.visible = has and not _collapsed
	_result.visible = not _collapsed and _result.text != ""
	if not has:
		_body = -1
		_target.visible = not _collapsed
		_target.text = tr("FL_CW_CAPT_NONE")
		_target.tooltip_text = tr("FL_CAPT_NONE")
		_target.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
		return
	_target.visible = true
	_target.tooltip_text = ""
	var b: int = tg["body"]
	var sys := world.sys
	_target.add_theme_color_override("font_color", FlightMapStyle.on_paper(FlightMap.STYLE.soi_color(sys.ids[b])))
	var eta := float(tg["t_enter"]) - world.time
	if eta > 1.0:
		_target.text = tr("FL_CAPT_TARGET") % [sys.display_name(b), FlightMap.fmt_eta(eta)]
	else:
		_target.text = tr("FL_CAPT_TARGET_IN") % sys.display_name(b)
	var planned := 0
	for n in world.plan.nodes:
		if n.auto_capture:
			planned += 1
	if planned > 0:
		_target.text += "
" + tr("FL_CAPT_PLANNED") % planned
	%BtnPlan.text = tr("FL_CAPT_REPLAN") if planned > 0 else tr("FL_CAPT_PLAN")
	if b != _body:
		_body = b
		_min_alt = world.capture_planner().min_altitude(b)
		var def := snappedf(maxf(_min_alt + 20000.0, sys.radius[b] * 0.06), 10000.0)
		_pe.min_value = ceilf(_min_alt / 1000.0)
		_pe.set_value_no_signal(def / 1000.0)
		_ap.set_value_no_signal(def / 1000.0)
		_pe.tooltip_text = "%s (%s)" % [tr("FL_CAPT_PE_TIP"), tr("FL_CAPT_MIN") % FlightHUD.fmt_dist(_min_alt)]
		_sync_form()


func _sync_form() -> void:
	_ap.editable = not _circular.button_pressed
	if _circular.button_pressed or _ap.value < _pe.value:
		_ap.set_value_no_signal(_pe.value)
	_inc.editable = _inc_check.button_pressed
	if not _inc_check.button_pressed:
		_inc_hint.text = tr("FL_CAPT_KEEP_PLANE")
	else:
		var i := _inc.value
		var kind := "FL_CAPT_PROGRADE" if i < 80.0 else ("FL_CAPT_POLAR" if i <= 100.0 else "FL_CAPT_RETRO")
		_inc_hint.text = tr(kind)


func _plan() -> void:
	if world == null:
		return
	_sync_form()
	var inc := _inc.value if _inc_check.button_pressed else NAN
	var res := world.plan_capture(_pe.value * 1000.0, _ap.value * 1000.0, inc)
	if not res["ok"]:
		_result.text = tr(res["msg"])
		_result.add_theme_color_override("font_color", CwPalette.DANGER)
	else:
		var ap: float = res["ap"]
		var txt := tr("FL_CAPT_RESULT") % [FlightHUD.fmt_speed(res["dv_corr"]), FlightHUD.fmt_speed(res["dv_capt"])]
		txt += "\n" + tr("FL_CAPT_ORBIT") % [FlightHUD.fmt_dist(res["pe"]),
			FlightHUD.fmt_dist(ap) if ap < INF else "—", "%.1f" % float(res["inc"])]
		if res["msg"] != "":
			txt += "\n" + tr(res["msg"])
		_result.text = txt
		_result.add_theme_color_override("font_color", CwPalette.SUCCESS if res["msg"] == "" else CwPalette.WARNING)
		if res.get("first") != null and map_view != null:
			map_view.select_node(res["first"])
		world.hud.toast(tr("FL_CAPT_DONE") % res["nodes"].size(), MarginPalette.SUCCESS)
	refresh(true)
