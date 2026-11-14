extends SceneTree
## One-shot generator of scenes/tycoon/launch/launch_sequence.tscn (the launch moment, see
## src/tycoon/launch/launch_sequence.gd). It lays out the first version of the scene: the
## particles, lights, rocket rig, shot camera, spectators, overlay UI and every keyed
## animation (the rocket's flight path and the camera moves are sampled here).
## After that the .tscn is the source: tune it in the editor. Running this again OVERWRITES
## the scene with the values below, and loses what was added to the scene since (the ShotRigs
## markers, the rig_zoom and _stage_separation keys, Stage/Rocket/Separation, the trail_ramps,
## the LaunchAudio instance).
## Run: godot --headless --path . --script res://tools/build_launch_sequence.gd

const OUT := "res://scenes/tycoon/launch/launch_sequence.tscn"
const SCRIPT := "res://src/tycoon/launch/launch_sequence.gd"
const PAD := "res://scenes/tycoon/buildings/pad.tscn"
const CREATURE := "res://scenes/npc/creature.tscn"
const THEME := "res://ui/cometworks_theme.tres"

# palette (ui/cometworks_palette.gd)
const SPACE := Color("#070b14")
const PANEL := Color("#0e1524")
const LINE := Color("#24324d")
const HAIRLINE := Color("#3a4d72")
const TEXT := Color("#e9eef7")
const TEXT_DIM := Color("#8c9ab5")
const TEAL := Color("#3fe0c5")
const VIOLET := Color("#8e7cff")
const IGNITION := Color("#ff8a3d")
const IGNITION_HI := Color("#ffa766")
const ICE := Color("#bfe8ff")
const WARNING := Color("#ffc547")
const DANGER := Color("#ff5c6c")
const SUCCESS := Color("#5bd68e")
## letterbox bars: the HUD's deep navy
const BAR_COLOR := Color(0.035, 0.043, 0.13, 0.97)
## secondary cream text (CwDim colour)
const TEXT_SOFT := Color(0.7647, 0.7882, 0.9176)

## letterbox bar height (px at 1600x900)
const BAR := 92.0
## rocket base on the pad (stage space; the stage sits on the pad lot, world-aligned)
const BASE := Vector3(0, 1.15, 0)
## the result shot of the crew (stage space; the crew stands around (9.8, 0, 11))
const CREW_CAM := Vector3(15.8, 2.3, 17.8)
const CREW_AIM := Vector3(7.6, 1.5, 12.6)
## downrange: towards the comet Mae-Gelo, over the far side of the campus
var DOWN := Vector3(-0.55, 0, -0.835).normalized()

# countdown timing
const TICK0 := 0.6
const TICK := 0.58
const IGNITE := 6.4
const COUNT_LEN := 7.0

var seq: Control
var anim_player: AnimationPlayer
var lib: AnimationLibrary


func _initialize() -> void:
	seq = Control.new()
	seq.name = "LaunchSequence"
	seq.set_anchors_preset(Control.PRESET_FULL_RECT)
	seq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seq.set_script(load(SCRIPT))
	var models: Array[PackedScene] = []
	for e in range(1, 6):
		models.append(load("res://assets/campus/pad/rocket_e%d.glb" % e))
	seq.set("rocket_models", models)
	_stage()
	_overlay()
	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	seq.add_child(anim_player)
	lib = AnimationLibrary.new()
	_anim_countdown()
	_anim_flight("success")
	_anim_flight("partial")
	_anim_fail()
	_anim_result()
	_anim_outro()
	_anim_reset()
	anim_player.add_animation_library("", lib)
	_own(seq)
	var ps := PackedScene.new()
	var err := ps.pack(seq)
	if err != OK:
		push_error("pack failed %d" % err)
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	err = ResourceSaver.save(ps, OUT)
	print("saved %s (%d)" % [OUT, err])
	seq.free()
	quit()


func _own(n: Node) -> void:
	for c in n.get_children():
		c.owner = seq
		if c.scene_file_path == "":
			_own(c)


# ------------------------------------------------------------ 3D stage
func _stage() -> void:
	var stage := Node3D.new()
	stage.name = "Stage"
	stage.position = Vector3(38, 0, 20)
	seq.add_child(stage)
	var pad := (load(PAD) as PackedScene).instantiate() as Node3D
	pad.name = "PreviewPad"
	pad.rotation.y = PI
	stage.add_child(pad)

	# --- rocket rig
	var rocket := Node3D.new()
	rocket.name = "Rocket"
	rocket.position = BASE
	stage.add_child(rocket)
	var model := Node3D.new()
	model.name = "Model"
	rocket.add_child(model)
	var body := (load("res://assets/campus/pad/rocket_e1.glb") as PackedScene).instantiate()
	body.name = "Body"
	model.add_child(body)
	var engine := Node3D.new()
	engine.name = "Engine"
	engine.position = Vector3(0, 0.1, 0)
	rocket.add_child(engine)
	engine.add_child(_flame())
	engine.add_child(_flame_core())
	engine.add_child(_trail_glow())
	engine.add_child(_trail_smoke())
	engine.add_child(_glint())
	var el := OmniLight3D.new()
	el.name = "EngineLight"
	el.light_color = Color(1.0, 0.62, 0.3)
	el.light_energy = 0.0
	el.omni_range = 22.0
	el.omni_attenuation = 1.1
	el.shadow_enabled = true
	el.position = Vector3(0, -0.6, 0)
	engine.add_child(el)
	# where a failed rocket pops (placed by _anim_fail on the keyed path)
	var fail := Node3D.new()
	fail.name = "FailFX"
	stage.add_child(fail)
	fail.add_child(_poof())
	fail.add_child(_debris())
	var pl := OmniLight3D.new()
	pl.name = "PopLight"
	pl.light_color = Color(1.0, 0.6, 0.35)
	pl.light_energy = 0.0
	pl.omni_range = 26.0
	fail.add_child(pl)

	# --- pad effects
	var fx := Node3D.new()
	fx.name = "PadFX"
	stage.add_child(fx)
	fx.add_child(_steam())
	fx.add_child(_smoke())
	fx.add_child(_sparks())
	var flash := OmniLight3D.new()
	flash.name = "FlashLight"
	flash.light_color = Color(1.0, 0.7, 0.42)
	flash.light_energy = 0.0
	flash.omni_range = 46.0
	flash.omni_attenuation = 0.9
	flash.position = Vector3(0, 2.5, 0)
	fx.add_child(flash)

	# --- spectators: a few Cometlings at the edge of the pad lot, facing the rocket
	var sp := Node3D.new()
	sp.name = "Spectators"
	stage.add_child(sp)
	var spots := [Vector3(9.0, 0, 10.6), Vector3(10.9, 0, 9.2), Vector3(7.4, 0, 12.0), Vector3(12.0, 0, 11.0), Vector3(9.8, 0, 12.8)]
	var ps := load(CREATURE) as PackedScene
	for i in spots.size():
		var c := ps.instantiate() as Node3D
		c.name = "Cometling%d" % (i + 1)
		var p: Vector3 = spots[i]
		c.transform = Transform3D(Basis.looking_at(-Vector3(p.x, 0, p.z), Vector3.UP, true).scaled(Vector3.ONE * 1.6), p)
		c.set("listen_to_events", false)
		c.set("personality_seed", 11 + i * 7)
		c.set("start_action", "idle")
		sp.add_child(c)
	# a warm fill on the crew's faces for the result card
	var cl := OmniLight3D.new()
	cl.name = "CrewLight"
	cl.light_color = Color(1.0, 0.78, 0.55)
	cl.light_energy = 0.0
	cl.omni_range = 9.0
	cl.position = Vector3(6.2, 3.2, 7.6)
	sp.add_child(cl)
	var crew_cam := Camera3D.new()
	crew_cam.name = "CrewCam"
	crew_cam.fov = 42.0
	crew_cam.near = 0.1
	crew_cam.far = 2400.0
	crew_cam.current = false
	crew_cam.transform = _look(CREW_CAM, CREW_AIM)
	sp.add_child(crew_cam)
	var confetti := _confetti()
	confetti.position = Vector3(9.8, 3.5, 11.0)
	sp.add_child(confetti)

	# --- the shot camera (CampusCamera copies it while the sequence plays)
	var rig := Node3D.new()
	rig.name = "CamRig"
	stage.add_child(rig)
	var cam := Camera3D.new()
	cam.name = "ShotCam"
	cam.fov = 42.0
	cam.near = 0.1
	cam.far = 2400.0
	cam.current = false
	rig.add_child(cam)
	cam.transform = _look(Vector3(30, 14, 30), Vector3(0, 5, 0))


# ------------------------------------------------------------ materials
func _cube_mat(unshaded: bool, additive: bool, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.roughness = 1.0
	m.disable_receive_shadows = true
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = Color(1, 1, 1)
		m.emission_energy_multiplier = emission
	return m


func _cube(size: float, mat: Material) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3.ONE * size
	b.material = mat
	return b


func _grad(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p: Vector2 in points:
		c.add_point(p)
	var t := CurveTexture.new()
	t.curve = c
	return t


func _particles(n: String, amount: int, lifetime: float, pm: ParticleProcessMaterial, mesh: Mesh) -> GPUParticles3D:
	var g := GPUParticles3D.new()
	g.name = n
	g.amount = amount
	g.lifetime = lifetime
	g.process_material = pm
	g.draw_pass_1 = mesh
	g.emitting = false
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 60, 80))
	return g


# ------------------------------------------------------------ particle systems
func _steam() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 2.2
	pm.emission_ring_inner_radius = 1.2
	pm.emission_ring_height = 0.3
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0.1, 0.35, 0.05)
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.particle_flag_rotate_y = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -40.0
	pm.angular_velocity_max = 40.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.scale_curve = _curve([Vector2(0, 0.3), Vector2(0.3, 1.0), Vector2(1, 1.5)])
	pm.color_ramp = _grad([0.0, 0.12, 0.55, 1.0], [Color(1, 1, 1, 0), Color(0.96, 0.98, 1, 0.9), Color(0.9, 0.94, 1, 0.55), Color(0.9, 0.94, 1, 0)])
	var g := _particles("Steam", 160, 2.4, pm, _cube(0.55, _cube_mat(false, false, 0.3)))
	g.position = Vector3(0, 0.6, 0)
	return g


func _smoke() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2
	pm.direction = Vector3(1, 0, 0)
	pm.spread = 180.0
	pm.flatness = 0.9
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3(0, 0.45, 0)
	pm.damping_min = 4.5
	pm.damping_max = 7.0
	pm.particle_flag_rotate_y = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -25.0
	pm.angular_velocity_max = 25.0
	pm.scale_min = 0.8
	pm.scale_max = 1.5
	pm.scale_curve = _curve([Vector2(0, 0.35), Vector2(0.25, 1.0), Vector2(1, 1.7)])
	pm.color_ramp = _grad([0.0, 0.06, 0.3, 0.75, 1.0], [Color(1, 0.86, 0.66, 0.0), Color(1, 0.9, 0.75, 0.95), Color(0.95, 0.94, 0.95, 0.9), Color(0.85, 0.87, 0.92, 0.55), Color(0.82, 0.85, 0.9, 0.0)])
	var g := _particles("Smoke", 420, 4.5, pm, _cube(1.0, _cube_mat(false, false, 0.18)))
	g.position = Vector3(0, 0.9, 0)
	g.visibility_aabb = AABB(Vector3(-60, -4, -60), Vector3(120, 40, 120))
	return g


func _sparks() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.8
	pm.direction = Vector3(0, 0.6, 0)
	pm.spread = 180.0
	pm.flatness = 0.4
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 15.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.scale_curve = _curve([Vector2(0, 1), Vector2(1, 0)])
	pm.color_ramp = _grad([0.0, 0.5, 1.0], [Color(4, 3.2, 1.8, 1), Color(3, 1.4, 0.4, 1), Color(1.5, 0.3, 0.1, 0)])
	var g := _particles("Sparks", 110, 1.4, pm, _cube(0.16, _cube_mat(true, true)))
	g.one_shot = true
	g.explosiveness = 0.85
	g.position = Vector3(0, 0.8, 0)
	return g


func _flame() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 9.0
	pm.initial_velocity_min = 14.0
	pm.initial_velocity_max = 21.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 6.0
	pm.damping_max = 10.0
	pm.particle_flag_rotate_y = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = 0.55
	pm.scale_max = 0.95
	pm.scale_curve = _curve([Vector2(0, 0.6), Vector2(0.2, 1.0), Vector2(1, 0.15)])
	pm.color_ramp = _grad([0.0, 0.2, 0.55, 1.0], [Color(5, 4.6, 3.4, 1), Color(4, 2.4, 0.9, 1), Color(2.4, 0.8, 0.25, 0.8), Color(0.6, 0.12, 0.08, 0)])
	var g := _particles("Flame", 140, 0.32, pm, _cube(0.55, _cube_mat(true, true)))
	g.local_coords = true
	g.fixed_fps = 0
	g.visibility_aabb = AABB(Vector3(-4, -10, -4), Vector3(8, 12, 8))
	return g


func _flame_core() -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.86, 0.55)
	m.emission_enabled = true
	m.emission = Color(1, 0.75, 0.4)
	m.emission_energy_multiplier = 6.0
	var p := PrismMesh.new()
	p.size = Vector3(0.9, 3.2, 0.9)
	p.material = m
	var mi := MeshInstance3D.new()
	mi.name = "FlameCore"
	mi.mesh = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the prism points down, its top at the nozzle
	mi.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, -1.6, 0))
	mi.scale = Vector3(1, 0.001, 1)
	mi.visible = false
	return mi


func _trail_glow() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 2.0
	pm.damping_max = 3.0
	pm.particle_flag_rotate_y = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	pm.scale_curve = _curve([Vector2(0, 1.0), Vector2(1, 0.0)])
	pm.color_ramp = _grad([0.0, 0.3, 1.0], [Color(4.5, 3.4, 1.8, 1), Color(3.2, 1.2, 0.35, 0.9), Color(1.2, 0.25, 0.4, 0)])
	var g := _particles("TrailGlow", 260, 1.1, pm, _cube(0.7, _cube_mat(true, true)))
	g.local_coords = false
	g.position = Vector3(0, -1.2, 0)
	g.visibility_aabb = AABB(Vector3(-400, -400, -400), Vector3(800, 800, 800))
	return g


func _trail_smoke() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0.25, 0.2, 0.1)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.particle_flag_rotate_y = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -20.0
	pm.angular_velocity_max = 20.0
	pm.scale_min = 1.0
	pm.scale_max = 1.6
	pm.scale_curve = _curve([Vector2(0, 0.5), Vector2(0.15, 1.0), Vector2(1, 2.6)])
	pm.color_ramp = _grad([0.0, 0.05, 0.4, 1.0], [Color(1, 0.8, 0.6, 0), Color(1, 0.92, 0.85, 0.9), Color(0.92, 0.93, 0.98, 0.6), Color(0.85, 0.88, 0.96, 0)])
	var g := _particles("TrailSmoke", 900, 6.5, pm, _cube(1.0, _cube_mat(false, false, 0.35)))
	g.local_coords = false
	g.position = Vector3(0, -2.2, 0)
	g.visibility_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	return g


## A soft star that keeps the rocket visible when it is a dot in the sky.
func _glint() -> MeshInstance3D:
	var tex := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 1.0])
	gr.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 0.85, 0.55, 0.85), Color(1, 0.55, 0.25, 0.25), Color(1, 0.4, 0.2, 0)])
	tex.gradient = gr
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = tex
	m.albedo_color = Color(3.0, 2.4, 1.6, 1)
	m.no_depth_test = false
	var q := QuadMesh.new()
	q.size = Vector2(6, 6)
	q.material = m
	var mi := MeshInstance3D.new()
	mi.name = "Glint"
	mi.mesh = q
	mi.position = Vector3(0, -1.0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transparency = 1.0
	return mi


func _poof() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2
	pm.direction = Vector3(0, 0.3, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 3.0
	pm.damping_max = 5.0
	pm.particle_flag_rotate_y = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -60.0
	pm.angular_velocity_max = 60.0
	pm.scale_min = 1.4
	pm.scale_max = 2.6
	pm.scale_curve = _curve([Vector2(0, 0.3), Vector2(0.15, 1.0), Vector2(1, 1.8)])
	pm.color_ramp = _grad([0.0, 0.06, 0.25, 1.0], [Color(3, 1.6, 0.6, 1), Color(1, 0.6, 0.35, 1), Color(0.42, 0.42, 0.48, 0.95), Color(0.3, 0.3, 0.36, 0)])
	var g := _particles("Poof", 140, 3.4, pm, _cube(0.9, _cube_mat(false, false, 0.15)))
	g.one_shot = true
	g.explosiveness = 1.0
	g.local_coords = false
	g.visibility_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
	return g


func _debris() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 13.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.particle_flag_rotate_y = true
	pm.angular_velocity_min = -300.0
	pm.angular_velocity_max = 300.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color_ramp = _grad([0.0, 0.4, 1.0], [Color(4, 2.6, 1.2, 1), Color(2.6, 0.9, 0.3, 1), Color(0.4, 0.2, 0.2, 0)])
	var g := _particles("Debris", 60, 2.2, pm, _cube(0.28, _cube_mat(true, true)))
	g.one_shot = true
	g.explosiveness = 0.95
	g.local_coords = false
	g.visibility_aabb = AABB(Vector3(-200, -200, -200), Vector3(400, 400, 400))
	return g


func _confetti() -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 2.5
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 40.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -6.0, 0)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.particle_flag_rotate_y = true
	pm.angular_velocity_min = -400.0
	pm.angular_velocity_max = 400.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8])
	g.colors = PackedColorArray([TEAL * 1.6, VIOLET * 1.6, IGNITION * 1.6, WARNING * 1.6, ICE * 1.6])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	pm.alpha_curve = _curve([Vector2(0, 1), Vector2(0.75, 1), Vector2(1, 0)])
	var mat := _cube_mat(true, false)
	var b := BoxMesh.new()
	b.size = Vector3(0.12, 0.03, 0.18)
	b.material = mat
	var p := _particles("Confetti", 160, 3.2, pm, b)
	p.one_shot = true
	p.explosiveness = 0.9
	return p


# ------------------------------------------------------------ overlay
## A label in one of the theme's type variations (ui/cometworks_theme.tres), optional size / colour.
func _label(n: String, text: String, variation: String, size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.name = n
	l.text = text
	l.theme_type_variation = StringName(variation)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _motion(node_name: String, script_name: String, props: Dictionary) -> Node:
	var n := Node.new()
	n.name = node_name
	n.set_script(load("res://src/tycoon/ui/motion/%s.gd" % script_name))
	for k: String in props:
		n.set(k, props[k])
	return n


func _dot(n: String, color: Color, px := 10.0) -> Panel:
	var d := Panel.new()
	d.name = n
	d.theme_type_variation = &"CwDot"
	d.self_modulate = color
	d.custom_minimum_size = Vector2(px, px)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d


## A small rounded pill (the HUD's hint style) holding `content`.
func _pill(n: String, content: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = n
	p.theme_type_variation = &"CwHintPill"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(content)
	return p


func _overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Overlay"
	layer.layer = 20
	seq.add_child(layer)
	var ui := Control.new()
	ui.name = "Frame"
	ui.unique_name_in_owner = true
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = load(THEME)
	layer.add_child(ui)

	# vignette
	var vt := GradientTexture2D.new()
	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	vg.colors = PackedColorArray([Color(0.03, 0.04, 0.12, 0), Color(0.03, 0.04, 0.12, 0.08), Color(0.03, 0.04, 0.12, 0.62)])
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.08, 1.08)
	vt.width = 256
	vt.height = 256
	var vig := TextureRect.new()
	vig.name = "Vignette"
	vig.texture = vt
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.modulate = Color(1, 1, 1, 0)
	ui.add_child(vig)

	# warm flash at ignition
	var fl := ColorRect.new()
	fl.name = "Flash"
	fl.color = Color(1, 0.9, 0.74, 1)
	fl.set_anchors_preset(Control.PRESET_FULL_RECT)
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.modulate = Color(1, 1, 1, 0)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fl.material = add
	ui.add_child(fl)

	_caption(ui)
	_bars(ui)
	_cards_node(ui)


func _bar(n: String) -> ColorRect:
	var b := ColorRect.new()
	b.name = n
	b.color = BAR_COLOR
	b.anchor_right = 1.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _bars(ui: Control) -> void:
	# top bar: the mission
	var top := _bar("BarTop")
	top.offset_top = -BAR
	top.offset_bottom = 0.0
	ui.add_child(top)
	var info := HBoxContainer.new()
	info.name = "Info"
	info.set_anchors_preset(Control.PRESET_FULL_RECT)
	info.offset_left = 48
	info.offset_right = -48
	info.add_theme_constant_override("separation", 18)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(info)
	var left := VBoxContainer.new()
	left.name = "Mission"
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_theme_constant_override("separation", 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(left)
	left.add_child(_label("Kicker", "TY_LAUNCH_CONTROL", "CwCapsAccent", 13))
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 14)
	left.add_child(row)
	var code := _label("MissionCode", "SND-01", "CwHeading", 28)
	code.unique_name_in_owner = true
	row.add_child(code)
	var route := _label("MissionRoute", "Sounding rocket  →  Suborbital", "CwBody", 17, TEXT_SOFT)
	route.unique_name_in_owner = true
	route.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(route)
	var right := HBoxContainer.new()
	right.name = "When"
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 14)
	info.add_child(right)
	var date := _label("MissionDate", "Year 1, week 12", "CwDim", 14)
	date.unique_name_in_owner = true
	date.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(date)
	var live_row := HBoxContainer.new()
	live_row.name = "Row"
	live_row.add_theme_constant_override("separation", 8)
	live_row.add_child(_dot("Dot", DANGER, 9.0))
	live_row.add_child(_label("Text", "TY_LAUNCH_LIVE", "CwBody", 14))
	var live := _pill("Live", live_row)
	live.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.add_child(live)
	live_row.get_node("Dot").add_child(_motion("Pulse", "cw_pulse", {"on_poke": false, "loop": true, "period": 1.6, "peak_scale": Vector2(1.35, 1.35), "glow": 1.4}))

	# bottom bar: status (left), the clock (centre), the skip pill (right)
	var bot := _bar("BarBottom")
	bot.anchor_top = 1.0
	bot.anchor_bottom = 1.0
	bot.offset_top = 0.0
	bot.offset_bottom = BAR
	ui.add_child(bot)
	var thread_tex := GradientTexture2D.new()
	var tg := Gradient.new()
	tg.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	tg.colors = PackedColorArray([TEAL, VIOLET, IGNITION])
	thread_tex.gradient = tg
	thread_tex.width = 256
	thread_tex.height = 2
	var thread := TextureRect.new()
	thread.name = "Thread"
	thread.texture = thread_tex
	thread.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thread.stretch_mode = TextureRect.STRETCH_SCALE
	thread.anchor_right = 1.0
	thread.offset_bottom = 3.0
	thread.scale = Vector2(0, 1)
	thread.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot.add_child(thread)
	var srow := HBoxContainer.new()
	srow.name = "Status"
	srow.anchor_bottom = 1.0
	srow.offset_left = 48
	srow.offset_right = 560
	srow.add_theme_constant_override("separation", 12)
	srow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot.add_child(srow)
	srow.add_child(_dot("Dot", IGNITION))
	var st := _label("StatusText", "TY_LAUNCH_STATUS_COUNT", "CwBody", 17)
	st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	st.size_flags_vertical = Control.SIZE_FILL
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(st)
	_countdown(bot)
	var hint := _label("Text", "TY_LAUNCH_SKIP", "CwDim", 13)
	var skip := _pill("Skip", hint)
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.anchor_top = 0.5
	skip.anchor_bottom = 0.5
	skip.offset_left = -48
	skip.offset_right = -48
	skip.offset_top = -17
	skip.offset_bottom = 17
	skip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	skip.grow_vertical = Control.GROW_DIRECTION_BOTH
	bot.add_child(skip)


## The clock lives in the bottom bar, centred: it never sits over the rocket.
func _countdown(bot: Control) -> void:
	var box := HBoxContainer.new()
	box.name = "Countdown"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -160
	box.offset_right = 160
	box.offset_top = -40
	box.offset_bottom = 40
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.modulate = Color(1, 1, 1, 0)
	bot.add_child(box)
	var t := _label("Prefix", "T−", "CwHeading", 26, TEAL)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(t)
	var d := _label("Digits", "10", "CwDisplay", 52)
	d.custom_minimum_size = Vector2(76, 0)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(d)
	d.add_child(_motion("Pulse", "cw_pulse", {"on_poke": true, "peak_scale": Vector2(1.18, 1.18), "glow": 1.35, "beat_seconds": 0.3}))
	var cap := _label("Caption", "TY_LAUNCH_TMINUS", "CwDim", 14)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(cap)


func _caption(ui: Control) -> void:
	var c := _label("Caption", "TY_LAUNCH_IGNITION", "CwDisplay", 84, IGNITION_HI)
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.offset_left = -700
	c.offset_right = 700
	c.offset_top = 130
	c.offset_bottom = 250
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.modulate = Color(1, 1, 1, 0)
	c.add_theme_color_override("font_outline_color", Color(0.04, 0.05, 0.15, 0.85))
	c.add_theme_constant_override("outline_size", 14)
	ui.add_child(c)
	# each new caption pops in (LaunchSequence._pop from the AnimationPlayer)
	c.add_child(_motion("Appear", "cw_appear", {"on_ready": false, "on_poke": true, "offset": Vector2(0, 18),
		"from_scale": Vector2(1.35, 1.35), "seconds": 0.34, "curve": CwMotion.Feel.OVERSHOOT}))


func _cards_node(ui: Control) -> void:
	var cards := Control.new()
	cards.name = "Cards"
	cards.unique_name_in_owner = true
	cards.set_anchors_preset(Control.PRESET_FULL_RECT)
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(cards)
	cards.add_child(_card("CardSuccess", SUCCESS, "TY_LAUNCH_KICK_SUCCESS", "TY_LAUNCH_TAG_SUCCESS", "TY_LAUNCH_LINE_SUCCESS"))
	cards.add_child(_card("CardPartial", WARNING, "TY_LAUNCH_KICK_PARTIAL", "TY_LAUNCH_TAG_PARTIAL", "TY_LAUNCH_LINE_PARTIAL"))
	cards.add_child(_card("CardFail", DANGER, "TY_LAUNCH_KICK_FAIL", "TY_LAUNCH_TAG_FAIL", "TY_LAUNCH_LINE_FAIL"))


## One result card: the theme's rounded panel, the outcome in its colour, a big grade and a
## "Continue" key. It pops in when shown (CwAppear on_visible).
func _card(n: String, accent: Color, kicker: String, tag: String, line: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = n
	card.unique_name_in_owner = true
	card.theme_type_variation = &"CwPanel"
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = 72
	card.offset_right = 72 + 500
	card.offset_top = -170
	card.offset_bottom = 170
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	card.add_child(_motion("Appear", "cw_appear", {"on_ready": false, "on_visible": true, "offset": Vector2(-28, 10),
		"from_scale": Vector2(0.9, 0.9), "pivot": Vector2(0.0, 0.5), "seconds": 0.38, "curve": CwMotion.Feel.OVERSHOOT}))
	var m := MarginContainer.new()
	m.name = "Margin"
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 26)
	m.add_theme_constant_override("margin_top", 20)
	m.add_theme_constant_override("margin_bottom", 20)
	card.add_child(m)
	var v := VBoxContainer.new()
	v.name = "VBox"
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	var dot := _dot("Dot", accent, 12.0)
	head.add_child(dot)
	var k := _label("Kicker", kicker, "CwHeading", 20, accent)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(k)
	var tag_l := _label("TagText", tag, "CwBody", 13, accent)
	var pill := _pill("Tag", tag_l)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(pill)
	var title := _label("Title", "SND-01", "CwDisplay", 44)
	v.add_child(title)
	v.add_child(_label("Route", "Sounding rocket  →  Suborbital", "CwBody", 16, TEXT_SOFT))
	var sep := HSeparator.new()
	sep.name = "Sep"
	v.add_child(sep)
	var stats := HBoxContainer.new()
	stats.name = "Stats"
	stats.add_theme_constant_override("separation", 36)
	v.add_child(stats)
	var grade := VBoxContainer.new()
	grade.name = "Grade"
	grade.add_theme_constant_override("separation", -6)
	stats.add_child(grade)
	grade.add_child(_label("GradeCaption", "TY_LAUNCH_GRADE", "CwCaps", 14))
	var gv := _label("GradeValue", "7.4", "CwDisplay", 64, accent)
	grade.add_child(gv)
	var ticker := _motion("Ticker", "cw_number_ticker", {"seconds": 0.9, "flash_strength": 0.0, "pop_scale": Vector2(1.08, 1.08)})
	gv.add_child(ticker)
	var odds := VBoxContainer.new()
	odds.name = "Odds"
	odds.add_theme_constant_override("separation", 2)
	odds.size_flags_vertical = Control.SIZE_SHRINK_END
	stats.add_child(odds)
	odds.add_child(_label("OddsCaption", "TY_LAUNCH_ODDS", "CwCaps", 14))
	odds.add_child(_label("OddsValue", "82%", "CwStat", 26))
	var fl := _label("Line", line, "CwBody", 16)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.custom_minimum_size = Vector2(440, 0)
	v.add_child(fl)
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	foot.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(foot)
	var b := Button.new()
	b.name = "Continue"
	b.text = "TY_LAUNCH_CONTINUE"
	b.theme_type_variation = &"CwKey"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(140, 0)
	foot.add_child(b)
	b.add_child(_motion("Motion", "cw_button_motion", {}))
	return card


# ------------------------------------------------------------ animation helpers
func _anim(n: String, length: float) -> Animation:
	var a := Animation.new()
	a.length = length
	lib.add_animation(n, a)
	return a


## keys: [[time, value, (transition)], ...]
func _track(a: Animation, path: String, keys: Array, discrete := false) -> int:
	var t := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t, NodePath(path))
	a.value_track_set_update_mode(t, Animation.UPDATE_DISCRETE if discrete else Animation.UPDATE_CONTINUOUS)
	a.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
	for k in keys:
		a.track_insert_key(t, k[0], k[1], k[2] if k.size() > 2 else 1.0)
	return t


func _method(a: Animation, path: String, keys: Array) -> void:
	var t := a.add_track(Animation.TYPE_METHOD)
	a.track_set_path(t, NodePath(path))
	for k in keys:
		a.track_insert_key(t, k[0], {"method": k[1], "args": k[2] if k.size() > 2 else []})


## Lowers an aim point so the view looks up at most `deg` degrees.
func _limit_pitch(from: Vector3, at: Vector3, deg: float) -> Vector3:
	var d := at - from
	var flat := Vector2(d.x, d.z).length()
	var up := tan(deg_to_rad(deg)) * flat
	if d.y > up:
		d.y = up
	return from + d


func _crew_camera(a: Animation, shots: Array) -> void:
	_camera(a, shots, "Stage/Spectators/CrewCam")


func _look(from: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(at - from, Vector3.UP), from)


## Camera keys: a list of [time, from, at, fov]; cuts are two keys at nearly the same time.
func _camera(a: Animation, shots: Array, cam := "Stage/CamRig/ShotCam") -> void:
	var tp := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tp, NodePath(cam + ":position"))
	var tq := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tq, NodePath(cam + ":quaternion"))
	var tf := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tf, NodePath(cam + ":fov"))
	for s in shots:
		var x := _look(s[1], s[2])
		a.track_insert_key(tp, s[0], x.origin)
		a.track_insert_key(tq, s[0], x.basis.get_rotation_quaternion())
		a.track_insert_key(tf, s[0], s[3])


const EASE_OUT := 0.3
const EASE_IN := 3.0
const EASE_IO := -2.0


# ------------------------------------------------------------ the flight path
## Rocket position after liftoff (seconds since liftoff): a gentle gravity turn downrange.
func _alt(t: float) -> float:
	return 1.4 * t * t + 0.18 * pow(t, 3.4)


func _rocket_pos(t: float, k := 1.0) -> Vector3:
	var h := _alt(t) * k
	var x := 0.004 * h * h if h < 75.0 else 22.5 + 0.6 * (h - 75.0)
	return BASE + Vector3(0, h, 0) + DOWN * x


func _rocket_basis(t: float, k := 1.0) -> Basis:
	var a := _rocket_pos(t, k)
	var b := _rocket_pos(t + 0.05, k)
	var up := (b - a).normalized()
	if up.length() < 0.5 or t <= 0.0:
		up = Vector3.UP
	var axis := Vector3.UP.cross(up)
	if axis.length() < 1e-4:
		return Basis()
	return Basis(axis.normalized(), Vector3.UP.angle_to(up))


func _flight_track(a: Animation, t0: float, t1: float, k := 1.0, wobble := Callable()) -> void:
	var tp := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tp, NodePath("Stage/Rocket:position"))
	var tr_ := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tr_, NodePath("Stage/Rocket:quaternion"))
	var t := 0.0
	while t <= t1 - t0 + 0.001:
		var b := _rocket_basis(t, k)
		if wobble.is_valid():
			b = b * Basis(Vector3(0, 0, 1), wobble.call(t))
		a.track_insert_key(tp, t0 + t, _rocket_pos(t, k))
		a.track_insert_key(tr_, t0 + t, b.get_rotation_quaternion())
		t += 0.1


# ------------------------------------------------------------ animations
func _anim_countdown() -> void:
	var a := _anim("countdown", COUNT_LEN)
	var F := "Overlay/Frame/"
	_track(a, F + "BarTop:offset_top", [[0.0, -BAR], [0.7, 0.0, EASE_OUT]])
	_track(a, F + "BarTop:offset_bottom", [[0.0, 0.0], [0.7, BAR, EASE_OUT]])
	_track(a, F + "BarBottom:offset_top", [[0.0, 0.0], [0.7, -BAR, EASE_OUT]])
	_track(a, F + "BarBottom:offset_bottom", [[0.0, BAR], [0.7, 0.0, EASE_OUT]])
	_track(a, F + "BarTop/Info:modulate", [[0.0, Color(1, 1, 1, 0)], [0.4, Color(1, 1, 1, 0)], [1.0, Color.WHITE]])
	_track(a, F + "Vignette:modulate", [[0.0, Color(1, 1, 1, 0)], [1.0, Color.WHITE]])
	_track(a, F + "BarBottom/Thread:scale", [[TICK0, Vector2(0, 1)], [IGNITE, Vector2(1, 1)]])
	_track(a, F + "BarBottom/Status/StatusText:text", [[0.0, "TY_LAUNCH_STATUS_COUNT"], [IGNITE, "TY_LAUNCH_STATUS_IGNITION"]], true)
	_track(a, F + "BarBottom/Status/Dot:modulate", _blink(0.0, COUNT_LEN, 0.5))
	# T-10 .. 0
	_track(a, F + "BarBottom/Countdown:modulate", [[0.0, Color(1, 1, 1, 0)], [TICK0 - 0.15, Color(1, 1, 1, 0)], [TICK0 + 0.1, Color.WHITE]])
	_track(a, F + "BarBottom/Countdown/Prefix:text", [[0.0, "T−"]], true)
	_track(a, F + "BarBottom/Countdown/Caption:text", [[0.0, "TY_LAUNCH_TMINUS"]], true)
	var digits := []
	var scale := []
	var col := []
	for i in 11:
		var t := TICK0 + i * TICK
		digits.append([t, "%d" % (10 - i)])
		scale.append([t, Vector2(1.22, 1.22)])
		scale.append([t + 0.24, Vector2(1, 1), EASE_OUT])
		if i < 8:
			col.append([t, ICE])
		else:
			col.append([t, IGNITION_HI])
	_track(a, F + "BarBottom/Countdown/Digits:text", digits, true)
	var beats := []
	for i in 11:
		beats.append([TICK0 + i * TICK, "beat"])
	_method(a, F + "BarBottom/Countdown/Digits/Pulse", beats)
	_track(a, F + "BarBottom/Countdown/Digits:modulate", col, true)
	# the pad vents
	_track(a, "Stage/PadFX/Steam:emitting", [[0.0, false], [0.25, true]], true)
	_track(a, "Stage/PadFX/Steam:amount_ratio", [[0.0, 0.35], [4.5, 0.7], [6.0, 1.0], [COUNT_LEN, 0.6]])
	_track(a, "Stage/Rocket:position", [[0.0, BASE], [IGNITE, BASE]] + _rumble(IGNITE, COUNT_LEN, 0.05))
	_track(a, "Stage/Rocket:quaternion", [[0.0, Quaternion()]])
	_track(a, "Stage/Rocket:visible", [[0.0, true]], true)
	# ignition
	_track(a, "Stage/Rocket/Engine/Flame:emitting", [[0.0, false], [IGNITE, true]], true)
	_track(a, "Stage/Rocket/Engine/Flame:amount_ratio", [[0.0, 1.0]])
	_track(a, "Stage/Rocket/Engine/FlameCore:visible", [[0.0, false], [IGNITE, true]], true)
	_track(a, "Stage/Rocket/Engine/FlameCore:scale", [[IGNITE, Vector3(0.6, 0.001, 0.6)], [IGNITE + 0.25, Vector3(1.1, 1.2, 1.1), EASE_OUT], [IGNITE + 0.4, Vector3(1, 0.9, 1)], [COUNT_LEN, Vector3(1, 1.05, 1)]])
	_track(a, "Stage/Rocket/Engine/EngineLight:light_energy", [[0.0, 0.0], [IGNITE, 0.0]] + _flicker(IGNITE + 0.05, COUNT_LEN, 9.0, 0.25))
	_track(a, "Stage/PadFX/FlashLight:light_energy", [[0.0, 0.0], [IGNITE, 0.0], [IGNITE + 0.08, 12.0], [COUNT_LEN, 5.0, EASE_OUT]])
	_track(a, F + "Flash:modulate", [[0.0, Color(1, 1, 1, 0)], [IGNITE, Color(1, 1, 1, 0)], [IGNITE + 0.06, Color(1, 1, 1, 0.4)], [IGNITE + 0.5, Color(1, 1, 1, 0), EASE_OUT]])
	_track(a, "Stage/PadFX/Smoke:emitting", [[0.0, false], [IGNITE + 0.05, true]], true)
	_method(a, "Stage/PadFX/Sparks", [[IGNITE + 0.04, "restart"]])
	_track(a, "Stage/Rocket/Engine/TrailGlow:emitting", [[0.0, false]], true)
	_track(a, "Stage/Rocket/Engine/TrailSmoke:emitting", [[0.0, false]], true)
	_track(a, "Stage/Rocket/Engine/Glint:transparency", [[0.0, 1.0]])
	_track(a, ".:shake", [[0.0, 0.0], [IGNITE, 0.0], [IGNITE + 0.12, 0.85], [COUNT_LEN, 0.55]])
	_track(a, ".:watch", [[0.0, 1.0]])
	_track(a, F + "Caption:text", [[0.0, "TY_LAUNCH_IGNITION"]], true)
	_track(a, F + "Caption:modulate", [[0.0, Color(1, 1, 1, 0)], [IGNITE, Color(1, 1, 1, 0)], [IGNITE + 0.1, Color.WHITE]])
	_method(a, F + "Caption/Appear", [[IGNITE, "play"]])
	_track(a, F + "Cards:modulate", [[0.0, Color.WHITE]])
	# the crew
	_method(a, ".", [[3.0, "_crowd", ["hello"]], [IGNITE + 0.1, "_emote", ["exclaim"]]])
	# camera: the pad at dusk, the crew waiting, then the low launch view
	var rk := BASE + Vector3(0, 5, 0)
	_camera(a, [
		[0.0, Vector3(34, 15, 26), rk + Vector3(0, -1, 0), 40.0],
		[2.6, Vector3(27, 10, 24), rk, 38.0],
		[2.62, Vector3(14.6, 1.5, 18.4), Vector3(1.5, 4.0, 0.5), 44.0],
		[4.6, Vector3(13.8, 1.3, 17.0), Vector3(1.0, 4.8, 0.5), 42.0],
		[4.62, Vector3(5.5, 1.0, 13.5), Vector3(-0.5, 4.2, 0), 52.0],
		[COUNT_LEN, Vector3(5.8, 0.9, 14.2), Vector3(-0.3, 4.8, 0), 52.0],
	])


func _blink(t0: float, t1: float, period: float) -> Array:
	var out := []
	var t := t0
	var on := true
	while t <= t1:
		out.append([t, Color(1, 1, 1, 1.0 if on else 0.25)])
		on = not on
		t += period
	return out


func _rumble(t0: float, t1: float, amp: float) -> Array:
	var out := []
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var t := t0
	while t <= t1:
		out.append([t, BASE + Vector3(r.randf_range(-amp, amp), 0, r.randf_range(-amp, amp))])
		t += 0.05
	return out


func _flicker(t0: float, t1: float, base: float, amount: float, seed := 3) -> Array:
	var out := []
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var t := t0
	while t <= t1:
		out.append([t, base * (1.0 + r.randf_range(-amount, amount))])
		t += 0.06
	return out


func _anim_flight(kind: String) -> void:
	var L := 7.5
	var a := _anim("flight_" + kind, L)
	var F := "Overlay/Frame/"
	var lift := 0.3
	var wob := Callable()
	if kind == "partial":
		wob = func(t: float) -> float:
			var w := smoothstep(2.4, 2.9, t) * (1.0 - smoothstep(3.8, 4.6, t))
			return sin(t * 9.0) * deg_to_rad(5.0) * w
	_flight_track(a, lift, L, 1.0, wob)
	_track(a, "Stage/Rocket:visible", [[0.0, true]], true)
	# hold-down rumble before release
	var pre := _rumble(0.0, lift - 0.05, 0.05)
	var tp := a.find_track(NodePath("Stage/Rocket:position"), Animation.TYPE_VALUE)
	for k in pre:
		a.track_insert_key(tp, k[0], k[1])
	var tq := a.find_track(NodePath("Stage/Rocket:quaternion"), Animation.TYPE_VALUE)
	a.track_insert_key(tq, 0.0, Quaternion())
	# engine and trail
	_track(a, "Stage/Rocket/Engine/Flame:emitting", [[0.0, true]], true)
	_track(a, "Stage/Rocket/Engine/FlameCore:visible", [[0.0, true]], true)
	var flame_ratio := [[0.0, 1.0]]
	var core := [[0.0, Vector3(1, 1.05, 1)], [1.5, Vector3(1.1, 1.5, 1.1)], [L, Vector3(1.2, 1.7, 1.2)]]
	var light := _flicker(0.0, L, 9.0, 0.25)
	var trail_ratio := [[0.0, 1.0]]
	if kind == "partial":
		flame_ratio = [[0.0, 1.0], [2.4, 1.0], [2.55, 0.2], [2.7, 1.0], [2.9, 0.15], [3.1, 0.9], [3.35, 0.25], [3.6, 1.0]]
		core = [[0.0, Vector3(1, 1.05, 1)], [1.5, Vector3(1.1, 1.5, 1.1)], [2.4, Vector3(1.1, 1.5, 1.1)], [2.55, Vector3(0.7, 0.4, 0.7)], [2.7, Vector3(1.1, 1.4, 1.1)], [2.9, Vector3(0.6, 0.3, 0.6)], [3.1, Vector3(1, 1.3, 1)], [3.35, Vector3(0.7, 0.4, 0.7)], [3.6, Vector3(1.1, 1.5, 1.1)], [L, Vector3(1.2, 1.7, 1.2)]]
		light = _flicker(0.0, 2.4, 9.0, 0.25) + [[2.55, 2.0], [2.7, 9.0], [2.9, 1.5], [3.1, 8.0], [3.35, 2.0]] + _flicker(3.6, L, 9.0, 0.25, 5)
		trail_ratio = [[0.0, 1.0], [2.5, 1.0], [2.6, 0.15], [2.75, 1.0], [2.9, 0.1], [3.2, 0.8], [3.4, 0.2], [3.65, 1.0]]
	_track(a, "Stage/Rocket/Engine/Flame:amount_ratio", flame_ratio)
	_track(a, "Stage/Rocket/Engine/FlameCore:scale", core)
	_track(a, "Stage/Rocket/Engine/EngineLight:light_energy", light)
	_track(a, "Stage/Rocket/Engine/TrailGlow:emitting", [[0.0, false], [lift, true]], true)
	_track(a, "Stage/Rocket/Engine/TrailSmoke:emitting", [[0.0, false], [lift + 0.3, true]], true)
	_track(a, "Stage/Rocket/Engine/TrailGlow:amount_ratio", trail_ratio)
	_track(a, "Stage/Rocket/Engine/TrailSmoke:amount_ratio", trail_ratio)
	_track(a, "Stage/Rocket/Engine/Glint:transparency", [[0.0, 1.0], [2.0, 1.0], [4.0, 0.0]])
	_track(a, "Stage/PadFX/Smoke:emitting", [[0.0, true], [2.4, false]], true)
	_track(a, "Stage/PadFX/Steam:emitting", [[0.0, true], [0.8, false]], true)
	_track(a, "Stage/PadFX/FlashLight:light_energy", [[0.0, 5.0], [0.4, 7.0], [2.5, 0.0, EASE_OUT]])
	_track(a, ".:shake", [[0.0, 0.55], [lift, 1.0], [1.6, 0.6], [3.5, 0.15], [5.0, 0.0]] if kind == "success" else
		[[0.0, 0.55], [lift, 1.0], [1.6, 0.6], [2.5, 0.2], [2.6, 0.5], [3.4, 0.4], [4.0, 0.1], [5.0, 0.0]])
	# overlay: T+ clock, LIFTOFF!, status
	_track(a, F + "BarBottom/Countdown/Prefix:text", [[0.0, "T−"], [lift, "T+"]], true)
	_track(a, F + "BarBottom/Countdown/Caption:text", [[0.0, "TY_LAUNCH_TMINUS"], [lift, "TY_LAUNCH_TPLUS"]], true)
	var digits := [[0.0, "0"]]
	for s in range(1, 8):
		digits.append([lift + s, "%d" % s])
	_track(a, F + "BarBottom/Countdown/Digits:text", digits, true)
	_track(a, F + "BarBottom/Countdown/Digits:modulate", [[0.0, IGNITION_HI], [lift, ICE]], true)
	_track(a, F + "BarBottom/Countdown:modulate", [[0.0, Color.WHITE], [L - 0.6, Color.WHITE], [L, Color(1, 1, 1, 0)]])
	_track(a, F + "Caption:text", [[0.0, "TY_LAUNCH_IGNITION"], [lift, "TY_LAUNCH_LIFTOFF"]], true)
	_track(a, F + "Caption:modulate", [[0.0, Color.WHITE], [lift, Color.WHITE], [2.4, Color.WHITE], [3.0, Color(1, 1, 1, 0)]] if kind == "success" else
		[[0.0, Color.WHITE], [lift, Color.WHITE], [2.0, Color(1, 1, 1, 0)], [2.5, Color(1, 1, 1, 0)], [2.6, Color.WHITE], [4.2, Color.WHITE], [4.8, Color(1, 1, 1, 0)]])
	_method(a, F + "Caption/Appear", [[lift, "play"]] if kind == "success" else [[lift, "play"], [2.5, "play"]])
	var tick_beats := []
	for sec in range(1, 8):
		tick_beats.append([lift + sec, "beat"])
	_method(a, F + "BarBottom/Countdown/Digits/Pulse", tick_beats)
	if kind == "partial":
		_track(a, F + "Caption:text", [[0.0, "TY_LAUNCH_IGNITION"], [lift, "TY_LAUNCH_LIFTOFF"], [2.5, "TY_LAUNCH_SPUTTER"]], true)
		a.remove_track(a.find_track(NodePath(F + "Caption:text"), Animation.TYPE_VALUE))
		_track(a, F + "Caption:text", [[0.0, "TY_LAUNCH_IGNITION"], [lift, "TY_LAUNCH_LIFTOFF"], [2.5, "TY_LAUNCH_SPUTTER"]], true)
		_track(a, F + "Caption:self_modulate", [[0.0, Color.WHITE], [2.5, Color(1.0, 0.85, 0.45)]], true)
	else:
		_track(a, F + "Caption:self_modulate", [[0.0, Color.WHITE]], true)
	var status := [[0.0, "TY_LAUNCH_STATUS_IGNITION"], [lift, "TY_LAUNCH_STATUS_LIFTOFF"], [3.2, "TY_LAUNCH_STATUS_NOMINAL"]]
	if kind == "partial":
		status = [[0.0, "TY_LAUNCH_STATUS_IGNITION"], [lift, "TY_LAUNCH_STATUS_LIFTOFF"], [2.5, "TY_LAUNCH_STATUS_SPUTTER"], [4.2, "TY_LAUNCH_STATUS_RECOVERED"]]
	_track(a, F + "BarBottom/Status/StatusText:text", status, true)
	_track(a, F + "BarBottom/Status/Dot:modulate", _blink(0.0, L, 0.5))
	_track(a, F + "BarBottom/Thread:scale", [[0.0, Vector2(1, 1)]])
	# the crew cheers
	var calls := [[lift + 0.2, "_crowd", ["launch"]], [4.8, "_crowd", ["success"]]]
	if kind == "partial":
		calls = [[lift + 0.2, "_crowd", ["launch"]], [2.7, "_emote", ["sweat"]], [4.6, "_crowd", ["success"]]]
	_method(a, ".", calls)
	_method(a, "Stage/Spectators/Confetti", [[4.9, "restart"]])
	# camera: low at the pad tilting up, then the wide arc towards the comet
	var low := Vector3(5.8, 0.9, 14.2)
	var shots := [[0.0, low, Vector3(-0.3, 4.8, 0), 52.0]]
	var t := lift
	while t <= 2.3:
		var p := _rocket_pos(t - lift)
		shots.append([t, low + Vector3(0, (t - lift) * 0.4, 0), p + Vector3(0, 3.5 - (t - lift) * 0.6, 0), 52.0 + (t - lift) * 4.0])
		t += 0.25
	# the wide view: behind and beside the flight path, the arc bends towards the comet
	var side := DOWN.cross(Vector3.UP)
	var wide_from := -DOWN * 40.0 + side * 28.0 + Vector3(0, 6, 0)
	var t_cut := 2.32
	shots.append([t_cut, wide_from, _rocket_pos(t_cut - lift).lerp(Vector3.ZERO, 0.3) + Vector3(0, 6, 0), 48.0])
	t = 2.6
	while t <= L + 0.001:
		var p2 := _rocket_pos(t - lift)
		# dolly back and up so the horizon stays while the rocket climbs
		var f := wide_from - DOWN * 50.0 * smoothstep(3.0, L, t) + Vector3(0, (t - t_cut) * 1.1, 0)
		var aim := _limit_pitch(f, p2.lerp(Vector3(0, 4, 0), lerpf(0.3, 0.5, smoothstep(2.6, L, t))), 24.0)
		shots.append([t, f, aim, 48.0 + smoothstep(2.6, L, t) * 10.0])
		t += 0.3
	_camera(a, shots)


func _anim_fail() -> void:
	var L := 6.4
	var a := _anim("flight_fail", L)
	var F := "Overlay/Frame/"
	var lift := 0.45
	var stall := 2.6     # engine out
	var poof := 3.7
	# slow climb with a growing wobble, then the stall: it noses over and pops
	var tp := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tp, NodePath("Stage/Rocket:position"))
	var tq := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(tq, NodePath("Stage/Rocket:quaternion"))
	for k in _rumble(0.0, lift, 0.06):
		a.track_insert_key(tp, k[0], k[1])
	a.track_insert_key(tq, 0.0, Quaternion())
	var t := lift
	var pos := BASE
	var side := Vector3(-0.83, 0, 0.55).cross(Vector3.UP).normalized()  # tips away from the crew
	var top := BASE + Vector3(0, 3.0 * pow(stall - lift, 2), 0)
	while t <= poof + 0.001:
		var s := t - lift
		if t < stall:
			pos = BASE + Vector3(0, 3.0 * s * s, 0)
		else:
			var u := t - stall
			pos = top + Vector3(0, 6.0 * u - 4.9 * u * u, 0) + side * (2.4 * u * u)
		var tilt := 0.0
		if t < stall:
			tilt = sin(s * 7.0) * deg_to_rad(3.0 + 7.0 * s / (stall - lift))
		else:
			tilt = deg_to_rad(10.0 + 75.0 * smoothstep(0.0, poof - stall, t - stall))
		a.track_insert_key(tp, t, pos)
		a.track_insert_key(tq, t, Basis(Vector3.UP.cross(side).normalized(), tilt).get_rotation_quaternion())
		t += 0.1
	_track(a, "Stage/Rocket:visible", [[0.0, true], [poof + 0.05, false]], true)
	# the engine coughs and dies
	var ratio := [[0.0, 1.0]]
	var light := []
	var r := RandomNumberGenerator.new()
	r.seed = 21
	t = 0.0
	while t < stall:
		var cough := fmod(t, 0.5) < 0.12 and t > lift
		ratio.append([t, 0.15 if cough else 1.0])
		light.append([t, (1.5 if cough else 8.0) * r.randf_range(0.8, 1.2)])
		t += 0.06
	ratio.append([stall, 0.0])
	light.append([stall, 0.0])
	_track(a, "Stage/Rocket/Engine/Flame:amount_ratio", ratio)
	_track(a, "Stage/Rocket/Engine/Flame:emitting", [[0.0, true], [stall, false]], true)
	_track(a, "Stage/Rocket/Engine/FlameCore:visible", [[0.0, true], [stall, false]], true)
	_track(a, "Stage/Rocket/Engine/FlameCore:scale", [[0.0, Vector3(1, 1.05, 1)], [stall - 0.3, Vector3(0.8, 0.7, 0.8)], [stall, Vector3(0.3, 0.1, 0.3)]])
	_track(a, "Stage/Rocket/Engine/EngineLight:light_energy", light)
	_track(a, "Stage/Rocket/Engine/TrailGlow:emitting", [[0.0, false], [lift, true], [stall, false]], true)
	_track(a, "Stage/Rocket/Engine/TrailSmoke:emitting", [[0.0, false], [lift + 0.2, true], [poof, false]], true)
	_track(a, "Stage/Rocket/Engine/TrailGlow:amount_ratio", [[0.0, 0.6]])
	_track(a, "Stage/Rocket/Engine/TrailSmoke:amount_ratio", [[0.0, 0.7]])
	_track(a, "Stage/Rocket/Engine/Glint:transparency", [[0.0, 1.0]])
	_track(a, "Stage/PadFX/Smoke:emitting", [[0.0, true], [1.8, false]], true)
	_track(a, "Stage/PadFX/Steam:emitting", [[0.0, true], [0.8, false]], true)
	_track(a, "Stage/PadFX/FlashLight:light_energy", [[0.0, 7.0], [0.4, 8.0], [2.0, 0.0, EASE_OUT], [poof, 0.0], [poof + 0.06, 14.0], [poof + 0.8, 0.0, EASE_OUT]])
	(seq.get_node("Stage/FailFX") as Node3D).position = a.value_track_interpolate(tp, poof)
	_method(a, "Stage/FailFX/Poof", [[poof, "restart"]])
	_method(a, "Stage/FailFX/Debris", [[poof, "restart"]])
	_track(a, "Stage/FailFX/PopLight:light_energy", [[0.0, 0.0], [poof, 0.0], [poof + 0.05, 10.0], [poof + 0.9, 0.0, EASE_OUT]])
	_track(a, ".:shake", [[0.0, 0.55], [lift, 0.8], [stall, 0.3], [stall + 0.3, 0.0], [poof, 0.0], [poof + 0.05, 0.7], [poof + 0.9, 0.0]])
	# overlay
	_track(a, F + "BarBottom/Countdown/Prefix:text", [[0.0, "T−"], [lift, "T+"]], true)
	_track(a, F + "BarBottom/Countdown/Caption:text", [[0.0, "TY_LAUNCH_TMINUS"], [lift, "TY_LAUNCH_TPLUS"]], true)
	var digits := [[0.0, "0"]]
	for s in range(1, 7):
		digits.append([lift + s, "%d" % s])
	_track(a, F + "BarBottom/Countdown/Digits:text", digits, true)
	_track(a, F + "BarBottom/Countdown/Digits:modulate", [[0.0, IGNITION_HI], [lift, ICE], [stall, DANGER]], true)
	_track(a, F + "BarBottom/Countdown:modulate", [[0.0, Color.WHITE], [L - 0.6, Color.WHITE], [L, Color(1, 1, 1, 0)]])
	_track(a, F + "Caption:text", [[0.0, "TY_LAUNCH_IGNITION"], [lift, "TY_LAUNCH_LIFTOFF"], [stall, "TY_LAUNCH_ANOMALY"]], true)
	_track(a, F + "Caption:self_modulate", [[0.0, Color.WHITE], [stall, Color(1.0, 0.45, 0.5)]], true)
	_track(a, F + "Caption:modulate", [[0.0, Color.WHITE], [1.8, Color.WHITE], [2.2, Color(1, 1, 1, 0)], [stall, Color(1, 1, 1, 0)], [stall + 0.1, Color.WHITE], [L - 0.8, Color.WHITE], [L - 0.2, Color(1, 1, 1, 0)]])
	_method(a, F + "Caption/Appear", [[lift, "play"], [stall, "play"]])
	_track(a, F + "BarBottom/Status/StatusText:text", [[0.0, "TY_LAUNCH_STATUS_IGNITION"], [lift, "TY_LAUNCH_STATUS_LIFTOFF"], [stall, "TY_LAUNCH_STATUS_ANOMALY"], [poof + 0.5, "TY_LAUNCH_STATUS_LOST"]], true)
	_track(a, F + "BarBottom/Status/Dot:modulate", _blink(0.0, L, 0.25))
	_track(a, F + "BarBottom/Thread:scale", [[0.0, Vector2(1, 1)]])
	_method(a, ".", [[lift + 0.2, "_crowd", ["launch"]], [stall + 0.2, "_emote", ["exclaim"]], [poof + 0.3, "_crowd", ["failure"]], [poof + 2.0, "_emote", ["sweat"]]])
	# camera: the low view follows, then a slow push on the cloud
	var shots := [[0.0, Vector3(5.8, 0.9, 14.2), Vector3(-0.3, 4.8, 0), 52.0]]
	t = lift
	var pv := a.find_track(NodePath("Stage/Rocket:position"), Animation.TYPE_VALUE)
	shots.append([lift + 0.6, Vector3(5.8, 0.9, 14.2), Vector3(-0.3, 6.5, 0), 52.0])
	var wide := Vector3(12, 3.2, 25)
	t = lift + 0.62
	while t <= L + 0.001:
		var rp: Vector3 = a.value_track_interpolate(pv, minf(t, poof))
		var aim := Vector3(0, 7, 0).lerp(rp, 0.7)
		shots.append([t, wide.lerp(Vector3(10.5, 3.0, 22), smoothstep(lift, L, t)), aim, 56.0 - smoothstep(poof, L, t) * 5.0])
		t += 0.3
	_camera(a, shots)


func _anim_result() -> void:
	var a := _anim("result", 4.5)
	var F := "Overlay/Frame/"
	# the crew after the flight, seen by CrewCam (next to them, not scaled with the rocket);
	# they turn to it, the pad and its smoke behind them, on the right of the card
	_crew_camera(a, [[0.0, CREW_CAM, CREW_AIM, 42.0], [4.5, CREW_CAM + Vector3(-0.7, -0.15, -0.8), CREW_AIM, 40.0]])
	_track(a, "Stage/Spectators/CrewLight:light_energy", [[0.0, 0.0], [0.6, 2.2]])
	_track(a, ".:watch", [[0.0, 0.85]])
	# the pad's smoke clouds would hide the crew in the later eras' bigger launches
	_track(a, "Stage/PadFX/Smoke:visible", [[0.0, false]], true)
	_track(a, "Stage/PadFX/Steam:visible", [[0.0, false]], true)
	_track(a, F + "Flash:modulate", [[0.0, Color(1, 1, 1, 0.12)], [0.35, Color(1, 1, 1, 0)]])
	_track(a, F + "Cards:modulate", [[0.0, Color.WHITE]])
	_track(a, F + "BarBottom/Countdown:modulate", [[0.0, Color(1, 1, 1, 0)]])
	_track(a, F + "Caption:modulate", [[0.0, Color(1, 1, 1, 0)]])
	_track(a, F + "BarBottom/Status/StatusText:text", [[0.0, "TY_LAUNCH_STATUS_REPORT"]], true)
	_track(a, ".:shake", [[0.0, 0.0]])


func _anim_outro() -> void:
	var a := _anim("outro", 0.9)
	var F := "Overlay/Frame/"
	_track(a, F + "Cards:modulate", [[0.0, Color.WHITE], [0.35, Color(1, 1, 1, 0)]])
	_track(a, F + "BarTop:offset_top", [[0.1, 0.0], [0.8, -BAR, EASE_IN]])
	_track(a, F + "BarTop:offset_bottom", [[0.1, BAR], [0.8, 0.0, EASE_IN]])
	_track(a, F + "BarBottom:offset_top", [[0.1, -BAR], [0.8, 0.0, EASE_IN]])
	_track(a, F + "BarBottom:offset_bottom", [[0.1, 0.0], [0.8, BAR, EASE_IN]])
	_track(a, F + "Vignette:modulate", [[0.0, Color.WHITE], [0.9, Color(1, 1, 1, 0)]])
	_track(a, F + "BarBottom/Countdown:modulate", [[0.0, Color(1, 1, 1, 0)]])
	_track(a, F + "Caption:modulate", [[0.0, Color(1, 1, 1, 0)]])
	_track(a, "Stage/Rocket/Engine/TrailGlow:emitting", [[0.0, false]], true)
	_track(a, "Stage/Rocket/Engine/Flame:emitting", [[0.0, false]], true)
	_track(a, "Stage/Rocket/Engine/EngineLight:light_energy", [[0.0, 0.0]])
	_track(a, ".:shake", [[0.0, 0.0]])


## RESET: every animated property at its resting value (the scene as built).
func _anim_reset() -> void:
	var reset := Animation.new()
	reset.length = 0.001
	var seen := {}
	for an in lib.get_animation_list():
		var a := lib.get_animation(an)
		for i in a.get_track_count():
			if a.track_get_type(i) != Animation.TYPE_VALUE:
				continue
			var path := a.track_get_path(i)
			if seen.has(path):
				continue
			seen[path] = true
			var node := seq.get_node_or_null(NodePath(String(path).get_slice(":", 0)))
			if node == null:
				push_warning("no node for %s" % path)
				continue
			var value: Variant = node.get_indexed(NodePath(String(path).get_slice(":", 1)))
			var t := reset.add_track(Animation.TYPE_VALUE)
			reset.track_set_path(t, path)
			reset.track_insert_key(t, 0.0, value)
	lib.add_animation("RESET", reset)
