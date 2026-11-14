extends SceneTree
## Saves the validation rockets (src/hangar/example_vessels.gd) as editor scenes in
## scenes/examples/. Open them in the editor to see how a rocket is put together:
## the scene tree IS the attach tree, and each node's inspector shows its part id,
## the node it is attached to and its symmetry tag.
## Run: godot --headless --path . --script res://tools/make_example_scenes.gd

const IDS := ["andorinha", "condor", "garca"]


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://scenes/examples")
	for id in IDS:
		var v := Vessel.new()
		get_root().add_child(v)
		ExampleVessels.build(v, id)
		_name_nodes(v.root, 0)
		v.root.name = ExampleVessels.display_name(id)
		var ps := v.to_packed_scene()
		var path := "res://scenes/examples/%s.tscn" % id
		var err := ResourceSaver.save(ps, path)
		print("%s: %d parts -> %s (%s)" % [id, v.all_parts().size(), path, error_string(err)])
		v.queue_free()
	quit()


## Readable node names: "<attach node> · <part id>", e.g. "bottom · tank_hydrolox_l8".
func _name_nodes(p: PartInstance, depth: int) -> void:
	for c in p.part_children():
		c.name = "%s · %s" % [c.parent_node_name.replace(":", " "), c.part_id]
		_name_nodes(c, depth + 1)
