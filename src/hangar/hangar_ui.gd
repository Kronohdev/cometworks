class_name HangarUI
extends CanvasLayer
## Hangar HUD. The layout lives in scenes/hangar.tscn (styled by ui/margin_theme.tres,
## generated with the palette by tools/make_ui_kit.py); this script fills in data and
## handles the HUD modes:
##   - top bar: File menu, undo/redo | tools (symmetry selector, angle snap, nodes)
##     | view (help, language, HUD) | Launch
##   - parts panel: search, category tabs (+ favorites), part cards, part card with stat
##     chips; collapses to a rail of category icons (« button)
##   - stages panel: compact / detailed stage cards, check badges, marker toggles and a
##     Crew tab (CrewSlot); collapses to its header (» button)
##   - readout (always visible with the HUD): ascent Δv vs target, TWR, mass, parts, cost
##   - HUD button / F2 hides every panel; ? / F1 shows the controls; Ctrl+F searches
## Static labels use translation keys as text, so Godot re-translates them.

signal part_chosen(id: String)
signal new_pressed
signal save_pressed
signal load_pressed
signal language_toggled
signal markers_toggled(com: bool, cot: bool, col: bool)
## Cycles to the next symmetry mode (X key, right-click on the symmetry button).
signal symmetry_pressed
## A symmetry mode picked in the selector (1, 2, 3, 4, 6 or 8 copies).
signal symmetry_chosen(n: int)
signal angle_snap_pressed
signal undo_pressed
signal redo_pressed
signal example_chosen(id: String)
signal nodes_toggled(on: bool)
## LMB on the part palette (outside the part cards): the hangar deletes the held part.
signal palette_clicked
signal height_changed(y: float)
## The Launch button (top bar, right).
signal launch_pressed

const STAGE_CARD := preload("res://scenes/ui/stage_card.tscn")
const PART_CARD := preload("res://scenes/ui/part_card.tscn")
const CHIP := preload("res://scenes/ui/chip.tscn")
const ICON_DIR := "res://ui/part_icons/"
const ICON_COLLAPSE := preload("res://ui/kit/icon_collapse.svg")
const ICON_EXPAND := preload("res://ui/kit/icon_expand.svg")
const ICON_OK := preload("res://ui/kit/icon_check.svg")
const ICON_WARN := preload("res://ui/kit/icon_warn.svg")
const ICON_DANGER := preload("res://ui/kit/icon_danger.svg")
const ICON_INFO := preload("res://ui/kit/icon_info.svg")
const SYM_ICONS := {
	1: preload("res://ui/kit/icon_sym_1.svg"), 2: preload("res://ui/kit/icon_sym_2.svg"),
	3: preload("res://ui/kit/icon_sym_3.svg"), 4: preload("res://ui/kit/icon_sym_4.svg"),
	6: preload("res://ui/kit/icon_sym_6.svg"), 8: preload("res://ui/kit/icon_sym_8.svg"),
}
const SYMMETRY_MODES: Array[int] = [1, 2, 3, 4, 6, 8]
const LEO_TARGET := 9400.0
## File menu item ids (examples start at FILE_EXAMPLES).
const FILE_NEW := 0
const FILE_SAVE := 1
const FILE_LOAD := 2
const FILE_EXAMPLES := 100
const PARTS_WIDE := 300.0
const PARTS_RAIL := 64.0
const CATEGORY_COLUMNS := 7
const FAV_CATEGORY := "favorites"
const PREFS_PATH := "user://hangar_prefs.cfg"
## Vessel warnings (full sentences from Vessel._warnings) -> short badge text and tone.
const WARN_BADGES := [
	["WARN_NO_CORE", "WARN_S_NO_CORE", MarginChip.Tone.DANGER],
	["WARN_NO_FUEL", "WARN_S_NO_FUEL", MarginChip.Tone.DANGER],
	["WARN_TWR_LOW", "WARN_S_TWR_LOW", MarginChip.Tone.DANGER],
	["WARN_TWR_MARGINAL", "WARN_S_TWR_MARGINAL", MarginChip.Tone.WARN],
	["WARN_DV_LOW", "WARN_S_DV_LOW", MarginChip.Tone.WARN],
	["WARN_UNSTABLE", "WARN_S_UNSTABLE", MarginChip.Tone.DANGER],
]

var _category: String = "command"
var _examples: Array[String] = []
var _status_timer := 0.0
var _last_analysis: Dictionary = {}
var _last_extra: Dictionary = {}
var _symmetry := 1
var _icon_cache: Dictionary = {}
var _search := ""
var _favorites: Array[String] = []
var _info_id := ""
var _detailed := false
var _hud_on := true
var parts_collapsed := false
var stages_collapsed := false

@onready var _root: Control = $Root
@onready var _parts_panel: PanelContainer = %PartsPanel
@onready var _stages_panel: PanelContainer = %StagesPanel
@onready var _readout: Control = %Readout
@onready var _parts_title: Label = %PartsTitle
@onready var _category_bar: GridContainer = %CategoryBar
@onready var _category_row: Control = %CategoryRow
@onready var _category_name: Label = %CategoryName
@onready var _category_count: Label = %CategoryCount
@onready var _btn_file: MenuButton = %BtnFile
@onready var _btn_snap: Button = %BtnSnap
@onready var _btn_sym: Button = %BtnSym
@onready var _btn_nodes: Button = %BtnNodes
@onready var _btn_help: Button = %BtnHelp
@onready var _btn_hud: Button = %BtnHud
@onready var _btn_launch: Button = %BtnLaunch
@onready var _btn_parts: Button = %BtnPartsCollapse
@onready var _btn_stages: Button = %BtnStagesCollapse
@onready var _btn_detail: Button = %BtnStageDetail
@onready var _search_box: LineEdit = %Search
@onready var _part_scroll: ScrollContainer = %PartScroll
@onready var _part_grid: GridContainer = %PartGrid
@onready var _parts_empty: Label = %PartsEmpty
@onready var _info_card: Control = %InfoCard
@onready var _info_body: Control = %InfoBody
@onready var _info_hint: Control = %InfoHint
@onready var _preview: TextureRect = %PartPreview
@onready var _part_name: Label = %PartName
@onready var _part_category: Label = %PartCategory
@onready var _part_desc: Label = %PartDesc
@onready var _chip_mass: MarginChip = %ChipMass
@onready var _chip_thrust: MarginChip = %ChipThrust
@onready var _chip_isp: MarginChip = %ChipIsp
@onready var _chip_prop: MarginChip = %ChipProp
@onready var _chip_size: MarginChip = %ChipSize
@onready var _chip_cost: MarginChip = %ChipCost
@onready var _tab_stages: Button = %TabStages
@onready var _tab_crew: Button = %TabCrew
@onready var _stages_body: Control = %StagesBody
@onready var _stage_page: Control = %StagePage
@onready var _crew_page: Control = %CrewPage
@onready var _crew_slot: Control = %CrewSlot
@onready var _crew_empty: Control = %CrewEmpty
@onready var _stage_scroll: ScrollContainer = %StageScroll
@onready var _stage_list: VBoxContainer = %StageList
@onready var _stages_empty: Label = %StagesEmpty
@onready var _checks: HFlowContainer = %Checks
@onready var _checks_head: Control = %ChecksHead
@onready var _dv_value: Label = %DvValue
@onready var _dv_target: Label = %DvTarget
@onready var _dv_stack: HBoxContainer = %DvStack
@onready var _dv_rest: Control = %SegRest
@onready var _ro_twr: Label = %RoTwr
@onready var _ro_mass: Label = %RoMass
@onready var _ro_parts: Label = %RoParts
@onready var _ro_cost: Label = %RoCost
@onready var _ro_status: MarginChip = %RoStatus
@onready var _toast: Control = %Toast
@onready var _status: Label = %Status
@onready var _empty_hint: Control = %EmptyHint
@onready var _help: Control = %HelpOverlay
@onready var _hover: PanelContainer = %HoverInfo
@onready var _hover_name: Label = %HoverName
@onready var _hover_detail: Label = %HoverDetail
@onready var _height: VSlider = %HeightSlider
@onready var _chk_com: Button = %ChkCoM
@onready var _chk_cot: Button = %ChkCoT
@onready var _chk_col: Button = %ChkCoL
@onready var _sym_popup: PopupPanel = %SymPopup
@onready var _sym_row: Container = %SymRow


func _ready() -> void:
	_load_prefs()
	%BtnLang.pressed.connect(func() -> void: language_toggled.emit())
	%BtnUndo.pressed.connect(func() -> void: undo_pressed.emit())
	%BtnRedo.pressed.connect(func() -> void: redo_pressed.emit())
	_btn_launch.pressed.connect(func() -> void: launch_pressed.emit())
	_btn_sym.pressed.connect(_open_symmetry)
	_btn_sym.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			symmetry_pressed.emit()
			_btn_sym.accept_event())
	for b in _sym_row.get_children():
		var n := int(String(b.name).trim_prefix("Sym"))
		(b as Button).pressed.connect(func() -> void: _choose_symmetry(n))
	_btn_snap.pressed.connect(func() -> void: angle_snap_pressed.emit())
	_btn_nodes.toggled.connect(func(on: bool) -> void: nodes_toggled.emit(on))
	_btn_help.toggled.connect(func(on: bool) -> void: _help.visible = on)
	_btn_hud.toggled.connect(func(on: bool) -> void: set_hud_visible(on))
	_btn_parts.pressed.connect(func() -> void: set_parts_collapsed(not parts_collapsed))
	_btn_stages.pressed.connect(func() -> void: set_stages_collapsed(not stages_collapsed))
	_btn_detail.toggled.connect(_set_detailed)
	_tab_stages.toggled.connect(func(_on: bool) -> void: _update_tabs())
	_tab_crew.toggled.connect(func(_on: bool) -> void: _update_tabs())
	_crew_slot.child_entered_tree.connect(func(_n: Node) -> void: _update_tabs.call_deferred())
	_crew_slot.child_exiting_tree.connect(func(_n: Node) -> void: _update_tabs.call_deferred())
	_btn_file.get_popup().id_pressed.connect(_on_file_menu)
	# category buttons are authored in the scene; each node is named after its category id
	for b in _category_bar.get_children():
		(b as Button).toggled.connect(func(on: bool) -> void:
			if on:
				_category = b.name
				if parts_collapsed:
					set_parts_collapsed(false)
				_fill_parts())
	for c in [_chk_com, _chk_cot, _chk_col]:
		c.toggled.connect(func(_on: bool) -> void:
			markers_toggled.emit(_chk_com.button_pressed, _chk_cot.button_pressed, _chk_col.button_pressed))
	_parts_panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			palette_clicked.emit())
	_search_box.text_changed.connect(func(t: String) -> void:
		_search = t.strip_edges().to_lower()
		_fill_parts())
	_search_box.gui_input.connect(func(e: InputEvent) -> void:
		var k := e as InputEventKey
		if k and k.pressed and k.keycode == KEY_ESCAPE:
			if _search_box.text != "":
				_search_box.clear()
				_search = ""
				_fill_parts()
			_search_box.release_focus()
			_search_box.accept_event())
	_stage_list.minimum_size_changed.connect(_fit_stage_list.call_deferred)
	_height.value_changed.connect(func(v: float) -> void: height_changed.emit(v))
	_update_tabs()
	refresh_texts()


func _process(delta: float) -> void:
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0:
			_toast.visible = false
	# the part card keeps the last hovered part while the mouse is over the palette
	if _info_id != "" and not _parts_panel.get_global_rect().has_point(_root.get_global_mouse_position()):
		_show_part_info("")


## Typing in the search box never reaches the hangar shortcuts (LineEdit consumes the
## keys); clicking anywhere else gives the keyboard back.
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and _search_box.has_focus() \
			and not _search_box.get_global_rect().has_point(mb.position):
		_search_box.release_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_F1:
		_btn_help.button_pressed = not _btn_help.button_pressed
	elif k.keycode == KEY_F2:
		_btn_hud.button_pressed = not _btn_hud.button_pressed
	elif k.keycode == KEY_F and k.ctrl_pressed:
		if not _hud_on:
			set_hud_visible(true)
		if parts_collapsed:
			set_parts_collapsed(false)
		_search_box.grab_focus()
		_search_box.select_all()
		get_viewport().set_input_as_handled()


## Decimal number with the locale's decimal separator ("1,5" in Portuguese).
static func num(v: float, nd := 0) -> String:
	var s := String.num(v, nd)
	if TranslationServer.get_locale().begins_with("pt"):
		s = s.replace(".", ",")
	return s


## Like num(), with thousands grouped by a space (SI style: "16 170").
static func numk(v: float, nd := 0) -> String:
	var s := String.num(absf(v), nd)
	var dot := s.find(".")
	var ip := s if dot < 0 else s.substr(0, dot)
	var fp := "" if dot < 0 else s.substr(dot + 1)
	var out := ""
	while ip.length() > 3:
		out = " " + ip.right(3) + out
		ip = ip.left(ip.length() - 3)
	out = ip + out
	if fp != "":
		out += ("," if TranslationServer.get_locale().begins_with("pt") else ".") + fp
	return ("-" if v < 0.0 else "") + out


static func _mass_text(kg: float) -> String:
	return "%s kg" % numk(kg) if kg < 1000.0 else "%s t" % numk(kg / 1000.0, 2 if kg < 10000.0 else 1)


# ------------------------------------------------------------ HUD modes
func set_hud_visible(on: bool) -> void:
	_hud_on = on
	_btn_hud.set_pressed_no_signal(on)
	for c in [_parts_panel, _stages_panel, _height, _readout]:
		c.visible = on
	_empty_hint.visible = on and int(_last_extra.get("parts", 0)) == 0
	if not on:
		_help.visible = false
		_btn_help.set_pressed_no_signal(false)
		_sym_popup.hide()
		hide_hover()


## Collapsed: only the category icons remain, as a short vertical rail.
func set_parts_collapsed(on: bool) -> void:
	parts_collapsed = on
	for c in [_parts_title, _search_box, _category_row, _part_scroll, _info_card]:
		(c as Control).visible = not on
	_parts_empty.visible = false
	_category_bar.columns = 1 if on else CATEGORY_COLUMNS
	_parts_panel.offset_right = _parts_panel.offset_left + (PARTS_RAIL if on else PARTS_WIDE)
	_parts_panel.anchor_bottom = 0.0 if on else 1.0
	_parts_panel.offset_bottom = (_parts_panel.offset_top + 10.0) if on else -12.0
	_btn_parts.icon = ICON_EXPAND if on else ICON_COLLAPSE
	if not on:
		_fill_parts()


## Collapsed: only the panel header (tabs) stays.
func set_stages_collapsed(on: bool) -> void:
	stages_collapsed = on
	_stages_body.visible = not on
	_btn_detail.visible = not on and _tab_stages.button_pressed
	_btn_stages.icon = ICON_COLLAPSE if on else ICON_EXPAND


func _set_detailed(on: bool) -> void:
	_detailed = on
	_btn_detail.set_pressed_no_signal(on)
	for c in _stage_list.get_children():
		(c as StageCard).set_detailed(on)


func _update_tabs() -> void:
	var crew := _tab_crew.button_pressed
	_stage_page.visible = not crew
	_crew_page.visible = crew
	_crew_empty.visible = _crew_slot.get_child_count() == 0
	_btn_detail.visible = not crew and not stages_collapsed
	if crew and stages_collapsed:
		set_stages_collapsed(false)


## The stage list grows with its cards up to the room left on screen, then scrolls.
func _fit_stage_list() -> void:
	var want := _stage_list.get_combined_minimum_size().y
	var room := get_viewport().get_visible_rect().size.y - _stages_panel.offset_top - 300.0
	_stage_scroll.custom_minimum_size.y = minf(want, maxf(room, 140.0))


# ------------------------------------------------------------ texts that need data or formatting
func refresh_texts() -> void:
	set_symmetry(_symmetry)
	set_angle_snap(_btn_snap.button_pressed)
	for b in _category_bar.get_children():
		var id := String(b.name)
		if id == FAV_CATEGORY:
			(b as Button).tooltip_text = "%s (%d)\n%s" % [tr("UI_FAVORITES"), _favorites.size(), tr("UI_FAV_TIP")]
		else:
			(b as Button).tooltip_text = "%s (%d)" % [PartDB.category_name(id), PartDB.parts_in_category(id).size()]
	for b in _sym_row.get_children():
		var n := int(String(b.name).trim_prefix("Sym"))
		(b as Button).tooltip_text = tr("UI_SYM_SINGLE") if n == 1 else tr("UI_SYM_COPIES") % n
	_fill_parts()
	_show_part_info(_info_id)
	_fill_file_menu()
	show_analysis(_last_analysis, _last_extra)


func set_symmetry(n: int) -> void:
	_symmetry = n
	_btn_sym.text = "%d×" % n
	_btn_sym.icon = SYM_ICONS.get(n, SYM_ICONS[1])
	_btn_sym.tooltip_text = "%s\n%s" % [tr("UI_SYMMETRY_TIP"), tr("UI_SYM_SINGLE") if n == 1 else tr("UI_SYM_COPIES") % n]
	for b in _sym_row.get_children():
		(b as Button).set_pressed_no_signal(String(b.name) == "Sym%d" % n)


func _open_symmetry() -> void:
	set_symmetry(_symmetry)
	var r := _btn_sym.get_global_rect()
	_sym_popup.popup(Rect2i(Vector2i(int(r.position.x) - 8, int(r.end.y) + 10), Vector2i.ZERO))


func _choose_symmetry(n: int) -> void:
	_sym_popup.hide()
	if symmetry_chosen.get_connections().is_empty():
		# the hangar only knows how to cycle: step until it lands on the chosen mode
		for i in SYMMETRY_MODES.size():
			if _symmetry == n:
				break
			symmetry_pressed.emit()
	else:
		symmetry_chosen.emit(n)
	set_symmetry(_symmetry)


func set_show_nodes(on: bool) -> void:
	_btn_nodes.set_pressed_no_signal(on)


func set_height(y: float) -> void:
	_height.set_value_no_signal(y)


func set_angle_snap(on: bool) -> void:
	_btn_snap.set_pressed_no_signal(on)
	_btn_snap.text = "15°" if on else tr("UI_SNAP_FREE")


func set_examples(ids: Array[String]) -> void:
	_examples = ids
	_fill_file_menu()


func _fill_file_menu() -> void:
	var pm := _btn_file.get_popup()
	pm.clear()
	pm.add_icon_item(preload("res://ui/kit/icon_new.svg"), tr("UI_NEW"), FILE_NEW)
	pm.add_icon_item(preload("res://ui/kit/icon_save.svg"), tr("UI_SAVE"), FILE_SAVE)
	pm.add_icon_item(preload("res://ui/kit/icon_load.svg"), tr("UI_LOAD"), FILE_LOAD)
	pm.add_separator(tr("UI_EXAMPLES"))
	for i in _examples.size():
		pm.add_icon_item(preload("res://ui/kit/icon_examples.svg"), ExampleVessels.display_name(_examples[i]), FILE_EXAMPLES + i)


func _on_file_menu(id: int) -> void:
	match id:
		FILE_NEW:
			new_pressed.emit()
		FILE_SAVE:
			save_pressed.emit()
		FILE_LOAD:
			load_pressed.emit()
		_:
			if id >= FILE_EXAMPLES:
				example_chosen.emit(_examples[id - FILE_EXAMPLES])


func flash(msg: String, seconds := 3.0) -> void:
	_status.text = msg
	_toast.visible = msg != ""
	_status_timer = seconds


## Small card next to the mouse with the hovered part's name, mass and free nodes.
func show_hover(id: String, mouse: Vector2, free_nodes: int) -> void:
	if not _hud_on:
		return  # HUD hidden: keep the view clean
	var p := PartDB.get_part(id)
	_hover_name.text = PartDB.part_name(id)
	_hover_detail.text = tr("UI_HOVER_DETAIL") % [numk(PartDB.wet_mass(p)), free_nodes]
	_hover.visible = true
	_hover.reset_size()
	var vp := get_viewport().get_visible_rect().size
	var pos := mouse + Vector2(18, 18)
	pos.x = minf(pos.x, vp.x - _hover.size.x - 8)
	pos.y = minf(pos.y, vp.y - _hover.size.y - 8)
	_hover.position = pos


func hide_hover() -> void:
	_hover.visible = false


# ------------------------------------------------------------ part palette
func _icon(id: String) -> Texture2D:
	var model: String = PartDB.get_part(id).get("model", id)
	if not _icon_cache.has(model):
		var path := ICON_DIR + model + ".png"
		_icon_cache[model] = load(path) if ResourceLoader.exists(path) else null
	return _icon_cache[model]


## Card label: the part name without the parenthesized note ("Kestrel-1 (sea level)").
static func _short_name(id: String) -> String:
	var n := PartDB.part_name(id)
	var i := n.find(" (")
	return n if i < 0 else n.substr(0, i)


func _fill_parts() -> void:
	for c in _part_grid.get_children():
		_part_grid.remove_child(c)
		c.queue_free()
	var ids: Array[String] = []
	if _search != "":
		# search across every category, by localized name or id
		_category_name.text = tr("UI_SEARCH_RESULTS")
		for c in PartDB.category_ids():
			for id in PartDB.parts_in_category(c):
				if PartDB.part_name(id).to_lower().contains(_search) or id.contains(_search):
					ids.append(id)
	elif _category == FAV_CATEGORY:
		_category_name.text = tr("UI_FAVORITES")
		for id in _favorites:
			if not PartDB.get_part(id).is_empty():
				ids.append(id)
	else:
		_category_name.text = PartDB.category_name(_category)
		ids = PartDB.parts_in_category(_category)
	_category_count.text = str(ids.size())
	for id in ids:
		var card: Button = PART_CARD.instantiate()
		card.text = _short_name(id)
		card.icon = _icon(id)
		card.tooltip_text = PartDB.part_name(id)
		card.get_node("Fav").visible = _favorites.has(id)
		card.pressed.connect(func() -> void:
			_show_part_info(id)
			part_chosen.emit(id))
		card.mouse_entered.connect(func() -> void: _show_part_info(id))
		card.gui_input.connect(func(e: InputEvent) -> void:
			var mb := e as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				_toggle_favorite(id)
				card.accept_event())
		_part_grid.add_child(card)
	_parts_empty.visible = ids.is_empty() and not parts_collapsed
	if ids.is_empty():
		_parts_empty.text = tr("UI_NO_RESULTS") if _search != "" else tr("UI_FAV_EMPTY")


func _toggle_favorite(id: String) -> void:
	if _favorites.has(id):
		_favorites.erase(id)
		flash(tr("UI_FAV_REMOVED") % PartDB.part_name(id), 1.5)
	else:
		_favorites.append(id)
		flash(tr("UI_FAV_ADDED") % PartDB.part_name(id), 1.5)
	_save_prefs()
	if _category == FAV_CATEGORY and _search == "":
		_fill_parts()
	else:
		for c in _part_grid.get_children():
			if (c as Button).tooltip_text == PartDB.part_name(id):
				c.get_node("Fav").visible = _favorites.has(id)
	refresh_category_tips()


func refresh_category_tips() -> void:
	var fav := _category_bar.get_node_or_null(FAV_CATEGORY) as Button
	if fav:
		fav.tooltip_text = "%s (%d)\n%s" % [tr("UI_FAVORITES"), _favorites.size(), tr("UI_FAV_TIP")]


func _load_prefs() -> void:
	var cf := ConfigFile.new()
	if cf.load(PREFS_PATH) == OK:
		for id in cf.get_value("palette", "favorites", PackedStringArray()):
			_favorites.append(String(id))


func _save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.load(PREFS_PATH)
	cf.set_value("palette", "favorites", PackedStringArray(_favorites))
	cf.save(PREFS_PATH)


func _show_part_info(id: String) -> void:
	_info_id = id
	_info_body.visible = id != ""
	_info_hint.visible = id == ""
	if id == "":
		return
	var p := PartDB.get_part(id)
	_preview.texture = _icon(id)
	_part_name.text = PartDB.part_name(id)
	_part_category.text = PartDB.category_name(p.get("category", ""))
	_chip_mass.set_chip(_mass_text(PartDB.wet_mass(p)))
	var engine := PartDB.is_engine(p)
	_chip_thrust.visible = engine
	_chip_isp.visible = engine
	if engine:
		_chip_thrust.set_chip("%s / %s kN" % [numk(p.get("thrust_sl_kn", 0), 1), numk(p.get("thrust_vac_kn", 0), 1)])
		_chip_isp.set_chip("%s / %s s" % [numk(p.get("isp_sl_s", 0)), numk(p.get("isp_vac_s", 0))])
	var prop := PartDB.prop_mass(p)
	_chip_prop.visible = prop > 0.0 and not engine
	if prop > 0.0 and not engine:
		var pname := PartDB.loc(PartDB.propellants.get(p.get("propellant", ""), {}).get("name", ""))
		_chip_prop.set_chip(_mass_text(prop), MarginChip.Tone.NEUTRAL, "%s\n%s" % [tr("UI_CHIP_PROP_TIP"), pname])
	var size: String = p.get("size", "")
	_chip_size.visible = PartDB.size_classes.has(size)
	if _chip_size.visible:
		_chip_size.set_chip("%s · Ø %s m" % [size, num(PartDB.size_classes[size], 2)])
	_chip_cost.set_chip("US$ %s M" % num(p.get("cost_musd", 0), 2))
	_part_desc.text = PartDB.loc(p.get("desc", ""))


# ------------------------------------------------------------ stages, checks and readout
## extra: {"parts": int, "cost": float, "stable": int (-1 unknown, 0 no, 1 yes, 2 gimbal)}
func show_analysis(a: Dictionary, extra: Dictionary) -> void:
	_last_analysis = a
	_last_extra = extra
	for c in _stage_list.get_children():
		_stage_list.remove_child(c)
		c.queue_free()
	for c in _checks.get_children():
		_checks.remove_child(c)
		c.queue_free()
	var stages: Array = a.get("stages", [])
	var n_parts := int(extra.get("parts", 0))
	_empty_hint.visible = _hud_on and n_parts == 0
	_stages_empty.visible = stages.is_empty()
	_ro_parts.text = numk(n_parts)
	_ro_cost.text = "US$ %s M" % num(extra.get("cost", 0.0), 1)
	_dv_target.text = tr("UI_TARGET_SHORT") % numk(LEO_TARGET)
	for i in range(stages.size() - 1, -1, -1):
		var card: StageCard = STAGE_CARD.instantiate()
		_stage_list.add_child(card)
		card.setup(stages[i], i == 0, MarginPalette.data(i))
		card.set_detailed(_detailed)
	_fill_dv_bar(stages)
	if stages.is_empty():
		_dv_value.text = "—"
		_dv_value.add_theme_color_override("font_color", MarginPalette.TEXT_DIM)
		_ro_twr.text = "—"
		_ro_twr.add_theme_color_override("font_color", MarginPalette.TEXT_DIM)
		_ro_mass.text = _mass_text(a.get("mass_kg", 0.0)) if n_parts > 0 else "—"
	else:
		var dv: float = a["ascent_dv"]
		_dv_value.text = "%s m/s" % numk(dv)
		_dv_value.add_theme_color_override("font_color", MarginPalette.SUCCESS if dv >= LEO_TARGET else MarginPalette.WARNING)
		var twr: float = a.get("liftoff_twr", 0.0)
		_ro_twr.text = num(twr, 2)
		var tc := MarginPalette.SUCCESS if twr >= 1.2 else (MarginPalette.WARNING if twr >= 1.0 else MarginPalette.DANGER)
		_ro_twr.add_theme_color_override("font_color", tc)
		_ro_mass.text = _mass_text(a["mass_kg"])
	_fill_checks(a.get("warnings", []), int(extra.get("stable", -1)), n_parts)
	_fit_stage_list.call_deferred()


## Stacked Δv bar: one segment per stage (stage colours), the rest of the LEO target empty.
func _fill_dv_bar(stages: Array) -> void:
	var total := 0.0
	for st in stages:
		total += float(st["dv_vac"])
	var segs := _dv_stack.get_children().filter(func(n: Node) -> bool: return n is ColorRect)
	for i in segs.size():
		var seg := segs[i] as ColorRect
		seg.visible = i < stages.size() and float(stages[i]["dv_vac"]) > 0.0
		if seg.visible:
			seg.size_flags_stretch_ratio = maxf(float(stages[i]["dv_vac"]), 1.0)
			seg.tooltip_text = "%s · %s m/s" % [tr("UI_STAGE_N") % stages[i]["stage"], numk(stages[i]["dv_vac"])]
	var ascent: float = _last_analysis.get("ascent_dv", 0.0)
	var scale := total / maxf(ascent, 1.0)  # segments are vac Δv; the bar shows the ascent share
	_dv_rest.visible = ascent < LEO_TARGET
	_dv_rest.size_flags_stretch_ratio = maxf((LEO_TARGET - ascent) * scale, 1.0)


func _match_warning(line: String, key: String) -> bool:
	var parts := tr(key).split("%")
	for i in parts.size():
		var frag := parts[i]
		if i > 0:
			var j := 0
			while j < frag.length() and not ("sdfi".contains(frag[j])):
				j += 1
			frag = frag.substr(j + 1)
		frag = frag.strip_edges()
		if frag != "" and not line.contains(frag):
			return false
	return true


func _add_check(label: String, tone: MarginChip.Tone, tip: String) -> MarginChip:
	var chip: MarginChip = CHIP.instantiate()
	_checks.add_child(chip)
	var icon: Texture2D = {MarginChip.Tone.OK: ICON_OK, MarginChip.Tone.WARN: ICON_WARN,
		MarginChip.Tone.DANGER: ICON_DANGER}.get(tone, ICON_INFO)
	chip.set_chip(label, tone, tip, icon)
	return chip


func _fill_checks(warns: Array, stable: int, n_parts: int) -> void:
	var worst := MarginChip.Tone.OK
	for line: String in warns:
		var label := tr("UI_ISSUE")
		var tone := MarginChip.Tone.WARN
		for wb in WARN_BADGES:
			if _match_warning(line, wb[0]):
				label = tr(wb[1])
				tone = wb[2]
				break
		_add_check(label, tone, line)
		if tone == MarginChip.Tone.DANGER or worst == MarginChip.Tone.OK:
			worst = tone
	if stable == 1:
		_add_check(tr("STAB_S_STABLE"), MarginChip.Tone.OK, tr("UI_STABLE"))
	elif stable == 2:
		_add_check(tr("STAB_S_GIMBAL"), MarginChip.Tone.INFO, tr("UI_GIMBAL"))
	_checks.visible = _checks.get_child_count() > 0 or (n_parts > 0 and warns.is_empty())
	_checks_head.visible = _checks.visible
	if n_parts == 0:
		_ro_status.set_chip(tr("UI_EMPTY_SHORT"), MarginChip.Tone.NEUTRAL, tr("UI_EMPTY"), ICON_INFO)
	elif warns.is_empty():
		_add_check(tr("OK_READY_SHORT"), MarginChip.Tone.OK, tr("OK_READY"))
		_ro_status.set_chip(tr("OK_READY_SHORT"), MarginChip.Tone.OK, tr("OK_READY"), ICON_OK)
	else:
		var text := tr("UI_ISSUE_1") if warns.size() == 1 else tr("UI_ISSUES") % warns.size()
		var tips := PackedStringArray()
		for line: String in warns:
			tips.append("• " + line)
		_ro_status.set_chip(text, worst, "\n".join(tips), ICON_DANGER if worst == MarginChip.Tone.DANGER else ICON_WARN)
