class_name SurfaceHUD
extends CanvasLayer
## HUD of scenes/surface/surface_demo.tscn. Layout, theme and static labels are
## authored in the scene; this script only fills data. Text comes from
## i18n/surface_strings.csv (EN/PT); static labels use keys as text so Godot
## re-translates them when the locale changes.

signal planet_selected(index: int)
signal lod_view_toggled(on: bool)

const TRANSLATIONS := ["res://i18n/surface_strings.en.translation", "res://i18n/surface_strings.pt.translation"]

@onready var _picker: OptionButton = %PlanetPicker
@onready var _desc: Label = %Description
@onready var _facts: Label = %Facts
@onready var _stats: Label = %Stats
@onready var _lang: Button = %LangButton
@onready var _lod: CheckButton = %LodToggle

var _profiles: Array[PlanetSurfaceProfile] = []
var _current: PlanetSurfaceProfile


## Registers the surface translations if the project does not list them yet.
static func ensure_translations() -> void:
	if TranslationServer.translate(&"SURF_TITLE") != &"SURF_TITLE":
		return
	for path: String in TRANSLATIONS:
		if ResourceLoader.exists(path):
			var t := load(path) as Translation
			if t:
				TranslationServer.add_translation(t)


func _ready() -> void:
	ensure_translations()
	_picker.item_selected.connect(func(i: int) -> void: planet_selected.emit(i))
	_lang.pressed.connect(_toggle_language)
	_lod.toggled.connect(func(on: bool) -> void: lod_view_toggled.emit(on))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func set_profiles(list: Array[PlanetSurfaceProfile], selected: int) -> void:
	_profiles = list
	_picker.clear()
	for p in list:
		_picker.add_item(tr(p.name_key))
	_picker.select(selected)


func show_profile(p: PlanetSurfaceProfile, index: int = -1) -> void:
	_current = p
	if index >= 0 and index < _picker.item_count:
		_picker.select(index)
	_refresh_texts()


func _toggle_language() -> void:
	TranslationServer.set_locale("en" if TranslationServer.get_locale().begins_with("pt") else "pt")


func _refresh_texts() -> void:
	for i in _profiles.size():
		_picker.set_item_text(i, tr(_profiles[i].name_key))
	if _current == null:
		return
	_desc.text = tr(_current.description_key) if _current.description_key != "" else ""
	var atmo := tr("SURF_AIRLESS")
	if _current.has_atmosphere:
		atmo = tr("SURF_ATMO_FMT") % num(_current.surface_pressure_kpa, 2 if _current.surface_pressure_kpa < 10.0 else 1)
	_facts.text = "%s  %s m/s²  (%s g)\n%s  %s\n%s  %s km" % [
		tr("SURF_GRAVITY"), num(_current.gravity, 2), num(_current.gravity / 9.80665, 2),
		tr("SURF_ATMOSPHERE"), atmo,
		tr("SURF_RADIUS"), num(_current.radius_km, 0)]


## stats: VoxelTerrain.get_stats() + "fps", "alt", "speed".
func update_stats(st: Dictionary) -> void:
	var tris: int = st.get("tris", 0)
	var naive: int = st.get("naive_tris", 0)
	var red := 0.0 if naive == 0 else 100.0 * (1.0 - float(tris) / float(naive))
	var lods: PackedInt32Array = st.get("per_lod", PackedInt32Array())
	var lod_txt := ""
	for i in lods.size():
		if lods[i] > 0:
			lod_txt += "%d:%d " % [i, lods[i]]
	var lines := [
		"%s %s" % [tr("SURF_FPS"), num(st.get("fps", 0.0), 0)],
		"%s %d  (%s %s)" % [tr("SURF_CHUNKS"), st.get("chunks", 0), tr("SURF_LOD"), lod_txt.strip_edges()],
		"%s %s  (-%s%% %s)" % [tr("SURF_TRIS"), num_k(tris), num(red, 0), tr("SURF_VS_NAIVE")],
		"%s %s ms" % [tr("SURF_GEN"), num(st.get("gen_ms_avg", 0.0), 1)],
		"%s %d / %d" % [tr("SURF_JOBS"), st.get("jobs", 0), st.get("queued", 0)],
		"%s %d" % [tr("SURF_COLLISION"), st.get("collision_chunks", 0)],
		"%s %s MB · %s %s MB" % [tr("SURF_MEMORY"), num(st.get("mem_mb", 0.0), 0), tr("SURF_VRAM"), num(st.get("vram_mb", 0.0), 0)],
		"%s %s m · %s %s m/s" % [tr("SURF_ALTITUDE"), num(st.get("alt", 0.0), 0), tr("SURF_SPEED"), num(st.get("speed", 0.0), 0)],
	]
	_stats.text = "\n".join(lines)


func set_lod_view(on: bool) -> void:
	_lod.set_pressed_no_signal(on)


static func num(v: float, decimals: int = 1) -> String:
	var s := String.num(v, decimals) if decimals > 0 else str(int(roundf(v)))
	if decimals > 0 and not s.contains("."):
		s += "." + "0".repeat(decimals)
	if TranslationServer.get_locale().begins_with("pt"):
		s = s.replace(".", ",")
	return s


static func num_k(v: int) -> String:
	if v >= 1000000:
		return num(v / 1.0e6, 2) + " M"
	if v >= 1000:
		return num(v / 1000.0, 1) + " k"
	return str(v)
