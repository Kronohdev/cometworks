class_name FlightHUD
extends CanvasLayer
## Lean flight HUD. Layout, styles and icons live in scenes/flight/flight_hud.tscn (theme
## ui/margin_theme.tres); this script only fills values, moves the navball markers and
## shows / hides panels. Static texts are translation keys (i18n/flight_strings.csv).
##   top strip: altitude, mission clock, time warp
##   left: flight data (Ap / Pe, speeds, G, dynamic pressure with Max-Q, Δv) - collapsible
##   right: stage stack (scenes/flight/flight_stage_row.tscn rows) - collapsible
##   bottom: navball cluster (throttle, speed, navball with prograde / retrograde, modes)
##   F2 hides everything, F1 shows the controls.

signal action(what: String)

const STAGE_ROW := preload("res://scenes/flight/flight_stage_row.tscn")
const EVENT_ROW := preload("res://scenes/flight/flight_event_row.tscn")
const ICON_COLLAPSE := preload("res://ui/kit/icon_collapse.svg")
const ICON_EXPAND := preload("res://ui/kit/icon_expand.svg")
const TOAST_KEYS := {
	"EV_IGNITION_PAD": "MSG_IGNITION", "EV_LIFTOFF": "MSG_LIFTOFF", "EV_MAXQ": "MSG_MAXQ",
	"EV_BOOSTER_SEP": "MSG_BOOSTER_SEP", "EV_STAGE_SEP": "MSG_STAGE_SEP", "EV_FAIRING": "MSG_FAIRING",
	"EV_FLAMEOUT": "MSG_FLAMEOUT", "EV_SPACE": "MSG_SPACE", "EV_ORBIT": "MSG_ORBIT", "EV_CRASH": "MSG_CRASH",
}

const DESIGN_SIZE := Vector2(1600, 900)

var world: Node = null
var hud_visible := true
var _toast_t := 0.0
var _rows: Array[FlightStageRow] = []
var _row_stage_count := -1
var _tele_collapsed := false
var _stages_collapsed := false
var _last_report := {}

@onready var _root: Control = %Root
@onready var _alt: Label = %AltValue
@onready var _clock: Label = %Clock
@onready var _warp: Label = %Warp
@onready var _ap: Label = %ApValue
@onready var _pe: Label = %PeValue
@onready var _tap: Label = %TapValue
@onready var _vs: Label = %VsValue
@onready var _hs: Label = %HsValue
@onready var _mach: Label = %MachValue
@onready var _g: Label = %GValue
@onready var _g_bar: ProgressBar = %GBar
@onready var _q: Label = %QValue
@onready var _q_bar: ProgressBar = %QBar
@onready var _maxq_tag: Label = %MaxQTag
@onready var _dv_stage: Label = %DvStageValue
@onready var _dv_total: Label = %DvTotalValue
@onready var _tele_body: Control = %TeleBody
@onready var _stage_list: VBoxContainer = %StageList
@onready var _stages_body: Control = %StagesBody
@onready var _throttle_bar: ProgressBar = %ThrottleBar
@onready var _throttle_label: Label = %ThrottleLabel
@onready var _speed_mode: Label = %SpeedMode
@onready var _speed: Label = %SpeedValue
@onready var _hdg: Label = %HdgLabel
@onready var _ball: MeshInstance3D = %Ball
@onready var _ball_box: Control = %NavballBox
@onready var _mark_pro: Control = %MarkPro
@onready var _mark_retro: Control = %MarkRetro
@onready var _btn_sas: Button = %BtnSas
@onready var _btn_pro: Button = %BtnPro
@onready var _btn_retro: Button = %BtnRetro
@onready var _btn_auto: Button = %BtnAuto
@onready var _btn_map: Button = %BtnMap
@onready var _toast: Control = %Toast
@onready var _toast_label: Label = %ToastLabel
@onready var _help: Control = %Help
@onready var _pause: Control = %Pause
@onready var _report: Control = %Report
@onready var _hint: Label = %Hint
@onready var map_view: FlightMap = $MapView


func _ready() -> void:
	%BtnResume.pressed.connect(func() -> void: action.emit("resume"))
	%BtnRevertLaunch.pressed.connect(func() -> void: action.emit("revert_launch"))
	%BtnRevertHangar.pressed.connect(func() -> void: action.emit("revert_hangar"))
	%BtnEndFlight.pressed.connect(func() -> void: action.emit("end"))
	%BtnRLaunch.pressed.connect(func() -> void: action.emit("revert_launch"))
	%BtnRHangar.pressed.connect(func() -> void: action.emit("revert_hangar"))
	%BtnRContinue.pressed.connect(func() -> void: action.emit("continue"))
	%BtnWarpUp.pressed.connect(func() -> void: action.emit("warp_up"))
	%BtnWarpDown.pressed.connect(func() -> void: action.emit("warp_down"))
	%BtnStage.pressed.connect(func() -> void: action.emit("stage"))
	_btn_sas.pressed.connect(func() -> void: action.emit("sas"))
	_btn_pro.pressed.connect(func() -> void: action.emit("prograde"))
	_btn_retro.pressed.connect(func() -> void: action.emit("retrograde"))
	_btn_auto.pressed.connect(func() -> void: action.emit("auto"))
	_btn_map.pressed.connect(func() -> void: action.emit("map"))
	%BtnTeleCollapse.pressed.connect(func() -> void: set_tele_collapsed(not _tele_collapsed))
	%BtnStagesCollapse.pressed.connect(func() -> void: set_stages_collapsed(not _stages_collapsed))
	get_viewport().size_changed.connect(_rescale)
	_rescale()
	_toast.visible = false
	_help.visible = false
	_pause.visible = false
	_report.visible = false
	map_view.visible = false


func setup(w: Node) -> void:
	world = w


## The layout is authored for 1600x900; other window sizes scale the whole HUD.
func _rescale() -> void:
	var vp := get_viewport().get_visible_rect().size
	var k := minf(vp.x / DESIGN_SIZE.x, vp.y / DESIGN_SIZE.y)
	scale = Vector2(k, k)
	for c: Control in [_root, map_view]:
		c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		c.position = Vector2.ZERO
		c.size = vp / k


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false


# ------------------------------------------------------------ panels
func toggle_hud() -> void:
	hud_visible = not hud_visible
	_root.visible = hud_visible


func toggle_help() -> void:
	_help.visible = not _help.visible


func show_pause(on: bool) -> void:
	_pause.visible = on


func set_map_mode(on: bool) -> void:
	map_view.set_active(on)
	_btn_map.set_pressed_no_signal(on)


func set_tele_collapsed(on: bool) -> void:
	_tele_collapsed = on
	_tele_body.visible = not on
	%BtnTeleCollapse.icon = ICON_EXPAND if on else ICON_COLLAPSE


func set_stages_collapsed(on: bool) -> void:
	_stages_collapsed = on
	_stages_body.visible = not on
	%BtnStagesCollapse.icon = ICON_COLLAPSE if on else ICON_EXPAND


func toast(text: String, color := MarginPalette.TEXT, seconds := 3.0) -> void:
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", color)
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_t = seconds


func event(key: String, data: Dictionary) -> void:
	if not TOAST_KEYS.has(key):
		return
	var text := tr(TOAST_KEYS[key])
	if data.has("stage"):
		text = text % int(data["stage"]) if text.contains("%d") else text
	var col := MarginPalette.TEXT
	match key:
		"EV_MAXQ":
			col = MarginPalette.WARNING
		"EV_ORBIT", "EV_SPACE", "EV_LIFTOFF":
			col = MarginPalette.SUCCESS
		"EV_CRASH":
			col = MarginPalette.DANGER
			text = tr(String(data.get("reason", "CRASH_IMPACT")))
		"EV_BOOSTER_SEP", "EV_STAGE_SEP", "EV_FAIRING":
			col = MarginPalette.ACCENT
	toast(text, col, 4.0 if key == "EV_ORBIT" else 2.6)


# ------------------------------------------------------------ formatting
static func fmt_dist(m: float) -> String:
	if is_inf(m) or is_nan(m):
		return "—"
	var a := absf(m)
	if a < 10000.0:
		return "%s m" % _group(m, 0)
	if a < 1.0e7:
		return "%s km" % _group(m / 1000.0, 1)
	return "%s Mm" % _group(m / 1.0e6, 1)


static func fmt_speed(v: float) -> String:
	return "%s m/s" % _group(v, 0 if absf(v) >= 100.0 else 1)


static func fmt_time(t: float, sign_prefix := false) -> String:
	if is_inf(t) or is_nan(t):
		return "—"
	var s := int(absf(t))
	var h := s / 3600
	var m := (s / 60) % 60
	var sec := s % 60
	var body := "%02d:%02d:%02d" % [h, m, sec] if h > 0 else "%02d:%02d" % [m, sec]
	if sign_prefix:
		return ("T+ " if t >= 0.0 else "T- ") + body
	return body


static func _group(v: float, decimals: int) -> String:
	var neg := v < 0.0
	var s := ("%." + str(decimals) + "f") % absf(v)
	var parts := s.split(".")
	var ip := parts[0]
	var out := ""
	var n := ip.length()
	for i in n:
		out += ip[i]
		var left := n - i - 1
		if left > 0 and left % 3 == 0:
			out += " "
	if parts.size() > 1:
		out += ("," if TranslationServer.get_locale().begins_with("pt") else ".") + parts[1]
	return ("-" if neg else "") + out


# ------------------------------------------------------------ telemetry
func update_telemetry(t: Dictionary) -> void:
	_alt.text = fmt_dist(t["alt"])
	_clock.text = fmt_time(t["met"], true) if t["launched"] else tr("FL_ON_PAD")
	_warp.text = "%d×" % int(t["warp"])
	_warp.add_theme_color_override("font_color", MarginPalette.ACCENT if int(t["warp"]) > 1 else MarginPalette.TEXT)
	var ap: float = t["ap"]
	var pe: float = t["pe"]
	_ap.text = fmt_dist(ap) if ap > -FlightOrbit.R * 0.99 else "—"
	_pe.text = fmt_dist(pe) if pe > -FlightOrbit.R * 0.99 else "—"
	_pe.add_theme_color_override("font_color", MarginPalette.SUCCESS if pe > FlightOrbit.ATMO_TOP else MarginPalette.TEXT)
	_tap.text = fmt_time(t["t_ap"])
	_vs.text = fmt_speed(t["vs"])
	_hs.text = fmt_speed(t["hs"])
	_mach.text = ("%.2f" % float(t["mach"])) if t["alt"] < FlightOrbit.ATMO_TOP else "—"
	var g: float = t["g"]
	_g.text = "%.2f g" % g
	_g_bar.value = clampf(g, 0.0, _g_bar.max_value)
	_tint_bar(_g_bar, MarginPalette.SUCCESS if g < 4.0 else (MarginPalette.WARNING if g < 8.0 else MarginPalette.DANGER))
	var q: float = t["q"]
	_q.text = "%.1f kPa" % (q / 1000.0)
	_q_bar.value = clampf(q / 1000.0, 0.0, _q_bar.max_value)
	_tint_bar(_q_bar, MarginPalette.ACCENT_2 if q < 25000.0 else (MarginPalette.WARNING if q < 45000.0 else MarginPalette.DANGER))
	_maxq_tag.visible = q > 3000.0 and not t["maxq_passed"]
	_dv_stage.text = fmt_speed(t["dv_stage"])
	_dv_total.text = fmt_speed(t["dv_total"])
	_throttle_bar.value = float(t["throttle"]) * 100.0
	_throttle_label.text = "%d%%" % int(round(float(t["throttle"]) * 100.0))
	var orbital: bool = t["alt"] > 30000.0
	_speed_mode.text = tr("FL_ORBIT_SPEED") if orbital else tr("FL_SURFACE_SPEED")
	_speed.text = fmt_speed(t["speed"])
	_btn_sas.set_pressed_no_signal(int(t["sas"]) != 0)
	_btn_pro.set_pressed_no_signal(int(t["sas"]) == FlightVessel.Sas.PROGRADE)
	_btn_retro.set_pressed_no_signal(int(t["sas"]) == FlightVessel.Sas.RETROGRADE)
	_btn_auto.set_pressed_no_signal(t["auto"])
	_update_navball(t)
	_update_stages(t)
	_hint.visible = not t["launched"]


func _tint_bar(bar: ProgressBar, c: Color) -> void:
	var sb := bar.get_theme_stylebox("fill")
	if not (sb is StyleBoxFlat):
		return
	if (sb as StyleBoxFlat).bg_color == c:
		return
	var f := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
	f.bg_color = c
	bar.add_theme_stylebox_override("fill", f)


func _update_navball(t: Dictionary) -> void:
	var up: Vector3 = t["up"]
	var east: Vector3 = t["east"]
	var north := up.cross(east).normalized()
	east = north.cross(up).normalized()
	# horizon frame H: x = east, y = up, z = south
	var to_h := Basis(east, up, -north).transposed()
	var qb: Quaternion = t["q_body"]
	var b := Basis(qb)
	var nose_h := to_h * (b * Vector3.UP)
	var top_h := to_h * (b * Vector3.BACK)
	var right_h := to_h * (b * Vector3.RIGHT)
	# ball rotation: nose -> towards the viewer (+Z), top -> +Y, right -> +X
	var r_ball := Basis(right_h, top_h, nose_h).transposed()
	_ball.basis = r_ball.orthonormalized()
	var heading := fposmod(rad_to_deg(atan2(nose_h.x, nose_h.z * -1.0)), 360.0)
	var pitch := rad_to_deg(asin(clampf(nose_h.y, -1.0, 1.0)))
	_hdg.text = "%s %03d°  ·  %s %+d°" % [tr("FL_HDG"), int(round(heading)) % 360, tr("FL_PITCH"), int(round(pitch))]
	var vel: Vector3 = t["vel"]
	var radius := _ball_box.size.x * 0.5 * 0.9
	var center := _ball_box.size * 0.5
	if vel.length() > 2.0:
		var v_ball := r_ball * (to_h * vel.normalized())
		_place_marker(_mark_pro, v_ball, center, radius)
		_place_marker(_mark_retro, -v_ball, center, radius)
	else:
		_mark_pro.visible = false
		_mark_retro.visible = false


func _place_marker(m: Control, d: Vector3, center: Vector2, radius: float) -> void:
	m.visible = d.z > -0.05
	m.position = center + Vector2(d.x, -d.y) * radius - m.size * 0.5
	m.modulate.a = clampf((d.z + 0.05) * 4.0, 0.0, 1.0)


func _update_stages(t: Dictionary) -> void:
	var v: FlightVessel = t["vessel"]
	var n: int = v.stage_count
	if n != _row_stage_count:
		for r in _rows:
			r.queue_free()
		_rows.clear()
		# last stage on top, like the hangar's stack order
		for i in n:
			var row: FlightStageRow = STAGE_ROW.instantiate()
			_stage_list.add_child(row)
			_rows.append(row)
		_row_stage_count = n
	var dv_by_stage := {}
	for r in t["dv_rows"]:
		dv_by_stage[int(r["stage"])] = r["dv"]
	for i in n:
		var stage := n - 1 - i
		var row := _rows[i]
		var fuel := v.stage_fuel(stage)
		var engs := v.stage_engines(stage)
		var lit := 0
		for e in engs:
			if float(e["thrust"]) > 0.0:
				lit += 1
		var state := "spent" if stage < v.current_stage else ("active" if stage == v.current_stage else "idle")
		row.visible = stage >= v.current_stage or stage >= n - 1
		row.set_data(stage + 1, state, engs.size(), lit, fuel, float(dv_by_stage.get(stage, 0.0)))


# ------------------------------------------------------------ report
func show_report(r: Dictionary) -> void:
	_last_report = r
	_report.visible = true
	_pause.visible = false
	var res: String = r["result"]
	var badge: Label = %ReportBadge
	var reached: bool = r["orbit"]
	if res == "crash":
		badge.text = tr("RP_CRASHED")
		badge.add_theme_color_override("font_color", MarginPalette.DANGER)
	elif reached:
		badge.text = tr("RP_ORBIT")
		badge.add_theme_color_override("font_color", MarginPalette.SUCCESS)
	else:
		badge.text = tr("RP_SUBORBITAL")
		badge.add_theme_color_override("font_color", MarginPalette.WARNING)
	%ReportVessel.text = String(r.get("vessel", ""))
	%RMaxAlt.text = fmt_dist(r["max_alt"])
	%RMaxSpeed.text = fmt_speed(r["max_speed"])
	%RMaxQ.text = "%.1f kPa  ·  T+%s  ·  %s" % [float(r["max_q"]) / 1000.0, fmt_time(r["max_q_t"]), fmt_dist(r["max_q_alt"])]
	%RMaxG.text = "%.2f g" % float(r["max_g"])
	%ROrbit.text = (tr("RP_YES") if reached else tr("RP_NO")) + "  ·  Ap %s  ·  Pe %s" % [
		fmt_dist(r["ap"]) if float(r["ap"]) > -FlightOrbit.R * 0.99 else "—", fmt_dist(r["pe"]) if float(r["pe"]) > -FlightOrbit.R * 0.99 else "—"]
	%ROrbit.add_theme_color_override("font_color", MarginPalette.SUCCESS if reached else MarginPalette.WARNING)
	var used: float = r["dv_used"]
	var pred: float = r["dv_predicted"]
	%RDv.text = "%s / %s  (%d%%)" % [fmt_speed(used), fmt_speed(pred), int(round(used / maxf(pred, 1.0) * 100.0))]
	%RDvBar.value = clampf(used / maxf(pred, 1.0) * 100.0, 0.0, 100.0)
	%RTime.text = fmt_time(r["time"])
	var reason: String = r.get("reason", "")
	%RReasonRow.visible = res == "crash"
	%RReason.text = tr(reason) if reason != "" else ""
	var plot: FlightPlot = %Plot
	plot.set_data(r["samples_t"], r["samples_alt"], r["samples_v"], r["events"])
	var tl: VBoxContainer = %Timeline
	for c in tl.get_children():
		c.queue_free()
	for e in r["events"]:
		var key: String = e["key"]
		if (not TOAST_KEYS.has(key) and key != "EV_IGNITION") or key == "EV_IGNITION_PAD":
			continue
		var row: Control = EVENT_ROW.instantiate()
		(row.get_node("Time") as Label).text = "T+" + fmt_time(e["t"])
		(row.get_node("Text") as Label).text = _event_text(key, e["data"])
		(row.get_node("Alt") as Label).text = fmt_dist(e["alt"])
		tl.add_child(row)
	%BtnRContinue.visible = res != "crash"


func hide_report() -> void:
	_report.visible = false


func _event_text(key: String, data: Dictionary) -> String:
	var k: String = TOAST_KEYS.get(key, "MSG_IGNITION_N")
	if key == "EV_IGNITION":
		k = "MSG_IGNITION_N"
	if key == "EV_CRASH":
		return tr(String(data.get("reason", "CRASH_IMPACT")))
	var s := tr(k)
	if s.contains("%d"):
		s = s % int(data.get("stage", 1))
	return s
