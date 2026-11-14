class_name CwOutline
extends MeshInstance3D
## Ink-outline post-process of a camera (scenes/fx/cw_outline.tscn: instance it as a child of a
## Camera3D). The full-screen quad and its shader (shaders/cw_outline.gdshader) do the work; this
## script keeps the quad at the camera's origin (the shader only draws for the camera that owns
## it), on a layer the camera sees, and shown only when the style is cartoon with outlines on
## (CwLook). Per-camera tuning: the material's Lines / Ink / Fade uniforms.


func _ready() -> void:
	add_to_group(CwLook.GROUP)
	transform = Transform3D.IDENTITY
	var cam := get_parent() as Camera3D
	if cam and cam.cull_mask != 0:
		# the lowest layer the camera renders
		var bit := 0
		while bit < 20 and (cam.cull_mask & (1 << bit)) == 0:
			bit += 1
		layers = 1 << bit
	CwLook.ensure_applied()
	refresh()


## Shows or hides the lines after the style changed.
func refresh() -> void:
	visible = CwLook.outlines_visible()
