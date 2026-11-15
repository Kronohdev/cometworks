class_name HangarUI
extends CanvasLayer
## Hangar HUD in the Cometworks look. The whole layout lives in scenes/hangar/ui/hangar_ui.tscn
## (cream sticker panels of ui/cometworks_theme.tres, candy icons in ui/cometworks/hangar/);
## this script only fills it with data and duplicates the hidden templates under Templates:
##   - top bar: Back, the workshop title (mission name), File menu, undo / redo, symmetry,
##     angle snap, nodes | help, language, HUD | Launch
##   - parts panel (left): search, category tabs (Recommended first, then favorites and the
##     catalog categories), the "Recommended for you" strip with one-click Add, and big part
##     cards (thumbnail, propellant colour, one plain stat). Engines that cannot burn what
##     the tanks carry are dimmed and tagged. Hovering a card opens the detail card beside
##     the panel. Collapses to a rail of category keys.
##   - rocket panel (right): the goal card (tycoon mission or the free workshop's training
##     goal), meters for reach (Δv), liftoff push (TWR), cost and mass against the goal, the
##     verdict, the plain-language problems, the stages and the crew drawer; markers toggles.
##   - toasts, the empty-pad hint, the 3D hover card, the help overlay and the symmetry popup.
## Advice and problems come from PartAdvisor (pure rules); the goal is FlightSession.mission
## (empty = free workshop). Static labels use translation keys as text, so Godot re-translates.

signal part_chosen(id: String)
## One-click Add on a recommendation: the hangar attaches it where `hint` says (PartAdvisor
## placement hints) or puts it in the player's hand.
signal part_quick_add(id: String, hint: String)
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
## The Back button (top bar, left) and the goal card's Back (embedded with a mission).
signal menu_pressed
## The goal card's "Usar na missão" (embedded hangar with a mission): the host takes the vessel.
signal use_pressed

const ICON_DIR := "res://ui/part_icons/"
const ICON_COLLAPSE := preload("res://ui/cometworks/hangar/ink_collapse.svg")
const ICON_EXPAND := preload("res://ui/cometworks/hangar/ink_expand.svg")
const ICON_OK := preload("res://ui/cometworks/hangar/ok.svg")
const ICON_WARN := preload("res://ui/cometworks/hangar/warn.svg")
const ICON_DANGER := preload("res://ui/cometworks/hangar/danger.svg")
const ICON_STAR := preload("res://ui/cometworks/hangar/recommended.svg")
const SYM_ICONS := {
	1: preload("res://ui/cometworks/hangar/ink_sym_1.svg"), 2: preload("res://ui/cometworks/hangar/ink_sym_2.svg"),
	3: preload("res://ui/cometworks/hangar/ink_sym_3.svg"), 4: preload("res://ui/cometworks/hangar/ink_sym_4.svg"),
	6: preload("res://ui/cometworks/hangar/ink_sym_6.svg"), 8: preload("res://ui/cometworks/hangar/ink_sym_8.svg"),
}
const SYMMETRY_MODES: Array[int] = [1, 2, 3, 4, 6, 8]
## Kept for callers of the old HUD: the free workshop's Δv goal.
const LEO_TARGET := PartAdvisor.LEO_DV
## File menu item ids (examples start at FILE_EXAMPLES).
const FILE_NEW := 0
const FILE_SAVE := 1
const FILE_LOAD := 2
const FILE_EXAMPLES := 100
const PARTS_WIDE := 408.0
const PARTS_RAIL := 150.0
## Category keys per row on the collapsed rail.
const RAIL_COLUMNS := 2
const CATEGORY_COLUMNS := 7
const REC_CATEGORY := "recommended"
const FAV_CATEGORY := "favorites"
const STRIP_ITEMS := 2
const PREFS_PATH := "user://hangar_prefs.cfg"
## Meter scales: the bar ends at goal * GOAL_SPAN, so the goal tick sits at 1 / GOAL_SPAN.
const GOAL_SPAN := 1.25
const TWR_SPAN := 2.5

## Propellant id -> colour of its stripe and drop on the part cards (edit in the inspector).
@export var propellant_colors: Dictionary = {}
## Stage colours, stage 1 first (stage cards).
@export var stage_colors: Array[Color] = []

var _category: String = REC_CATEGORY
var _examples: Array[String] = []
var _status_timer := 0.0
var _last_analysis: Dictionary = {}
var _last_extra: Dictionary = {}
var _symmetry := 1
var _icon_cache: Dictionary = {}
var _search := ""
var _favorites: Array[String] = []
var _detail_id := ""
var _hud_on := true
var _recs: Array[Dictionary] = []
var _problems: Array[Dictionary] = []
var _specs: Array = []
var _focus := ""
var parts_collapsed := false
var stages_collapsed := false
## Inside the tycoon (the hangar's `embedded`): Back reads "Voltar ao campus" and the goal card
## carries the mission's Back / "Usar na missão" buttons.
var embedded := false

@onready var _root: Control = $Root
@onready var _parts_panel: PanelContainer = %PartsPanel
@onready var _rocket_panel: PanelContainer = %RocketPanel
@onready var _parts_title: Label = %PartsTitle
@onready var _category_bar: GridContainer = %CategoryBar
@onready var _category_row: Control = %CategoryRow
@onready var _category_icon: TextureRect = %CategoryIcon
@onready var _category_name: Label = %CategoryName
@onready var _category_count: Label = %CategoryCount
@onready var _btn_file: MenuButton = %BtnFile
@onready var _btn_snap: Button = %BtnSnap
@onready var _btn_sym: Button = %BtnSym
@onready var _btn_nodes: Button = %BtnNodes
@onready var _btn_help: Button = %BtnHelp
@onready var _btn_hud: Button = %BtnHud
@onready var _btn_lang: Button = %BtnLang
@onready var _btn_launch: Button = %BtnLaunch
@onready var _btn_parts: Button = %BtnPartsCollapse
@onready var _btn_rocket: Button = %BtnRocketCollapse
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _search_box: LineEdit = %Search
@onready var _rec_strip: Control = %RecStrip
@onready var _rec_list: VBoxContainer = %RecList
@onready var _btn_see_all: Button = %BtnSeeAll
@onready var _part_scroll: ScrollContainer = %PartScroll
@onready var _part_list: VBoxContainer = %PartList
@onready var _rec_full: VBoxContainer = %RecFull
@onready var _rec_empty: Label = %RecEmpty
@onready var _part_grid: GridContainer = %PartGrid
@onready var _grid_caption: Label = %GridCaption
@onready var _verdict_mini: TextureRect = %VerdictMini
@onready var _parts_empty: Label = %PartsEmpty
@onready var _tpl_card: Button = %PartCardTemplate
@onready var _tpl_rec: Control = %RecRowTemplate
@onready var _tpl_problem: Control = %ProblemTemplate
@onready var _tpl_stage: Control = %StageTemplate
@onready var _detail: PanelContainer = %PartDetail
@onready var _rocket_body: Control = %RocketBody
@onready var _verdict_pill: Control = %VerdictPill
@onready var _verdict_icon: TextureRect = %VerdictIcon
@onready var _verdict: Label = %Verdict
@onready var _goal_caption: Label = %GoalCaption
@onready var _goal_title: Label = %GoalTitle
@onready var _goal_line: Label = %GoalLine
@onready var _meter_dv: Control = %MeterDv
@onready var _meter_twr: Control = %MeterTwr
@onready var _meter_cost: Control = %MeterCost
@onready var _meter_mass: Control = %MeterMass
@onready var _tab_stages: Button = %TabStages
@onready var _tab_crew: Button = %TabCrew
@onready var _problem_list: VBoxContainer = %ProblemList
@onready var _stage_list: VBoxContainer = %StageList
@onready var _stages_empty: Label = %StagesEmpty
@onready var _crew_info: Control = %CrewInfo
@onready var _crew_drawer: Control = %CrewDrawer
@onready var _crew_slot: Control = %CrewSlot
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
	CwIcon.sharpen_all(self)   # icons drawn bigger than their 32 px (the goal card's planet)
	_btn_lang.pressed.connect(func() -> void: language_toggled.emit())
	%BtnUndo.pressed.connect(func() -> void: undo_pressed.emit())
	%BtnRedo.pressed.connect(func() -> void: redo_pressed.emit())
	_btn_launch.pressed.connect(func() -> void: launch_pressed.emit())
	%BtnMenu.pressed.connect(func() -> void: menu_pressed.emit())
	%BtnGoalBack.pressed.connect(func() -> void: menu_pressed.emit())
	%BtnUse.pressed.connect(func() -> void: use_pressed.emit())
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
	%BtnHelpClose.pressed.connect(func() -> void: _btn_help.button_pressed = false)
	_btn_hud.toggled.connect(func(on: bool) -> void: set_hud_visible(on))
	_btn_parts.pressed.connect(func() -> void: set_parts_collapsed(not parts_collapsed))
	_btn_rocket.pressed.connect(func() -> void: set_stages_collapsed(not stages_collapsed))
	_btn_see_all.pressed.connect(func() -> void: select_category(REC_CATEGORY))
	_tab_stages.toggled.connect(func(_on: bool) -> void: _update_tabs())
	_tab_crew.toggled.connect(func(_on: bool) -> void: _update_tabs())
	_btn_file.get_popup().id_pressed.connect(_on_file_menu)
	# category keys are authored in the scene; each node is named after its category id
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
	_height.value_changed.connect(func(v: float) -> void: height_changed.emit(v))
	_update_tabs()
	refresh_texts()


func _process(delta: float) -> void:
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0:
			_toast.visible = false
	# the detail card stays while the mouse is over the palette
	if _detail_id != "" and not _parts_panel.get_global_rect().has_point(_root.get_global_mouse_position()):
		_show_detail("")


## Typing in the search box never reaches the hangar shortcuts (LineEdit consumes the
## keys); clicking anywhere else gives the keyboard back.
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and _search_box.has_focus() \
			and not _search_box.get_global_rect().has_point(_root.get_global_mouse_position()):
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


## Decimal number with the locale's decimal separator (kept for old callers).
static func num(v: float, nd := 0) -> String:
	return HangarFormat.num(v, nd)


## Thousands grouped by a space (kept for old callers).
static func numk(v: float, nd := 0) -> String:
	return HangarFormat.numk(v, nd)


## The mission the hangar builds for, or the free workshop's training goal.
static func current_goal() -> Dictionary:
	return FlightSession.mission if not FlightSession.mission.is_empty() else PartAdvisor.free_goal()


func _prop_color(prop: String) -> Color:
	return propellant_colors.get(prop, CwPalette.WELL_LINE)


# ------------------------------------------------------------ HUD modes
## The hangar inside the tycoon: Back goes to the campus and the goal card gets its buttons.
func set_embedded(on: bool) -> void:
	embedded = on
	var back := %BtnMenu as Button
	back.text = "TY_HG_CARD_TO_CAMPUS" if on else "HG_BACK"
	back.tooltip_text = "TY_HG_CARD_TO_CAMPUS" if on else "UI_BACK_MENU_TIP"
	_fill_goal()


func set_hud_visible(on: bool) -> void:
	_hud_on = on
	_btn_hud.set_pressed_no_signal(on)
	for c in [_parts_panel, _rocket_panel, _height]:
		c.visible = on
	_empty_hint.visible = on and int(_last_extra.get("parts", 0)) == 0
	_update_tabs()
	if not on:
		_help.visible = false
		_btn_help.set_pressed_no_signal(false)
		_sym_popup.hide()
		_show_detail("")
		hide_hover()


## Collapsed: only the category keys remain, as a slim rail.
func set_parts_collapsed(on: bool) -> void:
	parts_collapsed = on
	for c in [_parts_title, _search_box, _category_row, _part_scroll, %HintLine]:
		(c as Control).visible = not on
	_parts_empty.visible = false
	_category_bar.columns = RAIL_COLUMNS if on else CATEGORY_COLUMNS
	_parts_panel.offset_right = _parts_panel.offset_left + (PARTS_RAIL if on else PARTS_WIDE)
	_parts_panel.anchor_bottom = 0.0 if on else 1.0
	_parts_panel.offset_bottom = (_parts_panel.offset_top + 10.0) if on else -16.0
	_btn_parts.icon = ICON_EXPAND if on else ICON_COLLAPSE
	if on:
		_rec_strip.visible = false
		_show_detail("")
	else:
		_fill_parts()


## Collapsed: only the rocket panel's header (title + verdict) stays.
func set_stages_collapsed(on: bool) -> void:
	stages_collapsed = on
	_rocket_body.visible = not on
	_rocket_panel.anchor_bottom = 0.0 if on else 1.0
	_rocket_panel.offset_bottom = (_rocket_panel.offset_top + 10.0) if on else -16.0
	_btn_rocket.icon = ICON_COLLAPSE if on else ICON_EXPAND
	_verdict_mini.visible = on
	_update_tabs()


func select_category(id: String) -> void:
	var b := _category_bar.get_node_or_null(id) as Button
	if b:
		b.button_pressed = true


func _update_tabs() -> void:
	var crew := _tab_crew.button_pressed
	_problem_list.visible = not crew
	_stage_list.visible = not crew
	_stages_empty.visible = not crew and _stage_list.get_child_count() == 0
	_crew_info.visible = crew
	_crew_drawer.visible = crew and _hud_on and not stages_collapsed and _crew_slot.get_child_count() > 0


# ------------------------------------------------------------ texts that need data or formatting
func refresh_texts() -> void:
	set_symmetry(_symmetry)
	set_angle_snap(_btn_snap.button_pressed)
	_btn_lang.text = "EN" if TranslationServer.get_locale().begins_with("pt") else "PT"
	for b in _category_bar.get_children():
		(b as Button).tooltip_text = _category_title(String(b.name))
	for b in _sym_row.get_children():
		var n := int(String(b.name).trim_prefix("Sym"))
		(b as Button).tooltip_text = tr("UI_SYM_SINGLE") if n == 1 else tr("UI_SYM_COPIES") % n
	_fill_goal()
	_fill_file_menu()
	show_analysis(_last_analysis, _last_extra)
	_fill_parts()


func _category_title(id: String) -> String:
	match id:
		REC_CATEGORY:
			return tr("HG_RECOMMENDED")
		FAV_CATEGORY:
			return "%s (%d)\n%s" % [tr("UI_FAVORITES"), _favorites.size(), tr("UI_FAV_TIP")]
	return "%s (%d)" % [PartDB.category_name(id), PartDB.parts_in_category(id).size()]


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
	var xf := _root.get_viewport_transform()
	var pos := xf * Vector2(r.position.x - 8, r.end.y + 10)
	_sym_popup.popup(Rect2i(Vector2i(pos), Vector2i.ZERO))


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
	pm.add_icon_item(preload("res://ui/cometworks/hangar/ink_new.svg"), tr("UI_NEW"), FILE_NEW)
	pm.add_icon_item(preload("res://ui/cometworks/hangar/ink_save.svg"), tr("UI_SAVE"), FILE_SAVE)
	pm.add_icon_item(preload("res://ui/cometworks/hangar/ink_load.svg"), tr("UI_LOAD"), FILE_LOAD)
	pm.add_separator(tr("UI_EXAMPLES"))
	for i in _examples.size():
		pm.add_icon_item(preload("res://ui/cometworks/hangar/ink_examples.svg"), ExampleVessels.display_name(_examples[i]),
			FILE_EXAMPLES + i)


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
	if _toast.visible:
		CwMotion.poke(_toast)
	_status_timer = seconds


## The hangar reports a one-click Add: attached in place, or handed to the player.
func notify_added(id: String, attached: bool) -> void:
	if attached:
		CwSfx.play(&"workshop_clank")
		flash(tr("HG_ADDED") % PartDB.part_name(id), 2.0)
	else:
		flash(tr("HG_IN_HAND") % PartDB.part_name(id), 3.5)


## Small card next to the mouse with the hovered part's name, mass and free nodes.
func show_hover(id: String, mouse: Vector2, free_nodes: int) -> void:
	if not _hud_on:
		return  # HUD hidden: keep the view clean
	var p := PartDB.get_part(id)
	_hover_name.text = PartDB.part_name(id)
	_hover_detail.text = tr("UI_HOVER_DETAIL") % [HangarFormat.numk(PartDB.wet_mass(p)), free_nodes]
	_hover.visible = true
	_hover.reset_size()
	var m := _root.get_viewport_transform().affine_inverse() * mouse
	var vp := _root.size
	var pos := m + Vector2(18, 18)
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


## One plain number for the card: thrust for engines, fuel for tanks, mass for the rest.
static func _card_stat(p: Dictionary) -> String:
	if PartDB.is_engine(p):
		var sl := float(p.get("thrust_sl_kn", 0.0))
		return HangarFormat.thrust(sl if sl > 0.0 else float(p.get("thrust_vac_kn", 0.0)))
	if p.get("category", "") == "tank":
		return HangarFormat.mass(float(p.get("prop_mass_kg", 0.0)))
	return HangarFormat.mass(PartDB.wet_mass(p))


func _rec_of(id: String) -> Dictionary:
	for r in _recs:
		if r["id"] == id:
			return r
	return {}


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


## Rebuilds the cards of the current tab (search, Recommended, favorites or a category).
## `keep_scroll`: a refresh of the same tab (the vessel changed) keeps the scroll position.
func _fill_parts(keep_scroll := false) -> void:
	var scroll := _part_scroll.scroll_vertical
	_clear(_part_grid)
	_clear(_rec_full)
	var ids: Array[String] = []
	var rec_tab := _category == REC_CATEGORY and _search == ""
	if _search != "":
		_category_name.text = tr("UI_SEARCH_RESULTS")
		_category_icon.texture = preload("res://ui/cometworks/hangar/ink_search.svg")
		for c in PartDB.category_ids():
			for id in PartDB.parts_in_category(c):
				if PartDB.part_name(id).to_lower().contains(_search) or id.contains(_search):
					ids.append(id)
	elif rec_tab:
		_category_name.text = tr("HG_RECOMMENDED")
	elif _category == FAV_CATEGORY:
		_category_name.text = tr("UI_FAVORITES")
		for id in _favorites:
			if not PartDB.get_part(id).is_empty():
				ids.append(id)
	else:
		_category_name.text = PartDB.category_name(_category)
		ids = PartDB.parts_in_category(_category)
	if _search == "":
		var key := _category_bar.get_node_or_null(_category) as Button
		_category_icon.texture = key.icon if key else null
	if rec_tab:
		for r in _recs:
			_rec_full.add_child(_make_rec_row(r))
		_category_count.text = str(_recs.size())
		# below the advice: parts that go well with this rocket, to browse
		for id in PartAdvisor.compatible(_specs, _focus):
			if _rec_of(id).is_empty():
				ids.append(id)
	else:
		_category_count.text = str(ids.size())
	_rec_full.visible = rec_tab
	_grid_caption.visible = rec_tab and not ids.is_empty()
	_rec_empty.visible = rec_tab and _recs.is_empty()
	for id in ids:
		_part_grid.add_child(_make_card(id))
	_parts_empty.visible = not rec_tab and ids.is_empty() and not parts_collapsed
	if ids.is_empty() and not rec_tab:
		_parts_empty.text = tr("UI_NO_RESULTS") if _search != "" else tr("UI_FAV_EMPTY")
	_fill_rec_strip()
	if keep_scroll:
		_part_scroll.set_deferred("scroll_vertical", scroll)
	else:
		_part_scroll.scroll_vertical = 0


func _make_card(id: String) -> Button:
	var p := PartDB.get_part(id)
	var card := _tpl_card.duplicate() as Button
	card.unique_name_in_owner = false
	card.set_meta("part_id", id)
	(card.get_node("Margin/VBox/Bay/Thumb") as TextureRect).texture = _icon(id)
	(card.get_node("Margin/VBox/Name") as Label).text = PartDB.part_name(id)
	(card.get_node("Margin/VBox/Info/Stat") as Label).text = _card_stat(p)
	var prop: String = p.get("propellant", "")
	var stripe := card.get_node("Margin/VBox/Stripe") as ColorRect
	var drop := card.get_node("Margin/VBox/Info/Drop") as TextureRect
	stripe.visible = prop != ""
	drop.visible = prop != ""
	stripe.color = _prop_color(prop)
	drop.modulate = _prop_color(prop)
	_update_card(card)
	card.pressed.connect(func() -> void:
		_show_detail(id, card)
		part_chosen.emit(id))
	card.mouse_entered.connect(func() -> void: _show_detail(id, card))
	card.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_toggle_favorite(id)
			card.accept_event())
	card.visible = true
	return card


## Badges that follow the vessel: favorite, recommended, wrong propellant.
func _update_card(card: Control) -> void:
	var id: String = card.get_meta("part_id", "")
	var fit := PartAdvisor.engine_fit(id, _specs, _focus)
	card.get_node("Fav").visible = _favorites.has(id)
	card.get_node("RecBadge").visible = not _rec_of(id).is_empty()
	card.get_node("Mismatch").visible = fit < 0
	card.modulate = Color(1, 1, 1, 0.55) if fit < 0 else Color.WHITE


func _refresh_cards() -> void:
	for c in _part_grid.get_children():
		_update_card(c)


func _make_rec_row(r: Dictionary) -> Control:
	var id: String = r["id"]
	var p := PartDB.get_part(id)
	var row := _tpl_rec.duplicate() as Control
	row.unique_name_in_owner = false
	row.set_meta("part_id", id)
	(row.get_node("Row/Bay/Thumb") as TextureRect).texture = _icon(id)
	(row.get_node("Row/Texts/NameRow/Name") as Label).text = PartDB.part_name(id)
	(row.get_node("Row/Texts/Reason") as Label).text = PartAdvisor.reason_text(r)
	var prop: String = p.get("propellant", "")
	var drop := row.get_node("Row/Texts/NameRow/Drop") as TextureRect
	drop.visible = prop != ""
	drop.modulate = _prop_color(prop)
	var add := row.get_node("Row/Add") as Button
	add.pressed.connect(func() -> void: part_quick_add.emit(id, String(r["hint"])))
	row.mouse_entered.connect(func() -> void: _show_detail(id, row))
	row.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			part_chosen.emit(id)
			row.accept_event())
	row.visible = true
	return row


## The top picks above the cards while browsing a category (not in the Recommended tab).
func _fill_rec_strip() -> void:
	_clear(_rec_list)
	var show := not _recs.is_empty() and not (_category == REC_CATEGORY and _search == "") and not parts_collapsed
	_rec_strip.visible = show
	if not show:
		return
	for i in mini(STRIP_ITEMS, _recs.size()):
		_rec_list.add_child(_make_rec_row(_recs[i]))
	_btn_see_all.visible = _recs.size() > STRIP_ITEMS
	_btn_see_all.text = tr("HG_SEE_ALL") % _recs.size()


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
		_refresh_cards()
	refresh_category_tips()


func refresh_category_tips() -> void:
	var fav := _category_bar.get_node_or_null(FAV_CATEGORY) as Button
	if fav:
		fav.tooltip_text = _category_title(FAV_CATEGORY)


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


# ------------------------------------------------------------ part detail card
## Opens the detail card beside the palette, level with `anchor` (a card or a row).
func _show_detail(id: String, anchor: Control = null) -> void:
	_detail_id = id
	_detail.visible = id != "" and _hud_on
	if id == "":
		return
	var p := PartDB.get_part(id)
	%DetailThumb.texture = _icon(id)
	%DetailName.text = PartDB.part_name(id)
	var cat: String = p.get("category", "")
	%DetailCategory.text = PartDB.category_name(cat)
	var key := _category_bar.get_node_or_null(cat) as Button
	%DetailCatIcon.texture = key.icon if key else null
	%DetailDesc.text = PartDB.loc(p.get("desc", ""))
	# what the advisor thinks of it
	var rec := _rec_of(id)
	var fit := PartAdvisor.engine_fit(id, _specs, _focus)
	var advice: Control = %DetailAdvice
	advice.visible = true
	if not rec.is_empty():
		%DetailAdviceIcon.texture = ICON_STAR
		%DetailAdviceText.text = PartAdvisor.reason_text(rec)
	elif fit < 0:
		%DetailAdviceIcon.texture = ICON_WARN
		var have := PartAdvisor.matching_props(_specs, _focus).keys()
		%DetailAdviceText.text = tr("ADV_P_MISMATCH") % [_short_name(id), PartAdvisor.prop_name(p.get("propellant", "")),
			PartAdvisor.prop_name(have[0] if not have.is_empty() else "")]
	elif fit > 0:
		%DetailAdviceIcon.texture = ICON_OK
		%DetailAdviceText.text = tr("HG_FITS")
	else:
		advice.visible = false
	# plain stats
	var sl := float(p.get("thrust_sl_kn", 0.0))
	var vac := float(p.get("thrust_vac_kn", 0.0))
	_detail_row("Thrust", sl > 0.0, HangarFormat.thrust(sl))
	_detail_row("ThrustVac", vac > 0.0, HangarFormat.thrust(vac))
	var isl := float(p.get("isp_sl_s", 0.0))
	var ivac := float(p.get("isp_vac_s", 0.0))
	_detail_row("Isp", ivac > 0.0, ("%s–%s s" % [HangarFormat.numk(isl), HangarFormat.numk(ivac)]) if isl > 0.0
		else "%s s" % HangarFormat.numk(ivac))
	var prop: String = p.get("propellant", "")
	%CapFuel.visible = prop != ""
	%ValFuel.visible = prop != ""
	%FuelName.text = PartAdvisor.prop_name(prop)
	%FuelDrop.modulate = _prop_color(prop)
	var load_kg := PartDB.prop_mass(p)
	_detail_row("Carries", load_kg > 0.0, HangarFormat.mass(load_kg))
	_detail_row("Mass", true, HangarFormat.mass(PartDB.wet_mass(p)))
	var size: String = p.get("size", "")
	_detail_row("Size", PartDB.size_classes.has(size),
		"%s · Ø %s m" % [size, HangarFormat.num(float(PartDB.size_classes.get(size, 0.0)), 2)])
	var rel := float(p.get("reliability", 0.0))
	_detail_row("Rel", rel > 0.0, "%s%%" % HangarFormat.num(rel * 100.0, 1))
	_detail_row("Cost", true, HangarFormat.money(float(p.get("cost_musd", 0.0))))
	_place_detail(anchor)
	_place_detail.call_deferred(anchor)  # again once the wrapped labels know their width


func _detail_row(row: String, on: bool, value: String) -> void:
	var cap := _detail.find_child("Cap" + row, true, false) as Control
	var val := _detail.find_child("Val" + row, true, false) as Label
	cap.visible = on
	val.visible = on
	val.text = value


func _place_detail(anchor: Control) -> void:
	if not _detail.visible:
		return
	_detail.size = Vector2(_detail.custom_minimum_size.x, 0.0)
	_detail.reset_size()
	var vp := _root.size
	var x := _parts_panel.position.x + _parts_panel.size.x + 12.0
	var y := _parts_panel.position.y
	if is_instance_valid(anchor) and anchor.is_inside_tree():
		y = (_root.get_global_transform().affine_inverse() * anchor.global_position).y - 12.0
	y = clampf(y, _parts_panel.position.y, vp.y - _detail.size.y - 16.0)
	_detail.position = Vector2(x, y)


# ------------------------------------------------------------ goal, meters, problems, stages
func _fill_goal() -> void:
	var m := FlightSession.mission
	var actions := embedded and not m.is_empty()
	%GoalActions.visible = actions
	%GoalHint.visible = actions
	if m.is_empty():
		_subtitle.text = tr("HG_FREE")
		_goal_caption.text = tr("HG_FREE")
		_goal_title.text = tr("HG_FREE_GOAL")
		_goal_line.text = tr("HG_NEED_DV") % HangarFormat.numk(PartAdvisor.LEO_DV)
		return
	var title := String(m.get("title", ""))
	_subtitle.text = title if title != "" else tr("HG_MISSION")
	_goal_caption.text = tr("HG_MISSION")
	_goal_title.text = title
	var bits := PackedStringArray()
	if String(m.get("target", "")) != "":
		bits.append(tr("HG_TARGET") % String(m["target"]))
	if float(m.get("payload_kg", 0.0)) > 0.0:
		bits.append(tr("HG_PAYLOAD") % HangarFormat.mass(float(m["payload_kg"])))
	if bool(m.get("crewed", false)):
		bits.append(tr("UI_CREW"))
	_goal_line.text = " · ".join(bits)


## The part the player just picked up (the advice follows it: a tank asks for its engines).
func set_focus(id: String) -> void:
	if _last_extra.get("focus", "") == id:
		return
	var extra := _last_extra.duplicate()
	extra["focus"] = id
	# deferred: the click that picked the part may come from a card this refresh rebuilds
	show_analysis.call_deferred(_last_analysis, extra)


## extra: {"parts": int, "cost": float, "stable": int (-1 unknown, 0 no, 1 yes, 2 gimbal),
## "specs": stage specs (Vessel.compute_stages), "fairing_kg": float, "focus": part id}
func show_analysis(a: Dictionary, extra: Dictionary) -> void:
	_last_analysis = a
	_last_extra = extra
	_specs = extra.get("specs", [])
	_focus = extra.get("focus", "")
	var goal := current_goal()
	var n_parts := int(extra.get("parts", 0))
	var stable := int(extra.get("stable", -1))
	var fairing := float(extra.get("fairing_kg", 0.0))
	# with a payload the goal figures fly it on top
	var ga := a
	if not _specs.is_empty() and float(goal.get("payload_kg", 0.0)) > 0.0:
		ga = PartAdvisor.evaluate(_specs, goal, fairing)
	var ctx := {"focus": _focus, "stable": stable, "fairing_kg": fairing, "analysis": ga,
		"cost": float(extra.get("cost", 0.0))}
	_recs = PartAdvisor.advise(_specs, goal, ctx)
	_problems = PartAdvisor.problems(_specs, goal, ctx)
	_empty_hint.visible = _hud_on and n_parts == 0
	_fill_meters(ga, goal, extra)
	_fill_verdict(n_parts)
	_fill_problems()
	_fill_stages(a)
	_fill_goal()
	if _category == REC_CATEGORY and _search == "":
		_fill_parts(true)
	else:
		_fill_rec_strip()
		_refresh_cards()
	_update_tabs()


## One meter row: the value (counted up by its CwNumberTicker when `fmt` is given), the note
## under the bar and the bar itself (fill 0..1, goal tick at `marker`, < 0 = none).
func _meter(m: Control, value: float, fmt: Callable, note: String, fill: float, marker: float, tone: Color,
		bar_on := true) -> void:
	var lbl := m.get_node("Col/Top/Value") as Label
	if fmt.is_valid():
		CwNumberTicker.show(lbl, value, fmt)
	else:
		lbl.text = "—"
	lbl.add_theme_color_override("font_color", tone)
	(m.get_node("Col/Note") as Label).text = note
	var bar := m.get_node("Col/Bar") as CwSegmentBar
	bar.visible = bar_on
	bar.value = clampf(fill, 0.0, 1.0)
	bar.marker = marker


func _fill_meters(a: Dictionary, goal: Dictionary, extra: Dictionary) -> void:
	var none := (a.get("stages", []) as Array).is_empty()
	var need := float(goal.get("dv_needed", 0.0))
	var dv := float(a.get("ascent_dv", 0.0))
	var dv_tone := CwPalette.TEXT_DIM if none else (CwPalette.SUCCESS if dv >= need else CwPalette.WARNING)
	var fmt_dv := func(v: float) -> String: return "%s m/s" % HangarFormat.numk(v)
	var fmt_twr := func(v: float) -> String: return HangarFormat.num(v, 2)
	var fmt_cost := func(v: float) -> String: return HangarFormat.money(v)
	var fmt_mass := func(v: float) -> String: return HangarFormat.mass(v)
	_meter(_meter_dv, dv, Callable() if none else fmt_dv,
		tr("HG_GOAL_OF") % ("%s m/s" % HangarFormat.numk(need)) if need > 0.0 else "",
		dv / maxf(need * GOAL_SPAN, 1.0), 1.0 / GOAL_SPAN if need > 0.0 else -1.0, dv_tone)
	var twr := float(a.get("liftoff_twr", 0.0))
	var twr_tone := CwPalette.TEXT_DIM if none else (CwPalette.SUCCESS if twr >= PartAdvisor.TWR_GOOD
		else (CwPalette.WARNING if twr >= PartAdvisor.TWR_MIN else CwPalette.DANGER))
	_meter(_meter_twr, twr, Callable() if none else fmt_twr, tr("HG_TWR_NEED"), twr / TWR_SPAN,
		PartAdvisor.TWR_GOOD / TWR_SPAN, twr_tone)
	var cost := float(extra.get("cost", 0.0))
	var budget := float(goal.get("budget_musd", 0.0))
	var cost_tone := CwPalette.DANGER if budget > 0.0 and cost > budget else CwPalette.INK
	_meter(_meter_cost, cost, fmt_cost,
		tr("HG_BUDGET_OF") % HangarFormat.money(budget) if budget > 0.0 else tr("HG_NO_BUDGET"),
		cost / maxf(budget * GOAL_SPAN, 0.001), 1.0 / GOAL_SPAN, cost_tone, budget > 0.0)
	var n_parts := int(extra.get("parts", 0))
	var payload := float(goal.get("payload_kg", 0.0))
	var notes := PackedStringArray([tr("HG_PARTS_N") % n_parts])
	if payload > 0.0:
		notes.append(tr("HG_PAYLOAD") % HangarFormat.mass(payload))
	_meter(_meter_mass, float(a.get("mass_kg", 0.0)), fmt_mass if n_parts > 0 else Callable(), " · ".join(notes),
		0.0, -1.0, CwPalette.INK if n_parts > 0 else CwPalette.TEXT_DIM, false)


func _fill_verdict(n_parts: int) -> void:
	var before := _verdict.text
	_fill_verdict_text(n_parts)
	if _verdict.text != before and is_inside_tree():
		CwMotion.poke(_verdict)


func _fill_verdict_text(n_parts: int) -> void:
	_btn_launch.disabled = n_parts == 0
	(%BtnUse as Button).disabled = n_parts == 0
	if n_parts == 0:
		_verdict.text = tr("HG_EMPTY")
		_verdict_icon.texture = ICON_STAR
		_verdict_mini.texture = ICON_STAR
		_verdict_pill.tooltip_text = tr("HG_EMPTY_TEXT")
		return
	if _problems.is_empty():
		_verdict.text = tr("HG_READY")
		_verdict_icon.texture = ICON_OK
	else:
		_verdict.text = tr("HG_PROBLEM_1") if _problems.size() == 1 else tr("HG_PROBLEMS") % _problems.size()
		_verdict_icon.texture = ICON_DANGER if int(_problems[0]["tone"]) == PartAdvisor.Tone.DANGER else ICON_WARN
	_verdict_mini.texture = _verdict_icon.texture
	var tips := PackedStringArray([_verdict.text])
	for pr in _problems:
		tips.append("• " + PartAdvisor.problem_text(pr))
	_verdict_mini.tooltip_text = "\n".join(tips)


func _fill_problems() -> void:
	_clear(_problem_list)
	for pr in _problems:
		var row := _tpl_problem.duplicate() as Control
		row.unique_name_in_owner = false
		(row.get_node("Icon") as TextureRect).texture = ICON_DANGER if int(pr["tone"]) == PartAdvisor.Tone.DANGER else ICON_WARN
		(row.get_node("Text") as Label).text = PartAdvisor.problem_text(pr)
		row.visible = true
		_problem_list.add_child(row)


func _fill_stages(a: Dictionary) -> void:
	_clear(_stage_list)
	var stages: Array = a.get("stages", [])
	var parts: Array = a.get("stage_parts", [])
	for i in range(stages.size() - 1, -1, -1):
		var st: Dictionary = stages[i]
		var card := _tpl_stage.duplicate() as Control
		card.unique_name_in_owner = false
		var color := stage_colors[i % stage_colors.size()] if not stage_colors.is_empty() else CwPalette.PEACH
		(card.get_node("Row/Stripe") as ColorRect).color = color
		(card.get_node("Row/Texts/Head/Name") as Label).text = tr("HG_STAGE_N") % int(st["stage"])
		(card.get_node("Row/Texts/Head/First") as Control).visible = i == 0
		(card.get_node("Row/Texts/Head/Dv") as Label).text = "%s m/s" % HangarFormat.numk(st["dv_vac"])
		var twr := float(st["twr_sl"] if i == 0 else st["twr_vac"])
		var bits := PackedStringArray(["%s %s" % [tr("STAT_TWR"), HangarFormat.num(twr, 2)], HangarFormat.mass(st["m0_kg"])])
		if i < parts.size():
			bits.append(tr("HG_PARTS_N") % (parts[i] as Array).size())
		(card.get_node("Row/Texts/Line") as Label).text = " · ".join(bits)
		card.visible = true
		_stage_list.add_child(card)
	_stages_empty.visible = stages.is_empty() and not _tab_crew.button_pressed
