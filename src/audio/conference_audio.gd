class_name ConferenceAudio
extends Node
## The Conferência dos Cometinhos' soundscape: a child of the fair (ConferenceFair), added by
## ConferenceFlow when the fair opens and freed with it. It only listens to the fair (polls its
## state each frame), so the fair's own script stays free of sound code:
##   - the fair's bed: a happy crowd murmuring, with birds by day or crickets in the evening
##     (amb_fair_day / amb_fair_night crossfaded by `night`, the campus' night amount when the
##     fair opened: the campus clock holds while we are here), on the Ambience bus
##   - the fair's band, heard from across the plaza (music_fair) in place of the campus loop,
##     which comes back when the fair closes (the music never overlaps: CwSfx waits for one loop
##     to fade before the next)
##   - the player's footsteps (fair_step), one per stride, longer strides when running
##   - a soft chime when a Lenda, a rival or the award stage comes into talk range (the fair's
##     prompt picks something new to point at)
##   - the award: the fanfare as the host takes the stage, and when the winner is named
##     confetti pops and applause (a cheer too when the award is ours)
## Volumes, buses and variants are the sound library's (assets/audio/cw_sound_library.tres).

## night amount 0..1 (0 = day bed only, 1 = evening bed only)
@export_range(0.0, 1.0, 0.01) var night := 0.0
## metres per footstep walking / running (the fair's Cometlings stand 1.6x tall)
@export var stride_walk := 1.05
@export var stride_run := 1.55
## slower than this (m/s), no footsteps
@export var step_min_speed := 0.6
@export var day_sound: StringName = &"amb_fair_day"
@export var night_sound: StringName = &"amb_fair_night"
@export var music_track: StringName = &"music_fair"
@export var step_sound: StringName = &"fair_step"
@export var chime_sound: StringName = &"fair_talk_chime"
@export var fanfare_sound: StringName = &"fair_fanfare"
@export var applause_sound: StringName = &"fair_applause"
@export var confetti_sound: StringName = &"confetti_pop"
@export var cheer_sound: StringName = &"crowd_cheer"

var fair: ConferenceFair
var day_bed: CwAmbiencePlayer
var night_bed: CwAmbiencePlayer
## footsteps played (tests)
var steps := 0
var _prev_music := &""
var _last_pos := Vector3.INF
var _walked := 0.0
var _focus_key := ""
var _in_ceremony := false
var _named := false


func _init() -> void:
	name = "ConferenceAudio"


func _ready() -> void:
	fair = get_parent() as ConferenceFair
	day_bed = _bed(day_sound, "DayBed")
	night_bed = _bed(night_sound, "NightBed")
	var sfx := CwSfx.get_instance()
	_prev_music = sfx.current_music() if sfx and sfx.is_node_ready() else &"music_campus"
	if _prev_music == &"":
		_prev_music = &"music_campus"
	CwSfx.music(music_track)
	_mix()


func _exit_tree() -> void:
	CwSfx.music(_prev_music)


func _bed(sound_name: StringName, node_name: String) -> CwAmbiencePlayer:
	var sfx := CwSfx.get_instance()
	var s := sfx.sound(sound_name) if sfx and sfx.library else null
	if s == null or s.streams.is_empty():
		return null
	var p := CwAmbiencePlayer.new()
	p.name = node_name
	p.stream = s.streams[0]
	p.bus = s.bus if AudioServer.get_bus_index(s.bus) >= 0 else &"Master"
	p.volume_db = s.volume_db
	p.fade_in = 2.0
	add_child(p)
	return p


func _mix() -> void:
	var n := clampf(night, 0.0, 1.0)
	if day_bed:
		day_bed.mix = sqrt(1.0 - n)
	if night_bed:
		night_bed.mix = sqrt(n)


func _process(delta: float) -> void:
	if fair == null or fair.state == null:
		return
	_mix()
	_footsteps(delta)
	_focus()
	_ceremony()


# ------------------------------------------------------------------ footsteps
func _footsteps(delta: float) -> void:
	var p := fair.player
	if p == null:
		return
	var pos := p.global_position
	if _last_pos == Vector3.INF or delta <= 0.0:
		_last_pos = pos
		return
	var d := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
	_last_pos = pos
	var speed := d / delta
	if speed < step_min_speed or d > 3.0:   # standing, or a teleport (the stage)
		_walked = minf(_walked, stride_walk * 0.5)
		return
	var k := clampf((speed - p.walk_speed) / maxf(p.run_speed - p.walk_speed, 0.01), 0.0, 1.0)
	var stride := lerpf(stride_walk, stride_run, k)
	_walked += d
	if _walked >= stride:
		_walked = fmod(_walked, stride)
		steps += 1
		CwSfx.play(step_sound, 1.0 + 0.04 * k, 1.5 * k)


# ------------------------------------------------------------------ talk range
func _focus() -> void:
	var f := fair.focus
	var key := ""
	if f.has("npc"):
		key = "npc:%d" % (f["npc"]["node"] as Node).get_instance_id()
	elif f.has("stage"):
		key = "stage"
	elif f.has("exit"):
		key = "exit"
	if key == _focus_key:
		return
	_focus_key = key
	if key.begins_with("npc:"):
		CwSfx.play(chime_sound)
	elif key == "stage":
		CwSfx.play(chime_sound, 0.84)


# ------------------------------------------------------------------ the award
func _ceremony() -> void:
	var c := fair.ceremony
	if c.is_empty():
		_in_ceremony = false
		_named = false
		return
	if not _in_ceremony:
		_in_ceremony = true
		CwSfx.stinger(fanfare_sound)
	if not _named and bool(c.get("confetti", false)):
		_named = true
		var winner := String((c.get("rec", {}) as Dictionary).get("winner", ""))
		if winner == "":
			return
		CwSfx.run(confetti_sound, 3, 0.12, 0.08)
		CwSfx.play(applause_sound)
		if winner == RaceDirector.PLAYER:
			CwSfx.play(cheer_sound)
