class_name TycoonSave
extends RefCounted
## Cometworks saves (GDD sections 19 and 20, E0): one JSON file per slot in user://saves/
## ("1", "2", "3" and "auto", written every month by TycoonFlow). The file holds a version,
## the time it was written, a short summary for the menus and TycoonState.to_dict(), so
## every system that adds its fields to to_dict() / from_dict() is saved with no change here.
## JSON numbers are doubles: integers beyond 2^53 (RNG states) are written as tagged strings
## ("#i64:"), and the rare float whose JSON text does not read back bit-exact as its hex bits
## ("#f64:"), so a loaded campaign continues exactly as the saved one would have.
## Demonstration saves (slots "demo_*") ship with the game under res://data/demo_saves/: the
## start of each era and a fair-mode start, made from a real campaign by
## tools/make_demo_saves.gd and opened from the main menu's Demonstração panel. They are
## read-only in an export and never show up in list() / Continue.

const DIR := "user://saves/"
const VERSION := 1
const SLOTS: Array[String] = ["1", "2", "3"]
const AUTO := "auto"
const DEMO_DIR := "res://data/demo_saves/"
const DEMO_PREFIX := "demo_"
## The demonstration slots, in the order the menu lists them.
const DEMOS: Array[String] = ["demo_fair", "demo_era1", "demo_era2", "demo_era3", "demo_era4", "demo_era5"]
const TYCOON_SCENE := "res://scenes/tycoon/tycoon_main.tscn"
const _BIG := "#i64:"
const _F64 := "#f64:"


static func path(slot: String) -> String:
	return (DEMO_DIR if is_demo(slot) else DIR) + "tycoon_%s.json" % slot


static func is_demo(slot: String) -> bool:
	return slot.begins_with(DEMO_PREFIX)


## The demonstration saves that are there: [{"slot", "summary", "extra"}] in DEMOS order.
static func demos() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in DEMOS:
		var d := read(slot)
		if not d.is_empty():
			out.append({"slot": slot, "summary": d.get("summary", {}), "extra": d.get("extra", {})})
	return out


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path(slot))


## Writes the campaign to a slot. `extra` lands next to the state (e.g. {"fair_mode": true}).
static func save(state: TycoonState, slot: String, extra: Dictionary = {}) -> Error:
	DirAccess.make_dir_recursive_absolute(path(slot).get_base_dir())
	var data := {"version": VERSION, "saved_at": int(Time.get_unix_time_from_system()), "slot": slot,
		"summary": {"agency": state.agency_name, "year": state.year(), "week": state.week(), "era": state.era(),
			"cash": state.cash, "milestones": state.milestones},
		"extra": extra, "state": state.to_dict()}
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		push_error("TycoonSave: cannot write %s" % path(slot))
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(encode(data), "\t", false, true))
	return OK


## The whole save file (version, saved_at, summary, extra, state), {} when missing or broken.
static func read(slot: String) -> Dictionary:
	if not exists(slot):
		return {}
	var f := FileAccess.open(path(slot), FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary or int((d as Dictionary).get("version", 0)) < 1:
		return {}
	return decode(d)


## Loads a slot into a new TycoonState (null when the slot is empty or unreadable).
static func load_state(slot: String) -> TycoonState:
	var d := read(slot)
	if d.is_empty() or not d.get("state") is Dictionary:
		return null
	return state_from(d["state"])


static func state_from(state_dict: Dictionary) -> TycoonState:
	return TycoonState.from_dict(state_dict)


## Save summaries for the menus, newest first: [{"slot", "saved_at", "summary", "extra"}]
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	for file in DirAccess.get_files_at(DIR):
		if not (file.begins_with("tycoon_") and file.ends_with(".json")):
			continue
		var slot := file.trim_prefix("tycoon_").trim_suffix(".json")
		var d := read(slot)
		if not d.is_empty():
			out.append({"slot": slot, "saved_at": int(d.get("saved_at", 0)), "summary": d.get("summary", {}),
				"extra": d.get("extra", {})})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["saved_at"]) > int(b["saved_at"]))
	return out


static func has_any() -> bool:
	return not list().is_empty()


## The newest slot ("" when there is no save): what Continue opens.
static func latest_slot() -> String:
	var l := list()
	return String(l[0]["slot"]) if not l.is_empty() else ""


static func delete(slot: String) -> void:
	if exists(slot):
		DirAccess.remove_absolute(path(slot))


## Opens the tycoon scene on a saved campaign (the scene's TycoonMain reads `load_slot`).
static func open_in_game(tree: SceneTree, slot: String) -> void:
	var ps := load(TYCOON_SCENE) as PackedScene
	var scene := ps.instantiate()
	scene.set("load_slot", slot)
	var extra: Dictionary = read(slot).get("extra", {})
	if "fair_mode" in scene:
		scene.set("fair_mode", bool(extra.get("fair_mode", false)))
	tree.change_scene_to_node(scene)


# ------------------------------------------------------------ exact JSON
## Integers too big for a double become "#i64:<digits>" strings.
static func encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_INT:
			return _BIG + str(v) if absi(v) > 9007199254740992 else v
		TYPE_FLOAT:
			# Godot's JSON text can be one bit off; those floats keep their exact bits in hex
			if is_finite(v) and float(JSON.parse_string(JSON.stringify(v, "", false, true))) == v:
				return v
			var b := PackedByteArray()
			b.resize(8)
			b.encode_double(0, v)
			return _F64 + b.hex_encode()
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = encode(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(encode(x))
			return a
		TYPE_COLOR:
			return "#" + (v as Color).to_html()
	return v


static func decode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_STRING:
			var s := String(v)
			if s.begins_with(_BIG):
				return int(s.substr(_BIG.length()))
			if s.begins_with(_F64):
				return s.substr(_F64.length()).hex_decode().decode_double(0)
			return s
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = decode(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(decode(x))
			return a
	return v
