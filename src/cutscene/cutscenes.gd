class_name Cutscenes
extends RefCounted
## The story cutscenes of a campaign (scenes/cutscenes/<id>.tscn, src/cutscene/cutscene.gd):
##   "opening"        after the leader creator: who the Cometlings are, the Mother-Ice, the
##                    promise, the shed and the pad; it ends on the player's leader
##   "opening_short"  the same story in about 15 s, for the quick (fair mode) campaign
##   "ending_comet"   the comet passes and the player's probe met it: the probe at the
##                    Mother-Ice, its tail over the campus, the party, the leader
##   "ending_missed"  the comet passes without them: they watch it from the hill and
##                    promise to go next time
## Each plays once per campaign (TycoonState.story keeps the beats seen: "opening",
## "ending"), unless replayed from the pause menu ("Rewatch the opening"), and players can
## turn them off in the settings (user://settings.cfg, next to the launch cinematic).

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "tycoon"
const SETTINGS_KEY := "cutscenes"
const DIR := "res://scenes/cutscenes/"
const OPENING := "opening"
const OPENING_SHORT := "opening_short"
const ENDING_COMET := "ending_comet"
const ENDING_MISSED := "ending_missed"
const ALL := [OPENING, OPENING_SHORT, ENDING_COMET, ENDING_MISSED]
## cutscene id -> the story beat it stands for in TycoonState.story
const BEATS := {OPENING: "opening", OPENING_SHORT: "opening", ENDING_COMET: "ending", ENDING_MISSED: "ending"}

## the cutscene playing now (null when none)
static var current: Cutscene


static func path(id: String) -> String:
	return DIR + id + ".tscn"


static func enabled() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return bool(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, true))


static func set_enabled(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, on)
	cfg.save(SETTINGS_PATH)


static func beat(id: String) -> String:
	return String(BEATS.get(id, id))


## Has this campaign seen the story beat of cutscene `id`?
static func seen(state: TycoonState, id: String) -> bool:
	return state != null and bool(state.story.get(beat(id), false))


## The ending for a campaign whose comet has passed: the rendezvous if the player's comet
## mission met the Mother-Ice, else the bittersweet one.
static func ending_for(state: TycoonState) -> String:
	if state and state.race and state.race.met_comet(RaceDirector.PLAYER):
		return ENDING_COMET
	return ENDING_MISSED


static func is_playing() -> bool:
	return current != null and is_instance_valid(current) and current.playing


## Plays cutscene `id` over `host`'s screen and returns it (connect to `finished`), or null
## when it does not play: cutscenes are off, the campaign has seen it (unless `replay`),
## another one is playing or the scene is missing. Marks the beat as seen in `state`.
static func play(host: Node, id: String, state: TycoonState = null, replay := false) -> Cutscene:
	if host == null or not host.is_inside_tree():
		return null
	if not replay and (not enabled() or seen(state, id)):
		return null
	if is_playing():
		return null
	var ps := load(path(id)) as PackedScene if ResourceLoader.exists(path(id)) else null
	if ps == null:
		push_warning("Cutscenes: no cutscene %s" % id)
		return null
	var c := ps.instantiate() as Cutscene
	if c == null:
		return null
	c.id = id
	c.bind_state(state)
	if state:
		state.story[beat(id)] = true
	host.add_child(c)
	current = c
	c.start()
	return c
