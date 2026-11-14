class_name LaunchWatch
extends Control
## The launch watch and the close view of a craft (scenes/tycoon/tracking/launch_watch_overlay.tscn),
## laid over the flight's HUD by TycoonModes (open_watch / open_follow); the flight runs in its
## spectator mode, so this script is the one flying it:
##   launch  T-3 countdown, then the flight's auto-ascent from the pad. The outcome the launch
##           simulation gave is what you see: a failed launch breaks up when its track says it
##           did (SpaceTracking.fail_time, the same second the map shows it lost); a sounding
##           rocket coasts to the top and falls back; an orbit target ends in orbit (a rocket that
##           cannot make it alone gets the last push, FlightWorld.assist_orbit); GEO, the Moon and
##           the comet wait in the parking orbit for the departure burn (SpaceTracking.departure:
##           warped to, then an impulse) and leave on the transfer the map then draws.
##   follow  the craft where its track is now (placed by TycoonModes): nothing to fly, only to look.
## The card names the mission and the phase; the result card says what happened, with "Ver no
## mapa" (the solar-system map on this mission) and the way back. Camera, map (M) and time warp
## (, and .) stay the player's.

## seconds of countdown before the ignition
@export var countdown := 3.0
## seconds in orbit before the result card (a target in Earth orbit)
@export var orbit_hold := 4.0
## seconds after the departure burn before the result card
@export var burn_hold := 6.0
## the warp stops this long before the departure burn (s, flight time)
@export var burn_lead := 20.0

const PHASE_COLORS := {"lost": CwPalette.DANGER, "orbit": CwPalette.AURORA_TEAL, "transfer": CwPalette.COMET_ICE}

var modes: TycoonModes
var world: FlightWorld
## "launch" or "follow"
var mode := "launch"
var track: Dictionary = {}
var entry: Dictionary = {}
var outcome := "full"
var target := "leo"
## countdown, ascent, coast, fall, orbit, wait, transfer, lost, done, follow
var phase := "countdown"

var _t := 0.0
var _phase_t := 0.0
var _fail_at := -1.0
var _burn: Dictionary = {}
var _apogee := 0.0
var _result_at := -1.0
var _result_kind := ""
var _assisted := false
var _lost_met := -1.0


func _ready() -> void:
	%Back.pressed.connect(go_back)
	%ResBack.pressed.connect(go_back)
	%Keep.pressed.connect(func() -> void: %Result.visible = false)
	%SeeMap.pressed.connect(see_map)
	%Result.visible = false


## Called by TycoonModes once the flight is ready. args: {"mode", "track", "entry"}.
func bind(m: TycoonModes, w: FlightWorld, args: Dictionary) -> void:
	modes = m
	world = w
	mode = String(args.get("mode", "launch"))
	track = args.get("track", {})
	entry = args.get("entry", {})
	outcome = String(track.get("outcome", entry.get("outcome", "full")))
	target = String(track.get("target", entry.get("target", "leo")))
	if outcome == "fail":
		if not track.is_empty() and float(track.get("lost_t", -1.0)) >= 0.0:
			_fail_at = float(track["lost_t"]) - float(track["launch_t"])
		else:
			_fail_at = SpaceTracking.fail_time(String(track.get("id", entry.get("code", ""))))
	world.flight_ended.connect(_on_ended)
	if mode == "follow":
		_set_phase("follow")
	_fill_static()


func _fill_static() -> void:
	var s := modes.main.state if modes and modes.main else null
	%Caption.text = tr("TY_TRK_FOLLOW_CAPTION") if mode == "follow" else tr("TY_TRK_WATCH_CAPTION")
	var code := String(track.get("code", entry.get("code", "")))
	var what := ""
	if s:
		var mt := s.mission_type(String(track.get("type", entry.get("type", ""))))
		what = "%s → %s" % [tr(String(mt.get("name_key", ""))), _target_name()]
	%Title.text = "%s · %s" % [code, what] if code != "" else what
	%Back.text = tr("TY_TRK_BACK_MAP") if mode == "follow" else tr("TY_TRK_BACK_CAMPUS")
	%ResBack.text = %Back.text
	%Hint.text = tr("TY_TRK_WARP_HINT")
	_refresh_phase()


func _target_name() -> String:
	var s := modes.main.state if modes and modes.main else null
	return tr(String(s.mission_target(target).get("name_key", target))) if s else target


## Out: the campus (a watched launch) or the map (a followed craft: TycoonModes reopens it).
func go_back() -> void:
	if world:
		world.revert_to_hangar()


## The solar-system map on this mission.
func see_map() -> void:
	if modes == null:
		return
	var id := String(track.get("id", ""))
	var m := modes
	m.close_mode()
	m.open_space_map.call_deferred(id)


func _unhandled_input(event: InputEvent) -> void:
	if %Result.visible and event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		%Result.visible = false
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------ flying it
func _process(delta: float) -> void:
	if world == null:
		return
	_t += delta
	_phase_t += delta
	match phase:
		"countdown":
			if _t >= countdown:
				world.set_autopilot(true)
				_set_phase("ascent")
		"ascent":
			_ascent()
		"coast":
			if world.active.body.vertical_speed() < 0.0:
				_apogee = world.active.body.altitude()
				_set_phase("fall")
				_result_soon("suborbital", 1.0)
		"orbit":
			_orbit()
		"wait":
			if world.time >= float(_burn["t"]):
				world.kick(_burn["dv"])
				world.hud.toast(tr("TY_TRK_PH_BURN"), CwPalette.IGNITION_HI)
				_set_phase("transfer")
				_result_soon("transfer", burn_hold)
	if _result_at >= 0.0 and _t >= _result_at:
		_result_at = -1.0
		show_result(_result_kind)
	_refresh_phase()


func _ascent() -> void:
	var v := world.active
	var met := world.mission_time()
	if outcome == "fail":
		if world.launched and world.liftoff_time >= 0.0 and met >= _fail_at:
			world.force_failure(_crash_reason())
			_lost_met = met
			_set_phase("lost")
		return
	if v.crashed:
		_lost_met = met
		_set_phase("lost")
		return
	if target == "suborbital":
		var el := FlightOrbit.elements(v.body.pos(), v.body.vel())
		if float(el["ap_alt"]) > 115000.0 and v.body.altitude() > 25000.0:
			world.set_autopilot(false)
			v.throttle = 0.0
			_set_phase("coast")
		return
	if world.in_orbit():
		_set_phase("orbit")
		return
	# a rocket that cannot make orbit by itself (out of propellant high up, or far too slow)
	var spent := v.thrust_n <= 0.0 and v.current_stage >= v.stage_count - 1 and met > 20.0
	if not _assisted and ((spent and v.body.altitude() > 60000.0 and v.body.vertical_speed() < 150.0) or met > 1100.0):
		_assisted = true
		world.assist_orbit()


func _orbit() -> void:
	if target in ["leo", "sso"] or not (target == "geo" or target == "comet" or target.begins_with("lunar")):
		if _result_at < 0.0 and _result_kind == "":
			_result_soon("partial" if outcome == "partial" else "orbit", orbit_hold)
		return
	if _phase_t < 2.0:
		return
	_burn = SpaceTracking.departure(target, world.active.body.pos(), world.active.body.vel(), world.time)
	if _burn.is_empty():
		_result_soon("orbit", orbit_hold)
		_set_phase("done")
		return
	if float(_burn["t"]) - burn_lead > world.time + 1.0:
		world.warp_to(float(_burn["t"]) - burn_lead)
	_set_phase("wait")


func _crash_reason() -> String:
	var cause := String(entry.get("cause_key", "")).to_upper()
	if "STAG" in cause or "SEP" in cause:
		return "TY_TRK_CRASH_STAGE"
	if _fail_at < 75.0 or "ENG" in cause or "MOTOR" in cause:
		return "TY_TRK_CRASH_ENGINE"
	return "CRASH_Q"


func _on_ended(report: Dictionary) -> void:
	if String(report.get("result", "")) == "crash" or phase == "lost":
		_set_phase("lost")
		show_result("lost")


func _set_phase(p: String) -> void:
	phase = p
	_phase_t = 0.0


func _result_soon(kind: String, seconds: float) -> void:
	_result_kind = kind
	_result_at = _t + seconds


# ------------------------------------------------------------ texts
func _refresh_phase() -> void:
	var text := ""
	var col := CwPalette.TEXT
	match phase:
		"countdown":
			text = tr("TY_TRK_PH_COUNTDOWN") % ceili(maxf(countdown - _t, 0.0))
			col = CwPalette.IGNITION
		"ascent":
			text = tr("TY_TRK_PH_ASCENT") % FlightHUD.fmt_dist(world.active.body.altitude())
		"coast":
			text = tr("TY_TRK_PH_COAST") % FlightHUD.fmt_dist(world.active.body.altitude())
		"fall":
			text = tr("TY_TRK_PH_FALL")
		"orbit", "done":
			text = tr("TY_TRK_PH_ORBIT")
			col = PHASE_COLORS["orbit"]
		"wait":
			text = tr("TY_TRK_PH_WAIT") % FlightHUD.fmt_time(maxf(float(_burn.get("t", world.time)) - world.time, 0.0))
		"transfer":
			text = tr("TY_TRK_PH_TRANSFER") % _target_name()
			col = PHASE_COLORS["transfer"]
		"lost":
			text = tr("TY_TRK_PH_LOST")
			col = PHASE_COLORS["lost"]
		"follow":
			var s := modes.main.state if modes and modes.main else null
			if s and not track.is_empty():
				var t := SpaceTracking.now(s)
				text = SpaceMapOverlay.where_text(s, track, t)
	%Phase.text = text
	%Phase.add_theme_color_override("font_color", col)


## The result card: what the watched launch did ("lost", "orbit", "partial", "transfer",
## "suborbital").
func show_result(kind: String) -> void:
	_result_kind = kind
	var code := String(track.get("code", entry.get("code", "")))
	var v := world.active
	var el := FlightOrbit.elements(v.body.pos(), v.body.vel(), world.sys.mu[world.soi], world.sys.radius[world.soi])
	%ResCause.visible = false
	match kind:
		"lost":
			%ResTitle.text = tr("TY_TRK_RES_LOST")
			%ResText.text = tr("TY_TRK_RES_LOST_TEXT") % [code, FlightHUD.fmt_time(_lost_met if _lost_met >= 0.0 else world.mission_time())]
			var ck := String(entry.get("cause_key", ""))
			if ck != "":
				%ResCause.text = tr("TY_TRK_RES_CAUSE") % tr(ck)
				%ResCause.visible = true
		"orbit":
			%ResTitle.text = tr("TY_TRK_RES_ORBIT")
			%ResText.text = tr("TY_TRK_RES_ORBIT_TEXT") % [code, FlightHUD.fmt_dist(float(el["ap_alt"])),
				FlightHUD.fmt_dist(float(el["pe_alt"]))]
		"partial":
			%ResTitle.text = tr("TY_TRK_RES_PARTIAL")
			%ResText.text = tr("TY_TRK_RES_PARTIAL_TEXT")
		"transfer":
			%ResTitle.text = tr("TY_TRK_RES_TRANSFER")
			%ResText.text = tr("TY_TRK_RES_TRANSFER_TEXT") % [code, _target_name()]
		"suborbital":
			%ResTitle.text = tr("TY_TRK_RES_SUBORBITAL")
			%ResText.text = tr("TY_TRK_RES_SUBORBITAL_TEXT") % [code, FlightHUD.fmt_dist(_apogee)]
	var col: Color = CwPalette.DANGER if kind == "lost" else (CwPalette.WARNING if kind == "partial" else CwPalette.AURORA_TEAL)
	%ResTitle.add_theme_color_override("font_color", col)
	%SeeMap.visible = not String(track.get("id", "")).is_empty()
	%Result.visible = true
