class_name LeaderCreator
extends Control
## Leader creator (scenes/tycoon/ui/screens/leader_creator.tscn): the player makes their own
## Cometling, the leader of the agency, before the campus opens ("Nova campanha" in the main
## menu comes here first), and can restyle them later from the crew screen. A live 3D preview
## on a turntable (drag to turn) reacts to every change; the options are name, body and tip
## colours (curated swatches), hat, profession (gear + founding bonus), strength, personality,
## and the agency's name, race colour and emblem. Rules and choices: TycoonLeader,
## data/tycoon/leader.json.
##   mode "new"   standalone scene: Start opens the tycoon with TycoonMain.leader set, Back
##                returns to the main menu
##   mode "edit"  a HUD screen (bind() is called): Save updates the campaign's leader
##                (profession and strength locked), Cancel goes back to the crew screen
## Everything visual is in the scene; swatches, hats, professions and chips are copies of the
## hidden templates there.

signal finished(leader: Dictionary)

const SCENE := "res://scenes/tycoon/ui/screens/leader_creator.tscn"
const TYCOON := "res://scenes/tycoon/tycoon_main.tscn"
const MAIN_MENU := "res://scenes/menu/main_menu.tscn"
## turntable: radians per pixel dragged, inertia damping, resting yaw (a 3/4 view)
const DRAG_TURN := 0.012
const SPIN_DAMP := 3.5
const REST_YAW := 0.35

## "new" (before the campaign) | "edit" (from the crew screen)
var mode := "new"
## the leader being made (TycoonLeader.sanitize() format)
var leader: Dictionary = {}
## standalone: start loading the tycoon scene in the background while the player chooses
var preload_campus := true
var state: TycoonState
var clock: TycoonClock
var hud: Node

var _rng := RandomNumberGenerator.new()
var _pdata: Dictionary = {}
var _yaw := REST_YAW
var _spin := 0.0
var _dragging := false
var _idle_t := 0.0
var _leaving := false

@onready var creature: Cometling = %Creature
@onready var turntable: Node3D = %Turntable


func _ready() -> void:
	_rng.randomize()
	_pdata = TycoonState.load_json(TycoonState.PROFESSIONS_PATH)
	%NameEdit.text_changed.connect(set_leader_name)
	%NameEdit.text_submitted.connect(func(_t: String) -> void: _react("wave", "happy"))
	%RandomName.pressed.connect(func() -> void:
		set_leader_name(TycoonLeader.random_name(_rng))
		_react("wave", "happy"))
	%AgencyEdit.text_changed.connect(func(t: String) -> void:
		leader["agency_name"] = t
		_refresh_texts())
	%RandomAgency.pressed.connect(func() -> void:
		leader["agency_name"] = TycoonLeader.random_agency_name(_rng)
		refresh()
		_react("nod", "rocket"))
	%RandomAll.pressed.connect(randomize_all)
	%StartButton.pressed.connect(confirm)
	%BackButton.pressed.connect(back)
	%Preview.gui_input.connect(_on_preview_input)
	%Fade.visible = false
	var base := TycoonLeader.make_default(_rng)   # anything set before _ready (bind, a name) wins
	base["name"] = TycoonLeader.random_name(_rng)
	base.merge(leader, true)
	leader = base
	refresh()
	creature.play_sequence(["wave"])
	creature.show_emote("happy", 2.0)
	if mode == "new" and preload_campus and not Engine.is_editor_hint():
		ResourceLoader.load_threaded_request(TYCOON)


## HUD screen: edit the campaign's leader (or found one, for a campaign that has none).
func bind(s: TycoonState, c: TycoonClock, h: Node) -> void:
	state = s
	clock = c
	hud = h
	mode = "edit"
	leader = TycoonLeader.sanitize(s.leader) if not s.leader.is_empty() else TycoonLeader.make_default(_rng)
	if s.leader.is_empty():
		leader["agency_name"] = s.agency_name
	refresh()


func _process(delta: float) -> void:
	if not _dragging:
		_yaw += _spin * delta
		_spin *= exp(-SPIN_DAMP * delta)
		if absf(_spin) < 0.3:   # settle back to the 3/4 view, the short way round
			var to := REST_YAW + roundf((_yaw - REST_YAW) / TAU) * TAU
			_yaw = lerpf(_yaw, to, 1.0 - exp(-1.5 * delta))
	turntable.rotation.y = _yaw
	# every few seconds the preview does its personality thing
	_idle_t += delta
	if _idle_t > 7.0:
		_idle_t = 0.0
		if not creature.is_busy():
			var q := TycoonLeader.quirk(String(leader.get("quirk", "")))
			creature.play_sequence([String(q.get("shot", "nod"))])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		back()


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		if not _dragging and absf(_spin) < 0.5 and not creature.is_busy():
			creature.play_sequence(["surprise"])   # poked
	elif event is InputEventMouseMotion and _dragging:
		var dx := (event as InputEventMouseMotion).relative.x
		_yaw += dx * DRAG_TURN
		_spin = lerpf(_spin, dx * DRAG_TURN * 60.0, 0.5)


# ------------------------------------------------------------ choices
## Sets one option ("body", "spot", "hat", "profession", "strength", "quirk", "agency_color",
## "emblem").
func pick(key: String, value: String) -> void:
	if mode == "edit" and key in ["profession", "strength"]:
		return
	if String(leader.get(key, "")) == value:
		return
	leader[key] = value
	if not is_node_ready():
		return
	refresh()
	match key:
		"body", "spot":
			_react("spin" if key == "body" else "jump", "sparkle")
		"hat":
			_react("surprise", "heart")
		"profession":
			_react("cheer", {"pilot": "rocket", "scientist": "planet", "researcher": "idea",
				"flight_controller": "chat", "test_technician": "check"}.get(value, "wrench"))
		"strength":
			_react("jump", "fire" if value == "courage" else ("idea" if value == "curiosity" else "wrench"))
		"quirk":
			var q := TycoonLeader.quirk(value)
			_react(String(q.get("shot", "cheer")), String(q.get("emote", "happy")))
		"agency_color", "emblem":
			_react("nod", "star")


func set_leader_name(n: String) -> void:
	leader["name"] = n
	if not is_node_ready():
		return
	if %NameEdit.text != n:
		%NameEdit.text = n
	_refresh_texts()


func randomize_all() -> void:
	var keep := leader.duplicate()
	leader = TycoonLeader.make_random(_rng)
	if mode == "edit":
		for k in ["profession", "strength", "agency_name", "seed"]:
			leader[k] = keep[k]
	refresh()
	_react("spin", "star")
	creature.play_sequence(["spin", "cheer"])


func _react(shot: String, emote: String) -> void:
	_idle_t = 0.0
	creature.play_sequence([shot])
	creature.show_emote(emote, 1.6)


# ------------------------------------------------------------ confirm / back
func confirm() -> void:
	if _leaving:
		return
	var l := TycoonLeader.sanitize(leader)
	leader = l
	finished.emit(l)
	if mode == "edit":
		TycoonLeader.update(state, l)
		_back_to_crew()
		return
	_leaving = true
	creature.play_sequence(["cheer", "jump"])
	creature.show_emote("rocket", 2.0)
	%Loading.text = tr("TY_LEADER_LOADING")
	%Fade.visible = true
	%Fade.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(%Fade, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_open_campus)


func _open_campus() -> void:
	var ps: PackedScene = null
	if ResourceLoader.load_threaded_get_status(TYCOON) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ps = ResourceLoader.load_threaded_get(TYCOON) as PackedScene
	if ps == null:
		ps = load(TYCOON) as PackedScene
	var scene := ps.instantiate()
	scene.set("leader", leader)
	scene.set("intro_cutscene", Cutscenes.OPENING)   # the story, then the campus
	get_tree().change_scene_to_node(scene)


func back() -> void:
	if _leaving:
		return
	if mode == "edit":
		_back_to_crew()
	else:
		_leaving = true
		get_tree().change_scene_to_file(MAIN_MENU)


func _back_to_crew() -> void:
	if hud and hud.has_method("open_screen"):
		hud.call("open_screen", "crew", {"staff_id": TycoonLeader.ID})
	else:
		queue_free()


# ------------------------------------------------------------ refresh
func refresh() -> void:
	if not is_node_ready():
		return
	leader = TycoonLeader.sanitize(leader) if String(leader.get("name", "")).strip_edges() != "" \
		else _sanitized_keep_name()
	var edit := mode == "edit"
	%Subtitle.text = tr("TY_LEADER_SUBTITLE_EDIT" if edit else "TY_LEADER_SUBTITLE")
	%StartButton.text = tr("TY_LEADER_SAVE" if edit else "TY_LEADER_START")
	%BackButton.text = tr("TY_LEADER_CANCEL" if edit else "TY_LEADER_BACK")
	if %NameEdit.text != String(leader["name"]) and not %NameEdit.has_focus():
		%NameEdit.text = String(leader["name"])
	if %AgencyEdit.text != String(leader["agency_name"]) and not %AgencyEdit.has_focus():
		%AgencyEdit.text = String(leader["agency_name"])
	_fill_swatches(%BodyTemplate, TycoonLeader.body_colors(), "body")
	_fill_swatches(%SpotTemplate, TycoonLeader.spot_colors(), "spot")
	_fill_swatches(%AgencyTemplate, TycoonLeader.agency_colors(), "agency_color")
	_fill_emblems()
	_fill_chips(%HatTemplate, TycoonLeader.hats(), "hat", "TY_LEADER_HAT_")
	_fill_chips(%StrengthTemplate, TycoonLeader.strengths(), "strength", "TY_LEADER_STR_", edit)
	_fill_chips(%QuirkTemplate, TycoonLeader.quirks(), "quirk", "TY_LEADER_QUIRK_")
	_fill_professions(edit)
	_refresh_texts()
	_dress()


## While the name field is empty the leader keeps an empty name (sanitize would fill it in).
func _sanitized_keep_name() -> Dictionary:
	var l := TycoonLeader.sanitize(leader)
	l["name"] = ""
	return l


func _dress() -> void:
	var prof := String(leader["profession"])
	creature.glow_color = Color(String(_profession(prof).get("color", "#7ee08a")))
	TycoonLeader.apply_look(creature, leader)


func _refresh_texts() -> void:
	var nm := String(leader.get("name", "")).strip_edges()
	%PreviewName.text = nm if nm != "" else tr("TY_LEADER_NAME_PLACEHOLDER")
	var p := _profession(String(leader["profession"]))
	var col := Color(String(p.get("color", "#8c9ab5")))
	%PreviewProf.text = tr(String(p.get("name_key", "")))
	%PreviewProf.add_theme_color_override("font_color", CwPalette.ink(col))
	%PreviewBulb.self_modulate = col
	var an := String(leader.get("agency_name", "")).strip_edges()
	%PreviewAgency.text = an if an != "" else "Cometworks"
	%PreviewAgencyDot.self_modulate = Color(String(leader["agency_color"]))
	var emblem := TycoonLeader.emblem_icon(String(leader.get("emblem", "")))
	if emblem:
		%PreviewAgencyDot.texture = emblem
	%StartButton.disabled = nm == ""


func _profession(id: String) -> Dictionary:
	for p: Dictionary in _pdata.get("professions", []):
		if p["id"] == id:
			return p
	return {}


func _fill_swatches(template: Control, colors: Array, key: String) -> void:
	var nodes := TycoonHUD._copies(template, colors.size())
	for i in colors.size():
		var b := nodes[i] as Button
		var hex := String(colors[i])
		b.set_meta("value", hex)
		(b.get_node("Fill") as Control).self_modulate = Color(hex)
		b.set_pressed_no_signal(String(leader.get(key, "")) == hex)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: pick(key, String(b.get_meta("value"))))


## The agency emblems: copies of EmblemTemplate, the icon tinted with the agency colour.
func _fill_emblems() -> void:
	var ids := TycoonLeader.emblems()
	var nodes := TycoonHUD._copies(%EmblemTemplate, ids.size())
	var col := Color(String(leader["agency_color"]))
	for i in ids.size():
		var b := nodes[i] as Button
		var id := String(ids[i])
		b.set_meta("value", id)
		var icon := b.get_node("Icon") as TextureRect
		icon.texture = TycoonLeader.emblem_icon(id)
		var on := String(leader.get("emblem", "")) == id
		# on the lit (pressed) key the icon takes the key's dark text colour, like a label would
		icon.self_modulate = b.get_theme_color("font_pressed_color") if on else col
		b.set_pressed_no_signal(on)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: pick("emblem", String(b.get_meta("value"))))


func _fill_chips(template: Control, ids: Array, key: String, prefix: String, locked := false) -> void:
	var nodes := TycoonHUD._copies(template, ids.size())
	for i in ids.size():
		var b := nodes[i] as Button
		var id := String(ids[i])
		b.set_meta("value", id)
		b.text = tr(prefix + id.to_upper())
		b.set_pressed_no_signal(String(leader.get(key, "")) == id)
		b.disabled = locked and String(leader.get(key, "")) != id
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: pick(key, String(b.get_meta("value"))))
	if key == "strength":
		var d := TycoonLeader.data().get("traits", {}) as Dictionary
		%StrengthHint.text = tr("TY_LEADER_STRENGTH_LINE") % [tr(prefix + String(leader[key]).to_upper()),
			roundi(float(d.get("strong", 0.85)) * 100.0), roundi(float(d.get("other", 0.6)) * 100.0)]


func _fill_professions(locked: bool) -> void:
	var profs: Array = _pdata.get("professions", [])
	var nodes := TycoonHUD._copies(%ProfTemplate, profs.size())
	for i in profs.size():
		var p: Dictionary = profs[i]
		var b := nodes[i] as Button
		var id := String(p["id"])
		var col := Color(String(p.get("color", "#8c9ab5")))
		b.set_meta("value", id)
		(b.get_node("HBox/Tab") as ColorRect).color = col
		(b.get_node("HBox/Bulb") as TextureRect).self_modulate = col
		(b.get_node("HBox/Text/Name") as Label).text = tr(String(p.get("name_key", "")))
		# the favoured bar: one of the chips authored in the card (Eng, Sci, Ops, Rel)
		var bar := String(p.get("primary", "eng")).capitalize()
		for chip: Control in b.get_node("HBox/Text/Favours").get_children():
			if chip is PanelContainer:
				chip.visible = String(chip.name) == bar
		b.set_pressed_no_signal(id == String(leader["profession"]))
		b.disabled = locked and id != String(leader["profession"])
		b.modulate.a = 0.4 if b.disabled else 1.0
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: pick("profession", String(b.get_meta("value"))))
	# the chosen profession's founding bonus
	var cur := _profession(String(leader["profession"]))
	var col := Color(String(cur.get("color", "#8c9ab5")))
	%DetailBulb.self_modulate = col
	%DetailName.text = tr(String(cur.get("name_key", "")))
	%DetailName.add_theme_color_override("font_color", CwPalette.ink(col))
	var bonus := TycoonLeader.bonus(String(leader["profession"]))
	var spec := String(bonus.get("spec", ""))
	%DetailSpec.text = tr("TY_LEADER_SPEC_LINE") % tr("TY_CREW_SPEC_" + spec.to_upper()) if spec != "" else ""
	%DetailSpecDesc.text = tr("TY_CREW_SPEC_" + spec.to_upper() + "_DESC") if spec != "" else ""
	var parts: Array[String] = []
	var start: Dictionary = bonus.get("start", {})
	for k: String in start:
		var v := float(start[k])
		if k == "cash":
			parts.append(tr("TY_LEADER_BONUS_CASH") % TycoonHUD.fmt_cr(v))
		else:
			parts.append(tr("TY_LEADER_BONUS_" + k.to_upper()) % roundi(v))
	%DetailStart.text = tr("TY_LEADER_START_LINE") % ", ".join(parts) if not parts.is_empty() else ""
	%DetailLocked.visible = locked


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh()
