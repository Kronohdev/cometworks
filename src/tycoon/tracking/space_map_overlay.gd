class_name SpaceMapOverlay
extends Control
## The campus' "Mapa do Sistema Solar" (scenes/tycoon/tracking/space_map_overlay.tscn), laid over
## the flight's map by TycoonModes.open_space_map (the flight scene in its map-only mode: the
## real-scale map with the planets, their orbits and labels). This adds the missions in space
## (SpaceTracking): a marker per craft in its agency's colour (the rivals' too), its path drawn
## with the map's own lines (FlightMap.new_line), the list panel to jump between them and the
## selected one's card ("Acompanhar" opens it up close in the 3D flight, TycoonModes.open_follow).
## The header also shows the real calendar date of that time (the planets are where they really
## are that day, FlightSolar on the ephemeris) and how far the comet Mae-Gelo is from the Sun.
## Bodies are drawn at readable sizes (FlightMap.readable); distances and orbits stay real.
## The map's time is the campus calendar (FlightWorld.clock_source): the clock keeps running at
## its speed (the header's keys change it, pause included), so the crafts and the planets move.
## Orbits too fast to follow at that speed (a low orbit goes round dozens of times a second) turn
## at `fast_orbit_seconds` per revolution instead: visual only, the track keeps the real place.
## Everything visual is in the scene: rows and markers are copies of its hidden templates
## (TycoonHUD._copies); Space pauses as on the campus; Esc lets go of the selected craft, then
## leaves (FlightWorld; M leaves too).

## seconds of real time per revolution for orbits too fast to follow at the clock's speed
@export var fast_orbit_seconds := 8.0
## path widths (px): every craft's current leg, the selected craft's whole path
@export var line_width := 2.0
@export var selected_width := 3.2
## how much a lost craft (and its path) fades
@export_range(0.0, 1.0, 0.05) var lost_alpha := 0.4
## markers and labels get this much lighter than the agency colour (the map is dark)
@export_range(0.0, 1.0, 0.05) var marker_lighten := 0.25

const STATUS_COLORS := {"flight": CwPalette.COMET_ICE, "orbit": CwPalette.AURORA_TEAL, "arrived": CwPalette.AURORA_VIOLET,
	"lost": CwPalette.DANGER}
const FILTERS := ["all", "mine", "rivals"]

var modes: TycoonModes
var world: FlightWorld
var map: FlightMap
var state: TycoonState
var clock: TycoonClock
## the selected track's id ("" = none)
var selected := ""
var _selecting := false
## "all", "mine" or "rivals"
var filter := "all"

var _frac := 0.0
var _vis := 0.0
var _lines: Dictionary = {}
var _list_dirty := true
var _text_timer := 0.0


func _ready() -> void:
	%Back.pressed.connect(func() -> void:
		if world:
			world.revert_to_hangar())
	%Pause.pressed.connect(_set_speed.bind(0))
	%S1.pressed.connect(_set_speed.bind(1))
	%S2.pressed.connect(_set_speed.bind(2))
	%S3.pressed.connect(_set_speed.bind(3))
	%FilterAll.pressed.connect(set_filter.bind("all"))
	%FilterMine.pressed.connect(set_filter.bind("mine"))
	%FilterRivals.pressed.connect(set_filter.bind("rivals"))
	%Watch.pressed.connect(watch_selected)
	%Drive.pressed.connect(drive_selected)
	%Release.pressed.connect(select.bind(""))
	%Detail.visible = false


## Called by TycoonModes once the flight (map only) is ready. args: {"focus": track id or ""}.
func bind(m: TycoonModes, w: FlightWorld, args: Dictionary) -> void:
	modes = m
	world = w
	map = w.map
	state = m.main.state
	clock = m.main.clock
	_frac = clock.week_fraction()
	world.clock_source = campaign_time
	world.time = campaign_time()
	map.tracked_focus = _focus_info
	var hint := map.get_node_or_null("%Hint") as Control
	if hint:
		hint.visible = false   # the flight map's maneuver hint: nothing to plan here
		var pill := hint.get_parent() as Control
		if pill and pill != map.overlay:
			pill.visible = false   # its pill too (it would sit there empty)
	SpaceTracking.sync(state)
	state.changed.connect(_mark_dirty)
	clock.speed_changed.connect(_press_speed)
	_press_speed(clock.speed)
	map.set_readable(true)
	map.set_scale_mode(1, true)
	map.focus_changed.connect(_on_map_focus)
	var focus := String(args.get("focus", ""))
	if focus != "" and not SpaceTracking.find(state, focus).is_empty():
		select(focus)
	_fill_list()


## The fraction of the week on show (kept while the clock is paused, so the map does not jump).
func week_fraction() -> float:
	return _frac


## The map's time (FlightWorld.clock_source): the campus calendar in seconds.
func campaign_time() -> float:
	if clock.speed > 0:
		_frac = clock.week_fraction()
	return SpaceTracking.now(state, _frac)


func _set_speed(sp: int) -> void:
	clock.set_speed(sp)


func _press_speed(sp: int) -> void:
	var keys: Array = [%Pause, %S1, %S2, %S3]
	for i in keys.size():
		(keys[i] as Button).set_pressed_no_signal(i == sp)


func _mark_dirty() -> void:
	_list_dirty = true


func set_filter(f: String) -> void:
	filter = f
	%FilterAll.set_pressed_no_signal(f == "all")
	%FilterMine.set_pressed_no_signal(f == "mine")
	%FilterRivals.set_pressed_no_signal(f == "rivals")
	if selected != "" and not _passes(SpaceTracking.find(state, selected)):
		select("")
	_fill_list()


func _passes(trk: Dictionary) -> bool:
	if trk.is_empty():
		return false
	var mine := String(trk.get("owner", "")) == SpaceTracking.PLAYER
	return filter == "all" or (filter == "mine" and mine) or (filter == "rivals" and not mine)


## The tracks on show, in list order: still flying first, newest first.
func shown_tracks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for trk: Dictionary in SpaceTracking.missions(state):
		if _passes(trk):
			out.append(trk)
	var t := world.time if world else SpaceTracking.now(state)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la := SpaceTracking.status_at(a, t) == "lost"
		var lb := SpaceTracking.status_at(b, t) == "lost"
		if la != lb:
			return lb
		return float(a["launch_t"]) > float(b["launch_t"]))
	return out


# ------------------------------------------------------------ selection
## Selects a track (the map focuses it and follows it); "" lets go (the map stays on its body).
func select(id: String) -> void:
	var trk := SpaceTracking.find(state, id) if id != "" else {}
	_selecting = true
	if map:
		map.set_focus(map.frame_body(), true)
	selected = id if not trk.is_empty() else ""
	if map and selected != "":
		map.set_focus(-2, true)
		map.dist = _frame_distance(trk)
		map.pitch = maxf(map.pitch, 0.45)
	_selecting = false
	_fill_list()
	_fill_detail()


## The map went to a body by itself (a click on it, the ‹ › arrows, Tab, Solar): it no longer
## follows the selected craft, so the list and the detail let go of it too.
func _on_map_focus(f: int) -> void:
	if _selecting or f == -2 or selected == "":
		return
	selected = ""
	_fill_list()
	_fill_detail()


func _focus_info() -> Dictionary:
	var trk := SpaceTracking.find(state, selected)
	if trk.is_empty():
		return {}
	var st := display_state(trk, world.time)
	return {"body": st["body"], "pos": st["pos"], "name": String(trk.get("code", ""))}


## Map distance that frames a craft's path: its orbit, or a transfer's span.
func _frame_distance(trk: Dictionary) -> float:
	var sys := FlightSolar.get_system()
	var t := world.time
	var st := SpaceTracking.state_at(trk, t)
	var b := int(st["body"])
	var size := FlightOrbit.length(st["pos"])
	var c := SpaceTracking.leg_conic(trk, int(st["leg"]))
	if c and c.e < 1.0 and c.ra < sys.soi[b]:
		size = c.ra
	elif c:
		size = maxf(size, sys.sma[sys.moon] if b == sys.earth else size) * 1.2
	return maxf(size * FlightMap.K * 4.5, sys.radius[b] * FlightMap.K * 3.0)


## "Acompanhar": the selected craft up close in the 3D flight.
func watch_selected() -> void:
	if selected == "" or modes == null:
		return
	modes.open_follow(selected)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := (event as InputEventKey).keycode
	if k == KEY_SPACE and clock:
		clock.toggle_pause()   # as on the campus
		get_viewport().set_input_as_handled()
	elif k == KEY_ESCAPE and selected != "":
		select("")
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------ per frame
## Where a craft is drawn at time t: its track's place, except on an orbit too fast to follow at
## the clock's speed, which turns at `fast_orbit_seconds` per revolution (visual only).
func display_state(trk: Dictionary, t: float) -> Dictionary:
	var st := SpaceTracking.state_at(trk, t)
	if clock == null or clock.speed == 0 or String(st["status"]) == "lost" or String(st["kind"]) == "fixed":
		return st
	var c := SpaceTracking.leg_conic(trk, int(st["leg"]))
	if c == null or c.e >= 1.0:
		return st
	var game_rate := SpaceTracking.WEEK / maxf(clock.seconds_per_week(), 0.001)
	if c.period / game_rate >= fast_orbit_seconds:
		return st
	var leg: Dictionary = trk["legs"][int(st["leg"])]
	var t1 := float(leg["t1"])
	if t1 >= 0.0 and t1 - t < c.period:
		return st
	var tv := float(leg["t0"]) + c.period * fposmod(_vis / fast_orbit_seconds + SpaceTracking.hash01(String(trk["id"])), 1.0)
	var s := c.state_at(tv)
	st["pos"] = PackedFloat64Array([s[0], s[1], s[2]])
	st["vel"] = PackedFloat64Array([s[3], s[4], s[5]])
	return st


func _process(delta: float) -> void:
	if world == null or map == null or not map.visible:
		return
	if clock.speed > 0:
		_vis += delta
	var t := world.time
	var shown := shown_tracks()
	var marks := TycoonHUD._copies(%MarkerTemplate, shown.size())
	var used := {}
	var placed: Array[Rect2] = []
	var cam := map.camera
	for i in shown.size():
		var trk := shown[i]
		var mk := marks[i]
		var st := display_state(trk, t)
		var lost := String(st["status"]) == "lost"
		var col := SpaceTracking.color_of(state, trk)
		_place_lines(trk, t, lost, col, used)
		var p := map.map_position(int(st["body"]), st["pos"])
		if cam.is_position_behind(p):
			mk.visible = false
			continue
		var sp := cam.unproject_position(p)
		mk.visible = Rect2(Vector2.ZERO, size).has_point(sp)
		if not mk.visible:
			continue
		mk.position = sp - mk.size * 0.5
		mk.modulate.a = lost_alpha if lost else (0.45 if map.occluded(p) else 1.0)
		var id := String(trk["id"])
		if mk is OpsMarker:
			(mk as OpsMarker).color = col.lightened(marker_lighten)
			(mk as OpsMarker).selected = id == selected
		var code := mk.get_node("Code") as Label
		code.text = String(trk.get("code", ""))
		if not code.has_meta("home"):
			code.set_meta("home", code.position)
		code.position = code.get_meta("home")
		for k in 5:
			var r := Rect2(mk.position + code.position, code.size)
			var hit := false
			for q: Rect2 in placed:
				hit = hit or q.intersects(r)
			if not hit:
				break
			code.position.y += 14.0
		placed.append(Rect2(mk.position + code.position, code.size))
		mk.set_meta("track_id", id)
		if not mk.has_meta("wired"):
			mk.set_meta("wired", true)
			mk.gui_input.connect(_on_marker_input.bind(mk))
	for key: String in _lines:
		if not used.has(key):
			(_lines[key] as MeshInstance3D).visible = false
	_text_timer -= delta
	if _text_timer <= 0.0 or _list_dirty:
		_text_timer = 0.25
		%DateValue.text = "%02d · %02d" % [state.year(), state.week()]
		var sys := FlightSolar.get_system()
		%RealDate.text = SolarSystemOverlay.date_text(sys.date_at(t))
		if sys.comet >= 0:
			%Comet.text = tr("SSM_COMET_NOW") % comet_distance_text(sys.distance_at(sys.comet, t))
		if _list_dirty:
			_fill_list()
		_refresh_rows(t)
		_fill_detail()


func _on_marker_input(e: InputEvent, mk: Control) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
			and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		select(String(mk.get_meta("track_id", "")))
		accept_event()


## The path of a track: the leg it flies (every craft), the whole path (the selected one); each
## leg is drawn around its body's place now, as the map draws its own trajectories.
func _place_lines(trk: Dictionary, t: float, lost: bool, col: Color, used: Dictionary) -> void:
	var id := String(trk["id"])
	var sel := id == selected
	var legs: Array = trk["legs"]
	var cur := SpaceTracking.leg_index(trk, t)
	if lost and String(trk.get("outcome", "")) == "fail":
		return
	var sys := FlightSolar.get_system()
	for i in legs.size():
		var leg: Dictionary = legs[i]
		if String(leg["kind"]) == "fixed" or (i != cur and not sel) or (i < cur and sel and i < cur - 1):
			continue
		var key := "%s#%d" % [id, i]
		var mi: MeshInstance3D = _lines.get(key)
		if mi == null:
			mi = map.new_line()
			mi.mesh = FlightMapLines.polyline(SpaceTracking.leg_points(trk, i), FlightMap.K)
			mi.set_instance_shader_parameter(&"gap", Vector4.ZERO)
			mi.set_instance_shader_parameter(&"dash", 0.0)
			_lines[key] = mi
		used[key] = true
		mi.visible = true
		mi.position = map.body_map(sys.index_of(String(leg["body"])), t)
		var a := lost_alpha if lost else (0.95 if sel else 0.6)
		mi.set_instance_shader_parameter(&"line_color", Color(col.lightened(marker_lighten), a))
		mi.set_instance_shader_parameter(&"line_width", selected_width if sel else line_width)


# ------------------------------------------------------------ panels
func _fill_list() -> void:
	_list_dirty = false
	if state == null:
		return
	var shown := shown_tracks()
	var rows := TycoonHUD._copies(%RowTemplate, shown.size())
	%Empty.visible = shown.is_empty()
	var t := world.time if world else SpaceTracking.now(state)
	var active := 0
	for trk: Dictionary in SpaceTracking.missions(state):
		if SpaceTracking.status_at(trk, t) != "lost":
			active += 1
	%Count.text = tr("TY_TRK_COUNT") % active
	for i in shown.size():
		var row := rows[i] as Button
		var trk := shown[i]
		row.set_meta("track_id", String(trk["id"]))
		if not row.has_meta("wired"):
			row.set_meta("wired", true)
			row.pressed.connect(func() -> void: select(String(row.get_meta("track_id", ""))))
		(row.get_node("HBox/Dot") as ColorRect).color = SpaceTracking.color_of(state, trk)
		(row.get_node("HBox/Text/Code") as Label).text = String(trk.get("code", ""))
		var mt := state.mission_type(String(trk.get("type", "")))
		var tg := state.mission_target(String(trk.get("target", "")))
		(row.get_node("HBox/Text/What") as Label).text = "%s · %s" % [tr(String(mt.get("name_key", ""))),
			tr(String(tg.get("name_key", "")))]
	_refresh_rows(t)


func _refresh_rows(t: float) -> void:
	for c in %RowTemplate.get_parent().get_children():
		if c == %RowTemplate or not c.has_meta("track_id"):
			continue
		var trk := SpaceTracking.find(state, String(c.get_meta("track_id")))
		if trk.is_empty():
			continue
		var status := SpaceTracking.status_at(trk, t)
		var lab := c.get_node("HBox/Status") as Label
		lab.text = tr(SpaceTracking.status_key(status))
		lab.add_theme_color_override("font_color", STATUS_COLORS.get(status, CwPalette.TEXT))
		(c as Button).set_pressed_no_signal(String(trk["id"]) == selected)
		(c as Control).modulate.a = 0.6 if status == "lost" else 1.0


func _fill_detail() -> void:
	var trk := SpaceTracking.find(state, selected) if state else {}
	%Detail.visible = not trk.is_empty()
	if trk.is_empty():
		return
	var t := world.time if world else SpaceTracking.now(state)
	var col := SpaceTracking.color_of(state, trk)
	%DCode.text = String(trk.get("code", ""))
	%DOwner.text = owner_name(state, trk)
	%DOwner.add_theme_color_override("font_color", CwPalette.ink(col))
	var mt := state.mission_type(String(trk.get("type", "")))
	var tg := state.mission_target(String(trk.get("target", "")))
	%DWhat.text = "%s · %s" % [tr(String(mt.get("name_key", ""))), tr(String(tg.get("name_key", "")))]
	var status := SpaceTracking.status_at(trk, t)
	%DStatus.text = tr(SpaceTracking.status_key(status))
	%DStatus.add_theme_color_override("font_color", STATUS_COLORS.get(status, CwPalette.TEXT))
	%DWhere.text = where_text(state, trk, t)
	%DLaunched.text = tr("TY_TRK_LAUNCHED") % date_text(state, float(trk["launch_t"]))
	var ok := SpaceTracking.can_follow(trk, t)
	%Watch.disabled = not ok
	%WatchNote.visible = not ok
	%WatchNote.text = tr("TY_TRK_WATCH_LOST") if status == "lost" else tr("TY_TRK_WATCH_NO")
	# a rover mission on the surface: drive it (src/rover/rover_missions.gd)
	%Drive.visible = RoverMissions.can_drive(state, RoverMissions.mission_of_track(state, trk))


## "Controlar o rover": the selected rover mission's surface; back to the map on it afterwards.
func drive_selected() -> void:
	var trk := SpaceTracking.find(state, selected) if state else {}
	var m := RoverMissions.mission_of_track(state, trk)
	if modes == null or not RoverMissions.can_drive(state, m):
		return
	var mid := String(m["id"])
	var tid := selected
	var s := RoverMissions.start_drive(state, mid)
	var md := modes
	var st := state
	md.open_surface(s, func(r: Dictionary) -> void:
		RoverMissions.apply_result(st, mid, r)
		md.open_space_map.call_deferred(tid))


## "31,6 UA" / "0,92 AU": the comet's distance from the Sun.
static func comet_distance_text(m: float) -> String:
	var au := m / 1.495978707e11
	return "%s %s" % [SolarSystemOverlay.num(au, 2 if au < 10.0 else 1), TranslationServer.translate("SSM_AU")]


# ------------------------------------------------------------ words (also the launch watch's)
static func owner_name(s: TycoonState, trk: Dictionary) -> String:
	var owner := String(trk.get("owner", SpaceTracking.PLAYER))
	if owner == SpaceTracking.PLAYER:
		return s.agency_name
	return TranslationServer.translate(s.race.agency_name(owner)) if s.race else owner


## Campaign date of a time (s): "A3 · S12".
static func date_text(s: TycoonState, t: float) -> String:
	var w := int(floor(t / SpaceTracking.WEEK))
	return TranslationServer.translate("TY_TRK_DATE") % [w / s.weeks_per_year() + 1, w % s.weeks_per_year() + 1]


## "3 d 04 h" / "5 h 12 min" / "40 min".
static func eta_text(seconds: float) -> String:
	var m := int(seconds / 60.0)
	if m >= 1440:
		return "%d d %02d h" % [m / 1440, (m % 1440) / 60]
	if m >= 60:
		return "%d h %02d min" % [m / 60, m % 60]
	return "%d min" % maxi(m, 1)


## Where a craft is, in words ("Em órbita da Terra · 420 km", "A caminho da Lua · chega em 2 d").
static func where_text(s: TycoonState, trk: Dictionary, t: float) -> String:
	var sys := FlightSolar.get_system()
	var st := SpaceTracking.state_at(trk, t)
	var b := int(st["body"])
	var target := String(trk.get("target", ""))
	var target_name := TranslationServer.translate(String(s.mission_target(target).get("name_key", target)))
	match String(st["status"]):
		"lost":
			return TranslationServer.translate("TY_TRK_WHERE_LOST") % date_text(s, float(trk.get("lost_t", t)))
		"flight":
			var left := SpaceTracking.arrival_in(trk, t)
			if left > 0.0 and t >= float(trk["launch_t"]) + SpaceTracking.ASCENT_S:
				return TranslationServer.translate("TY_TRK_WHERE_TRANSFER") % [target_name, eta_text(left)]
			return TranslationServer.translate("TY_TRK_WHERE_ASCENT")
		"orbit":
			var alt := FlightOrbit.length(st["pos"]) - sys.radius[b]
			return TranslationServer.translate("TY_TRK_WHERE_ORBIT") % [sys.display_name(b), FlightHUD.fmt_dist(alt)]
		_:
			if target == "suborbital":
				return TranslationServer.translate("TY_TRK_WHERE_HOME")
			if target == "comet":
				return TranslationServer.translate("TY_TRK_WHERE_COMET")
			if target == "lunar_flyby":
				return TranslationServer.translate("TY_TRK_WHERE_FLYBY")
			return TranslationServer.translate("TY_TRK_WHERE_SURFACE") % sys.display_name(b)
