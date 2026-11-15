class_name RoverHUD
extends CanvasLayer
## HUD of the rover drive (scenes/rover/rover_hud.tscn). Layout, theme and static texts live in
## the scene; this script only fills data and duplicates its hidden templates (objective rows,
## tool buttons, map markers, toasts). Texts: i18n/rover_strings.csv.
##   mission card   body, rover, gravity / sun / radio delay, the objectives (done ones ticked)
##   mini-map       a top-down orthographic camera over the rover (its own SubViewport, north = -Z
##                  up) with a star per point of interest (gold: an objective, dim: done / already
##                  used) and the rover's arrow pointing where it drives; it heads the top-right
##                  SideColumn, whose SideSlot takes other surface cards (side_slot(): the
##                  free-play challenge card) stacked under it
##   gauges         battery, power in / out, speed, distance, science, what the rover is doing
##   tools          one button per tool of the design (keys 1..7), F uses the right one on the
##                  point of interest in reach (the prompt says which)
##   toasts         the rover's messages, after the radio delay ("Enviando comando…" meanwhile)
##   pause (Esc)    the summary and "Voltar à Terra" (leave_requested)

signal leave_requested
signal paused_changed(on: bool)

const TOOL_ICONS := {"photo": "planet", "panorama": "planet", "scan": "star", "drill": "build", "sample": "crew",
	"weather": "comet", "drone": "twinkle", "hop": "rocket"}
const ICONS := "res://ui/cometworks/icons/%s.svg"
const TONE_ICONS := {"good": "check", "bad": "shield", "warn": "flame", "star": "star", "science": "research"}
## group of the rover HUD (SurfaceExplore docks its challenge card in side_slot())
const GROUP := &"rover_hud"
## the arrow texture (icons/pointer.svg) points down the screen at rotation 0
const ARROW_REST := PI
const TOAST_TIME := 3.2
const MAX_TOASTS := 4

var rover: RoverController
var session: SurfaceSession
var body_name_key := ""
var paused := false
var _tools: Array[String] = []
var _toasts: Array[Dictionary] = []
var _markers: Array[Control] = []
var _poi_list: Array[Node] = []
var _sending := 0.0
var _refresh := 0.0
var _complete_shown := false


func _ready() -> void:
	add_to_group(GROUP)
	%Continue.pressed.connect(func() -> void: set_paused(false))
	%Leave.pressed.connect(func() -> void: leave_requested.emit())


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and rover:
		_fill_static()
		_fill_objectives()
		_fill_tools()


## Binds the HUD to a rover and its session.
func bind(r: RoverController, s: SurfaceSession, profile: PlanetSurfaceProfile) -> void:
	rover = r
	session = s
	body_name_key = profile.name_key if profile else ""
	rover.message.connect(toast)
	rover.tool_started.connect(func(_t: StringName, secs: float) -> void:
		_sending = secs
		%SendingText.text = tr("RV_H_SENDING") % _secs(secs))
	if session:
		session.objective_reached.connect(func(_id: StringName) -> void: _fill_objectives())
	_fill_static()
	_fill_objectives()
	_fill_tools()
	refresh_markers()


## The column under the mini-map where other surface HUDs stack their cards.
func side_slot() -> Control:
	return %SideSlot


## Screen rotation of the mini-map arrow for a rover heading `yaw` (forward = (-sin, 0, -cos)).
## The map camera looks straight down with -Z up and +X right, so the forward vector on the map
## is (-sin yaw, -cos yaw); the texture rests pointing down (+Y), hence ARROW_REST.
static func map_arrow_rotation(yaw: float) -> float:
	return wrapf(ARROW_REST - yaw, -PI, PI)


func set_paused(on: bool) -> void:
	paused = on
	%Pause.visible = on
	if on and session:
		%PauseSummary.text = tr("RV_H_SUMMARY") % [session.done_count(), session.objectives.size(), roundi(session.science),
			fmt_m(rover.distance if rover else 0.0)]
		%PauseNote.text = tr("RV_H_LEAVE_NOTE")
	paused_changed.emit(on)


func _fill_static() -> void:
	%Caption.text = tr("RV_H_CAPTION") % tr(body_name_key)
	%Title.text = String(rover.design.get("name", ""))
	var st := rover.stats
	%Facts.text = tr("RV_H_FACTS") % [num(rover.gravity, 2), roundi(rover.sun_factor * 100.0), delay_text(float(st.get("delay_s", 1.0)))]
	%Delay.text = tr("RV_H_DELAY") % delay_text(float(st.get("delay_s", 1.0)) * 2.0)
	%Help.text = tr("RV_H_CONTROLS_HOP") if rover.has_tool(&"hop") else tr("RV_H_CONTROLS")


func _fill_objectives() -> void:
	var list: Array[Dictionary] = session.objectives if session else []
	var rows := TycoonHUD._copies(%ObjTemplate, list.size())
	for i in list.size():
		var o: Dictionary = list[i]
		var row := rows[i]
		var done := bool(o["done"])
		var lbl := row.get_node("Text") as Label
		lbl.text = tr(String(o.get("label_key", "RV_OBJ_" + String(o["kind"]).to_upper())))
		if String(o["kind"]) == "drive" and not done:
			lbl.text += "  (%s / %s)" % [fmt_m(rover.distance), fmt_m(float(o.get("amount", 100.0)))]
		lbl.modulate.a = 0.55 if done else 1.0
		var mark := row.get_node("Mark") as TextureRect
		mark.texture = load(ICONS % ("check" if done else "star"))
		mark.modulate = CwPalette.SUCCESS if done else CwPalette.IGNITION
	%ObjEmpty.visible = list.is_empty()
	if session and session.is_complete() and not _complete_shown:
		_complete_shown = true
		%Complete.visible = true
		var tw := create_tween()
		tw.tween_interval(4.0)
		tw.tween_callback(func() -> void: %Complete.visible = false)


func _fill_tools() -> void:
	_tools.clear()
	for t in rover.stats.get("tools", []):
		_tools.append(String(t))
	if rover.has_tool(&"photo"):
		_tools.insert(_tools.find("photo") + 1, "panorama")
	var btns := TycoonHUD._copies(%ToolTemplate, _tools.size())
	for i in _tools.size():
		var b := btns[i] as Button
		var t := _tools[i]
		b.set_meta("tool", t)
		b.text = "%d · %s" % [i + 1, tr("RV_TOOL_" + t.to_upper())]
		var ip := ICONS % String(TOOL_ICONS.get(t, "star"))
		if ResourceLoader.exists(ip):
			b.icon = load(ip)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: use_tool(String(b.get_meta("tool", ""))))


func use_tool(t: String) -> void:
	if rover == null or paused:
		return
	rover.use_tool(StringName(t))


## The tool F uses on the point of interest in reach ("" = none), and that POI.
func prompt_tool() -> Array:
	if rover == null:
		return ["", null]
	# an action that answers an open objective first, then one not used there yet
	var fallback := ["", null]
	for t in ["drill", "sample", "scan", "photo"]:
		if not rover.has_tool(StringName(t)):
			continue
		var n := rover.nearest_for(StringName(t))
		if n == null or (t == "photo" and not n.call("in_reach", rover.position)):
			continue
		if session and not session.objective_for(n, StringName(t)).is_empty():
			return [t, n]
		if String(fallback[0]) == "" and not (n.get("used") as Dictionary).has(t):
			fallback = [t, n]
	return fallback


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo or rover == null:
		return
	var k := (event as InputEventKey).physical_keycode
	if k == KEY_ESCAPE:
		set_paused(not paused)
		get_viewport().set_input_as_handled()
		return
	if paused:
		return
	if k >= KEY_1 and k <= KEY_9:
		var i := k - KEY_1
		if i < _tools.size():
			use_tool(_tools[i])
			get_viewport().set_input_as_handled()
	elif k == KEY_F:
		var pt := prompt_tool()
		if String(pt[0]) != "":
			use_tool(String(pt[0]))
		get_viewport().set_input_as_handled()
	elif k == KEY_SPACE and rover.has_tool(&"hop"):
		use_tool("hop")
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------ live
func _process(delta: float) -> void:
	if rover == null:
		return
	var frac := rover.power_frac()
	var bar := %BatteryBar as CwSegmentBar
	bar.value = frac
	bar.color = CwPalette.AURORA_TEAL if frac > 0.35 else (CwPalette.WARNING if frac > 0.12 else CwPalette.DANGER)
	%BatteryValue.text = "%d%%" % roundi(frac * 100.0)
	%PowerLine.text = tr("RV_H_POWER") % [roundi(rover.power_in), roundi(rover.power_out)]
	%Speed.text = tr("RV_H_KMH") % num(absf(rover.speed) * 3.6, 1)
	%Distance.text = fmt_m(rover.distance)
	%Science.text = str(roundi(session.science)) if session else "0"
	%Status.text = tr(status_key())
	_sending = maxf(_sending - delta, 0.0)
	%Sending.visible = _sending > 0.0
	_update_toasts(delta)
	_update_map()
	var pt := prompt_tool()
	%Prompt.visible = String(pt[0]) != "" and not paused
	if %Prompt.visible:
		var n: Node = pt[1]
		var nk := String(n.get("name_key"))
		if nk == "":
			nk = "RV_POI_" + String(n.get("kind")).to_upper()
		%PromptText.text = tr("RV_PROMPT") % [tr("RV_ACT_" + String(pt[0]).to_upper()), tr(nk)]
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.5
		_fill_objectives()


## What the rover is doing, as a translation key.
func status_key() -> String:
	if rover.busy > 0.0 and rover.busy_tool != &"":
		return "RV_ST_BUSY_" + String(rover.busy_tool).to_upper()
	if rover.airborne:
		return "RV_ST_AIR"
	if rover.blocked:
		return "RV_ST_BLOCKED"
	if rover.slipping:
		return "RV_ST_STEEP"
	if rover.power_frac() <= 0.001 and rover.power_in < rover.power_out:
		return "RV_ST_EMPTY"
	if rover.power_in > rover.power_out and absf(rover.speed) < 0.1 and rover.power_frac() < 0.999:
		return "RV_ST_CHARGING"
	if absf(rover.speed) > 0.1:
		return "RV_ST_DRIVING"
	return "RV_ST_READY"


func toast(key: String, args: Array = [], tone := "good") -> void:
	if key == "":
		return
	var text := tr(key)
	var targs: Array = []
	for a in args:
		targs.append(tr(String(a)) if a is String else a)
	if not targs.is_empty() and text.contains("%"):
		text = text % targs
	_toasts.push_front({"text": text, "tone": tone, "t": TOAST_TIME})
	while _toasts.size() > MAX_TOASTS:
		_toasts.pop_back()
	_draw_toasts()


func _update_toasts(delta: float) -> void:
	var changed := false
	for t in _toasts.duplicate():
		t["t"] = float(t["t"]) - delta
		if float(t["t"]) <= 0.0:
			_toasts.erase(t)
			changed = true
	if changed:
		_draw_toasts()
	var rows := (%Toasts as Control).get_children()
	var i := 0
	for c in rows:
		if c == %ToastTemplate or not (c as Control).visible:
			continue
		if i < _toasts.size():
			(c as Control).modulate.a = clampf(float(_toasts[i]["t"]) / 0.4, 0.0, 1.0)
		i += 1


func _draw_toasts() -> void:
	var rows := TycoonHUD._copies(%ToastTemplate, _toasts.size())
	for i in _toasts.size():
		var t: Dictionary = _toasts[i]
		(rows[i].get_node("Row/Text") as Label).text = String(t["text"])
		var ic := rows[i].get_node("Row/Icon") as TextureRect
		ic.texture = load(ICONS % String(TONE_ICONS.get(String(t["tone"]), "star")))
		ic.modulate = {"good": CwPalette.SUCCESS, "bad": CwPalette.DANGER, "warn": CwPalette.WARNING,
			"star": CwPalette.IGNITION, "science": CwPalette.COMET_ICE}.get(String(t["tone"]), CwPalette.INK)


# ------------------------------------------------------------ mini-map
func refresh_markers() -> void:
	_poi_list.clear()
	if rover:
		for n in rover.interactables:
			if is_instance_valid(n):
				_poi_list.append(n)
	_markers = TycoonHUD._copies(%MarkerTemplate, _poi_list.size())


func _update_map() -> void:
	var cam := %MapCam as Camera3D
	cam.global_position = Vector3(rover.position.x, rover.position.y + 160.0, rover.position.z)
	var box := %MapBox as Control
	var sz := box.size
	var px := sz.x / cam.size
	var arrow := %RoverArrow as Control
	arrow.position = sz * 0.5 - arrow.size * 0.5
	arrow.rotation = map_arrow_rotation(rover.yaw)
	for i in _poi_list.size():
		if i >= _markers.size():
			break
		var n := _poi_list[i]
		var m := _markers[i]
		if not is_instance_valid(n):
			m.visible = false
			continue
		var p := (n as Node3D).global_position - rover.position
		var pos := sz * 0.5 + Vector2(p.x, p.z) * px
		var inside := Rect2(Vector2.ZERO, sz).grow(-6.0).has_point(pos)
		pos = pos.clamp(Vector2(6, 6), sz - Vector2(6, 6))
		m.position = pos - m.size * 0.5
		var wanted := false
		if session:
			for a in ["reach", "photo", "scan", "drill", "sample", "drone"]:
				if not session.objective_for(n, StringName(a)).is_empty():
					wanted = true
					break
		var used := not (n.get("used") as Dictionary).is_empty() or bool(n.get("was_reached"))
		m.modulate = CwPalette.BUTTER if wanted else (Color(1, 1, 1, 0.45) if used else CwPalette.ICE)
		m.scale = Vector2.ONE * (1.25 if wanted else 0.9) * (1.0 if inside else 0.8)
		m.visible = true


# ------------------------------------------------------------ formats
static func num(v: float, decimals: int = 1) -> String:
	var s := String.num(v, decimals) if decimals > 0 else str(roundi(v))
	if decimals > 0 and not s.contains("."):
		s += "." + "0".repeat(decimals)
	if TranslationServer.get_locale().begins_with("pt"):
		s = s.replace(".", ",")
	return s


static func fmt_m(m: float) -> String:
	if m >= 1000.0:
		return "%s km" % num(m / 1000.0, 2)
	return "%d m" % roundi(m)


static func _secs(s: float) -> String:
	return "%s s" % num(s, 1)


## A radio delay in plain words: "2,6 s", "12 min", "1 h 20 min".
static func delay_text(seconds: float) -> String:
	if seconds < 60.0:
		return "%s s" % num(seconds, 1)
	var mins := roundi(seconds / 60.0)
	if mins < 60:
		return "%d min" % mins
	return "%d h %d min" % [mins / 60, mins % 60]
