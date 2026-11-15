extends SceneTree
## Rasterises an SVG to a PNG with Godot's SVG renderer (ThorVG).
## godot --headless --path . --script res://tools/rasterize_svg.gd -- <in.svg> <out.png> [scale]


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var scale := float(a[2]) if a.size() > 2 else 1.0
	var img := Image.new()
	var err := img.load_svg_from_string(FileAccess.get_file_as_string(a[0]), scale)
	if err != OK:
		push_error("svg load failed: %s" % err)
		quit(1)
		return
	img.save_png(a[1])
	print("RASTER %s -> %s (%dx%d)" % [a[0], a[1], img.get_width(), img.get_height()])
	quit()
