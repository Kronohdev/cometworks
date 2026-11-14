class_name LeaderCreator
extends Control
## Leader creator (scenes/tycoon/ui/screens/leader_creator.tscn): the player makes their own
## Cometling, the leader of the agency, before the campus opens ("Nova campanha" in the main
## menu comes here first), and can restyle them later from the crew screen.
## The Cometling is the star: it stands big on a little floating island under the night sky
## (drag to turn it) and hops, emotes and pulls a face on every change, with the name tag
## (name + dice) right under it. The options come in four tabs, one on show at a time:
##   1 Look     body and tip colours (candy swatches), hat (icon tiles)
##   2 Job      profession tiles (icon, colour, favoured bar) + the founding bonus card
##   3 Way      strength cards and personality chips (with their emote)
##   4 Agency   the agency's name, race colour, emblem and the career's difficulty
##              (TycoonDifficulty: Fácil / Normal / Difícil; a new career only)
## A summary card sums the leader up next to the big Start key. Rules and choices:
## TycoonLeader, data/tycoon/leader.json.
##   mode "new"   standalone scene: Start opens the tycoon with TycoonMain.leader and
##                TycoonMain.difficulty set (and the opening cutscene), Back returns to the main menu
##   mode "edit"  a HUD screen (bind() is called): Save updates the campaign's leader
##                (profession and strength locked), Cancel goes back to the crew screen
## Everything visual is in the scene; swatches, tiles, cards and chips are copies of the hidden
## templates there, and the icons for professions, hats and strengths are set in the inspector.

signal finished(leader: Dictionary)

const SCENE := "res://scenes/tycoon/ui/screens/leader_creator.tscn"
const TYCOON := "res://scenes/tycoon/tycoon_main.tscn"
const MAIN_MENU := "res://scenes/menu/main_menu.tscn"
## turntable: radians per pixel dragged, inertia damping, resting yaw (a 3/4 view)
const DRAG_TURN := 0.012
const SPIN_DAMP := 3.5
const REST_YAW := 0.35
## the emote sheet of the Cometling (Cometling.EMOTES order), frames per row
const EMOTE_COLUMNS := 4
## stage width / height the camera's fov is authored for; a taller stage (a 4:3 window)
## keeps that width in view instead of the height, so the Cometling never gets cropped
const STAGE_ASPECT := 1.1

## profession id -> icon of its tile and of the bonus card
@export var profession_icons: Dictionary[String, Texture2D] = {}
## hat id -> icon of its tile
@export var hat_icons: Dictionary[String, Texture2D] = {}
## strength id -> icon of its card
@export var strength_icons: Dictionary[String, Texture2D] = {}
## the Cometling emote sheet (personality chips show their quirk's emote)
@export var emote_sheet: Texture2D

## "new" (before the campaign) | "edit" (from the crew screen)
var mode := "new"
## the leader being made (TycoonLeader.sanitize() format)
var leader: Dictionary = {}
## the career's difficulty (TycoonDifficulty level id); picked in mode "new" only
var difficulty := TycoonDifficulty.NORMAL
## standalone: start loading the tycoon scene in the background while the player chooses
var preload_campus := true
## the tab on show (0 look, 1 job, 2 way, 3 agency)
var page := 0
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
@onready var stage_camera: Camera3D = %Camera3D
@onready var _fov := stage_camera.fov


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
	%PrevButton.pressed.connect(func() -> void: show_page(page - 1))
	%NextButton.pressed.connect(func() -> void: show_page(page + 1))
	for i in _tabs().size():
		_tabs()[i].pressed.connect(show_page.bind(i))
	%Preview.gui_input.connect(_on_preview_input)
	%Preview.resized.connect(_fit_camera)
	_fit_camera()
	%Fade.visible = false
	var base := TycoonLeader.make_default(_rng)   # anything set before _ready (bind, a name) wins
	base["name"] = TycoonLeader.random_name(_rng)
	base.merge(leader, true)
	leader = base
	show_page(page, false)
	refresh()
	creature.play_sequence(["wave"])
	creature.show_emote("happy", 2.0)
	creature.set_expression("joy", 2.0)
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


## Wide stage: the authored vertical fov. Tall stage: the same width stays in view.
func _fit_camera() -> void:
	var s := (%Preview as Control).size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	if s.x / s.y >= STAGE_ASPECT:
		stage_camera.keep_aspect = Camera3D.KEEP_HEIGHT
		stage_camera.fov = _fov
	else:
		stage_camera.keep_aspect = Camera3D.KEEP_WIDTH
		stage_camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_fov) * 0.5) * STAGE_ASPECT))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		back()


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		if not _dragging and absf(_spin) < 0.5 and not creature.is_busy():
			creature.poke()   # poked
	elif event is InputEventMouseMotion and _dragging:
		var dx := (event as InputEventMouseMotion).relative.x
		_yaw += dx * DRAG_TURN
		_spin = lerpf(_spin, dx * DRAG_TURN * 60.0, 0.5)


# ------------------------------------------------------------ tabs
func _tabs() -> Array[Button]:
	var out: Array[Button] = []
	for b in %Tabs.get_children():
		if b is Button:
			out.append(b)
	return out


func _pages() -> Array[Control]:
	var out: Array[Control] = []
	for p in %Pages.get_children():
		if p is Control:
			out.append(p)
	return out


## Shows tab `i` (0 look, 1 job, 2 way, 3 agency); the Cometling hops along.
func show_page(i: int, hop := true) -> void:
	var pages := _pages()
	page = clampi(i, 0, pages.size() - 1)
	var tabs := _tabs()
	for k in pages.size():
		pages[k].visible = k == page
		if k < tabs.size():
			tabs[k].set_pressed_no_signal(k == page)
	_show_key(%PrevButton, page > 0)
	_show_key(%NextButton, page < pages.size() - 1)
	%StepLabel.text = tr("TY_LEADER_STEP") % [page + 1, pages.size()]
	if hop and is_node_ready():
		_idle_t = 0.0
		if not creature.is_busy():
			creature.play_sequence(["hop"])


## Prev / Next keep their place in the row (the step label stays centred) when not needed.
func _show_key(b: Button, on: bool) -> void:
	b.modulate.a = 1.0 if on else 0.0
	b.disabled = not on
	b.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE


# ------------------------------------------------------------ choices
## Sets one option ("body", "spot", "hat", "profession", "strength", "quirk", "agency_color",
## "emblem", or "difficulty" for the career).
func pick(key: String, value: String) -> void:
	if key == "difficulty":
		if mode == "edit" or difficulty == value:
			return
		difficulty = TycoonDifficulty.sanitize(value)
		if is_node_ready():
			refresh()
			_react("nod", "fire" if difficulty == "hard" else ("heart" if difficulty == "easy" else "star"), "content")
		return
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
			_react("surprise", "heart", "surprised")
		"profession":
			_react("cheer", {"pilot": "rocket", "scientist": "planet", "researcher": "idea",
				"flight_controller": "chat", "test_technician": "check"}.get(value, "wrench"))
		"strength":
			_react("jump", "fire" if value == "courage" else ("idea" if value == "curiosity" else "wrench"))
		"quirk":
			var q := TycoonLeader.quirk(value)
			_react(String(q.get("shot", "cheer")), String(q.get("emote", "happy")))
		"agency_color", "emblem":
			_react("nod", "star", "content")


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


## The Cometling reacts to a change: a move, an emote, a face, a burst of sparkles, and the
## summary card gives a little beat.
func _react(shot: String, emote: String, face := "joy") -> void:
	_idle_t = 0.0
	creature.play_sequence([shot])
	creature.show_emote(emote, 1.6)
	creature.set_expression(face, 1.4)
	var burst := %Burst as CPUParticles3D
	burst.restart()
	CwMotion.poke(%Summary)


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
	scene.set("difficulty", difficulty)
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
	%StepLabel.text = tr("TY_LEADER_STEP") % [page + 1, _pages().size()]
	if %NameEdit.text != String(leader["name"]) and not %NameEdit.has_focus():
		%NameEdit.text = String(leader["name"])
	if %AgencyEdit.text != String(leader["agency_name"]) and not %AgencyEdit.has_focus():
		%AgencyEdit.text = String(leader["agency_name"])
	_fill_swatches(%BodyTemplate, TycoonLeader.body_colors(), "body")
	_fill_swatches(%SpotTemplate, TycoonLeader.spot_colors(), "spot")
	_fill_swatches(%AgencyTemplate, TycoonLeader.agency_colors(), "agency_color")
	_fill_emblems()
	_fill_hats()
	_fill_strengths(edit)
	_fill_quirks()
	_fill_professions(edit)
	_fill_difficulty()
	%Difficulty.visible = not edit   # chosen once, when the career starts
	%JobLocked.visible = edit
	%WayLocked.visible = edit
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


## Name tag ribbon, agency preview and the summary card.
func _refresh_texts() -> void:
	var nm := String(leader.get("name", "")).strip_edges()
	var p := _profession(String(leader["profession"]))
	var col := Color(String(p.get("color", "#8c9ab5")))
	var prof_name := tr(String(p.get("name_key", "")))
	%PreviewProf.text = prof_name
	%PreviewBulb.texture = profession_icons.get(String(leader["profession"]), %PreviewBulb.texture)
	%Ribbon.self_modulate = col.lerp(Color.WHITE, 0.35)
	var an := String(leader.get("agency_name", "")).strip_edges()
	var agency := an if an != "" else "Cometworks"
	var acol := Color(String(leader["agency_color"]))
	var emblem := TycoonLeader.emblem_icon(String(leader.get("emblem", "")))
	%PreviewAgency.text = agency
	for disc: Panel in [%PreviewAgencyDisc, %SummaryDisc]:
		disc.self_modulate = acol
	if emblem:
		%PreviewAgencyDot.texture = emblem
		%SummaryEmblem.texture = emblem
	%SummaryName.text = nm if nm != "" else tr("TY_LEADER_NAME_PLACEHOLDER")
	%SummaryLine.text = "%s · %s" % [prof_name, agency]
	%SummaryBonus.text = tr("TY_LEADER_SUMMARY_BONUS") % _bonus_text(String(leader["profession"]))
	%StartButton.disabled = nm == ""


func _profession(id: String) -> Dictionary:
	for p: Dictionary in _pdata.get("professions", []):
		if p["id"] == id:
			return p
	return {}


## "+3 de reputação" (the profession's founding bonus, joined when there are several).
func _bonus_text(profession_id: String) -> String:
	var parts: Array[String] = []
	var start: Dictionary = TycoonLeader.bonus(profession_id).get("start", {})
	for k: String in start:
		var v := float(start[k])
		if k == "cash":
			parts.append(tr("TY_LEADER_BONUS_CASH") % TycoonHUD.fmt_cr(v))
		else:
			parts.append(tr("TY_LEADER_BONUS_" + k.to_upper()) % roundi(v))
	return ", ".join(parts)


## Wires a copy once: pressing it picks its "value" meta for `key`.
func _wire(b: Button, key: String) -> void:
	if not b.has_meta("wired"):
		b.set_meta("wired", true)
		b.pressed.connect(func() -> void: pick(key, String(b.get_meta("value"))))


## Selected state of a copy: pressed key and its check badge.
func _select(b: Button, on: bool) -> void:
	b.set_pressed_no_signal(on)
	var check := b.get_node_or_null("Check") as CanvasItem
	if check:
		check.visible = on


func _fill_swatches(template: Control, colors: Array, key: String) -> void:
	var nodes := TycoonHUD._copies(template, colors.size())
	for i in colors.size():
		var b := nodes[i] as Button
		var hex := String(colors[i])
		b.set_meta("value", hex)
		(b.get_node("Fill") as Control).self_modulate = Color(hex)
		_select(b, String(leader.get(key, "")) == hex)
		_wire(b, key)


## The agency emblems: copies of EmblemTemplate, the icon on a disc of the agency colour.
func _fill_emblems() -> void:
	var ids := TycoonLeader.emblems()
	var nodes := TycoonHUD._copies(%EmblemTemplate, ids.size())
	var col := Color(String(leader["agency_color"]))
	for i in ids.size():
		var b := nodes[i] as Button
		var id := String(ids[i])
		b.set_meta("value", id)
		(b.get_node("Disc") as Control).self_modulate = col
		(b.get_node("Disc/Icon") as TextureRect).texture = TycoonLeader.emblem_icon(id)
		_select(b, String(leader.get("emblem", "")) == id)
		_wire(b, "emblem")


func _fill_hats() -> void:
	var ids := TycoonLeader.hats()
	var nodes := TycoonHUD._copies(%HatTemplate, ids.size())
	for i in ids.size():
		var b := nodes[i] as Button
		var id := String(ids[i])
		b.set_meta("value", id)
		var icon := b.get_node("Box/Icon") as TextureRect
		icon.texture = hat_icons.get(id, icon.texture)
		(b.get_node("Box/Name") as Label).text = tr("TY_LEADER_HAT_" + id.to_upper())
		_select(b, String(leader.get("hat", "")) == id)
		_wire(b, "hat")


func _fill_strengths(locked: bool) -> void:
	var ids := TycoonLeader.strengths()
	var nodes := TycoonHUD._copies(%StrengthTemplate, ids.size())
	for i in ids.size():
		var b := nodes[i] as Button
		var id := String(ids[i])
		b.set_meta("value", id)
		var icon := b.get_node("Box/Icon") as TextureRect
		icon.texture = strength_icons.get(id, icon.texture)
		(b.get_node("Box/Name") as Label).text = tr("TY_LEADER_STR_" + id.to_upper())
		(b.get_node("Box/Tip") as Label).text = tr("TY_CREW_" + id.to_upper() + "_TIP")
		var on := String(leader.get("strength", "")) == id
		_select(b, on)
		b.disabled = locked and not on
		b.modulate.a = 0.45 if b.disabled else 1.0
		_wire(b, "strength")
	var d := TycoonLeader.data().get("traits", {}) as Dictionary
	%StrengthHint.text = tr("TY_LEADER_STRENGTH_LINE") % [tr("TY_LEADER_STR_" + String(leader["strength"]).to_upper()),
		roundi(float(d.get("strong", 0.85)) * 100.0), roundi(float(d.get("other", 0.6)) * 100.0)]


func _fill_quirks() -> void:
	var ids := TycoonLeader.quirks()
	var nodes := TycoonHUD._copies(%QuirkTemplate, ids.size())
	for i in ids.size():
		var b := nodes[i] as Button
		var id := String(ids[i])
		b.set_meta("value", id)
		var emote := b.get_node("Box/Emote") as TextureRect
		emote.texture = _emote_icon(String(TycoonLeader.quirk(id).get("emote", "happy")))
		(b.get_node("Box/Text/Name") as Label).text = tr("TY_LEADER_QUIRK_" + id.to_upper())
		(b.get_node("Box/Text/Tip") as Label).text = tr("TY_LEADER_QUIRK_" + id.to_upper() + "_TIP")
		_select(b, String(leader.get("quirk", "")) == id)
		_wire(b, "quirk")


## The difficulty levels: copies of DiffTemplate, one per level of data/tycoon/difficulty.json.
func _fill_difficulty() -> void:
	var levels := TycoonDifficulty.levels()
	var nodes := TycoonHUD._copies(%DiffTemplate, levels.size())
	for i in levels.size():
		var lv: Dictionary = levels[i]
		var b := nodes[i] as Button
		var id := String(lv["id"])
		b.set_meta("value", id)
		(b.get_node("Box/Name") as Label).text = tr(String(lv.get("name_key", id)))
		(b.get_node("Box/Tip") as Label).text = tr(String(lv.get("desc_key", "")))
		_select(b, id == difficulty)
		_wire(b, "difficulty")


## One frame of the emote sheet (the bubble the Cometling pops for that emote).
func _emote_icon(emote: String) -> Texture2D:
	if emote_sheet == null:
		return null
	var i := maxi(0, Cometling.EMOTES.find(emote))
	var size := emote_sheet.get_size() / float(EMOTE_COLUMNS)
	var at := AtlasTexture.new()
	at.atlas = emote_sheet
	at.region = Rect2(Vector2(i % EMOTE_COLUMNS, i / EMOTE_COLUMNS) * size, size)
	return at


func _fill_professions(locked: bool) -> void:
	var profs: Array = _pdata.get("professions", [])
	var nodes := TycoonHUD._copies(%ProfTemplate, profs.size())
	for i in profs.size():
		var p: Dictionary = profs[i]
		var b := nodes[i] as Button
		var id := String(p["id"])
		var col := Color(String(p.get("color", "#8c9ab5")))
		b.set_meta("value", id)
		(b.get_node("Box/Disc") as Control).self_modulate = col
		var icon := b.get_node("Box/Disc/Icon") as TextureRect
		icon.texture = profession_icons.get(id, icon.texture)
		(b.get_node("Box/Name") as Label).text = tr(String(p.get("name_key", "")))
		# the favoured bar: one of the chips authored in the tile (Eng, Sci, Ops, Rel)
		var bar := String(p.get("primary", "eng")).capitalize()
		for chip: Control in b.get_node("Box/Favours").get_children():
			if chip is PanelContainer:
				chip.visible = String(chip.name) == bar
		var on := id == String(leader["profession"])
		_select(b, on)
		b.disabled = locked and not on
		b.modulate.a = 0.45 if b.disabled else 1.0
		_wire(b, "profession")
	# the chosen profession's card: specialisation and founding bonus
	var prof_id := String(leader["profession"])
	var cur := _profession(prof_id)
	var col := Color(String(cur.get("color", "#8c9ab5")))
	%DetailDisc.self_modulate = col
	%DetailIcon.texture = profession_icons.get(prof_id, %DetailIcon.texture)
	%DetailName.text = tr(String(cur.get("name_key", "")))
	var spec := String(TycoonLeader.bonus(prof_id).get("spec", ""))
	%DetailSpec.text = tr("TY_LEADER_SPEC_LINE") % tr("TY_CREW_SPEC_" + spec.to_upper()) if spec != "" else ""
	%DetailSpecDesc.text = tr("TY_CREW_SPEC_" + spec.to_upper() + "_DESC") if spec != "" else ""
	var bonus := _bonus_text(prof_id)
	%DetailStart.text = tr("TY_LEADER_START_LINE") % bonus if bonus != "" else ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh()
