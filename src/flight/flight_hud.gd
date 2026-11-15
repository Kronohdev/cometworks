class_name FlightHUD
extends CanvasLayer
## Flight HUD in the Cometworks sticker look. Layout, styles and icons live in
## scenes/flight/flight_hud.tscn (theme ui/cometworks_theme.tres); this script only fills values,
## moves the navball markers and shows / hides panels. Static texts are translation keys
## (i18n/flight_strings.csv, i18n/flight_cw_strings.csv).
##   left column: the goal card (the mission, its progress and a plain "do this now" hint) and the
##   flight gauges (altitude, speed, delta-v left vs what the goal still needs, highest / lowest
##   point; "More data" opens vertical / horizontal speed, Mach, G, dynamic pressure, stage dv)
##   top: mission clock and time warp
##   right: stage stickers (scenes/flight/flight_stage_row.tscn rows) and the staging key
##   bottom: navball cluster (engine lever, navball with prograde / retrograde and the maneuver
##   marker, modes) with the burn countdown strip above it
##   bottom-right (map view): the maneuver-node panel (dv fields, time, warp / execute)
##   first flight: hint bubbles (FlightTips) that walk through ignition, the turn, staging, the map
##   end: a calm end-of-flight card; in a mission flight it hands back to the campus review
##   F2 hides everything, F1 shows the controls.

signal action(what: String)

const STAGE_ROW := preload("res://scenes/flight/flight_stage_row.tscn")
const EVENT_ROW := preload("res://scenes/flight/flight_event_row.tscn")
const ICON_COLLAPSE := preload("res://ui/cometworks/hangar/ink_collapse.svg")
const ICON_EXPAND := preload("res://ui/cometworks/hangar/ink_expand.svg")
const ICON_OK := preload("res://ui/cometworks/hangar/ok.svg")
const ICON_WARN := preload("res://ui/cometworks/hangar/warn.svg")
const ICON_DANGER := preload("res://ui/cometworks/hangar/danger.svg")
const ICON_PLANET := preload("res://ui/cometworks/icons/planet.svg")
const ICON_ROCKET := preload("res://ui/cometworks/icons/rocket.svg")
## goal lines: the edge of space, a stable orbit's lowest point (m), the delta-v to low orbit (m/s)
const SPACE_ALT := 100000.0
const ORBIT_PE := 140000.0
const LEO_DV := 9400.0
## the turn east starts here (m); the coach's "highest point is enough" line (m)
const TURN_ALT := 600.0
const AP_ENOUGH := 150000.0
const TOAST_KEYS := {
	"EV_IGNITION_PAD": "MSG_IGNITION", "EV_LIFTOFF": "MSG_LIFTOFF", "EV_MAXQ": "MSG_MAXQ",
	"EV_BOOSTER_SEP": "MSG_BOOSTER_SEP", "EV_STAGE_SEP": "MSG_STAGE_SEP", "EV_FAIRING": "MSG_FAIRING",
	"EV_FLAMEOUT": "MSG_FLAMEOUT", "EV_SPACE": "MSG_SPACE", "EV_ORBIT": "MSG_ORBIT", "EV_CRASH": "MSG_CRASH",
	"EV_SOI": "MSG_SOI",
}

const DESIGN_SIZE := Vector2(1600, 900)

## candy colour of each stage sticker (stage 1 first, then repeating)
@export var stage_colors: Array[Color] = [Color("#ff9a5c"), Color("#7cc8ff"), Color("#b39cff"), Color("#6fe0be")]

var world: FlightWorld = null
var hud_visible := true
## what the flight is for: "space" (suborbital), "orbit" (low orbit / test flight) or "beyond"
var goal_kind := "orbit"
var _goal_dv := LEO_DV
var _goal_done := false
var _now_key := ""
var _pitch := 90.0
var _tele_folded_by_map := false
var _toast_t := 0.0
var _rows: Array[FlightStageRow] = []
var _row_stage_count := -1
var _tele_collapsed := false
## the stages panel was folded to make room for the orbit-insertion panel (map view)
var _stages_folded_by_map := false
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
@onready var _mark_node: Control = %MarkNode
@onready var _burn_strip: Control = %BurnStrip
@onready var _burn_caption: Label = %Caption
@onready var _burn_count: Label = %BurnCountdown
@onready var _burn_dv: Label = %BurnDv
@onready var _burn_time: Label = %BurnTime
@onready var _mnv: Control = %Maneuver
@onready var _capt: FlightCapturePanel = %Capture
@onready var _mnv_body: Control = %Body
@onready var _mnv_empty: Control = %Empty
@onready var _spins: Array[SpinBox] = [%ProSpin, %NorSpin, %RadSpin]
@onready var _alt_caption: Label = %AltCaption
@onready var _dv_bar: CwSegmentBar = %DvBar
@onready var _dv_note: Label = %DvNote
@onready var _goal_bar: CwSegmentBar = %GoalBar
@onready var _goal_progress: Label = %GoalProgress
@onready var _toast_dot: Control = %ToastDot
@onready var _tips: FlightTips = %Tip
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
	%BtnNodePrev.pressed.connect(func() -> void: _cycle_node(-1))
	%BtnNodeNext.pressed.connect(func() -> void: _cycle_node(1))
	%BtnNodeDelete.pressed.connect(func() -> void:
		if panel_node():
			map_view.select_node(panel_node())
			map_view.delete_selected())
	%BtnOrbitBack.pressed.connect(func() -> void: _shift_node(-1.0, true))
	%BtnOrbitFwd.pressed.connect(func() -> void: _shift_node(1.0, true))
	%BtnTimeBack.pressed.connect(func() -> void: _shift_node(-1.0, false))
	%BtnTimeFwd.pressed.connect(func() -> void: _shift_node(1.0, false))
	%BtnWarpNode.pressed.connect(func() -> void: world.warp_to_next_node())
	%BtnExecute.toggled.connect(func(on: bool) -> void: world.set_executor(on))
	for i in 3:
		var k := i
		_spins[i].value_changed.connect(func(v: float) -> void: _on_spin(k, v))
		_spins[i].get_line_edit().focus_mode = Control.FOCUS_CLICK
	%BtnStagesCollapse.pressed.connect(func() -> void: set_stages_collapsed(not _stages_collapsed))
	%BtnTipsAgain.pressed.connect(func() -> void:
		_tips.restart()
		_help.visible = false)
	set_tele_collapsed(true)
	get_viewport().size_changed.connect(_rescale)
	_rescale()
	_toast.visible = false
	_burn_strip.visible = false
	_mnv.visible = false
	_capt.visible = false
	_mark_node.visible = false
	_help.visible = false
	_pause.visible = false
	_report.visible = false
	map_view.visible = false


func setup(w: Node) -> void:
	world = w
	_capt.bind(w, map_view)
	_fill_goal()


## The goal card: the tycoon mission (FlightSession.mission) or the free test flight's orbit.
func _fill_goal() -> void:
	var m := FlightSession.mission
	var target := String(m.get("target_id", ""))
	goal_kind = "orbit"
	if target == "suborbital":
		goal_kind = "space"
	elif target != "" and not target in ["leo", "sso"]:
		goal_kind = "beyond"
	_goal_dv = float(m.get("dv_needed", 0.0))
	if _goal_dv <= 0.0:
		_goal_dv = LEO_DV
	if m.is_empty():
		%GoalCaption.text = tr("FL_CW_GOAL_TEST")
		%GoalTitle.text = world.vessel_name if world and world.vessel_name != "" else tr("FL_CW_GOAL_TEST")
		%GoalLine.text = tr("FL_CW_GOAL_TEST_LINE")
		(%GoalIcon as TextureRect).texture = ICON_ROCKET
	else:
		%GoalCaption.text = tr("FL_CW_GOAL_MISSION")
		%GoalTitle.text = String(m.get("title", ""))
		var goal := String(m.get("goal", ""))
		%GoalLine.text = tr("FL_CW_GOAL_LINE") % [goal, String(m.get("target", ""))] if goal != "" else String(m.get("target", ""))
		(%GoalIcon as TextureRect).texture = ICON_PLANET
		CwIcon.sharpen(%GoalIcon as TextureRect)


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
	if _capt.visible:
		_capt.refresh(false, delta)
		# stacked right above the maneuver panel (both grow upwards)
		_capt.size = Vector2(_mnv.size.x, 0.0)
		_capt.position = Vector2(_mnv.position.x, _mnv.position.y - _capt.get_combined_minimum_size().y - 8.0)
		# no room under the stages panel: fold it while the map is open
		var sp := $Root/StagesPanel as Control
		if not _stages_collapsed and _capt.position.y < sp.position.y + sp.size.y + 8.0:
			set_stages_collapsed(true)
			_stages_folded_by_map = true
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
	# the tip on show waits behind the pause menu
	_tips.visible = not on and _tips.current != "" and not _report.visible


func set_map_mode(on: bool) -> void:
	map_view.set_active(on)
	_btn_map.set_pressed_no_signal(on)
	_mnv.visible = on
	_capt.visible = on
	if not on and _stages_folded_by_map:
		_stages_folded_by_map = false
		set_stages_collapsed(false)
	# the map bar takes the bottom-left corner: "More data" folds while the map is open
	if on and not _tele_collapsed:
		set_tele_collapsed(true)
		_tele_folded_by_map = true
	elif not on and _tele_folded_by_map:
		_tele_folded_by_map = false
		set_tele_collapsed(false)
	if on:
		_update_maneuver()
		_capt.refresh(true)


# ------------------------------------------------------------ maneuver panel
## The node shown in the panel: the one selected on the map, else the next one.
func panel_node() -> FlightManeuverNode:
	if map_view.selected != null and world.plan.nodes.has(map_view.selected):
		return map_view.selected
	return world.plan.first()


func _cycle_node(d: int) -> void:
	var nodes := world.plan.nodes
	if nodes.is_empty():
		return
	var i := nodes.find(panel_node())
	map_view.select_node(nodes[posmod(i + d, nodes.size())])
	_update_maneuver()


func _on_spin(axis: int, v: float) -> void:
	var n := panel_node()
	if n == null:
		return
	var dv := n.dv
	dv[axis] = v
	world.plan.set_dv(n, dv)


## Node time: one orbit (of the path it sits on) or 30 s earlier / later.
func _shift_node(sign: float, orbit: bool) -> void:
	var n := panel_node()
	if n == null:
		return
	var step := 30.0
	if orbit:
		step = 3600.0
		if world.traj:
			for s in world.traj.segments:
				if s.end == FlightTrajectory.End.NODE and s.node_index < world.plan.nodes.size() 						and world.plan.nodes[s.node_index] == n and s.conic.is_closed():
					step = s.conic.period
	if Input.is_key_pressed(KEY_SHIFT) and not orbit:
		step *= 10.0
	world.plan.set_time(n, n.time + sign * step, world.time)


func _update_maneuver() -> void:
	if world == null:
		return
	var n := panel_node()
	var has := n != null
	if _mnv_body.visible != has or _mnv_empty.visible == has:
		_mnv_body.visible = has
		_mnv_empty.visible = not has
		# grows up from the bottom-right corner, as tall as what it shows
		_mnv.offset_top = _mnv.offset_bottom - _mnv.get_combined_minimum_size().y
	%BtnNodePrev.disabled = world.plan.nodes.size() < 2
	%BtnNodeNext.disabled = world.plan.nodes.size() < 2
	%BtnNodeDelete.disabled = not has
	if not has:
		%NodeIndex.text = ""
		return
	%NodeIndex.text = "%d/%d" % [world.plan.index_of(n) + 1, world.plan.nodes.size()]
	var dv := n.remaining_world().length() if n.locked else n.dv_total()
	%NodeDvValue.text = fmt_speed(dv)
	var bt := world.node_burn_time(n)
	%NodeBurnValue.text = fmt_time(bt) if bt > 0.0 else tr("FL_NO_ENGINE")
	%NodeEtaValue.text = FlightMap.fmt_eta(n.time - world.time)
	for i in 3:
		var sp := _spins[i]
		if not sp.get_line_edit().has_focus():
			sp.set_value_no_signal(snappedf(n.dv[i], 0.1))
	# the orbit after this node and what it leads to
	var after := ""
	var enc := ""
	if world.traj:
		var idx := world.plan.index_of(n)
		for s in world.traj.segments:
			if s.plan == idx + 1:
				var c := s.conic
				var r: float = world.sys.radius[s.body]
				if c.is_closed() and c.ra < world.sys.soi[s.body]:
					after = "%s %s  ·  %s %s" % [tr("FL_AP"), fmt_dist(c.ra - r), tr("FL_PE"), fmt_dist(c.rp - r)]
				else:
					after = "%s %s  ·  %s" % [tr("FL_PE"), fmt_dist(c.rp - r), tr("FL_ESCAPE_ORBIT")]
				break
		var e := world.traj.encounter_summary(world.sys, idx + 1)
		if not e.is_empty():
			enc = tr("FL_NODE_ENCOUNTER") % [world.sys.display_name(e["body"]), fmt_dist(e["pe_alt"]),
				FlightMap.fmt_eta(float(e["t_pe"]) - world.time)]
	%After.text = after
	%Encounter.text = enc
	%Encounter.visible = enc != ""
	%BtnExecute.set_pressed_no_signal(world.executor != null)


func set_tele_collapsed(on: bool) -> void:
	_tele_collapsed = on
	_tele_body.visible = not on
	%BtnTeleCollapse.icon = ICON_EXPAND if on else ICON_COLLAPSE


func set_stages_collapsed(on: bool) -> void:
	_stages_collapsed = on
	_stages_body.visible = not on
	# the sticker hugs what is left
	($Root/StagesPanel as Control).size.y = 0.0
	%BtnStagesCollapse.icon = ICON_COLLAPSE if on else ICON_EXPAND


## A short sticker message under the clock. `color` tints its candy dot (the text stays ink, so
## it reads on the paper); the dark-look whites and greys some callers pass become lilac.
func toast(text: String, color := CwPalette.LILAC, seconds := 3.0) -> void:
	_toast_label.text = text
	if color.s < 0.2:
		color = CwPalette.LILAC
	_toast_dot.self_modulate = color
	_toast.size = Vector2.ZERO
	_toast.position.x = (_root.size.x - _toast.get_combined_minimum_size().x) * 0.5
	if not _toast.visible or _toast.modulate.a < 0.99:
		CwMotion.poke(_toast)
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_t = seconds


func event(key: String, data: Dictionary) -> void:
	if not TOAST_KEYS.has(key):
		return
	var text := tr(TOAST_KEYS[key])
	if data.has("stage"):
		text = text % int(data["stage"]) if text.contains("%d") else text
	if data.has("body") and text.contains("%s"):
		text = text % String(data["body"])
	var col := CwPalette.LILAC
	match key:
		"EV_MAXQ":
			col = CwPalette.BUTTER
		"EV_ORBIT", "EV_SPACE", "EV_LIFTOFF":
			col = CwPalette.MINT
		"EV_CRASH":
			col = CwPalette.PINK
			text = tr(String(data.get("reason", "CRASH_IMPACT")))
		"EV_BOOSTER_SEP", "EV_STAGE_SEP", "EV_FAIRING", "EV_IGNITION_PAD":
			col = CwPalette.PEACH
		"EV_SOI":
			col = CwPalette.ICE
	toast(text, col, 4.0 if key == "EV_ORBIT" or key == "EV_SOI" else 2.6)


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
## Time warp as shown in the top strip: 1×, 100×, 10k×, 1M×.
static func fmt_warp(w: int) -> String:
	if w >= 1000000:
		return "%dM×" % (w / 1000000)
	if w >= 10000:
		return "%dk×" % (w / 1000)
	return "%d×" % w


func update_telemetry(t: Dictionary) -> void:
	_alt.text = fmt_dist(t["alt"])
	var soi_name: String = t.get("soi_name", "")
	_alt_caption.text = tr("FL_CW_ALT") if int(t.get("soi", 3)) == world.sys.earth else tr("FL_CW_ALT_AT") % soi_name.to_upper()
	_clock.text = fmt_time(t["met"], true) if t["launched"] else tr("FL_ON_PAD")
	# effective warp; a picked warp the physics cannot reach yet shows as "100×/1000×"
	var w := int(t["warp"])
	var ws := int(t.get("warp_set", w))
	_warp.text = fmt_warp(w) if ws <= w else "%s/%s" % [fmt_warp(w), fmt_warp(ws)]
	var wc := CwPalette.INK
	if ws > w:
		wc = CwPalette.WARNING
	elif w > 1:
		wc = CwPalette.AURORA_VIOLET
	_warp.add_theme_color_override("font_color", wc)
	var ap: float = t["ap"]
	var pe: float = t["pe"]
	_ap.text = fmt_dist(ap) if ap > -FlightOrbit.R * 0.99 else "—"
	_pe.text = fmt_dist(pe) if pe > -FlightOrbit.R * 0.99 else "—"
	_pe.add_theme_color_override("font_color", CwPalette.SUCCESS if pe > FlightOrbit.ATMO_TOP else CwPalette.INK)
	_tap.text = fmt_time(t["t_ap"])
	_vs.text = fmt_speed(t["vs"])
	_hs.text = fmt_speed(t["hs"])
	_mach.text = ("%.2f" % float(t["mach"])) if t["alt"] < FlightOrbit.ATMO_TOP else "—"
	var g: float = t["g"]
	_g.text = "%.2f g" % g
	_g_bar.value = clampf(g, 0.0, _g_bar.max_value)
	_tint_bar(_g_bar, CwPalette.MINT if g < 4.0 else (CwPalette.BUTTER if g < 8.0 else CwPalette.PINK))
	var q: float = t["q"]
	_q.text = "%.1f kPa" % (q / 1000.0)
	_q_bar.value = clampf(q / 1000.0, 0.0, _q_bar.max_value)
	_tint_bar(_q_bar, CwPalette.ICE if q < 25000.0 else (CwPalette.BUTTER if q < 45000.0 else CwPalette.PINK))
	_maxq_tag.visible = q > 3000.0 and not t["maxq_passed"]
	_dv_stage.text = fmt_speed(t["dv_stage"])
	_dv_total.text = fmt_speed(t["dv_total"])
	_throttle_bar.value = float(t["throttle"]) * 100.0
	_throttle_label.text = "%d%%" % int(round(float(t["throttle"]) * 100.0))
	var orbital: bool = t["alt"] > 30000.0
	_speed_mode.text = tr("FL_CW_SPEED_ORBIT") if orbital else tr("FL_CW_SPEED_SURFACE")
	_speed.text = fmt_speed(t["speed"])
	_btn_sas.set_pressed_no_signal(int(t["sas"]) != 0)
	_btn_pro.set_pressed_no_signal(int(t["sas"]) == FlightCraft.Sas.PROGRADE)
	_btn_retro.set_pressed_no_signal(int(t["sas"]) == FlightCraft.Sas.RETROGRADE)
	_btn_auto.set_pressed_no_signal(t["auto"])
	_update_navball(t)
	t["pitch"] = _pitch
	_update_burn(t)
	_update_stages(t)
	if _mnv.visible:
		_update_maneuver()
	_update_goal(t)
	_update_coach(t)
	if not _pause.visible and not _report.visible:
		_tips.update(t, map_view.visible)


## Goal progress (the card's gauge and line) and the delta-v gauge: what is left in the tanks
## against what the goal still needs.
func _update_goal(t: Dictionary) -> void:
	var max_alt := float(world.stats.get("max_alt", 0.0))
	var ap: float = t["ap"]
	var pe: float = t["pe"]
	# on the pad (or a hyperbola) the elements are not an orbit yet
	if not t["launched"] or is_nan(ap) or ap < -FlightOrbit.R * 0.99:
		ap = 0.0
	if is_nan(pe):
		pe = -FlightOrbit.R
	var orbit: bool = t.get("orbit", false)
	var dv_left: float = t["dv_total"]
	var beyond := maxf(_goal_dv - LEO_DV, 0.0)
	var p := 0.0
	var line := ""
	match goal_kind:
		"space":
			_goal_done = _goal_done or max_alt >= SPACE_ALT
			p = max_alt / SPACE_ALT
			line = tr("FL_CW_GOAL_ALT") % fmt_dist(max_alt)
		_:
			var in_orbit := orbit or int(t.get("soi", world.sys.earth)) != world.sys.earth
			if goal_kind == "orbit":
				_goal_done = _goal_done or in_orbit
			else:
				_goal_done = _goal_done or int(t.get("soi", world.sys.earth)) == world.sys.moon or (in_orbit and dv_left >= beyond)
			var orbit_share := 1.0 if goal_kind == "orbit" else 0.7
			if in_orbit and goal_kind == "beyond":
				p = orbit_share + (1.0 - orbit_share) * clampf(dv_left / maxf(beyond, 1.0), 0.0, 1.0)
				line = tr("FL_CW_GOAL_TRIP") % [fmt_speed(dv_left), fmt_speed(beyond)]
			elif ap < ORBIT_PE:
				p = orbit_share * 0.5 * clampf(ap / ORBIT_PE, 0.0, 1.0)
				line = tr("FL_CW_GOAL_AP") % fmt_dist(maxf(ap, 0.0))
			else:
				p = orbit_share * (0.5 + 0.5 * clampf(pe / ORBIT_PE, 0.0, 1.0))
				line = tr("FL_CW_GOAL_PE") % fmt_dist(pe) if pe > 0.0 else tr("FL_CW_GOAL_PE_UNDER")
	if _goal_done:
		p = 1.0
		line = tr("FL_CW_GOAL_DONE")
	_goal_bar.value = clampf(p, 0.0, 1.0)
	_goal_progress.text = line
	_goal_progress.add_theme_color_override("font_color", CwPalette.SUCCESS if _goal_done else CwPalette.TEXT_DIM)
	# delta-v: tanks vs what the goal still asks (the hangar's need less what the engines gave)
	var need := 0.0 if _goal_done else maxf(_goal_dv - float(world.sim.craft.dv_used), 0.0)
	var top := maxf(maxf(dv_left, need) * 1.15, 1.0)
	_dv_bar.value = dv_left / top
	_dv_bar.marker = need / top if need > 0.0 else -1.0
	if _goal_done:
		_dv_note.text = tr("FL_CW_DV_DONE")
		_dv_note.add_theme_color_override("font_color", CwPalette.SUCCESS)
	elif dv_left >= need:
		_dv_note.text = tr("FL_CW_DV_OK") % _group(dv_left - need, 0)
		_dv_note.add_theme_color_override("font_color", CwPalette.SUCCESS)
	else:
		_dv_note.text = tr("FL_CW_DV_SHORT") % _group(need - dv_left, 0)
		_dv_note.add_theme_color_override("font_color", CwPalette.WARNING)


## The "do this now" line: one plain instruction for this moment of the flight.
func _update_coach(t: Dictionary) -> void:
	var key := now_key(t)
	if key != _now_key:
		_now_key = key
		_hint.text = tr(key) % fmt_dist(TURN_ALT) if key == "FL_CW_NOW_CLIMB" else tr(key)
		CwMotion.poke(%NowCard)
		if key in ["FL_CW_NOW_STAGE", "FL_CW_NOW_IGNITE"]:
			CwMotion.poke(%BtnStage)
	var v: FlightCraft = t["vessel"]
	var btn := %BtnStage as Button
	if not t["launched"]:
		btn.text = tr("FL_CW_STAGE_IGNITE")
	elif v.current_stage >= v.stage_count - 1:
		btn.text = tr("FL_CW_STAGE_LAST")
	else:
		btn.text = tr("FL_CW_STAGE_NEXT")
	btn.disabled = t["launched"] and v.current_stage >= v.stage_count - 1


## Translation key of the instruction for this telemetry (see _update_coach).
func now_key(t: Dictionary) -> String:
	var v: FlightCraft = t["vessel"]
	var alt := float(t["alt"])
	var ap := float(t["ap"])
	var pe := float(t["pe"])
	if is_nan(ap):
		ap = 0.0
	if is_nan(pe):
		pe = -FlightOrbit.R
	var thrust := float(t["thrust"])
	var max_alt := float(world.stats.get("max_alt", 0.0)) if world else alt
	if v.crashed:
		return "FL_CW_NOW_LOST"
	if not t["launched"]:
		return "FL_CW_NOW_AUTO" if t["auto"] else "FL_CW_NOW_IGNITE"
	if goal_kind == "space" and max_alt >= SPACE_ALT:
		return "FL_CW_NOW_SPACE"
	if t.get("orbit", false) or int(t.get("soi", 3)) != world.sys.earth:
		return "FL_CW_NOW_TRIP" if goal_kind == "beyond" else "FL_CW_NOW_ORBIT"
	if t["auto"]:
		return "FL_CW_NOW_AUTO"
	if FlightTips.stage_empty(t):
		return "FL_CW_NOW_STAGE"
	if float(t["vs"]) < -5.0 and ap < FlightOrbit.ATMO_TOP and thrust <= 0.0 and v.current_stage >= v.stage_count - 1:
		return "FL_CW_NOW_FALLING"
	if goal_kind == "space":
		if ap >= SPACE_ALT * 1.1 and thrust <= 0.0:
			return "FL_CW_NOW_COAST_UP"
		if ap >= SPACE_ALT * 1.1:
			return "FL_CW_NOW_CUT"
	var thr := float(t["throttle"])
	if thr < 0.02 and thrust <= 0.0 and ap < ORBIT_PE:
		return "FL_CW_NOW_THROTTLE"
	if goal_kind != "space":
		var following := int(t["sas"]) == FlightCraft.Sas.PROGRADE
		if alt < TURN_ALT and _pitch > 78.0:
			return "FL_CW_NOW_CLIMB"
		if alt < 45000.0 and not following:
			if _pitch > 78.0:
				return "FL_CW_NOW_TURN"
			# tilted: wait until the velocity (the prograde circle) catches up with the nose
			var pro := rad_to_deg(asin(clampf(float(t["vs"]) / maxf(float(t["speed"]), 1.0), -1.0, 1.0)))
			return "FL_CW_NOW_WAIT_G" if pro > _pitch + 1.5 else "FL_CW_NOW_PRESS_G"
		if ap < AP_ENOUGH:
			return "FL_CW_NOW_RAISE_AP" if thrust > 0.0 else "FL_CW_NOW_THROTTLE"
		if thrust > 0.0 and alt < FlightOrbit.ATMO_TOP:
			return "FL_CW_NOW_CUT"
		if pe < ORBIT_PE:
			return "FL_CW_NOW_COAST" if thrust <= 0.0 and float(t["t_ap"]) > 45.0 else "FL_CW_NOW_CIRCLE"
		return "FL_CW_NOW_ORBIT"
	return "FL_CW_NOW_RAISE_AP" if thrust > 0.0 else "FL_CW_NOW_THROTTLE"


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
	_pitch = pitch
	_hdg.text = tr("FL_CW_HDG_LINE") % [int(round(heading)) % 360, int(round(pitch))]
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
	var node: Dictionary = t.get("node", {})
	if not node.is_empty() and float(node["dv"]) > 0.05:
		var d_ball := r_ball * (to_h * (node["dir"] as Vector3))
		_place_marker(_mark_node, d_ball, center, radius)
	else:
		_mark_node.visible = false


## Burn countdown above the navball: time to the burn start (half the burn before the
## node), the Δv left and the burn time.
func _update_burn(t: Dictionary) -> void:
	var node: Dictionary = t.get("node", {})
	_burn_strip.visible = not node.is_empty()
	if node.is_empty():
		return
	var tb: float = node["t_burn"]
	var burning := tb <= 0.0 and float(t["thrust"]) > 0.0
	_burn_caption.text = tr("FL_BURNING") if burning else tr("FL_BURN_IN")
	_burn_count.text = FlightMap.fmt_eta(tb) if not burning else fmt_time(maxf(float(node["burn"]) * 0.5 + float(node["t_node"]), 0.0))
	_burn_count.add_theme_color_override("font_color", CwPalette.WARNING if tb < 10.0 else CwPalette.INK)
	_burn_dv.text = "Δv %s" % fmt_speed(node["dv"])
	var bt: float = node["burn"]
	_burn_time.text = ("%s %s" % [tr("FL_BURN"), fmt_time(bt)]) if bt > 0.0 else tr("FL_NO_ENGINE")


func _place_marker(m: Control, d: Vector3, center: Vector2, radius: float) -> void:
	m.visible = d.z > -0.05
	m.position = center + Vector2(d.x, -d.y) * radius - m.size * 0.5
	m.modulate.a = clampf((d.z + 0.05) * 4.0, 0.0, 1.0)


func _update_stages(t: Dictionary) -> void:
	var v: FlightCraft = t["vessel"]
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
		var col := stage_colors[stage % stage_colors.size()] if not stage_colors.is_empty() else CwPalette.PEACH
		row.set_data(stage + 1, state, engs.size(), lit, fuel, float(dv_by_stage.get(stage, 0.0)), col)


# ------------------------------------------------------------ report
func show_report(r: Dictionary) -> void:
	_last_report = r
	_report.visible = true
	_pause.visible = false
	_tips.visible = false
	var res: String = r["result"]
	var badge: Label = %ReportBadge
	var reached: bool = r["orbit"]
	var max_alt := float(r["max_alt"])
	var space := max_alt >= SPACE_ALT
	var mission := world != null and world.mission_mode
	%ReportTitle.text = tr("FL_CW_RP_TITLE_MISSION") if mission else tr("FL_CW_RP_TITLE_TEST")
	var icon := ICON_WARN
	var col := CwPalette.WARNING
	var reason: String = r.get("reason", "")
	if res == "crash":
		badge.text = tr("FL_CW_RP_LOST")
		icon = ICON_DANGER
		col = CwPalette.DANGER
		%ReportSummary.text = tr("FL_CW_RP_SUM_LOST") % (tr(reason) + "." if reason != "" else "")
	elif reached:
		badge.text = tr("FL_CW_RP_ORBIT")
		icon = ICON_OK
		col = CwPalette.SUCCESS
		%ReportSummary.text = tr("FL_CW_RP_SUM_ORBIT") % fmt_dist(r["pe"])
	elif space and goal_kind == "space":
		badge.text = tr("FL_CW_RP_SPACE")
		icon = ICON_OK
		col = CwPalette.SUCCESS
		%ReportSummary.text = tr("FL_CW_RP_SUM_SPACE") % fmt_dist(max_alt)
	else:
		badge.text = tr("FL_CW_RP_SPACE") if space else tr("FL_CW_RP_SUBORBITAL")
		%ReportSummary.text = tr("FL_CW_RP_SUM_SUB") % fmt_dist(max_alt)
	badge.add_theme_color_override("font_color", col)
	(%ReportIcon as TextureRect).texture = icon
	%ReportNext.visible = mission
	%ReportVessel.text = String(r.get("vessel", ""))
	%RMaxAlt.text = fmt_dist(r["max_alt"])
	%RMaxSpeed.text = fmt_speed(r["max_speed"])
	%RMaxQ.text = "%.1f kPa" % (float(r["max_q"]) / 1000.0)
	%RMaxQ.tooltip_text = "T+%s  ·  %s" % [fmt_time(r["max_q_t"]), fmt_dist(r["max_q_alt"])]
	%RMaxG.text = "%.2f g" % float(r["max_g"])
	%ROrbit.text = (tr("RP_YES") if reached else tr("RP_NO")) + "  ·  Ap %s  ·  Pe %s" % [
		fmt_dist(r["ap"]) if float(r["ap"]) > -FlightOrbit.R * 0.99 else "—", fmt_dist(r["pe"]) if float(r["pe"]) > -FlightOrbit.R * 0.99 else "—"]
	%ROrbit.add_theme_color_override("font_color", CwPalette.SUCCESS if reached else CwPalette.WARNING)
	var used: float = r["dv_used"]
	var pred: float = r["dv_predicted"]
	%RDv.text = "%s / %s m/s" % [_group(used, 0), _group(pred, 0)]
	%RDv.tooltip_text = "%d%%" % int(round(used / maxf(pred, 1.0) * 100.0))
	%RDvBar.value = clampf(used / maxf(pred, 1.0) * 100.0, 0.0, 100.0)
	%RTime.text = fmt_time(r["time"])
	%RReasonRow.visible = res == "crash" and reason != ""
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
	_tips.visible = _tips.current != ""


func _event_text(key: String, data: Dictionary) -> String:
	var k: String = TOAST_KEYS.get(key, "MSG_IGNITION_N")
	if key == "EV_IGNITION":
		k = "MSG_IGNITION_N"
	if key == "EV_CRASH":
		return tr(String(data.get("reason", "CRASH_IMPACT")))
	var s := tr(k)
	if s.contains("%d"):
		s = s % int(data.get("stage", 1))
	elif s.contains("%s"):
		s = s % String(data.get("body", ""))
	return s
