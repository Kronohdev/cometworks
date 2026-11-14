extends SceneTree
## Every node in every scene under res://scenes hangs from a parent that the scene declares
## (a moved or renamed node otherwise leaves its children behind: Godot drops them on load
## with "Parent path ... vanished", e.g. the HUD number tickers after the stat labels moved).
## Paths inside instanced sub-scenes (editable children) are only checked for their first
## segment, which must be a declared node; an inherited scene also knows its base's nodes.
## Run: godot --headless --path . --script res://tests/test_scene_paths.gd

var _failures := 0
var _scenes := 0


func _initialize() -> void:
	var stack: Array[String] = ["res://scenes"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(d):
			stack.append(d + "/" + sub)
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".tscn"):
				_check_scene(d + "/" + f)
	print("%d scenes checked" % _scenes)
	print("RESULT: ", "PASS" if _failures == 0 else "FAIL (%d)" % _failures)
	quit(1 if _failures else 0)


func _check_scene(path: String) -> void:
	_scenes += 1
	_declared(path, true)


## The node paths a scene declares (with its base scene's, for an inherited scene); with
## `report` it also fails on nodes hanging from an undeclared parent.
func _declared(path: String, report: bool) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var declared := {".": true}
	var instanced := {}   # paths of nodes that are sub-scene instances
	var name_re := RegEx.create_from_string("name=\"([^\"]+)\"")
	var parent_re := RegEx.create_from_string("parent=\"([^\"]*)\"")
	var inst_re := RegEx.create_from_string("instance=ExtResource\\(\"([^\"]+)\"\\)")
	var ext_re := RegEx.create_from_string("\\[ext_resource [^\\]]*path=\"([^\"]+)\"[^\\]]* id=\"([^\"]+)\"")
	var ext := {}
	for m in ext_re.search_all(text):
		ext[m.get_string(2)] = m.get_string(1)
	for line in text.split("\n"):
		if not line.begins_with("[node "):
			continue
		var nm := name_re.search(line)
		if nm == null:
			continue
		var pm := parent_re.search(line)
		var im := inst_re.search(line)
		if pm == null:
			# the root: an inherited scene starts from its base scene's nodes
			if im and ext.has(im.get_string(1)):
				declared.merge(_declared(String(ext[im.get_string(1)]), false))
			continue
		var parent := pm.get_string(1)
		var own := nm.get_string(1) if parent == "." else parent + "/" + nm.get_string(1)
		if report and not declared.has(parent):
			var inside_instance := false
			for inst: String in instanced:
				if parent.begins_with(inst + "/"):
					inside_instance = true
					break
			if not inside_instance:
				_failures += 1
				print("  FAIL %s: '%s' hangs from '%s', which the scene does not declare" % [path, nm.get_string(1), parent])
		declared[own] = true
		if im:
			instanced[own] = true
	return declared
