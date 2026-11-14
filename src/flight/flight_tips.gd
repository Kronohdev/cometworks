class_name FlightTips
extends PanelContainer
## First-flight tips: a short sequence of hint bubbles for players who never flew a rocket game
## (the engine lever, ignition, the turn east, dropping an empty stage, the map). Each tip shows
## once its moment comes, points at its control (anchors, set in scenes/flight/flight_hud.tscn)
## and goes away on "Got it", on "Skip tips" (all of them) or when the player does what it asks.
## Seen tips are remembered in user://settings.cfg under [flight] (tips_done), so they show only
## the first time; the F1 help panel can bring them back (reset()). The bubble's look, texts and
## buttons live in the scene; this script picks the tip, fills it and places it.
## Not shown in headless runs (automated tests) unless `force` is set; `persist` off keeps a
## scripted run (screenshots) from writing the settings.

signal tip_shown(id: String)

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "flight"
const KEY := "tips_done"
## the tips in order: id -> [title key, text key]
const STEPS := {
	"throttle": ["FL_CW_TIP_THROTTLE_T", "FL_CW_TIP_THROTTLE"],
	"ignite": ["FL_CW_TIP_IGNITE_T", "FL_CW_TIP_IGNITE"],
	"turn": ["FL_CW_TIP_TURN_T", "FL_CW_TIP_TURN"],
	"stage": ["FL_CW_TIP_STAGE_T", "FL_CW_TIP_STAGE"],
	"map": ["FL_CW_TIP_MAP_T", "FL_CW_TIP_MAP"],
}
## altitude (m) from which the turn tip shows (FlightHUD.TURN_ALT)
const TURN_ALT := 600.0

## show the tips even in headless runs (tests)
static var force := false
## write the seen tips to the settings file
static var persist := true

## the control each tip points at (id -> NodePath, relative to this node)
@export var anchors := {}
## theme variations of the bubble: with its tail (above the control) / plain (below it)
@export var style_above := &"CwBubble"
@export var style_below := &"CwPanelLilac"
## gap between the bubble and its control (px)
@export var gap := 10.0

var current := ""
var _done := {}
var _start_stage := -99

@onready var _step: Label = %TipStep
@onready var _title: Label = %TipTitle
@onready var _text: Label = %TipText


func _ready() -> void:
	visible = false
	%BtnTipOk.pressed.connect(func() -> void: complete(current))
	%BtnTipSkip.pressed.connect(skip_all)
	_done = load_done()


static func enabled() -> bool:
	return force or DisplayServer.get_name() != "headless"


static func load_done() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var out := {}
	for id in cfg.get_value(SECTION, KEY, []):
		out[String(id)] = true
	return out


static func all_done() -> bool:
	return load_done().size() >= STEPS.size()


## Forgets the seen tips (they show again on the next flight).
static func reset() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION, KEY, [])
	cfg.save(SETTINGS_PATH)


func is_done(id: String) -> bool:
	return _done.has(id)


func restart() -> void:
	_done.clear()
	if persist:
		reset()
	_hide()


func complete(id: String) -> void:
	if id == "":
		return
	_done[id] = true
	_save()
	if id == current:
		_hide()


func skip_all() -> void:
	for id in STEPS:
		_done[id] = true
	_save()
	_hide()


func _save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SECTION, KEY, _done.keys())
	cfg.save(SETTINGS_PATH)


func _hide() -> void:
	current = ""
	visible = false


## Picks the tip for this moment of the flight (telemetry from FlightWorld, `map` = the map is
## open) and completes the one on show when the player did what it asked.
func update(t: Dictionary, map: bool) -> void:
	if not enabled() or _done.size() >= STEPS.size():
		if visible:
			_hide()
		return
	var v: FlightVessel = t["vessel"]
	var launched: bool = t["launched"]
	var auto: bool = t["auto"]
	var pitch := float(t.get("pitch", 90.0))
	# lifting off covers the pad tips (shown or not)
	if launched and not (_done.has("throttle") and _done.has("ignite")):
		_done["throttle"] = true
		_done["ignite"] = true
		_save()
		if current in ["throttle", "ignite"]:
			_hide()
	# the one on show: done by doing it?
	match current:
		"turn":
			if auto or int(v.sas) == FlightVessel.Sas.PROGRADE:
				complete("turn")
		"stage":
			if v.current_stage != _start_stage:
				complete("stage")
		"map":
			if map:
				complete("map")
	if v.crashed:
		return
	# the first tip whose moment it is; an earlier one (more urgent: an empty stage) takes the
	# bubble from a later one on show, which comes back afterwards
	for id: String in STEPS:
		if id == current:
			break
		if not _done.has(id) and _want(id, t, map):
			_show(id, v)
			return
	if current != "":
		_place()
		return
	for id: String in STEPS:
		if not _done.has(id) and _want(id, t, map):
			_show(id, v)
			return


func _want(id: String, t: Dictionary, map: bool) -> bool:
	var launched: bool = t["launched"]
	var alt := float(t["alt"])
	match id:
		"throttle", "ignite":
			return not launched
		"turn":
			return launched and not t["auto"] and alt > TURN_ALT and float(t.get("pitch", 90.0)) > 78.0 \
				and alt < 45000.0 and int(t["sas"]) != FlightVessel.Sas.PROGRADE
		"stage":
			return launched and not t["auto"] and stage_empty(t)
		"map":
			return launched and not map and (alt > 70000.0 or bool(t.get("orbit", false)))
	return false


## The active stage has no thrust and nothing left to burn, and another stage waits.
static func stage_empty(t: Dictionary) -> bool:
	var v: FlightVessel = t["vessel"]
	if v.current_stage < 0 or v.current_stage >= v.stage_count - 1 or float(t["thrust"]) > 0.0:
		return false
	var f := v.stage_fuel(v.current_stage)
	return f[0] + f[2] <= 1.0


func _show(id: String, v: FlightVessel) -> void:
	current = id
	_start_stage = v.current_stage
	var keys: Array = STEPS[id]
	_step.text = tr("FL_CW_TIP_STEP") % [STEPS.keys().find(id) + 1, STEPS.size()]
	_title.text = tr(String(keys[0]))
	_text.text = tr(String(keys[1]))
	visible = true
	size = Vector2.ZERO
	_place()
	CwMotion.poke(self)
	tip_shown.emit(id)


## Above its control with the tail pointing at it, or below when there is no room above;
## always inside the HUD.
func _place() -> void:
	var path: NodePath = anchors.get(current, NodePath())
	var target := get_node_or_null(path) as Control
	var parent := get_parent() as Control
	if target == null or parent == null or not target.is_visible_in_tree():
		return
	size = Vector2.ZERO
	var r := target.get_global_rect()
	var s := get_combined_minimum_size()
	var view := parent.get_global_rect()
	var above := r.position.y - s.y - gap > view.position.y + 96.0
	var want := style_above if above else style_below
	if theme_type_variation != want:
		theme_type_variation = want
		s = get_combined_minimum_size()
	var pos := Vector2(r.position.x + r.size.x * 0.5 - 34.0, r.position.y - s.y - gap) if above \
		else Vector2(r.end.x - s.x, r.end.y + gap)
	pos.x = clampf(pos.x, view.position.x + 12.0, view.end.x - s.x - 12.0)
	pos.y = clampf(pos.y, view.position.y + 12.0, view.end.y - s.y - 12.0)
	global_position = pos
