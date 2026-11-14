extends SceneTree
## Image-definition comparison on the campus (scenes/tycoon/tycoon_main.tscn, era 5, every lot
## at level 3): the same frames under each mode, saved as aa_<mode>_<view>.png (views: game,
## close) with the GPU time of the game view per mode. Modes:
##   fxaa, off, msaa2, msaa4, smaa, msaa4_smaa   the window's anti-aliasing
##   msaa4_nolines, msaa4_nocrease               MSAA 4x without the ink / without crease ink
##   msaa4_sq0, msaa4_sq2, msaa4_sq3             MSAA 4x with sun shadow filter hard / medium / high
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_aa_compare.gd -- <out_dir> [modes]

## mode -> [msaa_3d, screen_space_aa, shadow filter quality (-1 = project setting)]
const MODES := {
	"fxaa": [Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_FXAA, -1],
	"off": [Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED, -1],
	"msaa2": [Viewport.MSAA_2X, Viewport.SCREEN_SPACE_AA_DISABLED, -1],
	"msaa4": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED, -1],
	"smaa": [Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_SMAA, -1],
	"msaa4_smaa": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_SMAA, -1],
	"msaa4_nolines": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED, -1],
	"msaa4_nocrease": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED, -1],
	"msaa4_sq0": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED, 0],
	"msaa4_sq2": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED, 2],
	"msaa4_sq3": [Viewport.MSAA_4X, Viewport.SCREEN_SPACE_AA_DISABLED, 3],
}
const VIEWS := {
	"game": [Vector3(70, 70, 95), Vector3(4, 0, 2)],
	"close": [Vector3(14, 6, 26), Vector3(2, 1.5, 6)],
}

var out_dir := "user://"
var main: TycoonMain


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var modes: Array = MODES.keys()
	if args.size() > 1:
		modes = args[1].split(",")
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await _frames(5)
	main.clock.set_speed(0)
	var cam := main.camera
	cam.set_process(false)
	var s := main.state
	s.weeks = 4 * 5 * 52 + 10
	for lot: String in s.lot_ids():
		s.buildings[lot] = {"kind": s.lot_kind(lot), "level": 3, "target": 3, "weeks_left": 0}
	s.changed.emit()
	await _frames(30)
	var sq := int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"))
	var outline := cam.get_node_or_null("CwOutline") as MeshInstance3D
	var om := outline.get_active_material(0) as ShaderMaterial if outline else null
	var normal_weight: float = om.get_shader_parameter(&"normal_weight") if om else 0.0
	for m: String in modes:
		var mm: Array = MODES[m]
		get_root().msaa_3d = mm[0]
		get_root().screen_space_aa = mm[1]
		RenderingServer.directional_soft_shadow_filter_set_quality(sq if int(mm[2]) < 0 else int(mm[2]) as RenderingServer.ShadowQuality)
		if outline:
			outline.visible = m != "msaa4_nolines"
			om.set_shader_parameter(&"normal_weight", 0.0 if m == "msaa4_nocrease" else normal_weight)
		for v: String in VIEWS:
			var vv: Array = VIEWS[v]
			cam.global_transform = Transform3D(Basis.looking_at(vv[1] - vv[0], Vector3.UP), vv[0])
			await _frames(12)
			if v == "game":
				await _measure(m)
			await RenderingServer.frame_post_draw
			var img := get_root().get_texture().get_image()
			var path := out_dir.path_join("aa_%s_%s.png" % [m, v])
			print("saved ", path, " err=", img.save_png(path))
	quit()


func _measure(label: String) -> void:
	var vp := get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _frames(20)
	var gpu := 0.0
	var n := 120
	for i in n:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	print("AA %-14s gpu %.2f ms" % [label, gpu / n])


func _frames(k: int) -> void:
	for i in k:
		await process_frame
