class_name LaunchSequence
extends Control
## The launch moment of a mission project (scenes/tycoon/launch/launch_sequence.tscn, opened
## as the HUD screen "launch" by ProjectFlow when ProjectDesk launches a project).
##
## Everything you see is authored in the scene and keyed in its AnimationPlayer:
##   Stage            3D, placed on the launch pad: the rocket (engine flame, glowing trail,
##                    smoke trail), pad steam, ignition smoke and sparks, the ignition flash,
##                    the failure "poof" (a puff of smoke and twinkling stars, no debris),
##                    confetti and fireworks for a success, the shot camera (ShotCam) and a few
##                    spectator Cometlings. PreviewPad is the pad itself, for the editor only.
##   Overlay          a CanvasLayer over the HUD in the theme's look: letterbox bars (the clock
##                    sits in the bottom one, the skip hint is a pill), captions that pop
##                    (CwAppear), a warm flash, vignette and one result card per outcome
##                    (Success / Partial / Fail: rounded panel, big grade, "Continue" key).
##   Stage/Spectators the team, with CrewCam for the result shot (they turn to face it).
##   ShotRigs         the shot alternatives, Marker3D children tried in order (Front, Left, ...):
##                    each one places the whole Stage (rocket path, cameras, crew) around the
##                    pad. The first whose key shots see the rocket and the crew past the
##                    campus' buildings and trees (LaunchSightlines) is used; turn or add
##                    markers in the editor to change them. ShotRigs sits on the pad of the
##                    preview, like the Stage; only the markers' places relative to it count.
##   AnimationPlayer  "countdown" (T-10..0, ignition), then "flight_success", "flight_partial"
##                    or "flight_fail", then "result" (the card comes in) and "outro".
##   The target       shows on the way up: the glowing trail takes the target's colour ramp
##                    (`trail_ramps`, one GradientTexture1D per mission target, authored in the
##                    scene) and near the top of the climb the stage lets go (keyed call
##                    _stage_separation: the Stage/Rocket/Separation puff in the trail's colour;
##                    a suborbital hop has no stage to drop).
##   The rocket       the one the project designed (E2): the result's "rocket" parts are built
##                    by a DesignedRocket (scenes/tycoon/launch/designed_rocket.tscn, under
##                    Stage/Rocket/Model) from the same packed vessel the career flight flies
##                    (LaunchVessels.scene_for, with the mission's rover), at the flight's
##                    campus size. Results without a design show the example rocket the flight
##                    flies for them (TycoonModes.watch_vessel); the era models are a fallback.
##   The cause        a failed launch names what broke (the result's "cause_key", from the
##                    Design Review's risks) on the failure card.
## This script only drives it: picks the pad (the result's "pad", LaunchPads), the shot rig and
## the rocket, fills the texts, hands the campus camera to ShotCam (CampusCamera.begin_cinematic), fades the HUD chrome, makes
## the Cometlings cheer, and lets the player skip (click, Esc or Space: to the card, then out).
## The game clock is paused by ProjectFlow while a "launch" screen is up.
## Players can turn the sequence off in the settings (LaunchSequence.set_enabled()).
##
## One continuous launch (inside the tycoon, TycoonModes): at T-0 the career flight starts
## (TycoonModes.start_launch: a CareerFlight of the project's real rocket, flying the outcome
## this result already is) and every outcome climbs off the pad here ("flight_success" for all:
## a failure happens up in the sky, at its second). `handoff_time` into the climb the camera
## punches through a white cloud (PunchLayer/Punch) and comes out in the 3D flight
## (TycoonModes.open_launch_flight), on the same shot, the campus itself under the rocket:
## the flight goes on up to orbit and beyond. Leaving it ("Voltar ao campus") brings the team
## and the result card back here; the flight goes on in the background, on the Solar System map.

signal finished

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "tycoon"
const SETTINGS_KEY := "launch_cinematic"
const DESIGNED_ROCKET := "res://scenes/tycoon/launch/designed_rocket.tscn"

@export_group("Rocket")
## the rocket model per era (1..5), the same ones the pad shows
@export var rocket_models: Array[PackedScene] = []
## the designed rocket's look (DesignedRocket); empty: scenes/tycoon/launch/designed_rocket.tscn
@export var designed_rocket: PackedScene
## rocket size per launch class (data/tycoon/projects.json launch.type_class)
@export var class_scale := {"sounding": 0.8, "light": 0.95, "medium": 1.05, "heavy": 1.15, "lunar": 1.25}
## width and height (m) of the rocket the shots and the engine are made for (era 1)
@export var reference_size := Vector2(1.4, 7.0)
## the most the shot rig grows for a big rocket (times its authored size)
@export var max_rig_scale := 2.6
## how the shot rig grows with the height of a real vessel (DesignedRocket): its size is
## (height / reference_size.y) ^ this (1 = in proportion, like the era models)
@export_range(0.2, 1.0, 0.05) var vessel_rig_power := 0.5
@export_group("Smoke")
## bigger rockets make bigger clouds from more cubes, not from bigger ones: a cloud `f` times
## wider has cubes f^cube_exponent bigger and (f / that)^2 times as many of them
@export_range(0.0, 1.0, 0.05) var cube_exponent := 0.3
## at most this many times the authored number of cubes
@export var max_amount_scale := 2.5
@export_group("Shots")
## sight samples of a shot rig that may be blocked before the next one is tried
@export var blocked_tolerance := 0
## seconds into the flight the sight lines are checked (later the rocket is above everything)
@export var sight_window := 3.5
## cameras lower than this (m) must stay over the campus plateau (off it the ground drops: a
## camera that low would look into the cliff)
@export var plateau_camera_height := 2.0
## a ShotCam closer than this (m) to the crew and facing them is a crew shot: it must see them
@export var crew_shot_distance := 16.0
@export_group("Target")
## the glowing trail's colour ramp per mission target (data/tycoon/missions.json targets);
## a target without one keeps the authored warm trail
@export var trail_ramps: Dictionary[String, Texture2D] = {}
## how much of the target's colour the smoke trail takes (0 = the authored white smoke)
@export_range(0.0, 1.0, 0.05) var smoke_tint := 0.35
## targets whose rocket drops no stage on the way (no separation puff)
@export var no_separation: Array[String] = ["suborbital"]
@export_group("Pad")
## the pad's yaw the scene is laid out for (PreviewPad's, read in _ready when it is there)
@export var authored_pad_yaw := PI
@export_group("Timing")
## seconds the result card stays after the "result" animation before the sequence ends by itself
@export var result_hold := 2.5
@export_group("Flight")
## seconds into the climb when the camera goes through the cloud into the 3D flight
@export var handoff_time := 4.3
## seconds the cloud takes to cover the screen, and to clear in the flight
@export var punch_in := 0.25
@export var punch_out := 0.7
@export_group("Crowd")
## campus Cometlings closer than this to the pad (m) cheer too
@export var cheer_radius := 45.0
@export_group("Animated")
## camera shake, 0..1 (keyed in the AnimationPlayer)
@export_range(0.0, 1.0, 0.01) var shake := 0.0
## how much the spectators watch the rocket, 0..1 (keyed)
@export_range(0.0, 1.0, 0.01) var watch := 1.0
## how much the shot rig grows with a big rocket, 0..1 (keyed: 0 on the crew, so the team keeps
## its size in every era)
@export_range(0.0, 1.0, 0.01) var rig_zoom := 1.0

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
## the mission_launched result being shown
var result := {}
## "success", "partial" or "fail"
var kind := "success"
var camera: CampusCamera
var campus: Campus
## the lot the rocket leaves from, and the stage's frame there (the pad's place and facing)
var pad_lot := ""
var pad_frame := Transform3D.IDENTITY
## the ShotRigs marker in use, the blocked sight samples of each one tried, and why
## ({rig: {"ground", "off_plateau", "inside", "rocket", "crew", "result"}})
var shot_rig := ""
var shot_report := {}
var shot_reasons := {}

var _pad: CampusBuilding
var _phase := ""   # "", "show", "result", "outro", "done"
var _hold := 0.0
var _hud_tween: Tween
var _rig_size := 1.0      # the shot rig's size for this rocket (rig_zoom 1)
var _rocket_height := 7.0
## the rocket flying: the vessel the career flight flies (null only for the era-model fallback)
var designed: DesignedRocket
## the tycoon's modes (the live flight) and the career flight of this launch
var modes: TycoonModes
var run: CareerFlight
## "" (not yet), "campus" (climbing here), "punch", "flight" (in the 3D flight), "back"
var flight_phase := ""

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var stage: Node3D = $Stage
@onready var rocket: Node3D = $Stage/Rocket
@onready var shot_cam: Camera3D = $Stage/CamRig/ShotCam
@onready var cam_rig: Node3D = $Stage/CamRig
@onready var spectators: Node3D = $Stage/Spectators
@onready var crew_cam: Camera3D = $Stage/Spectators/CrewCam


# ------------------------------------------------------------ settings
static func enabled() -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return bool(cfg.get_value(SETTINGS_SECTION, SETTINGS_KEY, true))


static func set_enabled(on: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, SETTINGS_KEY, on)
	cfg.save(SETTINGS_PATH)


## The look of a launch outcome: "success" (full, exceptional), "partial" or "fail".
static func kind_of(r: Dictionary) -> String:
	var outcome := String(r.get("outcome", "full" if bool(r.get("success", false)) else "fail"))
	if not bool(r.get("success", outcome != "fail")) or outcome == "fail":
		return "fail"
	return "partial" if outcome == "partial" else "success"


# ------------------------------------------------------------ setup
func _ready() -> void:
	var preview := get_node_or_null("Stage/PreviewPad") as Node3D
	if preview:
		authored_pad_yaw = preview.rotation.y
		preview.queue_free()
	$Overlay.visible = true
	for c in _cards():
		c.visible = false
		var b := c.find_child("Continue", true, false) as Button
		if b:
			b.pressed.connect(_outro)
	anim.animation_finished.connect(_on_animation_finished)


## HUD screen hook.
func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h
	var main := h.owner as TycoonMain if h else null
	if main:
		camera = main.camera
		campus = main.campus
		modes = main.modes


## HUD screen hook: {"result": <mission_launched result>}.
func open_with(args: Dictionary) -> void:
	play(args.get("result", {}))


## Starts the sequence for a mission_launched result.
func play(r: Dictionary) -> void:
	result = r
	kind = kind_of(r)
	if camera == null:
		camera = get_viewport().get_camera_3d() as CampusCamera
	_place_on_pad()
	_dress_rocket()
	_dress_target()
	_dress_spectators()
	_choose_shot_rig()
	_fill_texts()
	if camera:
		camera.begin_cinematic(shot_cam)
	_fade_hud(0.0, 0.5)
	_phase = "show"
	anim.play("countdown")


## The pad it leaves from: the result's "pad" (ProjectDesk picked it, LaunchPads), else the
## one LaunchPads would pick. The stage takes the pad's place and facing.
func _place_on_pad() -> void:
	pad_lot = String(result.get("pad", ""))
	if pad_lot == "" and state:
		pad_lot = LaunchPads.pick(state, ProjectRules.launch_class(String(result.get("type", ""))))
	if campus == null:
		return
	var lot := campus.lots.get_node_or_null(pad_lot) as Node3D
	if lot == null:
		pad_lot = "pad"
		lot = campus.lots.get_node_or_null(pad_lot) as Node3D
	if lot == null:
		return
	_pad = campus.building_node(pad_lot)
	# the scene is authored around a pad turned `authored_pad_yaw` (PreviewPad): turn with this one
	var face := _pad.global_rotation.y if _pad else lot.global_rotation.y + float(lot.get_meta("face", 0.0))
	pad_frame = Transform3D(Basis(Vector3.UP, face - authored_pad_yaw), lot.global_position)
	stage.global_transform = pad_frame
	if _pad:
		_pad.hold_rocket(true)


func _dress_rocket() -> void:
	var era := state.era() if state else 1
	var model := rocket.get_node("Model") as Node3D
	var parts: Dictionary = (result.get("rocket", {}) as Dictionary).get("parts", {})
	var target := String(result.get("target", "leo"))
	var k := 1.0
	var core_w := 0.0
	# the rocket the career flight flies (TycoonModes.watch_vessel: the design's vessel from
	# LaunchVessels.scene_for with the mission's rover, or the example rocket of a launch with no
	# design), shown by DesignedRocket through the flight's own builder
	for c in model.get_children():
		model.remove_child(c)
		c.queue_free()
	var dps := designed_rocket if designed_rocket else load(DESIGNED_ROCKET) as PackedScene
	designed = dps.instantiate() as DesignedRocket
	model.add_child(designed)
	if not parts.is_empty():
		designed.build(parts, payload_of(state, result), target, state)
	elif not designed.show_scene(TycoonModes.watch_vessel(state, {}, target)):
		# fallback only: nothing to fly, the era's own rocket
		model.remove_child(designed)
		designed.queue_free()
		designed = null
	if designed:
		core_w = designed.core_size.x
	else:
		var e := clampi(era, 1, maxi(rocket_models.size(), 1))
		if e - 1 < rocket_models.size() and rocket_models[e - 1] != null:
			model.add_child(rocket_models[e - 1].instantiate())
		var cls := ProjectRules.launch_class(String(result.get("type", "")))
		k = float(class_scale.get(cls, 1.0))
	model.scale = Vector3.ONE * k
	# the engine and the shots grow with the rocket (the shots are framed for the era 1 one)
	var box := _bounds(model)
	if core_w <= 0.0:
		core_w = box.size.x * k
	var girth := maxf(core_w / reference_size.x, 0.5)
	($Stage/Rocket/Engine as Node3D).scale = Vector3.ONE * girth
	_rocket_height = box.size.y * k
	# the clouds grow with the rocket: its girth, or its height (a real vessel is slimmer than
	# the era models the clouds were made for, a tall one still makes a big cloud)
	_scale_fx(pow(maxf(girth, _rocket_height / reference_size.y), 0.7))
	# the shots were framed for the era models (about 1:5); a real vessel is slim (1:15 and
	# more), so the rig backs off less for its height or it frames empty sky around a sliver
	var hk := _rocket_height / reference_size.y
	_rig_size = clampf(pow(hk, vessel_rig_power) if designed else hk, 1.0, max_rig_scale)
	cam_rig.scale = Vector3.ONE * lerpf(1.0, _rig_size, rig_zoom)


## The payload modules a launch result carries (its own "payload", else its project's history
## entry): what LaunchVessels puts on the rocket (a rover rides on it).
static func payload_of(s: TycoonState, r: Dictionary) -> Array:
	var pl: Variant = r.get("payload", null)
	if pl is Array:
		return pl
	if s == null:
		return []
	var e := ProjectDesk.history_entry(s, String(r.get("project_id", "")))
	return e.get("payload", []) if e.get("payload", []) is Array else []


## The target in the sky: the trail's colour ramp, the separation puff in its colour, placed
## along the rocket and sized with it.
func _dress_target() -> void:
	var target := String(result.get("target", ""))
	var ramp := trail_ramps.get(target) as Texture2D
	var glow := get_node("Stage/Rocket/Engine/TrailGlow") as GPUParticles3D
	if ramp:
		var pm := (glow.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
		pm.color_ramp = ramp
		glow.process_material = pm
	var tint := _ramp_tint(ramp)
	if ramp and smoke_tint > 0.0:
		var smoke := get_node("Stage/Rocket/Engine/TrailSmoke") as GPUParticles3D
		var sm := (smoke.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
		sm.color = Color.WHITE.lerp(tint, smoke_tint)
		smoke.process_material = sm
	var sep := get_node_or_null("Stage/Rocket/Separation") as GPUParticles3D
	if sep == null:
		return
	sep.position.y = _rocket_height * 0.45
	var spm := (sep.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
	var f := maxf(_rocket_height / reference_size.y, 1.0)
	spm.emission_ring_radius *= sqrt(f)
	spm.emission_ring_inner_radius *= sqrt(f)
	spm.initial_velocity_min *= sqrt(f)
	spm.initial_velocity_max *= sqrt(f)
	spm.color = tint
	sep.process_material = spm


## The target colour of a trail ramp (its tail, brought to a 0..1 brightness), white without one.
static func _ramp_tint(ramp: Texture2D) -> Color:
	var g := (ramp as GradientTexture1D).gradient if ramp is GradientTexture1D else null
	if g == null:
		return Color.WHITE
	var c := g.sample(0.5)
	var top := maxf(maxf(c.r, c.g), maxf(c.b, 0.001))
	return Color(c.r / top, c.g / top, c.b / top, 1.0).lerp(Color.WHITE, 0.25)


## The project's team plays the spectators (their colours and profession looks).
func _dress_spectators() -> void:
	if state == null:
		return
	var h := ProjectDesk.history_entry(state, String(result.get("project_id", "")))
	var team: Array = h.get("staff", [])
	var i := 0
	for sp in spectators.get_children():
		var cr := sp as Cometling
		if cr == null:
			continue
		if i < team.size():
			var m := TycoonCrew.find(state, String(team[i]))
			if not m.is_empty():
				CometlingLooks.apply(cr, int(m.get("variant", 0)), TycoonCrew.look_role(String(m.get("profession", ""))))
				cr.glow_color = TycoonCrew.profession_color(state, String(m.get("profession", "")))
		i += 1


# ------------------------------------------------------------ shot rigs
## Tries the ShotRigs markers in order and keeps the first whose key shots are clear (see
## _blocked_samples), else the least blocked one. The Stage goes there.
func _choose_shot_rig() -> void:
	shot_report = {}
	shot_reasons = {}
	shot_rig = ""
	var rigs: Array[Node3D] = []
	var holder := get_node_or_null("ShotRigs")
	if holder:
		for m in holder.get_children():
			if m is Marker3D:
				rigs.append(m)
	if rigs.is_empty():
		stage.global_transform = pad_frame
		return
	var sight: LaunchSightlines = null
	if campus:
		# the pad's own tower counts; its rocket (held off: this one flies instead) and rollout do not
		var skip: Array = []
		if _pad:
			skip = _pad.find_children("Rocket", "Node3D", true, false)
		sight = LaunchSightlines.from_campus(campus, skip)
	var best := 0
	var best_n := 1000000
	for i in rigs.size():
		var why := {}
		var n := _blocked_samples(pad_frame * rigs[i].transform, sight, why) if sight else 0
		shot_report[String(rigs[i].name)] = n
		shot_reasons[String(rigs[i].name)] = why
		if n < best_n:
			best_n = n
			best = i
		if n <= blocked_tolerance:
			break
	shot_rig = String(rigs[best].name)
	stage.global_transform = pad_frame * rigs[best].transform


## How many key sight lines a stage placed at `xf` loses: every ShotCam key of the countdown and
## the early flight (and half way between) must see the rocket, and the crew when the shot faces
## them; CrewCam must see most of the crew; low cameras stay over the plateau and out of things;
## the crew stands on free ground.
func _blocked_samples(xf: Transform3D, sight: LaunchSightlines, why := {}) -> int:
	var count := func(reason: String, k: int) -> int:
		if k > 0:
			why[reason] = int(why.get(reason, 0)) + k
		return k
	var n := 0
	var crew: Array[Vector3] = []
	for sp in spectators.get_children():
		if sp is Cometling:
			var feet := xf * (spectators.transform * (sp as Node3D).transform.origin)
			if not sight.free_ground(feet):
				n += count.call("ground", 1)
			crew.append(feet + Vector3(0, 1.1, 0))
	var mid := Vector3.ZERO
	for c in crew:
		mid += c / crew.size()
	for a in ["countdown", "flight_" + kind]:
		var an := anim.get_animation(a)
		if an == null:
			continue
		var pos_t := an.find_track(NodePath("Stage/CamRig/ShotCam:position"), Animation.TYPE_VALUE)
		var rot_t := an.find_track(NodePath("Stage/CamRig/ShotCam:quaternion"), Animation.TYPE_VALUE)
		var rk_t := an.find_track(NodePath("Stage/Rocket:position"), Animation.TYPE_VALUE)
		var zoom_t := an.find_track(NodePath(".:rig_zoom"), Animation.TYPE_VALUE)
		if pos_t < 0:
			continue
		var times: Array[float] = []
		var keys := an.track_get_key_count(pos_t)
		for k in keys:
			var t := an.track_get_key_time(pos_t, k)
			times.append(t)
			if k + 1 < keys:
				times.append((t + an.track_get_key_time(pos_t, k + 1)) * 0.5)
		for t in times:
			if a != "countdown" and t > sight_window:
				continue
			var z := float(an.value_track_interpolate(zoom_t, t)) if zoom_t >= 0 else 1.0
			var cam := xf * ((an.value_track_interpolate(pos_t, t) as Vector3) * lerpf(1.0, _rig_size, z))
			if sight.inside(cam):
				n += count.call("inside", 1)
				continue
			if cam.y < plateau_camera_height and not sight.on_plateau(cam, 1.0):
				n += count.call("off_plateau", 1)
				continue
			var rp: Vector3 = an.value_track_interpolate(rk_t, t) if rk_t >= 0 else rocket.position
			if sight.blocked(cam, xf * (rp + Vector3(0, _rocket_height * 0.3, 0))) \
					and sight.blocked(cam, xf * (rp + Vector3(0, _rocket_height * 0.8, 0))):
				n += count.call("rocket", 1)
			if rot_t >= 0 and not crew.is_empty():
				var fwd := xf.basis * (Basis(an.value_track_interpolate(rot_t, t) as Quaternion) * Vector3.FORWARD)
				if cam.distance_to(mid) < crew_shot_distance and fwd.normalized().dot((mid - cam).normalized()) > 0.94:
					n += count.call("crew", _hidden(sight, cam, crew))
	# the result shot on the team (CrewCam is not scaled)
	var ra := anim.get_animation("result")
	var cc_t := ra.find_track(NodePath("Stage/Spectators/CrewCam:position"), Animation.TYPE_VALUE) if ra else -1
	if cc_t >= 0:
		for k in ra.track_get_key_count(cc_t):
			var cam := xf * (spectators.transform * (ra.track_get_key_value(cc_t, k) as Vector3))
			n += count.call("result", 2 if sight.inside(cam) else 2 * _hidden(sight, cam, crew))
	return n


## 1 when most of the crew is out of sight from `cam`.
static func _hidden(sight: LaunchSightlines, cam: Vector3, crew: Array[Vector3]) -> int:
	var lost := 0
	for c in crew:
		if sight.blocked(cam, c):
			lost += 1
	return 1 if lost * 2 > crew.size() else 0


func _fill_texts() -> void:
	var code := String(result.get("code", result.get("project_id", "")))
	var type_name := tr(String(state.mission_type(String(result.get("type", ""))).get("name_key", ""))) if state else ""
	var target_name := tr(String(state.mission_target(String(result.get("target", ""))).get("name_key", ""))) if state else ""
	var route := "%s  →  %s" % [type_name, target_name] if target_name != "" else type_name
	var rocket_name := String((result.get("rocket", {}) as Dictionary).get("name", ""))
	if rocket_name != "":
		route = tr("TY_LAUNCH_ROUTE_ROCKET") % [route, rocket_name]
	%MissionCode.text = code
	%MissionRoute.text = route
	if state:
		%MissionDate.text = tr("TY_LAUNCH_DATE") % [state.year(), state.week()]
	for card in _cards():
		(card.find_child("Title", true, false) as Label).text = code
		(card.find_child("Route", true, false) as Label).text = route
		(card.find_child("GradeValue", true, false) as Label).text = "0.0"
		(card.find_child("OddsValue", true, false) as Label).text = "%d%%" % int(round(float(result.get("p_success", 0.0)) * 100.0))
	if String(result.get("outcome", "")) == "exceptional":
		(%CardSuccess.find_child("Kicker", true, false) as Label).text = "TY_LAUNCH_KICK_EXCEPTIONAL"
	# what broke (the Design Review's risk that failed)
	var cause := %CardFail.find_child("Cause", true, false) as Label
	if cause:
		var ck := String(result.get("cause_key", ""))
		cause.visible = ck != ""
		cause.text = tr("TY_LAUNCH_CAUSE") % tr(ck) if ck != "" else ""


# ------------------------------------------------------------ the show
func _on_animation_finished(anim_name: StringName) -> void:
	match String(anim_name):
		"countdown":
			if _live():
				_start_flight()
				anim.play("flight_success")
			else:
				anim.play("flight_" + kind)
		"flight_success", "flight_partial", "flight_fail":
			_show_result()
		"result":
			_hold = result_hold
		"outro":
			_finish()


## The launch goes on in the 3D flight (inside the tycoon, with a real flight to show).
func _live() -> bool:
	return modes != null and is_instance_valid(modes) and modes.main != null and not result.is_empty()


## T-0: the career flight lifts off with this rocket; until the handoff it climbs here and this
## screen advances it.
func _start_flight() -> void:
	if run != null or not _live():
		return
	run = modes.start_launch(result)
	if run:
		modes.launch_hold += 1
		flight_phase = "campus"


func _release_flight() -> void:
	if flight_phase in ["campus", "punch"] and modes and is_instance_valid(modes):
		modes.launch_hold = maxi(modes.launch_hold - 1, 0)


## Through the cloud into the 3D flight, the camera where it is now.
func _handoff() -> void:
	if flight_phase != "campus":
		return
	flight_phase = "punch"
	var punch := get_node_or_null("%Punch") as CanvasItem
	var tw := create_tween()
	if punch:
		tw.tween_property(punch, "modulate:a", 1.0, punch_in)
	tw.tween_callback(func() -> void:
		var off := shot_cam.global_position - (rocket.global_position + Vector3(0, _rocket_height * 0.5, 0))
		_release_flight()
		if modes.open_launch_flight(off, _on_flight_closed, false, shot_cam.fov):
			flight_phase = "flight"
			anim.pause()
			$Overlay.visible = false
		else:
			flight_phase = "back"
		if punch:
			create_tween().tween_property(punch, "modulate:a", 0.0, punch_out))


## The player left the flight (or it ended): back to the team and the result card.
func _on_flight_closed() -> void:
	flight_phase = "back"
	$Overlay.visible = true
	# the modes let the campus camera go meanwhile: back on the team's shot
	if camera and is_instance_valid(camera):
		camera.begin_cinematic(crew_cam, 0.0)
	_crowd("success" if kind != "fail" else "failure")
	_show_result()


func _show_result() -> void:
	if _phase == "result" or _phase == "outro" or _phase == "done":
		return
	_phase = "result"
	var card: Control = null
	for c in _cards():
		c.visible = c.name == "Card" + kind.capitalize()
		if c.visible:
			card = c
	# the grade counts up on the card (CwNumberTicker under GradeValue)
	if card:
		var gv := card.find_child("GradeValue", true, false) as Label
		var fmt := func(v: float) -> String: return "%.1f" % v
		CwNumberTicker.show(gv, 0.0, fmt)
		CwNumberTicker.show(gv, float(result.get("grade", 0.0)), fmt)
	# cut to the team
	if camera and camera.is_cinematic():
		camera.begin_cinematic(crew_cam, 0.0)
	_crowd_mood()
	anim.play("result")


func _outro() -> void:
	if _phase == "outro" or _phase == "done":
		return
	_phase = "outro"
	_hold = 0.0
	if camera:
		camera.end_cinematic()
	_fade_hud(1.0, 0.8)
	anim.play("outro")


## Click, Esc or Space: during the show jump to the result card, on the card leave.
func skip() -> void:
	match _phase:
		"show":
			if _live() and flight_phase in ["", "campus"]:
				# the flight goes on without being watched
				_start_flight()
				_release_flight()
				flight_phase = "back"
			var flight := "flight_" + kind
			anim.play(flight)
			anim.seek(anim.current_animation_length, true)
			_crowd("success" if kind != "fail" else "failure")
			_show_result()
		"result":
			_outro()


func _finish() -> void:
	if _phase == "done":
		return
	_phase = "done"
	_restore()
	finished.emit()
	if hud and hud.current_screen() == "launch":
		hud.close_screen()
	elif not hud:
		queue_free()


func _restore() -> void:
	# the pad's rocket comes back as the state says: after a real launch the next one is rolled out
	if _pad and is_instance_valid(_pad):
		_pad.hold_rocket(false)
	if camera and is_instance_valid(camera):
		camera.cinematic_shake = 0.0
		if camera.is_cinematic():
			camera.end_cinematic()
	if hud and is_instance_valid(hud) and hud.is_inside_tree() and hud.modulate.a < 1.0:
		_fade_hud(1.0, 0.5)


func _exit_tree() -> void:
	_release_flight()
	if _phase != "done":
		_phase = "done"
		_restore()
		finished.emit()


func _process(delta: float) -> void:
	if flight_phase == "campus" and run:
		# the flight climbs with the campus show until the handoff
		run.advance(delta)
		run.take_pending()
		if anim.current_animation == "flight_success" and anim.current_animation_position >= handoff_time:
			_handoff()
	if flight_phase in ["punch", "flight"]:
		return
	if camera and camera.is_cinematic():
		camera.cinematic_shake = shake
	cam_rig.scale = Vector3.ONE * lerpf(1.0, _rig_size, rig_zoom)
	var look := rocket.global_position + Vector3(0, 4, 0)
	if _phase == "result" or _phase == "outro":
		look = crew_cam.global_position
	var cam3 := get_viewport().get_camera_3d()
	var bar := $Overlay/Frame/BarBottom as Control
	var floor_y := bar.get_global_rect().position.y if bar.is_visible_in_tree() else get_viewport().get_visible_rect().size.y
	for sp in spectators.get_children():
		if sp is Cometling:
			var cr := sp as Cometling
			cr.look_at_point(look, watch)
			# a spectator under the frame's bottom bar (the low lift / climb shots) would show only
			# its emote bubble poking over the bar, like a stray marker: no bubble out of the shot
			if cr.emote_sprite.visible and cam3:
				var body := cr.global_position + Vector3.UP * 0.6
				if cam3.is_position_behind(body) or cam3.unproject_position(body).y > floor_y:
					cr.emote_sprite.visible = false
	if _phase == "result" and _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			_outro()


func _input(event: InputEvent) -> void:
	if flight_phase in ["punch", "flight"] or (modes and is_instance_valid(modes) and modes.is_open()):
		return  # the 3D flight has the keys
	if _phase == "" or _phase == "done" or CwDevMenu.blocks_mouse(event):
		return  # (clicks on the dev menu are the menu's, not a skip)
	var hit := false
	if event is InputEventKey and event.pressed and not event.echo:
		hit = (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
		# the speed keys wait: the clock stays paused during the launch
		if not hit and (event as InputEventKey).keycode in [KEY_1, KEY_2, KEY_3]:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		hit = mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]
		# the card's "Continue" key takes its own click (it presses, then leaves)
		if hit and _phase == "result" and mb.button_index == MOUSE_BUTTON_LEFT and _over_continue(mb.position):
			return
		if not hit:
			get_viewport().set_input_as_handled()  # no zoom either
	if hit:
		get_viewport().set_input_as_handled()
		skip()


func _over_continue(pos: Vector2) -> bool:
	for c in _cards():
		var b := c.find_child("Continue", true, false) as Button
		if c.visible and b and b.get_global_rect().has_point(pos):
			return true
	return false


# ------------------------------------------------------------ keyed calls
## Called from the AnimationPlayer: the spectators and the campus Cometlings near the pad react
## ("launch", "success", "failure" as in Cometling.react()).
func _crowd(event: String) -> void:
	for sp in spectators.get_children():
		if sp is Cometling:
			(sp as Cometling).react(event)
	if campus == null:
		return
	for w in campus.cometlings():
		if w.global_position.distance_to(stage.global_position) > cheer_radius:
			continue
		var cr := w.get("creature") as Cometling
		if cr:
			cr.react(event)


## The crew on the result card: a dance for a success, a relieved nod for a partial one,
## sitting down sadly after a failure.
func _crowd_mood() -> void:
	if kind == "success":
		($Stage/Spectators/Confetti as GPUParticles3D).restart()
		var fw := get_node_or_null("Stage/Spectators/Fireworks") as FxOneShot
		if fw:
			fw.play()   # fireworks over the team (scenes/tycoon/fx/fireworks.tscn)
	var i := 0
	for sp in spectators.get_children():
		var cr := sp as Cometling
		if cr == null:
			continue
		# turn to the result camera (CrewCam): the card shows their faces
		var to := crew_cam.global_position - cr.global_position
		to.y = 0.0
		if to.length() > 0.1:
			var sc := cr.scale
			cr.global_basis = Basis.looking_at(to, Vector3.UP, true)
			cr.scale = sc
		match kind:
			"success":
				cr.play("dance")
				cr.show_emote(["heart", "star", "sparkle", "happy"][i % 4], 3.0)
			"partial":
				cr.play_sequence(["nod", "cheer"])
				cr.show_emote(["sweat", "happy"][i % 2], 2.5)
			_:
				cr.play("sit")
				cr.show_emote(["sweat", "question"][i % 2], 2.5)
		i += 1


## Called from the AnimationPlayer near the top of the climb: the spent stage lets go.
func _stage_separation() -> void:
	# the designed rocket's side boosters go first (even on a suborbital hop)
	if designed:
		designed.drop_boosters()
	if String(result.get("target", "")) in no_separation:
		return
	var sep := get_node_or_null("Stage/Rocket/Separation") as GPUParticles3D
	if sep:
		sep.restart()


## Called from the AnimationPlayer: one emote over every spectator.
func _emote(emote: String) -> void:
	for sp in spectators.get_children():
		if sp is Cometling:
			(sp as Cometling).show_emote(emote, 2.2)


# ------------------------------------------------------------ helpers
## Bigger rockets, bigger clouds: the world-space particles (trail, pad smoke, steam, sparks)
## do not follow their node's scale, so their materials get a scaled copy. The cloud grows by
## `f` (where the cubes start, how fast and far they go); the cubes themselves only by
## f^cube_exponent, and there are more of them to fill the bigger cloud.
func _scale_fx(f: float) -> void:
	if is_equal_approx(f, 1.0):
		return
	var cube := pow(f, cube_exponent)
	var more := clampf(pow(f / cube, 2.0), 1.0, max_amount_scale)
	for path in ["Stage/Rocket/Engine", "Stage/PadFX"]:
		for n in get_node(path).find_children("*", "GPUParticles3D", true, false):
			var g := n as GPUParticles3D
			var pm := g.process_material as ParticleProcessMaterial
			if g.local_coords or pm == null:
				continue
			pm = pm.duplicate() as ParticleProcessMaterial
			pm.scale_min *= cube
			pm.scale_max *= cube
			g.amount = maxi(int(round(g.amount * more)), 1)
			pm.emission_sphere_radius *= f
			pm.emission_ring_radius *= f
			pm.emission_ring_inner_radius *= f
			pm.initial_velocity_min *= f
			pm.initial_velocity_max *= f
			pm.damping_min *= f
			pm.damping_max *= f
			pm.gravity *= f
			g.process_material = pm
			g.visibility_aabb = AABB(g.visibility_aabb.position * f, g.visibility_aabb.size * f)


## Bounds of the meshes under a node, in the node's parent space (before its own scale).
static func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var inv := n.global_transform.affine_inverse()
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b := (inv * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _cards() -> Array[Control]:
	var out: Array[Control] = []
	for c in %Cards.get_children():
		if c is Control:
			out.append(c)
	return out


## Fades the HUD chrome (not this screen: the Overlay is its own CanvasLayer).
func _fade_hud(alpha: float, seconds: float) -> void:
	if hud == null:
		return
	if _hud_tween:
		_hud_tween.kill()
	_hud_tween = hud.create_tween()
	_hud_tween.tween_property(hud, "modulate:a", alpha, seconds)
