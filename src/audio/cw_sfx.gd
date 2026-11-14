class_name CwSfx
extends Node
## The game's sound player: the autoload "CwAudio" (scenes/audio/cw_sfx.tscn). Scripts only
## trigger by name; the sounds themselves (streams, volumes, pitch variance, bus, cooldown,
## polyphony, odds) live in the editable library assets/audio/cw_sound_library.tres, and the
## players (one-shot pool, 3D voice pool, the two music decks and the stinger) are nodes of
## the scene, duplicated from the templates there.
##   CwSfx.play(&"ui_click")                    a UI / 2D one-shot
##   CwSfx.play_at(&"voice_happy", pos, node)   a 3D one-shot in node's world (pooled)
##   CwSfx.music(&"music_campus")               crossfades to a music loop (&"" fades out)
##   CwSfx.stinger(&"stinger_milestone")        a jingle over the music (ducks it)
##   CwSfx.duck(&"launch", -14.0) / unduck()    holds the music lower while something plays
## Cometlings chirp through here: Cometling.show_emote() calls Cometling.emote_hook, which
## this node sets; the chirps are rare (library odds, a per-Cometling cooldown, a few voices)
## and spatial. Everything is silent and harmless without an audio device (Dummy driver):
## the players still run, and `plays` counts what played (tests).

signal played(sound_name: StringName)

const SCENE := "res://scenes/audio/cw_sfx.tscn"
const AUTOLOAD := "CwAudio"

@export var library: CwSoundLibrary
@export_group("Music")
## seconds of a music crossfade
@export_range(0.0, 10.0, 0.1) var music_fade := 2.5
## how far the music dips under a stinger
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var stinger_duck_db := -16.0
@export_group("Pools")
## UI / 2D one-shots that can sound at once
@export_range(2, 32) var one_shot_voices := 10
## spatial one-shots (Cometling chirps, campus clanks) that can sound at once
@export_range(1, 16) var spatial_voices := 4
@export_group("Cometling voices")
@export var voices_enabled := true
## seconds before the same Cometling chirps again
@export_range(0.0, 30.0, 0.1, "suffix:s") var voice_cooldown := 3.5
## farther from the camera than this, a Cometling stays quiet
@export_range(1.0, 200.0, 0.5, "suffix:m") var voice_max_distance := 40.0
## level of the chirps of Cometlings drawn in a sub-viewport (leader creator, portraits, the
## menu's peek), played flat on the UI bus
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var preview_voice_db := -7.0
## each Cometling keeps its own voice: pitch spread around 1 by its personality
@export_range(0.0, 0.5, 0.01) var voice_pitch_spread := 0.12
## emote bubble -> library sound (Cometling.EMOTES); missing = silent
@export var emote_voices := {
	"happy": &"voice_happy", "heart": &"voice_happy", "star": &"voice_happy", "sparkle": &"voice_happy",
	"note": &"voice_happy", "check": &"voice_happy", "rocket": &"voice_cheer", "fire": &"voice_cheer",
	"planet": &"voice_happy", "exclaim": &"voice_surprised", "question": &"voice_question",
	"idea": &"voice_question", "sweat": &"voice_sad", "chat": &"voice_babble", "wrench": &"voice_babble",
	"zzz": &"voice_snore"}

## sound name -> times it played (tests and debugging)
var plays := {}

static var _inst: CwSfx

var _rng := RandomNumberGenerator.new()
var _last := {}            # sound name -> seconds of its last start
var _pool: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _owner_of := {}        # player -> sound name
var _started := {}         # player -> start time
var _ends := {}            # player -> time its sound ends
var _music_name := &""
var _decks: Array[AudioStreamPlayer] = []
var _deck_gain := [0.0, 0.0]
var _deck_target := [0.0, 0.0]
var _deck_db := [0.0, 0.0]
var _deck := 0
var _fade_speed := 0.4
var _ducks := {}           # key -> dB
var _duck_now := 0.0
var _warned := {}
var _headless := not audible()

@onready var _one_shot: AudioStreamPlayer = $Players/OneShot
@onready var _spatial: AudioStreamPlayer3D = $Players/Spatial
@onready var _stinger: AudioStreamPlayer = $Music/Stinger


# ------------------------------------------------------------------ access
## The sound player (the autoload; made on demand when there is none, e.g. a bare test
## script). null in the editor.
static func get_instance() -> CwSfx:
	if is_instance_valid(_inst):
		return _inst
	if Engine.is_editor_hint():
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var n := tree.root.get_node_or_null(AUTOLOAD)
	if n is CwSfx:
		_inst = n
		return _inst
	var ps := load(SCENE) as PackedScene
	if ps == null:
		return null
	_inst = ps.instantiate() as CwSfx
	_inst.name = AUTOLOAD
	tree.root.add_child.call_deferred(_inst)
	return _inst


static func play(sound_name: StringName, pitch_scale := 1.0, volume_offset_db := 0.0) -> void:
	var s := get_instance()
	if s:
		s.play_sound(sound_name, pitch_scale, volume_offset_db)


static func play_at(sound_name: StringName, where: Vector3, from: Node = null, pitch_scale := 1.0) -> void:
	var s := get_instance()
	if s:
		s.play_sound_at(sound_name, where, from, pitch_scale)


static func music(track: StringName, fade := -1.0) -> void:
	var s := get_instance()
	if s:
		s.play_music(track, fade)


static func stinger(sound_name: StringName) -> void:
	var s := get_instance()
	if s:
		s.play_stinger(sound_name)


static func duck(key: StringName, db_amount: float) -> void:
	var s := get_instance()
	if s:
		s._ducks[key] = db_amount


static func unduck(key: StringName) -> void:
	var s := get_instance()
	if s:
		s._ducks.erase(key)


## How many times `sound_name` played since the start (tests).
static func count(sound_name: StringName) -> int:
	var s := get_instance()
	return int(s.plays.get(sound_name, 0)) if s else 0


## False in a headless run (Dummy audio driver): players are not started there, since the
## Dummy driver never mixes and their playbacks would only pile up until exit.
static func audible() -> bool:
	return DisplayServer.get_name() != "headless"


# ------------------------------------------------------------------ setup
func _enter_tree() -> void:
	if _inst == null or not is_instance_valid(_inst):
		_inst = self


func _exit_tree() -> void:
	if _inst == self:
		_inst = null
		if Cometling.emote_hook == _on_emote:
			Cometling.emote_hook = Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	MenuSettings.apply_audio()
	# the templates stay in the scene (silent); the pools are their copies
	for i in one_shot_voices:
		var p := _one_shot.duplicate() as AudioStreamPlayer
		p.name = "OneShot%d" % i
		$Players.add_child(p)
		_pool.append(p)
	for i in spatial_voices:
		var p := _spatial.duplicate() as AudioStreamPlayer3D
		p.name = "Spatial%d" % i
		$Players.add_child(p)
		_pool3d.append(p)
	_decks = [$Music/DeckA, $Music/DeckB]
	for d in _decks:
		d.volume_db = -80.0
	Cometling.emote_hook = _on_emote


# ------------------------------------------------------------------ one-shots
func sound(sound_name: StringName) -> CwSound:
	if library == null:
		return null
	var s := library.find(sound_name)
	if s == null and not _warned.has(sound_name):
		_warned[sound_name] = true
		push_warning("CwSfx: no sound '%s' in the library" % sound_name)
	return s


## Checks cooldown, odds and polyphony; returns the sound to play or null.
func _admit(sound_name: StringName) -> CwSound:
	var s := sound(sound_name)
	if s == null or s.streams.is_empty():
		return null
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(sound_name, -1000.0)) < s.cooldown:
		return null
	if s.chance < 1.0 and _rng.randf() > s.chance:
		return null
	var busy := 0
	for p: Node in _owner_of:
		if is_instance_valid(p) and _owner_of[p] == sound_name and _sounding(p):
			busy += 1
	if busy >= s.max_voices:
		return null
	_last[sound_name] = now
	return s


func _free_player(pool: Array) -> Node:
	var oldest: Node = null
	var oldest_t := INF
	for p: Node in pool:
		if not _sounding(p):
			return p
		var t := float(_started.get(p, 0.0))
		if t < oldest_t:
			oldest_t = t
			oldest = p
	return oldest


## Starts a player, unless there is no sound device to hear it (a headless run: the Dummy
## driver never mixes, so its playbacks would only pile up). Everything else (pools, counts,
## fades) runs the same.
func _start(p: Node) -> void:
	if not _headless:
		p.call("play")


## Still sounding: by the clock (start + length / pitch), so the polyphony limits hold the
## same with or without an audio device (the Dummy driver never finishes a stream).
func _sounding(p: Node) -> bool:
	return float(_ends.get(p, 0.0)) > Time.get_ticks_msec() / 1000.0


func _bus(name_: StringName) -> StringName:
	return name_ if AudioServer.get_bus_index(name_) >= 0 else &"Master"


func play_sound(sound_name: StringName, pitch_scale := 1.0, volume_offset_db := 0.0) -> AudioStreamPlayer:
	if not is_node_ready():
		return null
	var s := _admit(sound_name)
	if s == null:
		return null
	var p := _free_player(_pool) as AudioStreamPlayer
	if p == null:
		return null
	p.stop()
	p.stream = s.pick(_rng)
	p.bus = _bus(s.bus)
	p.volume_db = s.volume_db + volume_offset_db
	p.pitch_scale = maxf(0.05, s.pitch(_rng) * pitch_scale)
	_start(p)
	_note(p, sound_name)
	return p


func play_sound_at(sound_name: StringName, where: Vector3, from: Node = null, pitch_scale := 1.0) -> Node:
	if not is_node_ready():
		return null
	# drawn in a sub-viewport (a preview): flat and softer, on the UI bus
	if from and from.is_inside_tree() and from.get_viewport() != get_viewport():
		var flat := play_sound(sound_name, pitch_scale, preview_voice_db)
		if flat:
			flat.bus = _bus(&"UI")
		return flat
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(where) > voice_max_distance:
		return null
	var s := _admit(sound_name)
	if s == null:
		return null
	var p := _free_player(_pool3d) as AudioStreamPlayer3D
	if p == null:
		return null
	p.stop()
	p.global_position = where
	p.stream = s.pick(_rng)
	p.bus = _bus(s.bus)
	p.volume_db = s.volume_db
	p.pitch_scale = maxf(0.05, s.pitch(_rng) * pitch_scale)
	_start(p)
	_note(p, sound_name)
	return p


func _note(p: Node, sound_name: StringName) -> void:
	_owner_of[p] = sound_name
	var now := Time.get_ticks_msec() / 1000.0
	_started[p] = now
	var st: AudioStream = p.get("stream")
	var len_s := st.get_length() if st else 0.0
	_ends[p] = INF if (len_s <= 0.0 or _loops(st)) else now + len_s / maxf(float(p.get("pitch_scale")), 0.05)
	plays[sound_name] = int(plays.get(sound_name, 0)) + 1
	played.emit(sound_name)


static func _loops(st: AudioStream) -> bool:
	var w := st as AudioStreamWAV
	return w != null and w.loop_mode != AudioStreamWAV.LOOP_DISABLED


# ------------------------------------------------------------------ Cometling voices
func _on_emote(who: Node3D, emote: String) -> void:
	if not voices_enabled or not is_instance_valid(who) or not who.is_inside_tree() or not who.is_visible_in_tree():
		return
	var snd: StringName = StringName(emote_voices.get(emote, &""))
	if snd == &"":
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(who.get_meta(&"_cw_voice_t", -1000.0)) < voice_cooldown:
		return
	who.set_meta(&"_cw_voice_t", now)
	# a voice of its own: a pitch fixed by the Cometling's personality (or identity)
	var seed_v: int = int(who.get("personality_seed")) if who.get("personality_seed") else who.get_instance_id()
	var own := 1.0 + (float(absi(hash(seed_v)) % 1000) / 1000.0 - 0.5) * 2.0 * voice_pitch_spread
	var head := who.global_position + Vector3.UP * 0.8 * who.global_basis.get_scale().y
	play_sound_at(snd, head, who, own)


# ------------------------------------------------------------------ music
func play_music(track: StringName, fade := -1.0) -> void:
	if not is_node_ready():
		(func() -> void: play_music(track, fade)).call_deferred()
		return
	if fade < 0.0:
		fade = music_fade
	if track == _music_name:
		return
	_music_name = track
	var out := _deck
	_deck_target[out] = 0.0
	if track == &"":
		_fade_speed = 1.0 / maxf(fade, 0.01)
		return
	var s := sound(track)
	if s == null or s.streams.is_empty():
		return
	_deck = 1 - _deck
	var d: AudioStreamPlayer = _decks[_deck]
	d.stop()
	d.stream = s.pick(_rng)
	d.bus = _bus(s.bus)
	_deck_db[_deck] = s.volume_db
	_deck_gain[_deck] = 0.0
	_deck_target[_deck] = 1.0
	_fade_speed = 1.0 / maxf(fade, 0.01)
	d.volume_db = -80.0
	_start(d)
	plays[track] = int(plays.get(track, 0)) + 1
	played.emit(track)


## The music loop playing (&"" when none).
func current_music() -> StringName:
	return _music_name


func play_stinger(sound_name: StringName) -> void:
	if not is_node_ready():
		return
	var s := _admit(sound_name)
	if s == null:
		return
	_stinger.stop()
	_stinger.stream = s.pick(_rng)
	_stinger.bus = _bus(s.bus)
	_stinger.volume_db = s.volume_db
	_start(_stinger)
	_note(_stinger, sound_name)


## Cuts the stinger short (a scene change, a newer jingle).
func stop_stinger() -> void:
	_stinger.stop()
	_ends.erase(_stinger)


func _process(delta: float) -> void:
	# ducks: the deepest one wins, the stinger adds its own; eased so nothing jumps
	var want := 0.0
	for k in _ducks:
		want = minf(want, float(_ducks[k]))
	if _sounding(_stinger):
		want = minf(want, stinger_duck_db)
	_duck_now = move_toward(_duck_now, want, delta * (40.0 if want < _duck_now else 12.0))
	for i in _decks.size():
		var d: AudioStreamPlayer = _decks[i]
		_deck_gain[i] = move_toward(float(_deck_gain[i]), float(_deck_target[i]), delta * _fade_speed)
		var g := float(_deck_gain[i])
		if g <= 0.0005:
			if d.playing and float(_deck_target[i]) <= 0.0:
				d.stop()
			d.volume_db = -80.0
			continue
		# equal-power fade
		d.volume_db = float(_deck_db[i]) + linear_to_db(sin(g * PI * 0.5)) + _duck_now
