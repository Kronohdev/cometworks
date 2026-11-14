class_name LaunchAudio
extends Node
## The sound of the launch sequence (scenes/tycoon/launch/launch_audio.tscn, one instance in
## scenes/tycoon/launch/launch_sequence.tscn). Its own AnimationPlayer, Cues, holds an
## animation for each of the sequence's (countdown, flight_success, flight_partial,
## flight_fail, result, outro) with method keys that start the players under Players
## (cue("Ignition")) and value keys on their volumes (the rumble fading as the rocket climbs,
## dipping on every sputter). Scrub them in the editor next to the picture.
## This script only keeps Cues in step with the sequence's AnimationPlayer: when the sequence
## starts an animation, Cues starts the same one; when the sequence jumps (the player skips),
## Cues jumps too without firing the keys it skipped, and the long sounds fade out.
## The result chime follows the outcome (LaunchSequence.kind) via cue_result().

## the sequence's AnimationPlayer
@export var sequence_player: AnimationPlayer
## the sequence (its `kind`: "success", "partial" or "fail")
@export var sequence: Node
## a jump bigger than this (s) between the two players is a skip
@export_range(0.05, 2.0, 0.01) var skip_threshold := 0.3
## seconds to fade the long sounds out on a skip
@export_range(0.0, 2.0, 0.01) var skip_fade := 0.35
## players that are long beds and fade out on a skip or when the result comes in
@export var long_players: Array[AudioStreamPlayer] = []

## cue name -> times it started (tests)
var cued := {}

var _anim := &""
var _seeking := false

@onready var cues: AnimationPlayer = $Cues
@onready var players: Node = $Players


func _ready() -> void:
	if sequence_player == null:
		sequence_player = get_parent().get_node_or_null("AnimationPlayer") as AnimationPlayer
	if sequence == null:
		sequence = get_parent()


func _process(_delta: float) -> void:
	if sequence_player == null:
		return
	var a := sequence_player.current_animation
	if a != _anim:
		_anim = a
		_started(a)
		return
	if a == &"" or not cues.has_animation(a) or cues.current_animation != a:
		return
	var want := sequence_player.current_animation_position
	if absf(cues.current_animation_position - want) > skip_threshold:
		_jump(want)


func _started(a: StringName) -> void:
	if a == &"" or not cues.has_animation(a):
		return
	if a == &"result" or a == &"outro":
		fade_long()
	cues.play(a)
	var pos := sequence_player.current_animation_position
	if pos > skip_threshold:
		_jump(pos)


## The sequence jumped: follow it silently and let the long sounds go.
func _jump(to: float) -> void:
	_seeking = true
	cues.seek(to, true)
	_seeking = false
	fade_long()


## Method-key target: starts the player `player_name` under Players.
func cue(player_name: StringName) -> void:
	if _seeking:
		return
	var p := players.get_node_or_null(NodePath(player_name)) as AudioStreamPlayer
	if p == null:
		return
	p.stop()
	if p.has_meta(&"_level_db"):
		p.volume_db = float(p.get_meta(&"_level_db"))
	if CwSfx.audible():
		p.play()
	cued[player_name] = int(cued.get(player_name, 0)) + 1


## Method-key target: stops a player (with a short fade).
func stop_cue(player_name: StringName, fade := 0.2) -> void:
	var p := players.get_node_or_null(NodePath(player_name)) as AudioStreamPlayer
	if p and p.playing:
		_fade_out(p, fade)


## Method-key target: the result chime of the outcome.
func cue_result() -> void:
	var kind := String(sequence.get("kind")) if sequence and sequence.get("kind") != null else "success"
	cue(StringName("Result" + kind.capitalize()))


func fade_long() -> void:
	for p in long_players:
		if p and p.playing:
			_fade_out(p, skip_fade)


func _fade_out(p: AudioStreamPlayer, seconds: float) -> void:
	if not p.has_meta(&"_level_db"):
		p.set_meta(&"_level_db", p.volume_db)
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, maxf(seconds, 0.01)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(p.stop)
