extends SceneTree
## The cartoon look (shaders/include/cw_toon.gdshaderinc, scenes/fx/cw_outline.tscn, CwLook):
##   * every converted shader includes the toon light and parses (its parameter list carries
##     the include's toon_* uniforms and the shader's own ones)
##   * the shader globals exist in project.godot with sane values
##   * the Style / Outlines options toggle the cw_toon global and the outline nodes, live,
##     and persist in user://settings.cfg (the player's own file is restored afterwards); so
##     does the anti-aliasing (SMAA by default, MSAA 4x, off; FXAA never on)
##   * Cometling eyes, happy eyes and mouths use the face material (flat painted light, depth
##     bias over the head, no rim / glint), eyelids the lid material
##   * the main cameras carry the outline: campus, menu shots, launch, leader creator, rocket
##     designer, crew portrait, hangar and every cutscene shot
##   * the Cometling, campus and prop materials are toon materials
## Run: godot --headless --path . --script res://tests/test_toon.gd

const SHADERS := {
	"res://shaders/campus_voxel.gdshader": "glow_tint",
	"res://shaders/campus_terrain.gdshader": "grass_a",
	"res://shaders/campus_foliage.gdshader": "sway",
	"res://shaders/campus_road.gdshader": "era",
	"res://shaders/voxel_part.gdshader": "jitter",
	"res://shaders/cw_toon_solid.gdshader": "albedo",
	"res://scenes/npc/creature.gdshader": "eye_roughness",
}
const GLOBALS := ["cw_toon", "cw_toon_bands", "cw_toon_band_soft", "cw_toon_band_low",
	"cw_toon_band_high", "cw_toon_ramp", "cw_toon_light_scale", "cw_shadow_tint", "cw_shadow_fill",
	"cw_rim_color", "cw_rim_strength", "cw_outline_color", "cw_outline_strength"]
## scene -> camera paths that must carry a CwOutline child
const CAMERAS := {
	"res://scenes/tycoon/tycoon_main.tscn": ["Camera"],
	"res://scenes/tycoon/launch/launch_sequence.tscn": ["Stage/Spectators/CrewCam", "Stage/CamRig/ShotCam"],
	"res://scenes/tycoon/ui/screens/leader_creator.tscn": ["Margin/Layout/Body/Stage/Box/Window/Preview/Viewport/Camera3D"],
	"res://scenes/tycoon/ui/screens/rocket_designer.tscn": ["Panel/Margin/VBox/Body/Right/PreviewBay/Preview/Viewport/World/PreviewCam"],
	"res://scenes/tycoon/ui/screens/crew.tscn": ["Layout/Pages/Sheet/Left/VBox/Visor/Portrait/Viewport/Camera3D"],
	"res://scenes/tycoon/ui/cw_portrait_studio.tscn": ["Camera3D"],
	"res://scenes/hangar.tscn": ["CameraRig/Camera3D"],
}
const SHOT_DIRS := ["res://scenes/menu/shots", "res://scenes/cutscenes/shots"]

var _failures := 0


func _initialize() -> void:
	_check_shaders()
	_check_globals()
	_check_materials()
	_check_cameras()
	await _check_faces()
	await _check_option()
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", what)


func _params(shader: Shader) -> Array:
	var names := []
	for u: Dictionary in shader.get_shader_uniform_list(true):
		names.append(String(u["name"]))
	return names


func _check_shaders() -> void:
	for path: String in SHADERS:
		var sh := load(path) as Shader
		_expect(sh != null, "%s loads" % path)
		if sh == null:
			continue
		_expect(sh.code.contains("#include \"res://shaders/include/cw_toon.gdshaderinc\""), "%s includes the toon light" % path)
		var names := _params(sh)
		for want: String in ["toon_band_bias", "toon_shadow_fill", "toon_specular", "toon_rim", String(SHADERS[path])]:
			_expect(names.has(want), "%s parses with uniform %s (got %d uniforms)" % [path, want, names.size()])
	var outline := load("res://shaders/cw_outline.gdshader") as Shader
	var onames := _params(outline)
	for want: String in ["depth_threshold", "normal_threshold", "crease_min_size", "fade_end", "local_colour"]:
		_expect(onames.has(want), "outline shader parses with %s" % want)


func _check_globals() -> void:
	for g: String in GLOBALS:
		var key := "shader_globals/" + g
		_expect(ProjectSettings.has_setting(key), "global %s in project.godot" % g)
	_expect(float(CwLook.default_value(&"cw_toon")) == 1.0, "cartoon is the default style")
	var bands := int(CwLook.default_value(&"cw_toon_bands"))
	_expect(bands >= 2 and bands <= 4, "2..4 bands by default (got %d)" % bands)
	_expect(CwLook.default_value(&"cw_shadow_tint") is Color, "shadow tint is a colour")
	var ramp: Variant = CwLook.default_value(&"cw_toon_ramp")
	_expect(ramp is String and ResourceLoader.exists(String(ramp)), "toon ramp texture exists")
	var gl := RenderingServer.global_shader_parameter_get_list()
	if not gl.is_empty():
		for g: String in GLOBALS:
			_expect(gl.has(StringName(g)), "global %s registered with the renderer" % g)


func _check_materials() -> void:
	var cm := load("res://scenes/npc/creature_material.tres") as ShaderMaterial
	_expect(cm != null and cm.shader.code.contains("cw_toon.gdshaderinc"), "Cometlings use the toon light")
	for p: String in ["res://assets/campus/campus_voxel.tres", "res://assets/campus/nature/foliage.tres",
			"res://assets/campus/nature/grass.tres", "res://scenes/hangar/voxel_part.tres"]:
		var m := load(p) as ShaderMaterial
		_expect(m != null and m.shader.code.contains("cw_toon.gdshaderinc"), "%s uses the toon light" % p)
	# round voxel shapes opt out of crease lines by a roughness under the outline's threshold
	var om := load("res://scenes/fx/cw_outline_material.tres") as ShaderMaterial
	var min_r := float(om.get_shader_parameter("crease_min_roughness"))
	_expect(float(cm.get_shader_parameter("roughness")) < min_r, "Cometlings get no crease lines")
	# Cometling faces: flat painted light, pulled over the head voxels, no rim slivers or glint
	var fm := load("res://scenes/npc/creature_face_material.tres") as ShaderMaterial
	var lm := load("res://scenes/npc/creature_lid_material.tres") as ShaderMaterial
	_expect(fm != null and fm.shader == cm.shader and lm != null and lm.shader == cm.shader, "face / lid materials share the Cometling shader")
	if fm and lm:
		_expect(float(fm.get_shader_parameter("face_flat")) == 1.0, "faces are lit flat")
		_expect(float(fm.get_shader_parameter("face_depth_bias")) > 0.01, "faces drawn over the head voxels")
		_expect(float(fm.get_shader_parameter("face_depth_bias")) == float(lm.get_shader_parameter("face_depth_bias")),
			"lids keep the same bias as the eyes (they still close over them)")
		_expect(float(fm.get_shader_parameter("toon_rim")) == 0.0 and float(fm.get_shader_parameter("toon_specular")) == 0.0,
			"no rim or glint on the faces")
		_expect(float(fm.get_shader_parameter("roughness")) < min_r, "faces get no crease lines")
	_expect(float((load("res://assets/campus/nature/foliage.tres") as ShaderMaterial).get_shader_parameter("roughness_value")) < min_r,
		"trees get no crease lines")
	_expect(float((load("res://assets/campus/campus_voxel.tres") as ShaderMaterial).get_shader_parameter("roughness_value")) >= min_r,
		"buildings get crease lines")
	# no plain lit StandardMaterial3D left in the converted scenes
	for path: String in ["res://scenes/menu/shots/shot_workshop.tscn", "res://scenes/menu/shots/shot_launch.tscn",
			"res://scenes/tycoon/campus.tscn", "res://scenes/tycoon/leader/leader_hat.tscn",
			"res://scenes/cutscenes/sets/founding_yard.tscn"]:
		var text := FileAccess.get_file_as_string(path)
		_expect(text.contains("cw_toon_solid.gdshader"), "%s uses cw_toon_solid" % path)
		var plain := RegEx.create_from_string("\\[sub_resource type=\"StandardMaterial3D\" id=\"[^\"]+\"\\]\\n(albedo_color = [^\\n]+\\n)?roughness = ")
		_expect(plain.search(text) == null, "%s has no plain lit StandardMaterial3D left" % path)


## Every face part of a live Cometling wears the right material.
func _check_faces() -> void:
	var cm := load("res://scenes/npc/creature_material.tres") as ShaderMaterial
	var fm := load("res://scenes/npc/creature_face_material.tres") as ShaderMaterial
	var lm := load("res://scenes/npc/creature_lid_material.tres") as ShaderMaterial
	var cr := (load("res://scenes/npc/creature.tscn") as PackedScene).instantiate() as Cometling
	cr.listen_to_events = false
	get_root().add_child(cr)
	await process_frame
	var eye_mesh := cr.eye_l.find_children("*", "MeshInstance3D", true, false)
	var happy_mesh := cr.happy_l.find_children("*", "MeshInstance3D", true, false)
	var lid_mesh := cr.lid_l.find_children("*", "MeshInstance3D", true, false)
	var head_mesh := cr.neck.get_node("Mesh").find_children("*", "MeshInstance3D", true, false)
	_expect(not eye_mesh.is_empty() and (eye_mesh[0] as MeshInstance3D).material_override == fm, "eyes use the face material")
	_expect(not happy_mesh.is_empty() and (happy_mesh[0] as MeshInstance3D).material_override == fm, "happy eyes use the face material")
	_expect(not lid_mesh.is_empty() and (lid_mesh[0] as MeshInstance3D).material_override == lm, "lids use the lid material")
	var mouths := cr.mouth.find_children("*", "MeshInstance3D", true, false)
	var mouth_ok := not mouths.is_empty()
	for m in mouths:
		mouth_ok = mouth_ok and (m as MeshInstance3D).material_override == fm
	_expect(mouth_ok, "mouths use the face material")
	_expect(not head_mesh.is_empty() and (head_mesh[0] as MeshInstance3D).material_override == cm, "the head keeps the body material")
	cr.queue_free()
	await process_frame


func _outline_of(cam: Node) -> CwOutline:
	for c in cam.get_children():
		if c is CwOutline:
			return c
	return null


func _check_cameras() -> void:
	var scenes := CAMERAS.duplicate()
	for d: String in SHOT_DIRS:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".tscn"):
				scenes[d + "/" + f] = []
	var count := 0
	for path: String in scenes:
		var root := (load(path) as PackedScene).instantiate()
		var cams: Array = scenes[path]
		if cams.is_empty():
			# shots: every camera
			for c in root.find_children("*", "Camera3D", true, false):
				cams.append(String(root.get_path_to(c)))
			_expect(not cams.is_empty(), "%s has a camera" % path)
		for cp: String in cams:
			var cam := root.get_node_or_null(cp) as Camera3D
			_expect(cam != null, "%s: camera %s" % [path, cp])
			if cam:
				var o := _outline_of(cam)
				_expect(o != null, "%s: %s carries the outline" % [path, cp])
				if o:
					count += 1
					_expect(o.transform == Transform3D.IDENTITY, "%s: outline sits at the camera" % path)
					_expect(o.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: outline casts no shadow" % path)
		root.free()
	print("%d cameras carry the outline" % count)


func _check_option() -> void:
	var path := CwLook.PATH
	var had := FileAccess.file_exists(path)
	var backup := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()
	var cam := Camera3D.new()
	get_root().add_child(cam)
	var outline := (load("res://scenes/fx/cw_outline.tscn") as PackedScene).instantiate() as CwOutline
	cam.add_child(outline)
	await process_frame
	# the renderer may not hand globals back (headless); then the toggles are checked on CwLook
	var gl_ok := RenderingServer.global_shader_parameter_get(&"cw_toon") != null
	print("globals readable: ", gl_ok)

	CwLook.set_toon(true)
	CwLook.set_outlines(true)
	_expect(outline.visible, "cartoon + outlines: lines drawn")
	_expect(CwLook.toon_value() == 1.0, "cartoon: cw_toon set to 1")
	if gl_ok:
		_expect(float(RenderingServer.global_shader_parameter_get(&"cw_toon")) == 1.0, "cartoon: cw_toon = 1")
	MenuSettings.set_toon_style(false)
	_expect(not outline.visible, "classic: no lines")
	_expect(not MenuSettings.toon_style(), "classic style reads back")
	_expect(CwLook.toon_value() == 0.0, "classic: cw_toon set to 0")
	if gl_ok:
		_expect(float(RenderingServer.global_shader_parameter_get(&"cw_toon")) == 0.0, "classic: cw_toon = 0")
	var cfg := ConfigFile.new()
	cfg.load(path)
	_expect(String(cfg.get_value(CwLook.SECTION, "style", "")) == "classic", "style persists")
	MenuSettings.set_toon_style(true)
	_expect(outline.visible, "back to cartoon: lines again")
	MenuSettings.set_outlines(false)
	_expect(not outline.visible, "outlines off: no lines")
	cfg.load(path)
	_expect(bool(cfg.get_value(CwLook.SECTION, "outlines", true)) == false, "outlines choice persists")
	_expect(MenuSettings.toon_style(), "outlines off keeps the cartoon light")
	MenuSettings.set_outlines(true)
	_expect(outline.visible, "outlines on again")
	# anti-aliasing: SMAA by default (sharp, no FXAA blur), switchable live, persisted
	_expect(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")) == Viewport.MSAA_DISABLED,
		"project: no MSAA (its samples catch the voxel face cracks)")
	_expect(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa")) == Viewport.SCREEN_SPACE_AA_SMAA,
		"project: SMAA, not FXAA")
	_expect(CwLook.AA_DEFAULT == "smaa", "SMAA is the default choice")
	for mode: String in CwLook.AA_MODES:
		MenuSettings.set_antialiasing(mode)
		_expect(MenuSettings.antialiasing() == mode, "AA %s reads back" % mode)
		_expect(get_root().msaa_3d == CwLook.aa_msaa(mode), "AA %s: window MSAA" % mode)
		_expect(get_root().screen_space_aa == CwLook.aa_screen_space(mode), "AA %s: window screen-space AA" % mode)
		_expect(get_root().screen_space_aa != Viewport.SCREEN_SPACE_AA_FXAA, "AA %s: no FXAA" % mode)
	cfg.load(path)
	_expect(String(cfg.get_value(CwLook.SECTION, "antialiasing", "")) == "off", "AA choice persists")
	MenuSettings.set_antialiasing("bogus")
	_expect(MenuSettings.antialiasing() == "smaa", "unknown AA falls back to SMAA")
	# a scene's tints go back to the project values
	CwLook.set_global(&"cw_shadow_tint", Color.RED)
	CwLook.reset_tints()
	if gl_ok:
		_expect(RenderingServer.global_shader_parameter_get(&"cw_shadow_tint") == CwLook.default_value(&"cw_shadow_tint"), "tints reset")

	# the options panel drives the same settings
	var panel := (load("res://scenes/menu/options_panel.tscn") as PackedScene).instantiate() as MenuOptionsPanel
	get_root().add_child(panel)
	await process_frame
	panel.style_classic.pressed.emit()
	_expect(not CwLook.toon() and not outline.visible, "panel: Classic switches the look")
	_expect(panel.outlines_on.disabled, "panel: outline buttons off in the classic style")
	panel.style_toon.pressed.emit()
	_expect(CwLook.toon() and outline.visible, "panel: Cartoon switches back")
	panel.outlines_off.pressed.emit()
	_expect(not outline.visible, "panel: outlines off")
	panel.outlines_on.pressed.emit()
	panel.aa_msaa4.pressed.emit()
	_expect(get_root().msaa_3d == Viewport.MSAA_4X and get_root().screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED,
		"panel: MSAA 4x applied live")
	panel.aa_off.pressed.emit()
	_expect(get_root().msaa_3d == Viewport.MSAA_DISABLED and get_root().screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED,
		"panel: AA off applied live")
	panel.aa_smaa.pressed.emit()
	_expect(get_root().msaa_3d == Viewport.MSAA_DISABLED and get_root().screen_space_aa == Viewport.SCREEN_SPACE_AA_SMAA,
		"panel: SMAA applied live")
	panel.sync()
	_expect(panel.aa_smaa.button_pressed and not panel.aa_off.button_pressed, "panel: AA buttons show the choice")
	panel.queue_free()
	cam.queue_free()
	await process_frame

	# restore the player's settings
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(backup)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	CwLook.apply()
