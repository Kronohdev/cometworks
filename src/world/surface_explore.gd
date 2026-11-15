class_name SurfaceExplore
extends Node
## The free-play layer of a planet surface (scenes/surface/explore/surface_explore.tscn, the
## "Explore" node of every scenes/surface/<body>_surface.tscn). It runs whoever explores the
## surface: the rover of the drive scene (RoverDrive points the PlanetSurface focus at it and
## the rover reaches / uses its tools on the SurfaceInteractables itself) or, without a rover,
## the surface's fly camera (a little drone: this node then reaches places within a few metres
## and F investigates the nearest one).
##   discoveries  the first reach / action at a SurfacePoi is logged (SurfaceLog), shows its
##                card with the real-science fact, adds a note to the career's journal and
##                science (research points in a career, outside a rover mission)
##   finds        SurfaceCollectible pick-ups, logged per body (hidden on the next visit)
##   challenges   reach_before / jump / deliver / find_all / collect_all
##                (data/surface_explore.json, start rings: SurfaceChallenge nodes)
##   log          J opens the field log of the body (places, facts with sources, finds, challenges)
##   photo mode   P: the HUDs hide, the photo camera orbits the explorer (drag / arrows, wheel),
##                Enter or a click saves a picture to user://photos/ and every point of interest
##                in the frame counts as photographed
## All the UI is authored in the scene; this script fills it and duplicates hidden templates.
## Keys: J log · P photo mode · F investigate (drone only) · Esc back (drone only).

signal discovered(poi_id: String, first: bool)
signal found_collectible(id: String)
signal challenge_done(id: String, seconds: float)
signal leave_requested

const DATA_PATH := "res://data/surface_explore.json"
const PHOTO_DIR := "user://photos"
const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const CARD_TIME := 6.0
## drone (fly camera): reach a place flying lower than this above the ground
const DRONE_MAX_HEIGHT := 14.0
const DRONE_EXTRA_REACH := 3.0
## rovers: off the ground higher than this counts as airborne (when the explorer has no `airborne`)
const AIR_HEIGHT := 0.8

static var _data: Dictionary = {}

## the body (empty = the PlanetSurface profile id)
@export var body_id: StringName = &""
## show the UI (the screenshot tools turn it off)
@export var ui_visible: bool = true

var planet: PlanetSurface
var field_log: SurfaceLog
var state: TycoonState
var explorer: Node3D
var pois: Array[SurfacePoi] = []
var collectibles: Array[SurfaceCollectible] = []
## running challenges: {"entry", "node", "phase": "idle" | "armed" | "running" | "carry", "t", "air", "msg_t"}
var challenges: Array[Dictionary] = []
var photo_mode := false

var _bound := false
var _scan_t := 0.0
var _card_t := 0.0
var _ch_focus: Dictionary = {}
var _card_home: Array = []
var _ch_msg := ""
var _ch_msg_t := 0.0
var _hidden_layers: Array[CanvasLayer] = []
var _prev_cam: Camera3D
var _orbit := Vector3(0.6, 0.35, 14.0)  # yaw, pitch, distance
var _drag := false
var _paused_explorer: Node

@onready var photo_cam: Camera3D = $PhotoCamera
@onready var ui: CanvasLayer = $UI
## the challenge card (held here: with a rover it moves under the rover HUD's mini-map)
@onready var ch_card: Control = %ChallengeCard
@onready var _ch_name: Label = %ChName
@onready var _ch_status: Label = %ChStatus
@onready var _ch_timer: Label = %ChTimer


# ------------------------------------------------------------ data
static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data = parsed if parsed is Dictionary else {"bodies": {}}
	return _data


static func body_data(id: String) -> Dictionary:
	return (data().get("bodies", {}) as Dictionary).get(id, {})


static func poi_entry(id: StringName) -> Dictionary:
	if id == &"":
		return {}
	for b: String in data().get("bodies", {}):
		for e: Dictionary in body_data(b).get("pois", []):
			if String(e.get("id", "")) == String(id):
				return e
	return {}


static func challenge_entry(id: StringName) -> Dictionary:
	if id == &"":
		return {}
	for b: String in data().get("bodies", {}):
		for e: Dictionary in body_data(b).get("challenges", []):
			if String(e.get("id", "")) == String(id):
				return e
	return {}


static func collectible_type(type_id: String) -> Dictionary:
	return (data().get("collectible_types", {}) as Dictionary).get(type_id, {})


# ------------------------------------------------------------ setup
func _ready() -> void:
	planet = _find_planet()
	%Card.visible = false
	ch_card.visible = false
	%Log.visible = false
	%Photo.visible = false
	%LogClose.pressed.connect(close_log)
	%Back.pressed.connect(leave)
	ui.visible = ui_visible
	_bind.call_deferred()


func _find_planet() -> PlanetSurface:
	var n := get_parent()
	while n and not (n is PlanetSurface):
		n = n.get_parent()
	return n as PlanetSurface


func _bind() -> void:
	if _bound or planet == null:
		return
	_bound = true
	if body_id == &"" and planet.profile:
		body_id = planet.profile.id
	state = _find_state()
	field_log = SurfaceLog.open(state)
	field_log.add_visit(String(body_id))
	for n in planet.find_children("*", "SurfacePoi", true, false):
		var p := n as SurfacePoi
		pois.append(p)
		p.interacted.connect(_on_poi.bind(p))
	for n in planet.find_children("*", "SurfaceCollectible", true, false):
		var c := n as SurfaceCollectible
		collectibles.append(c)
		if field_log.is_collected(String(body_id), collectible_id(c)):
			c.hide_collected()
		else:
			c.collected.connect(_on_collected)
	for e: Dictionary in body_data(String(body_id)).get("challenges", []):
		var node: SurfaceChallenge = null
		for n in planet.find_children("*", "SurfaceChallenge", true, false):
			if String((n as SurfaceChallenge).entry_id) == String(e.get("id", "")):
				node = n
		challenges.append({"entry": e, "node": node, "phase": "idle", "t": 0.0, "air": 0.0, "armed_t": 0.0})
	_refresh_explorer()
	_fill_chip()
	field_log.save()


## The career this surface runs in (TycoonMain.state up the tree), or null.
func _find_state() -> TycoonState:
	var n: Node = self
	while n:
		if "state" in n and n.get("state") is TycoonState:
			return n.get("state")
		n = n.get_parent()
	return null


func _refresh_explorer() -> void:
	var f := planet.get_focus() if planet else null
	if f != explorer:
		explorer = f
		var drone := not is_rover()
		%Help.visible = drone
		%Back.visible = drone
		_dock_challenge_card()
		_fill_chip()


## With a rover the challenge card stacks under the rover HUD's mini-map (its SideSlot, group
## RoverHUD.GROUP) instead of its own top-right spot, so the two never overlap; back without one.
func _dock_challenge_card() -> void:
	var slot: Control = null
	if is_rover():
		for h in get_tree().get_nodes_in_group(RoverHUD.GROUP):
			if h.has_method("side_slot"):
				slot = h.call("side_slot")
				break
	var home := ui.get_node("Root") as Control
	var target := slot if slot else home
	if ch_card.get_parent() == target:
		return
	if _card_home.is_empty():
		# its spot in this scene (anchors and offsets), to put it back
		_card_home = [ch_card.anchor_left, ch_card.anchor_top, ch_card.anchor_right, ch_card.anchor_bottom,
			ch_card.offset_left, ch_card.offset_top, ch_card.offset_right, ch_card.offset_bottom]
	ch_card.reparent(target, false)
	if slot:
		ch_card.layout_mode = 2  # a container child: the slot lays it out
		return
	ch_card.layout_mode = 1
	for i in 4:
		ch_card.set_anchor(i as Side, float(_card_home[i]))
		ch_card.set_offset(i as Side, float(_card_home[i + 4]))


func _exit_tree() -> void:
	# docked in a HUD that may outlive this node: take it along
	if ch_card and is_instance_valid(ch_card) and not is_ancestor_of(ch_card):
		ch_card.queue_free()


## The explorer is the drive scene's rover (it reaches places and uses tools itself).
func is_rover() -> bool:
	return explorer != null and explorer.has_method("refresh_interactables")


func collectible_id(c: SurfaceCollectible) -> String:
	return "%s:%s" % [body_id, c.name]


func set_ui_visible(on: bool) -> void:
	ui_visible = on
	if ui:
		ui.visible = on


# ------------------------------------------------------------ discoveries
func _on_poi(rover: Node, action: StringName, res: Dictionary, poi: SurfacePoi) -> void:
	if not bool(res.get("ok", true)):
		return
	var id := String(poi.get_interact_id())
	var b := String(body_id)
	var first := field_log.mark_found(b, id)
	field_log.mark_action(b, id, String(action))
	if first:
		_credit(poi.science)
		if state:
			Discovery.note(state, "TY_SX_NOTE_FOUND", [poi.name_key, String(body_data(b).get("name_key", ""))])
		show_card("TY_SX_CARD_NEW", tr(poi.name_key), tr(poi.fact_key()),
			tr("TY_SX_CARD_SCIENCE") % roundi(poi.science))
	elif not is_rover() and action != &"reach":
		show_card("TY_SX_CARD_" + String(action).to_upper(), tr(poi.name_key), tr(poi.fact_key()), "")
	_challenge_poi_event(id, action, rover)
	discovered.emit(id, first)
	_check_totals()
	_fill_chip()
	field_log.save()


func _on_collected(c: SurfaceCollectible) -> void:
	var b := String(body_id)
	var id := collectible_id(c)
	if not field_log.mark_collected(b, id):
		return
	_credit(c.science)
	var t := c.type_id()
	var fact := ""
	if t == "comet_crumb":
		var lore: Array = data().get("crumb_lore", [])
		fact = tr(String(lore[posmod(c.lore_index, lore.size())])) if not lore.is_empty() else ""
	else:
		fact = tr(String((body_data(b).get("collect_facts", {}) as Dictionary).get(t,
			collectible_type(t).get("desc_key", ""))))
	show_card("TY_SX_CARD_FIND", tr(String(collectible_type(t).get("name_key", ""))), fact,
		tr("TY_SX_CARD_FINDS") % [field_log.collected_count(b), collectibles.size()])
	found_collectible.emit(id)
	_check_totals()
	_fill_chip()
	field_log.save()


## Science: the rover mission's session gets it from the rover side; free play in a career
## turns it into research points (data research_per_science), once per thing logged.
func _credit(amount: float) -> void:
	if amount <= 0.0:
		return
	var s := SurfaceSession.current
	if s and not bool(s.context.get("sandbox", false)) and s.context.has("mission_id"):
		return
	if s:
		s.add_science(amount, &"explore")
	if state:
		state.research_points += amount * float(data().get("research_per_science", 0.5))


func show_card(kicker_key: String, title: String, fact: String, foot: String) -> void:
	%CardKicker.text = tr(kicker_key)
	%CardTitle.text = title
	%CardFact.text = fact
	%CardFact.visible = fact != ""
	%CardFoot.text = foot
	%CardFoot.visible = foot != ""
	%Card.visible = true
	%Card.modulate.a = 1.0
	_card_t = CARD_TIME


func _fill_chip() -> void:
	if field_log == null:
		return
	var b := String(body_id)
	var total_pois := pois.size()
	%Found.text = tr("TY_SX_CHIP_PLACES") % [field_log.found_count(b), total_pois]
	%Collected.text = tr("TY_SX_CHIP_FINDS") % [field_log.collected_count(b), collectibles.size()]
	%Hints.text = tr("TY_SX_CHIP_KEYS")


# ------------------------------------------------------------ challenges
func _check_totals() -> void:
	for ch in challenges:
		var e: Dictionary = ch["entry"]
		var t := String(e.get("type", ""))
		if t == "find_all" and not pois.is_empty():
			var all := true
			for p in pois:
				if not field_log.is_found(String(body_id), String(p.get_interact_id())):
					all = false
					break
			if all:
				_complete(ch, 0.0)
		elif t == "collect_all" and not collectibles.is_empty() and field_log.collected_count(String(body_id)) >= collectibles.size():
			_complete(ch, 0.0)


## Deliveries: the rover takes the sample with its sample / drill tool (the drone just reaches
## the spot), then reaching the lander completes it.
func _challenge_poi_event(id: String, action: StringName, _rover: Node) -> void:
	for ch in challenges:
		var e: Dictionary = ch["entry"]
		if String(e.get("type", "")) != "deliver":
			continue
		var takes := not is_rover() or action == &"sample" or action == &"drill"
		if id == String(e.get("from", "")) and ch["phase"] != "carry" and takes:
			ch["phase"] = "carry"
			_ch_focus = ch
			_say(ch, "TY_SX_CH_CARRY")
		elif id == String(e.get("to", "")) and ch["phase"] == "carry":
			_complete(ch, 0.0)


func _complete(ch: Dictionary, seconds: float) -> void:
	var e: Dictionary = ch["entry"]
	var id := String(e.get("id", ""))
	var was_done := bool(field_log.challenge(String(body_id), id).get("done", false))
	var t := String(e.get("type", ""))
	if was_done and (t == "find_all" or t == "collect_all"):
		return
	var r := field_log.record_challenge(String(body_id), id, seconds)
	ch["phase"] = "idle"
	if bool(r["first"]):
		_credit(float(e.get("science", 0.0)))
	var foot := tr("TY_SX_CARD_SCIENCE") % roundi(float(e.get("science", 0.0))) if bool(r["first"]) else ""
	if seconds > 0.0:
		foot = (tr("TY_SX_CH_TIME") % seconds) + ("  ·  " + tr("TY_SX_CH_BEST") if bool(r["best"]) and not bool(r["first"]) else "") \
			+ ("  ·  " + foot if foot != "" else "")
	show_card("TY_SX_CARD_CHALLENGE", tr(String(e.get("name_key", ""))), tr(String(e.get("desc_key", ""))), foot)
	_ch_focus = ch
	_say(ch, "TY_SX_CH_DONE")
	challenge_done.emit(id, seconds)
	field_log.save()


func _say(ch: Dictionary, key: String) -> void:
	_ch_focus = ch
	_ch_msg = key
	_ch_msg_t = 5.0


func _airborne() -> bool:
	if explorer == null:
		return false
	if "airborne" in explorer:
		return bool(explorer.get("airborne"))
	var p := explorer.global_position
	return p.y - planet.ground_height(p.x, p.z) > AIR_HEIGHT


func _battery_empty() -> bool:
	return explorer != null and explorer.has_method("power_frac") and float(explorer.call("power_frac")) <= 0.001


func _poi_by_id(id: String) -> SurfacePoi:
	for p in pois:
		if String(p.get_interact_id()) == id:
			return p
	return null


func _tick_challenges(delta: float) -> void:
	if explorer == null:
		return
	var pos := explorer.global_position
	var ground_explorer := is_rover() or "airborne" in explorer
	for ch in challenges:
		var e: Dictionary = ch["entry"]
		var node: SurfaceChallenge = ch["node"]
		match String(e.get("type", "")):
			"reach_before":
				if node == null:
					continue
				var target := _poi_by_id(String(e.get("target", "")))
				if target == null:
					continue
				match String(ch["phase"]):
					"idle":
						if node.in_zone(pos):
							ch["phase"] = "armed"
							_say(ch, "TY_SX_CH_ARMED")
					"armed":
						if not node.in_zone(pos):
							ch["phase"] = "running"
							ch["t"] = 0.0
							_ch_focus = ch
							_ch_msg = ""
					"running":
						ch["t"] = float(ch["t"]) + delta
						_ch_focus = ch
						var d := target.global_position - pos
						d.y = 0.0
						if d.length() <= target.reach_radius + (0.0 if ground_explorer else DRONE_EXTRA_REACH):
							_complete(ch, float(ch["t"]))
						elif float(ch["t"]) > float(e.get("time_s", 120.0)) or _battery_empty():
							ch["phase"] = "idle"
							_say(ch, "TY_SX_CH_FAILED_BATTERY" if _battery_empty() else "TY_SX_CH_FAILED_TIME")
			"jump":
				if node == null or not ground_explorer:
					continue
				var air := _airborne()
				match String(ch["phase"]):
					"idle":
						if node.in_zone(pos) and not air:
							ch["phase"] = "armed"
							ch["armed_t"] = 8.0
							ch["air"] = 0.0
							_say(ch, "TY_SX_CH_JUMP_ARMED")
					"armed":
						if air:
							ch["air"] = float(ch["air"]) + delta
							_ch_focus = ch
						elif float(ch["air"]) > 0.0:
							var got := float(ch["air"])
							ch["air"] = 0.0
							if got >= float(e.get("air_s", 1.0)):
								_complete(ch, got)
							else:
								_ch_msg = "TY_SX_CH_JUMP_SHORT"
								_ch_msg_t = 4.0
								ch["last_air"] = got
								ch["phase"] = "idle"
						elif not node.in_zone(pos):
							ch["armed_t"] = float(ch["armed_t"]) - delta
							if float(ch["armed_t"]) <= 0.0:
								ch["phase"] = "idle"


func _fill_challenge_card(delta: float) -> void:
	_ch_msg_t = maxf(_ch_msg_t - delta, 0.0)
	var ch := _ch_focus
	var active := not ch.is_empty() and (String(ch["phase"]) in ["armed", "running", "carry"] or _ch_msg_t > 0.0)
	ch_card.visible = active and not photo_mode and ui_visible
	if not active:
		return
	var e: Dictionary = ch["entry"]
	_ch_name.text = tr(String(e.get("name_key", "")))
	var phase := String(ch["phase"])
	var timer := ""
	if String(e.get("type", "")) == "reach_before" and phase == "running":
		var left := float(e.get("time_s", 120.0)) - float(ch["t"])
		timer = "%d:%02d" % [int(maxf(left, 0.0)) / 60, int(maxf(left, 0.0)) % 60]
		_ch_status.text = tr("TY_SX_CH_RUNNING") % tr(_poi_name(String(e.get("target", ""))))
	elif String(e.get("type", "")) == "jump" and phase == "armed" and float(ch["air"]) > 0.0:
		timer = "%.1f s" % float(ch["air"])
		_ch_status.text = tr("TY_SX_CH_JUMP_AIR") % float(e.get("air_s", 1.0))
	elif _ch_msg != "" and _ch_msg_t > 0.0:
		var text := tr(_ch_msg)
		if _ch_msg == "TY_SX_CH_JUMP_SHORT":
			text = text % [float(ch.get("last_air", 0.0)), float(e.get("air_s", 1.0))]
		elif _ch_msg == "TY_SX_CH_ARMED":
			text = text % [tr(_poi_name(String(e.get("target", "")))), int(e.get("time_s", 120))]
		elif _ch_msg == "TY_SX_CH_JUMP_ARMED":
			text = text % float(e.get("air_s", 1.0))
		elif _ch_msg == "TY_SX_CH_CARRY":
			text = text % tr(_poi_name(String(e.get("to", ""))))
		_ch_status.text = text
	else:
		_ch_status.text = tr(String(e.get("desc_key", "")))
	_ch_timer.text = timer
	_ch_timer.visible = timer != ""


func _poi_name(id: String) -> String:
	var p := _poi_by_id(id)
	if p:
		return p.name_key
	return String(poi_entry(StringName(id)).get("name_key", ""))


# ------------------------------------------------------------ frame
func _process(delta: float) -> void:
	if not _bound:
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.2
		_refresh_explorer()
		if explorer and not is_rover() and not photo_mode:
			_drone_reach()
	if not photo_mode:
		_tick_challenges(delta)
	_fill_challenge_card(delta)
	if _card_t > 0.0:
		_card_t -= delta
		%Card.modulate.a = clampf(_card_t / 0.5, 0.0, 1.0)
		if _card_t <= 0.0:
			%Card.visible = false
	if photo_mode:
		_update_photo_cam(delta)


## Without a rover: the drone reaches the places it flies low over.
func _drone_reach() -> void:
	var p := explorer.global_position
	if p.y - planet.ground_height(p.x, p.z) > DRONE_MAX_HEIGHT:
		return
	for n in get_tree().get_nodes_in_group(SurfaceSession.GROUP):
		if not planet.is_ancestor_of(n) or bool(n.get("was_reached")):
			continue
		var d := (n as Node3D).global_position - p
		d.y = 0.0
		if d.length() <= float(n.get("reach_radius")) + DRONE_EXTRA_REACH:
			n.call("reached", explorer)


## Drone: F uses the next action of the nearest place in reach (photo, scan...).
func drone_investigate() -> Dictionary:
	if explorer == null:
		return {}
	var p := explorer.global_position
	var best: SurfaceInteractable = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(SurfaceSession.GROUP):
		if not planet.is_ancestor_of(n) or not (n is SurfaceInteractable):
			continue
		var d := (n as Node3D).global_position - p
		d.y *= 0.3
		var dl := d.length()
		if dl <= float(n.get("reach_radius")) + DRONE_EXTRA_REACH * 2.0 and dl < best_d:
			best = n
			best_d = dl
	if best == null:
		show_card("TY_SX_CARD_NOTHING", tr("TY_SX_NOTHING_TITLE"), tr("TY_SX_NOTHING_HINT"), "")
		return {}
	var act := &""
	for a: String in best.actions:
		if not best.used.has(StringName(a)):
			act = StringName(a)
			break
	if act == &"" and not best.actions.is_empty():
		act = StringName(best.actions[0])
	return best.interact(explorer, act)


func _unhandled_input(event: InputEvent) -> void:
	if photo_mode:
		_photo_input(event)
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_J:
			toggle_log()
			get_viewport().set_input_as_handled()
		KEY_P:
			enter_photo_mode()
			get_viewport().set_input_as_handled()
		KEY_F:
			if not is_rover():
				drone_investigate()
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if %Log.visible:
				close_log()
				get_viewport().set_input_as_handled()
			elif not is_rover():
				leave()
				get_viewport().set_input_as_handled()


## Back from the drone: the host (the campus viewer) closes it, standalone goes to the menu.
func leave() -> void:
	if field_log:
		field_log.save()
	leave_requested.emit()
	var n: Node = get_parent()
	while n:
		if n.has_method("surface_leave"):
			n.call("surface_leave")
			return
		n = n.get_parent()
	if get_tree().current_scene and planet and get_tree().current_scene == planet and ResourceLoader.exists(MENU_SCENE):
		get_tree().change_scene_to_file(MENU_SCENE)


# ------------------------------------------------------------ log
func toggle_log() -> void:
	if %Log.visible:
		close_log()
	else:
		open_log()


func open_log() -> void:
	fill_log()
	%Log.visible = true


func close_log() -> void:
	%Log.visible = false


func fill_log() -> void:
	var b := String(body_id)
	var bd := body_data(b)
	%LogTitle.text = tr("TY_SX_LOG_TITLE") % tr(String(bd.get("name_key", "")))
	var entries: Array = bd.get("pois", [])
	%LogSummary.text = tr("TY_SX_LOG_SUMMARY") % [field_log.found_count(b), entries.size(), field_log.collected_count(b),
		collectibles.size(), field_log.challenges_done(b), (bd.get("challenges", []) as Array).size(), int(field_log.body(b)["photos"])]
	var rows := TycoonHUD._copies(%PlaceTemplate, entries.size())
	for i in entries.size():
		var e: Dictionary = entries[i]
		var found := field_log.is_found(b, String(e.get("id", "")))
		var r := rows[i]
		(r.get_node("VBox/Name") as Label).text = ("✓ " + tr(String(e.get("name_key", "")))) if found else tr("TY_SX_LOG_UNKNOWN")
		var fact := r.get_node("VBox/Fact") as Label
		fact.text = tr(String(e.get("fact_key", ""))) if found else tr("TY_SX_LOG_UNKNOWN_HINT") % tr("TY_SX_KIND_" + String(e.get("kind", "")).to_upper())
		var src := r.get_node("VBox/Source") as Label
		src.text = tr("TY_SX_LOG_SOURCE") % String(e.get("source", "")) if found else ""
		src.visible = found
		r.modulate.a = 1.0 if found else 0.7
	var types := ["meteorite", "ice", "odd_rock", "comet_crumb"]
	var counts := {}
	var totals := {}
	for c in collectibles:
		var t := c.type_id()
		totals[t] = int(totals.get(t, 0)) + 1
		if field_log.is_collected(b, collectible_id(c)):
			counts[t] = int(counts.get(t, 0)) + 1
	var shown: Array = []
	for t: String in types:
		if int(totals.get(t, 0)) > 0:
			shown.append(t)
	var frows := TycoonHUD._copies(%FindTemplate, shown.size())
	for i in shown.size():
		var t: String = shown[i]
		(frows[i].get_node("Name") as Label).text = tr(String(collectible_type(t).get("name_key", "")))
		(frows[i].get_node("Count") as Label).text = "%d / %d" % [int(counts.get(t, 0)), int(totals.get(t, 0))]
	var chs: Array = bd.get("challenges", [])
	var crows := TycoonHUD._copies(%ChallengeTemplate, chs.size())
	for i in chs.size():
		var e: Dictionary = chs[i]
		var c := field_log.challenge(b, String(e.get("id", "")))
		var done := bool(c.get("done", false))
		(crows[i].get_node("VBox/Name") as Label).text = ("✓ " if done else "○ ") + tr(String(e.get("name_key", "")))
		(crows[i].get_node("VBox/Desc") as Label).text = tr(String(e.get("desc_key", "")))
		var st := crows[i].get_node("VBox/State") as Label
		st.text = (tr("TY_SX_LOG_BEST") % float(c["best"])) if done and c.has("best") else (tr("TY_SX_LOG_DONE") if done else "")
		st.visible = st.text != ""


# ------------------------------------------------------------ photo mode
func enter_photo_mode() -> void:
	if photo_mode:
		return
	photo_mode = true
	close_log()
	_prev_cam = get_viewport().get_camera_3d()
	_hidden_layers.clear()
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl != ui and cl.visible and _same_viewport(cl):
			cl.visible = false
			_hidden_layers.append(cl)
	%Card.visible = false
	%Chip.visible = false
	%Help.visible = false
	%Back.visible = false
	%Photo.visible = true
	%PhotoHint.text = tr("TY_SX_PHOTO_HINT")
	if _prev_cam:
		var to := _prev_cam.global_position - _orbit_center()
		_orbit = Vector3(atan2(to.x, to.z), clampf(asin(clampf(to.normalized().y, -1.0, 1.0)), 0.05, 1.3), clampf(to.length(), 4.0, 60.0))
		photo_cam.fov = _prev_cam.fov
	photo_cam.current = true
	if explorer and explorer.has_method("refresh_interactables"):
		_paused_explorer = explorer
		explorer.set_physics_process(false)
	elif explorer:
		_paused_explorer = explorer
		explorer.set_process(false)
	_update_photo_cam(0.0)


func _same_viewport(n: Node) -> bool:
	return n.get_viewport() == get_viewport()


func exit_photo_mode() -> void:
	if not photo_mode:
		return
	photo_mode = false
	for cl in _hidden_layers:
		if is_instance_valid(cl):
			cl.visible = true
	_hidden_layers.clear()
	%Photo.visible = false
	%Chip.visible = true
	%Help.visible = not is_rover()
	%Back.visible = not is_rover()
	photo_cam.current = false
	if is_instance_valid(_prev_cam):
		_prev_cam.current = true
	if is_instance_valid(_paused_explorer):
		if _paused_explorer.has_method("refresh_interactables"):
			_paused_explorer.set_physics_process(true)
		else:
			_paused_explorer.set_process(true)
	_paused_explorer = null


func _orbit_center() -> Vector3:
	if explorer:
		var p := explorer.global_position
		if not is_rover():
			# the drone looks at the ground in front of it
			var fwd := -explorer.global_basis.z
			fwd.y = 0.0
			p += fwd.normalized() * 10.0 if fwd.length() > 0.01 else Vector3.ZERO
			p.y = planet.ground_height(p.x, p.z)
		return p + Vector3(0, 1.0, 0)
	return Vector3.ZERO


func _update_photo_cam(delta: float) -> void:
	var k := 1.6 * delta
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		_orbit.x -= k
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		_orbit.x += k
	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
		_orbit.y = clampf(_orbit.y + k * 0.6, -0.1, 1.4)
	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
		_orbit.y = clampf(_orbit.y - k * 0.6, -0.1, 1.4)
	var c := _orbit_center()
	var dir := Vector3(sin(_orbit.x) * cos(_orbit.y), sin(_orbit.y), cos(_orbit.x) * cos(_orbit.y))
	var pos := c + dir * _orbit.z
	var g := planet.ground_height(pos.x, pos.z) + 1.2
	pos.y = maxf(pos.y, g)
	photo_cam.global_position = pos
	if pos.distance_to(c) > 0.1:
		photo_cam.look_at(c)


func _photo_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_P, KEY_ESCAPE:
				exit_photo_mode()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				take_photo()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_orbit.z = maxf(_orbit.z / 1.15, 3.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_orbit.z = minf(_orbit.z * 1.15, 120.0)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			take_photo()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		_orbit.x -= mm.relative.x * 0.005
		_orbit.y = clampf(_orbit.y + mm.relative.y * 0.004, -0.1, 1.4)
		get_viewport().set_input_as_handled()


## Saves the frame without the UI; every point of interest in view (within 90 m) is photographed.
func take_photo() -> String:
	%Photo.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	%Photo.visible = photo_mode
	DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := PHOTO_DIR.path_join("cometworks_%s_%s.png" % [body_id, stamp])
	if img:
		img.save_png(path)
	field_log.add_photo(String(body_id))
	var seen := photographed_pois()
	for p in seen:
		if p.accepts(&"photo"):
			p.interact(explorer, &"photo")
	var flash := %Flash as ColorRect
	flash.modulate.a = 0.85
	create_tween().tween_property(flash, "modulate:a", 0.0, 0.35)
	%PhotoHint.text = tr("TY_SX_PHOTO_SAVED") % [ProjectSettings.globalize_path(path), seen.size()]
	field_log.save()
	return path


func photographed_pois() -> Array[SurfacePoi]:
	var out: Array[SurfacePoi] = []
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return out
	for p in pois:
		var at := p.global_position + Vector3(0, 1.0, 0)
		if cam.global_position.distance_to(at) <= 90.0 and cam.is_position_in_frustum(at):
			out.append(p)
	return out
