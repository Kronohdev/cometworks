extends SceneTree
## Windowed screenshots of the Cometworks UI kit (scenes/tycoon/ui/cw_ui_kit.tscn), the
## showcase of every themed control (GDD section 22.9):
##   cw_kit_01          all controls, a text field focused (aurora underline)
##   cw_kit_02_popup    the option button's popup and a tooltip
## Run: godot --path . --resolution 1600x900 --script res://tests/screenshot_cw_ui_kit.gd -- <out_dir>

var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var kit := (load("res://scenes/tycoon/ui/cw_ui_kit.tscn") as PackedScene).instantiate() as Control
	get_root().add_child(kit)
	var tree := kit.get_node("Margin/Columns/Right/Tree") as Tree
	var root := tree.create_item()
	for branch in ["Propulsão", "Estruturas", "Ciência"]:
		var b := tree.create_item(root)
		b.set_text(0, branch)
		for leaf in ["Nível 1", "Nível 2"]:
			tree.create_item(b).set_text(0, leaf)
	(kit.get_node("Margin/Columns/Mid/Tabs/Equipe/List") as ItemList).select(1)
	await _frames(5)
	(kit.get_node("Margin/Columns/Left/Buttons/V/Line2") as LineEdit).grab_focus()
	await _frames(20)
	await _shot("cw_kit_01")
	var opt := kit.get_node("Margin/Columns/Left/Buttons/V/Row4/Option") as OptionButton
	opt.show_popup()
	await _frames(20)
	await _shot("cw_kit_02_popup")
	print("UI KIT SCREENSHOTS DONE")
	quit()


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := out_dir.path_join(shot_name + ".png")
	img.save_png(path)
	print("saved %s" % path)
