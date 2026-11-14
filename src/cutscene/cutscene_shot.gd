@tool
class_name CutsceneShot
extends MenuShot
## One shot of a story cutscene (scenes/cutscenes/shots/*.tscn). Like a main-menu shot
## (MenuShot: the camera eases along the Marker3D nodes in `path`, the AnimationPlayer plays
## the cues) and everything is authored in the shot's scene: the set (an instanced scene of
## scenes/cutscenes/sets/), lights, the Cometlings, the camera markers and the cues.
## A shot lasts as long as the animation it plays ("shot", or "short" for the quick version).
##
## Story cues are method tracks on the shot root, keyed in the AnimationPlayer:
##   say(key)                 a storybook line, typed out under the picture ({leader} and
##                            {agency} are filled in with the player's names)
##   hush()                   clears the line
##   card(key, kicker = "")   a title card over the picture; uncard() lets it go
##   sfx(name) / music(name) / stinger(name)   sounds of the library (CwSfx)
## Other tracks key the Cometlings (play, show_emote, set_expression, look_at_point) and the
## props. The Cutscene (src/cutscene/cutscene.gd) listens to the signals below.

signal line(key: String)
signal hushed
signal carded(key: String, kicker: String)
signal uncarded

## method names of the story cues (a line skip jumps over them; the others still fire)
const CUES := ["say", "hush", "card", "uncard", "sfx", "music", "stinger"]

## Cometlings dressed as the player's leader (colours, hat and the profession's glow)
@export var leader_cometlings: Array[Node3D] = []
## seconds of the dip from night into this shot (0 = a hard cut)
@export_range(0.0, 3.0, 0.05) var dip_in := 0.8
@export_group("Campus set")
## a Campus (scenes/tycoon/campus.tscn) in the shot: it shows a copy of the player's
## campaign (their buildings and crew), or a demo campus at `campus_era` / `campus_level`
@export var campus: Node3D
@export_range(1, 5) var campus_era := 5
@export_range(1, 3) var campus_level := 3


## Plays the shot with animation `anim`; the shot lasts as long as that animation.
func play_cut(anim: StringName = &"shot") -> void:
	if animation_player and animation_player.has_animation(anim):
		animation = anim
		duration = animation_player.get_animation(anim).length
	begin()


## Dresses the leader Cometlings and binds the campus. `leader` is TycoonLeader.sanitize()
## format ({} keeps the authored look); `state` may be null.
func setup(leader: Dictionary, state: TycoonState = null) -> void:
	if not leader.is_empty():
		var glow := _profession_color(String(leader.get("profession", "")))
		for c in leader_cometlings:
			if c is Cometling:
				TycoonLeader.apply_look(c as Cometling, leader)
				if glow.a > 0.0:
					(c as Cometling).glow_color = glow
	if campus and campus.has_method("bind"):
		campus.call("bind", _campus_state(state))


func _campus_state(state: TycoonState) -> TycoonState:
	if state:
		return TycoonState.from_dict(state.to_dict())   # a copy: the cutscene never touches the campaign
	var st := TycoonState.new_campaign(2026)
	st.weeks = (campus_era - 1) * 5 * st.weeks_per_year() + 10
	for lot: String in st.lot_ids():
		st.buildings[lot] = {"kind": st.lot_kind(lot), "level": campus_level, "target": campus_level, "weeks_left": 0}
	return st


static func _profession_color(id: String) -> Color:
	for p: Dictionary in TycoonState.load_json(TycoonState.PROFESSIONS_PATH).get("professions", []):
		if String(p.get("id", "")) == id:
			return Color(String(p.get("color", "#7ee08a")))
	return Color(0, 0, 0, 0)


# ------------------------------------------------------------ cues (keyed)
func say(key: String) -> void:
	line.emit(key)


func hush() -> void:
	hushed.emit()


func card(key: String, kicker := "") -> void:
	carded.emit(key, kicker)


func uncard() -> void:
	uncarded.emit()


func sfx(sound_name: String) -> void:
	CwSfx.play(StringName(sound_name))


func music(track: String) -> void:
	CwSfx.music(StringName(track))


func stinger(sound_name: String) -> void:
	CwSfx.stinger(StringName(sound_name))


# ------------------------------------------------------------ skipping
## Seconds at which the lines of the playing animation start.
func line_times() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var anim := _anim()
	if anim == null:
		return out
	for i in anim.get_track_count():
		if anim.track_get_type(i) != Animation.TYPE_METHOD or anim.track_get_path(i) != NodePath("."):
			continue
		for k in anim.track_get_key_count(i):
			if anim.method_track_get_name(i, k) == &"say":
				out.append(anim.track_get_key_time(i, k))
	out.sort()
	return out


## The next line after the current time (-1 when the shot has no more).
func next_line_time() -> float:
	for t in line_times():
		if t > time + 0.05:
			return t
	return -1.0


## Jumps ahead to `t` seconds: the Cometlings and props get the keys in between (so a skip
## never leaves someone mid-way), the story cues are skipped, and the line keyed at `t`
## comes up on the next frame.
func jump_to(t: float) -> void:
	var anim := _anim()
	if anim and t > time:
		var root := animation_player.get_node(animation_player.root_node)
		for i in anim.get_track_count():
			if anim.track_get_type(i) != Animation.TYPE_METHOD:
				continue
			var target := root.get_node_or_null(anim.track_get_path(i))
			if target == null:
				continue
			for k in anim.track_get_key_count(i):
				var kt := anim.track_get_key_time(i, k)
				var m := anim.method_track_get_name(i, k)
				if kt > time and kt < t - 0.001 and not String(m) in CUES and target.has_method(m):
					target.callv(m, anim.method_track_get_params(i, k))
	seek(maxf(t - 0.02, 0.0))


func _anim() -> Animation:
	if animation_player and animation_player.has_animation(animation):
		return animation_player.get_animation(animation)
	return null
