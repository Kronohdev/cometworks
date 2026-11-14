class_name CampusAudio
extends Node
## The campus soundscape (scenes/audio/campus_audio.tscn, one instance in
## scenes/tycoon/tycoon_main.tscn): the campus music loop (MusicCue), a day bed (birds,
## breeze) and a night bed (crickets, a far owl) crossfaded by the day cycle
## (CampusDayCycle.phase through the `night` curve), the workshop's distant clanks (a
## CwRandomEmitter placed on the first built lot of `clank_lots`), and the game's cues:
## a chime when a news line arrives, a stinger when the player takes a race milestone and
## on the finale. The beds dip while a full screen is open and a lot more during a launch.
## Levels, curves and sounds are edited in the scene; this script only drives them.

## CampusDayCycle (src/tycoon/campus_day_cycle.gd)
@export var day_cycle: CampusDayCycle
## night amount 0..1 over the cycle phase (0 golden hour, ~0.45 night, ~0.8 dawn)
@export var night: Curve
@export var day_bed: CwAmbiencePlayer
@export var night_bed: CwAmbiencePlayer
@export var clanks: CwRandomEmitter
## lots tried in order for the clanks (the first one with a building wins)
@export var clank_lots: PackedStringArray = ["workshop", "factory", "hq"]
## clank odds at full night (the day shift is busier)
@export_range(0.0, 1.0, 0.01) var night_clank_activity := 0.35
@export_group("Ducking")
## bed level while a full screen is open (0..1)
@export_range(0.0, 1.0, 0.01) var screen_mix := 0.6
## bed level during the launch sequence (it has its own sound)
@export_range(0.0, 1.0, 0.01) var launch_mix := 0.25
## music dip during the launch sequence
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var launch_music_db := -14.0
@export_group("Cues")
@export var news_sound: StringName = &"news_chime"
@export var milestone_stinger: StringName = &"stinger_milestone"
@export var finale_stinger: StringName = &"stinger_finale"
## screens that bring the finale stinger
@export var finale_screens: PackedStringArray = ["finale"]

var main: TycoonMain
var _duck := 1.0
var _duck_target := 1.0
var _news_top: Variant = null   # the newest news line (by reference: a new line is a new dictionary)
var _clank_lot := ""


func _ready() -> void:
	main = get_parent() as TycoonMain
	if main == null:
		return
	if main.is_node_ready():
		_bind()
	else:
		main.ready.connect(_bind, CONNECT_ONE_SHOT)


func _exit_tree() -> void:
	CwSfx.unduck(&"launch")


func _bind() -> void:
	var st := main.state
	if st == null:
		return
	if day_cycle == null:
		day_cycle = main.get_node_or_null("DayCycle") as CampusDayCycle
	st.changed.connect(_on_changed)
	st.milestone_claimed.connect(_on_milestone)
	_news_top = _news_head(st)
	main.hud.screen_opened.connect(_on_screen.bind(true))
	main.hud.screen_closed.connect(_on_screen.bind(false))
	_place_clanks()


# ------------------------------------------------------------------ beds
func night_amount() -> float:
	var p := day_cycle.phase if day_cycle else 0.0
	return clampf(night.sample_baked(p), 0.0, 1.0) if night else 0.0


func _process(delta: float) -> void:
	var n := night_amount()
	_duck = move_toward(_duck, _duck_target, delta * 1.5)
	if day_bed:
		day_bed.mix = sqrt(1.0 - n) * _duck
	if night_bed:
		night_bed.mix = sqrt(n) * _duck
	if clanks:
		clanks.activity = lerpf(1.0, night_clank_activity, n)


func _on_screen(screen_name: String, opened: bool) -> void:
	if screen_name == "launch":
		if opened:
			CwSfx.duck(&"launch", launch_music_db)
		else:
			CwSfx.unduck(&"launch")
	if opened and screen_name in finale_screens:
		CwSfx.stinger(finale_stinger)
	var cur := main.hud.current_screen() if opened else ""
	if cur == "launch":
		_duck_target = launch_mix
	elif cur != "":
		_duck_target = screen_mix
	else:
		_duck_target = 1.0


# ------------------------------------------------------------------ cues
static func _news_head(st: TycoonState) -> Variant:
	return null if st.news.is_empty() else st.news[0]


func _on_changed() -> void:
	var top: Variant = _news_head(main.state)
	if not is_same(top, _news_top):
		_news_top = top
		if top != null:
			CwSfx.play(news_sound)
	_place_clanks()


func _on_milestone(_milestone_id: String, by: String) -> void:
	if by == "player":
		CwSfx.stinger(milestone_stinger)


func _place_clanks() -> void:
	if clanks == null or main.campus == null:
		return
	var lot := ""
	for id in clank_lots:
		if int(main.state.building(id).get("level", 0)) > 0 and main.campus.lots.has_node(id):
			lot = id
			break
	if lot == _clank_lot:
		return
	_clank_lot = lot
	clanks.enabled = lot != ""
	if lot != "":
		clanks.global_position = main.campus.lot_position(lot) + Vector3.UP * 3.0
