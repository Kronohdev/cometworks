class_name CwDevMenu
extends CanvasLayer
## The developer menu: a floating, draggable, collapsible window over every scene (the
## autoload "CwDev", scenes/dev/dev_menu.tscn) to test the game quickly. F1 (F12 or the key
## under Esc, ' on ABNT2 keyboards, where a scene already uses F1: the hangar, the flight)
## opens and closes it; it never fires while a text field has the keyboard.
##
## Everything you see is authored in the scene with the Cometworks look (dense flavour:
## scenes/dev/dev_theme.tres): tabs, sections, buttons. A button only says what it does through
## its metadata: `action` (and `arg`): pressing it calls `_a_<action>(arg)` here, a toggle
## passes its state, a button in a ButtonGroup its arg; `_s_<action>(arg)` tells a toggle or
## slider what to show. Sections whose HFlowContainer has metadata `fill` ("screens",
## "cutscenes", "actions", ...) get copies of the hidden ButtonTemplate. A page or section with
## metadata `contexts` only shows in those contexts ("tycoon", "menu", "leader", "hangar",
## "flight", "cometlings"). So adding a button is adding it in the editor plus one `_a_` method.
##
## It does not pause the game (the Pausar key does, on request), keeps its place, its tab and
## whether it is collapsed in user://dev.cfg (it always starts closed, so screenshot tools never
## catch it), collects the warnings and errors the engine prints (a Logger) for
## the Log tab, and is only there in debug builds and the editor (or with the project setting
## cometworks/dev/enabled on). Hooks it uses in the game are named dev_*:
## ProjectDesk.dev_force_outcome / dev_finish_phase(), Discovery.reveal_all(), BriefingDesk.spawn(),
## TycoonModes.open_project_hangar() / open_project_flight() (the hangar and the flight in the campus),
## TycoonModes.open_watch_track() / TycoonMain.open_space_map() (the missions in space, SpaceTracking),
## TycoonModes.open_surface() / RoverMissions (rovers: the workshop, a rover on each surface, a test rover mission),
## TycoonClock.dev_turbo, TycoonCrew
## .dev_ignore_limit / dev_refresh_market(), Campus.dev_spawn_walkers() / dev_show_nav().

signal open_changed(open: bool)
## An action ran (tests): its name and the status line it left.
signal ran(action: String, message: String)

const SETTING := "cometworks/dev/enabled"
const CFG_PATH := "user://dev.cfg"
## controls in this group take the mouse away from the launch sequence's "click to skip"
const SHIELD := &"cw_dev_shield"
const SCREENS_DIR := "res://scenes/tycoon/ui/screens/"
const MENU := "res://scenes/menu/main_menu.tscn"
const TYCOON := "res://scenes/tycoon/tycoon_main.tscn"
const LEADER_CREATOR := "res://scenes/tycoon/ui/screens/leader_creator.tscn"
const HANGAR := "res://scenes/hangar.tscn"
const FLIGHT := "res://scenes/flight/flight.tscn"
## scenes that already use F1 (help, LOD view): there only F12 and ' open the menu
const F1_TAKEN := [HANGAR, FLIGHT]
const LOG_KEEP := 80
const LOG_SHOWN := 40
const CUTSCENE_NAMES := {"opening": "Abertura", "opening_short": "Abertura curta", "ending_comet": "Final (cometa)",
	"ending_missed": "Final (perdeu)"}
const CONTEXT_NAMES := {"tycoon": "campus", "menu": "menu principal", "leader": "criador de líder",
	"hangar": "hangar", "flight": "voo"}

var is_open := false
var collapsed := false
## newest last: {"kind": "error" | "warning", "text", "where", "time"}
var log_lines: Array[Dictionary] = []
## "followed" (the Cometling the campus camera follows) or "all"
var creature_target := "followed"

var _logger: DevLogger
var _wired: Array[Node] = []
var _drag := false
var _drag_off := Vector2.ZERO
var _ctx_key := ""
var _tags := {}
var _tick := 0.0
var _log_dirty := false
var _rng := RandomNumberGenerator.new()

@onready var panel: PanelContainer = %Panel
@onready var tabs: TabContainer = %Tabs


## Collects the engine's warnings and errors (any thread) until the menu takes them.
class DevLogger:
	extends Logger
	var _mutex := Mutex.new()
	var _pending: Array[Dictionary] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var where := "%s:%d" % [file.get_file(), line] if file != "" else ""
		_push("warning" if error_type == ERROR_TYPE_WARNING else "error", rationale if rationale != "" else code, where)

	func _log_message(message: String, error: bool) -> void:
		if error:
			_push("error", message.strip_edges(), "")

	func _push(kind: String, text: String, where: String) -> void:
		_mutex.lock()
		_pending.append({"kind": kind, "text": text, "where": where, "time": Time.get_time_string_from_system()})
		if _pending.size() > LOG_KEEP:
			_pending.pop_front()
		_mutex.unlock()

	func take() -> Array[Dictionary]:
		_mutex.lock()
		var out := _pending
		_pending = []
		_mutex.unlock()
		return out


## Tests only: behave as a release export (OS.is_debug_build() false) for menus made after it.
static var simulate_release := false


## Is the menu available in this build? Debug builds and the editor, or the project setting.
## A release export (export_presets.cfg, "Windows Desktop", debug off) has no dev menu: the
## node stays in the tree but hidden, disabled and deaf to F1 / F12 / '.
static func enabled() -> bool:
	return allowed(OS.is_debug_build() and not simulate_release, bool(ProjectSettings.get_setting(SETTING, false))) 		or unlocked()


## The dev code typed in Options › Acesso (only its SHA-256 lives here). Unlocking is kept in
## user://settings.cfg [dev] unlocked, so the menu stays available in that install.
const CODE_SHA256 := "ce3ae473dd94cd832ae7ee2e5e4cd0dd43d83cc04fe42ba46c1d0ba6de5af4f9"
const UNLOCK_CFG := "user://settings.cfg"


static func unlocked() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(UNLOCK_CFG) == OK and bool(cfg.get_value("dev", "unlocked", false))


## Checks a typed code; the right one unlocks the dev menu now and for later runs.
static func try_code(code: String) -> bool:
	if code.strip_edges().to_lower().sha256_text() != CODE_SHA256:
		return false
	var cfg := ConfigFile.new()
	cfg.load(UNLOCK_CFG)
	cfg.set_value("dev", "unlocked", true)
	cfg.save(UNLOCK_CFG)
	var tree := Engine.get_main_loop() as SceneTree
	var dev := tree.root.get_node_or_null("CwDev") if tree else null
	if dev and dev.has_method("_setup") and not dev.get_meta("set_up", false):
		dev.call("_setup")
	return true


static func allowed(debug_build: bool, forced_on: bool) -> bool:
	return debug_build or forced_on


## True when a mouse event lands on the dev menu (the launch sequence lets those through).
static func blocks_mouse(event: InputEvent) -> bool:
	var me := event as InputEventMouse
	var tree := Engine.get_main_loop() as SceneTree
	if me == null or tree == null:
		return false
	for n in tree.get_nodes_in_group(SHIELD):
		var c := n as Control
		if c and c.is_visible_in_tree() and c.get_global_rect().has_point(me.position):
			return true
	return false


# ------------------------------------------------------------ setup
func _ready() -> void:
	if not enabled():
		visible = false
		panel.visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		set_process_input(false)
		return
	_setup()


## Everything the menu needs to run; from _ready, or later when the dev code unlocks it.
func _setup() -> void:
	set_meta("set_up", true)
	visible = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	_rng.randomize()
	_logger = DevLogger.new()
	OS.add_logger(_logger)
	%Collapse.pressed.connect(func() -> void: set_collapsed(not collapsed))
	%Close.pressed.connect(func() -> void: set_open(false))
	%Header.gui_input.connect(_on_header_input)
	tabs.tab_changed.connect(func(_i: int) -> void:
		_save_cfg()
		_refresh_live())
	_fill_lists()
	_fill_targets()
	for n in panel.find_children("*", "", true, false):
		if n.has_meta("action"):
			_wire(n)
	_load_cfg()
	panel.visible = is_open
	%Body.visible = not collapsed
	set_process(is_open)
	if is_open:
		_refresh_context.call_deferred(true)


func _exit_tree() -> void:
	if _logger:
		OS.remove_logger(_logger)
		_logger = null


func _wire(n: Node) -> void:
	var action := String(n.get_meta("action"))
	var arg: Variant = n.get_meta("arg") if n.has_meta("arg") else null
	if n is Range:
		(n as Range).value_changed.connect(func(v: float) -> void:
			_slider_value(n as Range)
			run(action, [arg, v]))
	elif n is BaseButton:
		var b := n as BaseButton
		b.focus_mode = Control.FOCUS_NONE   # Space / Enter stay the game's
		if b.button_group != null or not b.toggle_mode:
			b.pressed.connect(func() -> void: run(action, arg))
		else:
			b.toggled.connect(func(on: bool) -> void: run(action, on))
	_wired.append(n)


# ------------------------------------------------------------ open, close, move
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not is_toggle_key(k) or _typing():
		return
	toggle()
	get_viewport().set_input_as_handled()


## F12, the key under Esc (' on ABNT2, ` on US) and F1 where the scene does not use it.
func is_toggle_key(k: InputEventKey) -> bool:
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return false
	if k.keycode == KEY_F12:
		return true
	if k.keycode == KEY_F1:
		return not f1_taken()
	return k.physical_keycode == KEY_QUOTELEFT and not k.shift_pressed


## Does the scene on show use F1 itself? (The hangar and the flight open inside the campus too.)
func f1_taken() -> bool:
	var cs := get_tree().current_scene
	if _modes_open():
		return true
	return cs != null and (cs.scene_file_path in F1_TAKEN or cs is SurfaceDemo)


func _modes_open() -> bool:
	var m := main()
	return m != null and m.modes != null and m.modes.is_open()


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func toggle() -> void:
	set_open(not is_open)


func set_open(on: bool) -> void:
	is_open = on
	panel.visible = on
	set_process(on)
	if on:
		_clamp_panel()
		_refresh_context(true)
	_save_cfg()
	open_changed.emit(on)


func set_collapsed(on: bool) -> void:
	collapsed = on
	%Body.visible = not on
	%Collapse.text = "+" if on else "–"
	panel.size = Vector2.ZERO   # shrink to the content
	_save_cfg()


func _on_header_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.double_click:
			set_collapsed(not collapsed)
			return
		_drag = mb.pressed
		_drag_off = panel.position - panel.get_global_mouse_position()
		if not mb.pressed:
			_save_cfg()
	elif event is InputEventMouseMotion and _drag:
		panel.position = panel.get_global_mouse_position() + _drag_off
		_clamp_panel()


## Keeps the header on screen.
func _clamp_panel() -> void:
	var vp := panel.get_viewport_rect().size
	var p := panel.position
	p.x = clampf(p.x, 60.0 - panel.size.x, vp.x - 60.0)
	p.y = clampf(p.y, 0.0, vp.y - 32.0)
	panel.position = p


func _load_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	collapsed = bool(cfg.get_value("menu", "collapsed", false))
	%Collapse.text = "+" if collapsed else "–"
	panel.position = cfg.get_value("menu", "position", panel.position)
	creature_target = String(cfg.get_value("menu", "creature_target", creature_target))
	var tab_name := String(cfg.get_value("menu", "tab", ""))
	for i in tabs.get_tab_count():
		if tabs.get_tab_control(i).name == tab_name:
			tabs.current_tab = i


func _save_cfg() -> void:
	if not is_inside_tree():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("menu", "collapsed", collapsed)
	cfg.set_value("menu", "position", panel.position)
	cfg.set_value("menu", "tab", String(tabs.get_current_tab_control().name) if tabs.get_current_tab_control() else "")
	cfg.set_value("menu", "creature_target", creature_target)
	cfg.save(CFG_PATH)


# ------------------------------------------------------------ live refresh
func _process(delta: float) -> void:
	_tick -= delta / maxf(Engine.time_scale, 0.01)
	if _tick > 0.0:
		return
	_tick = 0.25
	_refresh_context(false)
	_refresh_live()


## Re-reads where we are when the scene changed (or `force`): which tabs and sections show.
func _refresh_context(force: bool) -> void:
	var cs := get_tree().current_scene
	var m := main()
	var key := "%d|%d" % [cs.get_instance_id() if cs else 0, m.get_instance_id() if m else 0]
	if key == _ctx_key and not force:
		return
	_ctx_key = key
	_tags = context_tags()
	for i in tabs.get_tab_count():
		tabs.set_tab_hidden(i, not _applies(tabs.get_tab_control(i)))
	if tabs.is_tab_hidden(tabs.current_tab):
		for i in tabs.get_tab_count():
			if not tabs.is_tab_hidden(i):
				tabs.current_tab = i
				break
	for n in panel.find_children("*", "VBoxContainer", true, false):
		if n.has_meta("contexts"):
			(n as Control).visible = _applies(n)
	%Keys.text = "F12 · '" if f1_taken() else "F1 · F12"
	var where := "outra"
	for t: String in CONTEXT_NAMES:
		if _tags.has(t):
			where = CONTEXT_NAMES[t]
			break
	%Context.text = "Cena: %s · %s" % [where, cs.scene_file_path.get_file() if cs and cs.scene_file_path != "" else "—"]
	_sync_toggles()


func _applies(n: Node) -> bool:
	if not n.has_meta("contexts"):
		return true
	for t in n.get_meta("contexts"):
		if _tags.has(String(t)):
			return true
	return false


## Where the menu is: "any" always, plus "tycoon", "menu", "leader", "hangar", "flight" and
## "cometlings" (some Cometling to play with).
func context_tags() -> Dictionary:
	var tags := {"any": true}
	var cs := get_tree().current_scene
	if main():
		tags["tycoon"] = true
	if cs is MainMenu:
		tags["menu"] = true
	if cs is LeaderCreator:
		tags["leader"] = true
	if cs and cs.scene_file_path == HANGAR:
		tags["hangar"] = true
	if cs and (cs.scene_file_path == FLIGHT or cs is FlightWorld):
		tags["flight"] = true
	if _modes_open():
		tags[main().modes.kind] = true
	if not cometlings(true).is_empty():
		tags["cometlings"] = true
	return tags


func _refresh_live() -> void:
	var fps := Engine.get_frames_per_second()
	%Fps.text = "%d fps" % fps
	%PerfText.text = "%.1f ms por quadro · processo %.1f ms · física %.1f ms\n%d draw calls · %d objetos · %d nós\nmemória %.0f MB · Engine.time_scale %s×" % [
		1000.0 / maxf(fps, 1.0), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, _num(Engine.time_scale)]
	_drain_log()
	var m := main()
	if m:
		var p := _project(m.state)
		%ProjectInfo.text = "%s · %s · fase %d/3 · %d%%%s" % [p.code, p.type_id, p.phase + 1, roundi(p.progress() * 100.0),
			" · review: " + p.review_state if p.review_state != "" else ""] if p else "Nenhum projeto em andamento (Lançar teste cria um)."
	var who := targets()
	if creature_target == "followed" and m:
		var f := m.camera.followed()
		%CreatureInfo.text = "seguindo %s" % String(m.campus.cometling_member(f).get("name", "um Cometinho")) if f \
			else "ninguém seguido: clique num Cometinho"
	else:
		%CreatureInfo.text = "%d Cometinhos" % who.size()


# ------------------------------------------------------------ actions
## Runs a dev action by name (the buttons' metadata/action; tests call it directly) and shows
## the line it returns at the bottom. Returns that line.
func run(action: String, arg: Variant = null) -> String:
	var method := "_a_" + action
	var msg := ""
	if has_method(method):
		msg = String(call(method, arg))
	else:
		msg = "ação desconhecida: %s" % action
		push_warning("CwDev: unknown action '%s'" % action)
	_sync_toggles()
	%Status.text = msg
	ran.emit(action, msg)
	return msg


## Puts every toggle and slider in step with the game (`_s_<action>(arg)`).
func _sync_toggles() -> void:
	for n in _wired:
		var action := String(n.get_meta("action"))
		var arg: Variant = n.get_meta("arg") if n.has_meta("arg") else null
		var getter := "_s_" + action
		if not has_method(getter):
			continue
		if n is Range:
			var v: Variant = call(getter, arg)
			if v != null:
				(n as Range).set_value_no_signal(float(v))
			_slider_value(n as Range)
		elif n is BaseButton and (n as BaseButton).toggle_mode:
			(n as BaseButton).set_pressed_no_signal(bool(call(getter, arg)))


func _slider_value(r: Range) -> void:
	var lbl := r.get_parent().get_node_or_null("Value") as Label
	if lbl:
		lbl.text = "%d%%" % roundi(r.value * 100.0) if r.max_value <= 1.0 else _num(r.value)


# --- Geral
func _a_goto(where: Variant) -> String:
	var tree := get_tree()
	tree.paused = false
	match String(where):
		"menu":
			tree.change_scene_to_file(MENU)
		"new":
			tree.change_scene_to_file(LEADER_CREATOR)
		"direct", "fair":
			var scene := (load(TYCOON) as PackedScene).instantiate()
			if where == "fair":
				scene.set("fair_mode", true)
				scene.set("intro_cutscene", Cutscenes.OPENING_SHORT)
			tree.change_scene_to_node(scene)
		"conference":
			if main() != null:
				return _a_conference("go")
			# no campus yet: a direct campaign first, then the fair once it is up
			tree.change_scene_to_node((load(TYCOON) as PackedScene).instantiate())
			_conference_when_ready()
			return "indo para a conferência"
		"hangar":
			tree.change_scene_to_file(HANGAR)
		"flight":
			if not ResourceLoader.exists(FLIGHT):
				return "não há cena de voo"
			tree.change_scene_to_file(FLIGHT)
		_:
			return "destino desconhecido: %s" % where
	return "indo para: %s" % where


## Waits for the campus a "conference" goto just started, then opens the fair.
func _conference_when_ready() -> void:
	for i in 120:
		await get_tree().process_frame
		var m := main()
		if m != null and m.conference != null and m.state != null and m.is_node_ready():
			await get_tree().process_frame
			_a_conference("go")
			return


func _a_reload(_arg: Variant) -> String:
	if get_tree().current_scene == null:
		return "nenhuma cena para recarregar"
	get_tree().paused = false
	get_tree().reload_current_scene()
	return "cena recarregada"


func _a_pause_tree(on: Variant) -> String:
	get_tree().paused = bool(on)
	return "jogo pausado" if on else "jogo rodando"


func _s_pause_tree(_arg: Variant) -> bool:
	return get_tree().paused


func _a_time_scale(v: Variant) -> String:
	Engine.time_scale = float(v)
	return "Engine.time_scale = %s×" % _num(float(v))


func _s_time_scale(v: Variant) -> bool:
	return is_equal_approx(Engine.time_scale, float(v))


func _a_toon(on: Variant) -> String:
	CwLook.set_toon(bool(on))
	return "estilo: %s" % ("cartoon" if on else "clássico")


func _s_toon(_arg: Variant) -> bool:
	return CwLook.toon()


func _a_outlines(on: Variant) -> String:
	CwLook.set_outlines(bool(on))
	return "contornos %s" % ("ligados" if on else "desligados")


func _s_outlines(_arg: Variant) -> bool:
	return CwLook.outlines()


func _a_reduce_motion(on: Variant) -> String:
	MenuSettings.set_reduce_motion(bool(on))
	CwMotion.set_reduced(bool(on))
	return "movimento reduzido" if on else "movimento completo"


func _s_reduce_motion(_arg: Variant) -> bool:
	return CwMotion.reduced()


## Graphics quality 0 Baixo / 1 Médio / 2 Alto (GraphicsQuality, applied live and saved).
func _a_quality(l: Variant) -> String:
	GraphicsQuality.set_level(int(l))
	return "gráficos: %s" % ["baixo", "médio", "alto"][GraphicsQuality.current()]


func _s_quality(l: Variant) -> bool:
	return GraphicsQuality.current() == int(l)


func _a_mute(on: Variant) -> String:
	AudioServer.set_bus_mute(0, bool(on))
	return "som mudo" if on else "som ligado"


func _s_mute(_arg: Variant) -> bool:
	return AudioServer.is_bus_mute(0)


## Sliders: [settings key, value] ("volume", "music_volume", "sfx_volume": MenuSettings).
func _a_volume(kv: Variant) -> String:
	var v := float(kv[1])
	match String(kv[0]):
		"music_volume":
			MenuSettings.set_music_volume(v)
		"sfx_volume":
			MenuSettings.set_sfx_volume(v)
		_:
			MenuSettings.set_volume(v)
	return "%s %d%%" % [kv[0], roundi(v * 100.0)]


func _s_volume(key: Variant) -> float:
	match String(key):
		"music_volume":
			return MenuSettings.music_volume()
		"sfx_volume":
			return MenuSettings.sfx_volume()
	return MenuSettings.volume()


func _a_screenshot(_arg: Variant) -> String:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var path := "user://screenshots/dev_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	_take_screenshot(path)
	return "screenshot: %s" % ProjectSettings.globalize_path(path)


func _take_screenshot(path: String) -> void:
	var was := panel.visible
	panel.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	panel.visible = was
	if img == null or img.is_empty():
		%Status.text = "sem imagem para salvar (headless?)"
		return
	img.save_png(path)


func _a_open_user_dir(_arg: Variant) -> String:
	OS.shell_open(ProjectSettings.globalize_path("user://"))
	return ProjectSettings.globalize_path("user://")


# --- Campanha
## The tycoon on show (the current scene, or a TycoonMain a test put under the root).
func main() -> TycoonMain:
	# a campus on its way out (freed, or its camera already gone) no longer counts
	var cs := get_tree().current_scene
	if cs is TycoonMain and _alive(cs):
		return cs
	for c in get_tree().root.get_children():
		if c is TycoonMain and _alive(c):
			return c
	return null


static func _alive(m: TycoonMain) -> bool:
	return is_instance_valid(m) and not m.is_queued_for_deletion() and is_instance_valid(m.camera)


func _state() -> TycoonState:
	var m := main()
	return m.state if m else null


const NO_CAMPAIGN := "abra uma campanha primeiro"
## the dev menu's test missions in space, in turn: [type, target, outcome]
const SPACE_TESTS := [["demo_sat", "leo", "full"], ["orbiter", "lunar_orbit", "full"], ["comms", "geo", "full"],
	["lander", "lunar_surface", "full"], ["demo_sat", "leo", "fail"], ["comet_mission", "comet", "full"]]
var _space_test := 0


func _a_cash(v: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	s.cash += float(v)
	s.changed.emit()
	return "caixa: %s" % TycoonHUD.fmt_cr(s.cash)


func _a_reputation(v: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	s.reputation = clampf(s.reputation + float(v), 0.0, 100.0)
	s.changed.emit()
	return "reputação: %d" % roundi(s.reputation)


func _a_hype(v: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	s.hype = clampf(s.hype + float(v), 0.0, 100.0)
	s.changed.emit()
	return "hype: %d" % roundi(s.hype)


func _a_skip(unit: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	var n := 1
	match String(unit):
		"month":
			n = 1
			while n < 6 and s._month_of(s.weeks + n) == s._month_of(s.weeks):
				n += 1
		"year":
			n = s.weeks_per_year()
	var done := 0
	for i in n:
		if s.is_over():
			break
		s.advance_week()
		done += 1
	return "+%d semana(s): ano %d, semana %d" % [done, s.year(), s.week()]


func _a_speed(v: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	m.clock.set_speed(int(v))
	return "velocidade %d" % m.clock.speed


func _a_turbo(v: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	m.clock.dev_turbo = float(v)
	return "turbo ×%s: %s s por semana" % [_num(float(v)), _num(m.clock.seconds_per_week())]


func _s_turbo(v: Variant) -> bool:
	var m := main()
	return m != null and is_equal_approx(m.clock.dev_turbo, float(v))


## Era 1..5: the calendar jumps to the same week of the era's first year.
func _a_era(e: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	var era0 := s.era()
	var wpy := s.weeks_per_year()
	s.weeks = clampi((int(e) - 1) * 5 * wpy + s.weeks % wpy, 0, s.campaign_weeks() - 1)
	_after_jump(s, era0)
	return "era %d: ano %d" % [s.era(), s.year()]


## The comet's countdown at `n` weeks; 0 lets it pass now (the finale, its cutscene, the score).
func _a_comet(n: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	if s.race.finished:
		return "o cometa já passou"
	var era0 := s.era()
	s.weeks = maxi(s.campaign_weeks() - maxi(int(n), 1), 0)
	_after_jump(s, era0)
	if int(n) <= 0:
		s.advance_week()
		return "o cometa passou"
	return "cometa em %d semanas" % s.comet_weeks_left()


func _after_jump(s: TycoonState, era0: int) -> void:
	if s.era() != era0:
		s.news.push_front({"key": "TY_NEWS_ERA", "args": [s.era()]})
		s.era_changed.emit(s.era())
	s.changed.emit()


func _a_build_all(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	var n := 0
	for lot_id: String in s.lot_ids():
		var kind := s.lot_kind(lot_id)
		var top: int = (s.building_type(kind).get("levels", []) as Array).size()
		var b := s.building(lot_id).duplicate()
		if top <= 0 or (int(b.get("level", 0)) >= top and int(b.get("weeks_left", 0)) <= 0):
			continue
		b["kind"] = kind
		b["level"] = top
		b["target"] = top
		b["weeks_left"] = 0
		b["total_weeks"] = 0
		s.buildings[lot_id] = b
		s.building_finished.emit(lot_id, top)
		n += 1
	s.changed.emit()
	return "%d lotes no nível máximo" % n


func _a_research_all(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	var n := 0
	for t: Dictionary in TycoonResearch.techs():
		if not TycoonResearch.is_done(s, String(t["id"])):
			TycoonResearch.complete(s, String(t["id"]))
			n += 1
	s.changed.emit()
	return "%d pesquisas concluídas" % n


func _a_hire(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	if TycoonCrew.candidates(s).is_empty():
		TycoonCrew.dev_refresh_market(s)
	var cands := TycoonCrew.candidates(s)
	if cands.is_empty():
		return "nenhum candidato"
	var c: Dictionary = cands[_rng.randi() % cands.size()]
	s.cash = maxf(s.cash, TycoonCrew.hire_fee(s, c) + 1.0)
	TycoonCrew.dev_ignore_limit = true
	var err := TycoonCrew.hire(s, String(c["id"]))
	TycoonCrew.dev_ignore_limit = false
	return "não contratou: %s" % tr(err) if err != "" else "contratado: %s" % String(c.get("name", "?"))


func _a_morale(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	for m in s.staff:
		m["morale"] = 100.0
		m["napping"] = false
	s.changed.emit()
	return "moral 100 para %d Cometinhos" % s.staff.size()


func _a_level_up(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	var n := 0
	for m in s.staff:
		var lv := int(m.get("level", 1))
		if lv >= TycoonCrew.max_level():
			continue
		m["level"] = lv + 1
		m["xp"] = maxf(float(m.get("xp", 0.0)), float(lv) * TycoonCrew.xp_per_level())
		n += 1
	s.changed.emit()
	for c in targets_all():
		c.react("level_up")
	return "%d Cometinhos subiram de nível" % n


func _a_market(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	TycoonCrew.dev_refresh_market(s)
	return "%d candidatos novos" % TycoonCrew.candidates(s).size()


## A legendary hire (TycoonLegends) on the market now, and the hiring market on screen.
func _a_legend_hire(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	var c := TycoonLegends.dev_spawn(s)
	if c.is_empty():
		return "todas as Lendas já estão na equipe"
	var m := main()
	if m:
		m.hud.open_screen("crew", {"tab": "hire"})
	return "Lenda no mercado: %s" % String(c["name"])


## Every Lenda met (their cards readable) and the encyclopedia on "Quem inspirou".
func _a_legend_cards(_arg: Variant) -> String:
	var s := _state()
	var m := main()
	if s == null or m == null:
		return NO_CAMPAIGN
	TycoonLegends.dev_mentors = true
	for l in TycoonLegends.of_kind("hire"):
		var seen: Dictionary = TycoonLegends.st(s)["seen"]
		if not seen.has(String(l["id"])):
			seen[String(l["id"])] = s.weeks
	m.hud.open_screen("book")
	var scr := m.hud.get_node("%Screens").get_child(0) if m.hud.get_node("%Screens").get_child_count() > 0 else null
	if scr and scr.has_method("show_page"):
		scr.call("show_page", "legends")
	return "fichas das Lendas abertas"


## The mentors all arrive and a briefing one of them comments on goes to the top of the board.
func _a_mentor_hint(_arg: Variant) -> String:
	var s := _state()
	var m := main()
	if s == null or m == null:
		return NO_CAMPAIGN
	TycoonLegends.dev_mentors = true
	for b: Dictionary in BriefingDesk.briefings():
		var hints := TycoonLegends.mentor_hints(s, b, false)
		if hints.is_empty() or not BriefingDesk.spawn(s, String(b["id"])):
			continue
		m.hud.open_screen("briefings", {"briefing_id": String(b["id"])})
		return "%s comenta: %s" % [TycoonLegends.name_text(String(hints[0]["legend"])),
			TranslationServer.translate(BriefingDesk.title_key(String(b["id"])))]
	return "nenhum pedido com palpite de mentor"


func _a_contract(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	var ok := _acceptable(s)
	if ok.is_empty():
		TycoonContracts.renew(s)
		ok = _acceptable(s)
	if ok.is_empty():
		return "nenhum contrato aceitável (limite de %d ativos?)" % TycoonContracts.max_active(s)
	var c: Dictionary = ok[_rng.randi() % ok.size()]
	TycoonContracts.accept(s, String(c["id"]))
	return "contrato aceito: %s → %s" % [String(c.get("type", "")), String(c.get("target", ""))]


func _acceptable(s: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in TycoonContracts.offers(s):
		if TycoonContracts.can_accept(s, String(c["id"])):
			out.append(c)
	return out


func _a_milestone(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	var r := s.race
	var i := r.next_of(RaceDirector.PLAYER)
	if i >= r.milestones.size():
		return "todos os marcos já são seus"
	var id := String(r.milestones[i]["id"])
	r.claim(id, RaceDirector.PLAYER)
	return "marco: %s" % tr(String(r.milestones[i].get("name_key", id)))


## Conquistas (Achievements): "next" earns the first one not earned yet (its toast plays),
## "all" earns every one, "reset" forgets them all (the profile and this campaign), "screen"
## opens the badge book.
func _a_achievements(what: Variant) -> String:
	var s := _state()
	match String(what):
		"reset":
			Achievements.reset_profile(s)
			return "conquistas zeradas"
		"all":
			return "%d conquistas destravadas" % Achievements.unlock_all(s)
		"screen":
			var m := main()
			if m == null:
				return NO_CAMPAIGN
			m.hud.open_screen("achievements")
			return "tela: achievements"
	for a: Dictionary in Achievements.all():
		var id := String(a["id"])
		if not Achievements.is_unlocked(id):
			Achievements.unlock(s, id)
			return "conquista: %s" % tr(String(a.get("name_key", id)))
	return "todas as conquistas já são suas"


## The Conferência dos Cometinhos (ConferenceFlow): "invite" opens this year's invitation,
## "go" goes straight to the fair, "lab" too, framing the Mission Design Lab's booth
## (ConferenceFair.frame_design_lab: the leader in front of it, walking held; E still talks).
func _a_conference(what: Variant) -> String:
	var m := main()
	if m == null or m.conference == null:
		return NO_CAMPAIGN
	if String(what) == "lab" and m.conference.is_open() and m.conference.fair:
		m.conference.fair.frame_design_lab()
		return "no Mission Design Lab"
	if m.conference.is_open():
		m.conference.leave()
		return "de volta da feira"
	if String(what) == "go" or String(what) == "lab":
		m.conference.dev_open()
		if String(what) == "lab" and m.conference.fair:
			m.conference.fair.frame_design_lab()
			m.conference.fair.set_walking(true)
			return "no Mission Design Lab (ano %d)" % m.state.year()
		return "na feira (ano %d)" % m.state.year()
	m.hud.open_screen(ConferenceFlow.SCREEN)
	return "convite da conferência"


func _day_cycle() -> CampusDayCycle:
	var m := main()
	return m.get_node_or_null("DayCycle") as CampusDayCycle if m else null


func _a_day(v: Variant) -> String:
	var dc := _day_cycle()
	if dc == null:
		return "sem ciclo de dia aqui"
	dc.force_phase = float(v) if float(v) >= 0.0 else -0.01
	return "ciclo do dia segue o relógio" if float(v) < 0.0 else "hora do dia: fase %.2f" % float(v)


func _a_day_phase(kv: Variant) -> String:
	return _a_day(float(kv[1]))


func _s_day_phase(_arg: Variant) -> Variant:
	var dc := _day_cycle()
	return dc.phase if dc else null


func _a_save(slot: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	var err := TycoonSave.save(m.state, String(slot), {"fair_mode": m.clock.fair_mode})
	return "salvo no espaço %s" % slot if err == OK else "erro ao salvar: %s" % error_string(err)


func _a_load(slot: Variant) -> String:
	if not TycoonSave.exists(String(slot)):
		return "espaço %s vazio" % slot
	get_tree().paused = false
	TycoonSave.open_in_game(get_tree(), String(slot))
	return "carregando o espaço %s" % slot


# --- Projetos e lançamento
## The project the buttons act on: the first one still developing, else the first one.
func _project(s: TycoonState) -> MissionProject:
	if s == null or s.mission_projects.is_empty():
		return null
	for p: MissionProject in s.mission_projects:
		if p.review_state == "":
			return p
	return s.mission_projects[0]


func _flow() -> ProjectFlow:
	var m := main()
	if m:
		for c in m.get_children():
			if c is ProjectFlow:
				return c
	return null


func _a_finish_phase(_arg: Variant) -> String:
	var s := _state()
	var p := _project(s)
	if p == null:
		return "nenhum projeto"
	_drop_phases(p)
	if not ProjectDesk.dev_finish_phase(s, p.id):
		return "%s espera o Design Review" % p.code
	return "%s: %s" % [p.code, "pronto para o Design Review" if p.review_state == "waiting" else "fase %d" % (p.phase + 1)]


func _a_finish_dev(_arg: Variant) -> String:
	var s := _state()
	var p := _project(s)
	if p == null:
		return "nenhum projeto"
	_finish_dev(s, p)
	return "%s: desenvolvimento concluído" % p.code


## Runs the project to its Design Review; the phase screens it skipped do not come up.
func _finish_dev(s: TycoonState, p: MissionProject) -> void:
	_drop_phases(p)
	ProjectDesk.dev_finish_development(s, p.id)
	_drop_phases(p)


func _drop_phases(p: MissionProject) -> void:
	var flow := _flow()
	if flow:
		flow.dev_drop_phases(p.id)


func _a_open_review(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	var waiting := ProjectDesk.waiting_review(s)
	if waiting.is_empty():
		var p := _project(s)
		if p == null:
			return "nenhum projeto"
		_finish_dev(s, p)   # the review opens on its own (ProjectFlow)
		return "%s: desenvolvimento concluído, review aberto" % p.code
	var flow := _flow()
	if flow:
		flow.show_screen("design_review", {"project_id": waiting[0].id})
	else:
		main().hud.open_screen("design_review", {"project_id": waiting[0].id})
	return "Design Review de %s" % waiting[0].code


func _a_force(v: Variant) -> String:
	ProjectDesk.dev_force_outcome = String(v if v != null else "")
	return "próximo lançamento: %s" % ({"success": "sucesso", "partial": "parcial", "fail": "falha"}.get(String(v), "sorteio"))


func _s_force(v: Variant) -> bool:
	return ProjectDesk.dev_force_outcome == String(v if v != null else "")


## A sounding rocket to the suborbital hop with free Cometlings, launched at once (the forced
## outcome applies; the launch sequence and the review follow as in the game).
func _a_quick_launch(_arg: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	var s := m.state
	var team: Array[String] = []
	for f in ProjectDesk.free_staff(s):
		if TycoonCrew.is_working(f) and team.size() < 2:
			team.append(String(f["id"]))
	if team.is_empty():
		return "ninguém livre para o teste"
	var need := float(ProjectDesk.estimate(s, "sounding", {}, "suborbital")["total"])
	s.cash = maxf(s.cash, need + 1.0)
	var p := ProjectDesk.start_project(s, "sounding", "suborbital", team)
	if p == null:
		return "não começou: %s" % tr(ProjectDesk.start_error(s, "sounding", "suborbital", team))
	var forced := ProjectDesk.dev_force_outcome
	var entry := ProjectDesk.launch(s, p)
	if m.hud.current_screen() == "project_phase":
		m.hud.close_screen()   # the launch queued behind the phase screen goes now
	return "%s lançado: %s%s" % [p.code, String(entry.get("outcome", "?")), " (forçado)" if forced != "" else ""]


## Replays the launch cinematic for an outcome and the target chosen in the list.
func _a_replay(kind: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	var target := "leo"
	var opt := %LaunchTarget as OptionButton
	if opt.selected >= 0:
		target = String(opt.get_item_metadata(opt.selected))
	var r := replay_result(m.state, String(kind), target)
	m.hud.open_screen("launch", {"result": r})
	return "cinemática: %s → %s" % [kind, target]


## A mission_launched-like result for the launch sequence (no project behind it).
static func replay_result(s: TycoonState, kind: String, target: String) -> Dictionary:
	var type_id := "sounding"
	for t: Dictionary in s.mdata.get("types", []):
		if float((t.get("compat", {}) as Dictionary).get(target, 0.0)) > 0.0:
			type_id = String(t["id"])
			break
	var outcome: String = {"success": "full", "partial": "partial", "fail": "fail"}.get(kind, "full")
	var r := {"project_id": "", "code": "DEV-01", "type": type_id, "target": target,
		"grade": {"full": 8.0, "partial": 4.5, "fail": 2.0}[outcome], "success": outcome != "fail", "outcome": outcome,
		"p_success": 0.8, "pad": "", "cause": "", "cause_key": ""}
	var d := RocketDesigner.default_design(s, type_id, target)
	if not d.is_empty():
		r["rocket"] = {"parts": d.get("parts", {}), "name": "Dev", "family": "", "class": "", "flights": 0}
	return r


## The hangar inside the campus for the project in development (or the one waiting in its
## Design Review); with no project, the free workshop.
func _a_mission_hangar(_arg: Variant) -> String:
	var m := main()
	if m == null or m.modes == null:
		return NO_CAMPAIGN
	if m.modes.is_open():
		return "o hangar / o voo já está aberto"
	var p := _project(m.state)
	if m.hud.current_screen() != "":
		m.hud.close_screen()
	if not m.modes.open_project_hangar(p.id if p else ""):
		return "o hangar não abriu"
	return "hangar de %s" % p.code if p and m.modes.kind == "hangar" and not FlightSession.mission.is_empty() 		else "oficina livre (sem missão)"


## Puts the project on the pad with a rocket built in the hangar (an example vessel when it has
## none: Andorinha up to low orbit, Garça beyond) and opens the piloted flight; its verdict is the
## launch (the review follows). With no project, a sounding rocket project starts first.
func _a_mission_flight(_arg: Variant) -> String:
	var m := main()
	if m == null or m.modes == null:
		return NO_CAMPAIGN
	if m.modes.is_open():
		return "o hangar / o voo já está aberto"
	var s := m.state
	var p := _project(s)
	if p == null:
		var team: Array[String] = []
		for f in ProjectDesk.free_staff(s):
			if TycoonCrew.is_working(f) and team.size() < 2:
				team.append(String(f["id"]))
		if team.is_empty():
			return "ninguém livre para o teste"
		s.cash = maxf(s.cash, float(ProjectDesk.estimate(s, "sounding", {}, "suborbital")["total"]) + 1.0)
		p = ProjectDesk.start_project(s, "sounding", "suborbital", team)
		if p == null:
			return "não começou: %s" % tr(ProjectDesk.start_error(s, "sounding", "suborbital", team))
	if not HangarRocket.is_hangar(p.rocket.get("parts", {})):
		var mission := HangarRocket.mission_for(s, p.type_id, p.target_id, 0.0, p.code)
		var example := "andorinha" if float(mission["dv_needed"]) <= 9800.0 else "garca"
		var d := HangarRocket.from_scene(load("res://scenes/examples/%s.tscn" % example), mission, ExampleVessels.display_name(example))
		var parts := HangarRocket.adopt(s, d)
		var fam := RocketFamilies.ensure(s, parts, String(d["name"]))
		p.rocket = {"family": String(fam["id"]), "parts": RocketDesigner.normalize(fam["parts"])}
	p.review_state = "pad"
	ProjectDesk.sync_strips(s)
	_drop_phases(p)
	if m.hud.current_screen() != "":
		m.hud.close_screen()
	var pid := p.id
	var ok := m.modes.open_project_flight(pid, func(verdict: Dictionary) -> void:
		var pp := ProjectDesk.find(s, pid)
		if pp:
			ProjectDesk.launch(s, pp, verdict))
	return "%s na plataforma: voo pilotado" % p.code if ok else "o voo não abriu"


## A test mission in space (a track with no project behind it) and its launch watch; each press
## flies somewhere else: low orbit, the Moon, GEO, a landing, a failure, the comet.
func _a_space_test(_arg: Variant) -> String:
	var m := main()
	if m == null or m.modes == null:
		return NO_CAMPAIGN
	if m.modes.is_open():
		return "o hangar / o voo já está aberto"
	var s := m.state
	var pick: Array = SPACE_TESTS[_space_test % SPACE_TESTS.size()]
	_space_test += 1
	var id := "p:dev%d" % SpaceTracking.missions(s).size()
	var trk := SpaceTracking.build(SpaceTracking.PLAYER, id, "DEV-%02d" % _space_test, String(pick[0]), String(pick[1]),
		String(pick[2]), SpaceTracking.now(s))
	trk["project_id"] = ""
	SpaceTracking.missions(s).append(trk)
	if m.hud.current_screen() != "":
		m.hud.close_screen()
	if not m.modes.open_watch_track(id):
		return "o lançamento acompanhado não abriu"
	return "%s → %s (%s): lançamento acompanhado" % [trk["code"], pick[1], pick[2]]


func _a_space_map(_arg: Variant) -> String:
	var m := main()
	if m == null or m.modes == null:
		return NO_CAMPAIGN
	if m.modes.is_open():
		return "o hangar / o voo já está aberto"
	m.open_space_map()
	return "mapa do Sistema Solar: %d missões" % SpaceTracking.missions(m.state).size() if m.modes.kind == "map" else "o mapa não abriu"


# ------------------------------------------------------------ rovers (src/rover/)
const ROVER_BUILDER := "res://scenes/tycoon/ui/screens/rover_builder.tscn"


## The rover workshop: a campus screen in a campaign, else the sandbox workshop over the scene.
func _a_rover_builder(_arg: Variant) -> String:
	var m := main()
	if m and m.hud:
		if m.modes and m.modes.is_open():
			return "feche o hangar / o voo / a superfície primeiro"
		m.hud.open_screen("rover_builder")
		return "oficina de rovers (campanha: %d salvos)" % RoverGarage.designs(m.state).size()
	var scr := (load(ROVER_BUILDER) as PackedScene).instantiate()
	var layer := CanvasLayer.new()
	layer.layer = 50
	get_tree().root.add_child(layer)
	layer.add_child(scr)
	scr.tree_exited.connect(layer.queue_free)
	return "oficina de rovers (caixa de areia)"


## A sandbox rover on a surface: inside the campus (the surface mode) or as its own scene.
func _a_rover_surface(body: Variant) -> String:
	var b := StringName(String(body if body != null else "moon"))
	var s := SurfaceSession.start(b, RoverMissions.sandbox_design(b), RoverMissions.sandbox_objectives(b), {"sandbox": true, "return": "dev"})
	var m := main()
	if m and m.modes:
		if m.modes.is_open() and m.modes.kind != "map":
			return "feche o hangar / o voo primeiro"
		if m.hud.current_screen() != "":
			m.hud.close_screen()
		m.modes.open_surface(s)
		return "rover em %s (no campus)" % b
	get_tree().paused = false
	get_tree().change_scene_to_file(SurfaceSession.DRIVE_SCENE)
	return "rover em %s" % b


## A rover mission already on the Moon: the research it needs, a workshop rover, a forced success
## and the cruise skipped, then the map on it.
func _a_rover_test_mission(_arg: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	var s := m.state
	for t in ["rover_mobility", "guided_descent", "multispectral_imaging", "lunar_stage", "orbital_rocketry", "upper_stage",
			"radio_tracking", "small_sat_bus", "sun_sync_orbits"]:
		if not TycoonResearch.is_done(s, t):
			TycoonResearch.complete(s, t)
	var team: Array[String] = []
	for f in ProjectDesk.free_staff(s):
		if TycoonCrew.is_working(f) and team.size() < 4:
			team.append(String(f["id"]))
	if team.is_empty():
		return "ninguém livre para a missão"
	var d := RoverDesign.make("Tatu Dev", "wheels6", ["solar_wing", "battery", "camera", "spectrometer", "omni"])
	var payload := RoverDesign.payload_ids(d)
	s.cash = maxf(s.cash, float(ProjectDesk.estimate(s, "rover", {}, "lunar_surface")["total"]) + 2.0e6)
	var p := ProjectDesk.start_project(s, "rover", "lunar_surface", team, "", {}, {"payload": payload})
	if p == null:
		return "não começou: %s" % tr(ProjectDesk.start_error(s, "rover", "lunar_surface", team, {}, {"payload": payload}))
	ProjectDesk.dev_force_outcome = "success"
	ProjectDesk.launch(s, p, {"auto": true})
	if m.hud.current_screen() != "":
		m.hud.close_screen()
	var am := MissionOps.find(s, p.id)
	if am.is_empty():
		return "%s não chegou à operação" % p.code
	MissionOps.init_mission(s, am)
	am["weeks_total"] = int(am["weeks_total"]) - int(am["cruise_weeks"])
	am["cruise_weeks"] = 0
	am["status"] = "ops"
	RoverMissions.announce_arrivals(s)
	s.changed.emit()
	return "%s pousou na Lua: Controlar o rover no mapa" % p.code


func _rover_mission(s: TycoonState) -> Dictionary:
	for am in s.active_missions:
		if RoverMissions.can_drive(s, am):
			return am
	return {}


func _a_rover_drive_mission(_arg: Variant) -> String:
	var m := main()
	if m == null or m.modes == null:
		return NO_CAMPAIGN
	var am := _rover_mission(m.state)
	if am.is_empty():
		return "nenhum rover pousado (use Missão rover de teste)"
	if m.modes.is_open() and m.modes.kind != "map":
		return "feche o hangar / o voo primeiro"
	if m.hud.current_screen() != "":
		m.hud.close_screen()
	var mid := String(am["id"])
	var st := m.state
	m.modes.open_surface(RoverMissions.start_drive(st, mid), func(r: Dictionary) -> void:
		RoverMissions.apply_result(st, mid, r))
	return "controlando o rover de %s" % String(am.get("code", ""))


func _a_rover_end_mission(_arg: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	var s := m.state
	var am := _rover_mission(s)
	if am.is_empty():
		return "nenhuma missão rover em operação"
	am["weeks_total"] = int(am.get("age", 0)) + 1
	am["event"] = ""
	am["decision"] = {}
	s.advance_week()
	if m.hud.current_screen() != "":
		m.hud.close_screen()
	m.hud.open_screen("book")
	var scr := m.hud.get_node("%Screens").get_child(m.hud.get_node("%Screens").get_child_count() - 1)
	if scr.has_method("open_detail"):
		scr.call("open_detail")
	var a: Dictionary = s.mission_archive[-1] if not s.mission_archive.is_empty() else {}
	return RoverMissions.summary_text(a.get("surface", {})) if a.has("surface") else "a missão terminou"


func _a_watch_last(_arg: Variant) -> String:
	var m := main()
	if m == null or m.modes == null:
		return NO_CAMPAIGN
	if m.modes.is_open():
		return "o hangar / o voo já está aberto"
	if m.state.project_history.is_empty():
		return "nenhum projeto lançado ainda (use Lançar teste agora)"
	var h: Dictionary = m.state.project_history[-1]
	if m.hud.current_screen() != "":
		m.hud.close_screen()
	return "acompanhando %s" % h.get("code", "?") if m.modes.open_watch(String(h.get("id", ""))) else "não abriu"


## The comic recap (Vovô Edmundo) of the last launched project: the HUD screen "flight_comic"
## (its saved log, else the launch flown again at once).
func _a_flight_comic(_arg: Variant) -> String:
	var m := main()
	if m == null or m.hud == null:
		return NO_CAMPAIGN
	if m.modes and m.modes.is_open():
		return "o hangar / o voo já está aberto"
	if m.state.project_history.is_empty():
		return "nenhum projeto lançado ainda (use Lançar teste agora)"
	var h: Dictionary = m.state.project_history[-1]
	return "quadrinhos do %s" % h.get("code", "?") if m.hud.open_screen("flight_comic", {"project_id": String(h.get("id", ""))}) \
		else "não abriu"


func _a_rocket_parts(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	var n := 0
	for slot_id in RocketDesigner.slot_ids():
		for c in RocketDesigner.components(slot_id):
			if not bool(s.unlocked.get("rocket:" + String(c["id"]), false)):
				s.unlocked["rocket:" + String(c["id"])] = true
				n += 1
	s.changed.emit()
	return "%d peças de foguete liberadas" % n


# --- Cenas
func _a_cutscene(id: Variant) -> String:
	var m := main()
	var host: Node = m if m else get_tree().current_scene
	if host == null:
		return "nenhuma cena para hospedar"
	var c := Cutscenes.play(host, String(id), m.state if m else null, true)
	return "tocando: %s" % CUTSCENE_NAMES.get(String(id), id) if c else "não tocou (outra cena já toca?)"


func _a_cutscene_skip(_arg: Variant) -> String:
	if not Cutscenes.is_playing():
		return "nenhuma cena tocando"
	Cutscenes.current.skip_all()
	return "cena pulada"


func _a_cutscene_reset(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	s.story.clear()
	return "as cenas da campanha voltam a tocar"


func _a_cutscenes_enabled(on: Variant) -> String:
	Cutscenes.set_enabled(bool(on))
	return "cenas %s" % ("ligadas" if on else "desligadas")


func _s_cutscenes_enabled(_arg: Variant) -> bool:
	return Cutscenes.enabled()


func _a_launch_cinematic(on: Variant) -> String:
	LaunchSequence.set_enabled(bool(on))
	return "cinemática de lançamento %s" % ("ligada" if on else "desligada")


func _s_launch_cinematic(_arg: Variant) -> bool:
	return LaunchSequence.enabled()


# --- Telas
func _a_screen(screen_name: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	var ok := m.hud.open_screen(String(screen_name), screen_args(String(screen_name)))
	return "tela: %s" % screen_name if ok else "tela não existe: %s" % screen_name


## What a screen needs to open on its own (a project, a page, a launch result).
func screen_args(screen_name: String) -> Dictionary:
	var s := _state()
	match screen_name:
		"launch":
			return {"result": replay_result(s, "success", "leo")}
		"project_phase":
			var p := _project(s)
			return {"project_id": p.id if p else ""}
		"design_review":
			var w := ProjectDesk.waiting_review(s)
			return {"project_id": w[0].id if not w.is_empty() else ""}
		"project_review":
			return {"project_id": String(s.project_history[-1].get("id", "")) if not s.project_history.is_empty() else ""}
		"newspaper":
			return {"page": _paper_page(s)}
		"payload_planner", "project_team":
			var ty := ""
			for t: Dictionary in s.mdata.get("types", []):
				if s.mission_type_available(String(t["id"])):
					ty = String(t["id"])
			return {"type": ty, "target": ProjectDesk.default_target(s, ty)}
	return {}


# ------------------------------------------------------------ missions and discoveries
## The journal knows everything (Discovery.reveal_all).
func _a_reveal_discoveries(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	Discovery.reveal_all(s)
	return "caderno: tudo revelado (%d descobertas)" % Discovery.count(s)


# ------------------------------------------------------------ mission studies (FocusStudy)
## The type a study action works on: the project in development, the study under way, or the
## first type the lab can study.
func _study_type(s: TycoonState) -> String:
	var p := _project(s)
	if p and FocusStudy.tier(s, p.type_id) < FocusStudy.MAX_TIER:
		return p.type_id
	if FocusStudy.active(s) != "":
		return FocusStudy.active(s)
	for t: Dictionary in s.mdata.get("types", []):
		if FocusStudy.can_study(s, String(t["id"])):
			return String(t["id"])
	return ""


## Every mission type fully studied (all three levels), even the ones not unlocked yet.
func _a_study_reveal(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	return "estudos: %d níveis revelados" % FocusStudy.reveal_all(s, true)


## One more level of the project's type (or the study under way).
func _a_study_tier(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	var ty := _study_type(s)
	if ty == "":
		return "nada para estudar"
	FocusStudy.complete_tier(s, ty)
	return "estudo: %s no nível %d" % [ty, FocusStudy.tier(s, ty)]


## The study under way reaches its level now.
func _a_study_finish(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	var ty := FocusStudy.active(s)
	if ty == "":
		return "nenhum estudo em andamento"
	FocusStudy.complete_tier(s, ty)
	return "estudo concluído: %s no nível %d" % [ty, FocusStudy.tier(s, ty)]


## Forgets every study (the flights and the journal stay).
func _a_study_reset(_arg: Variant) -> String:
	var s := _state()
	if s == null:
		return NO_CAMPAIGN
	Discovery.d(s)["study"] = {}
	TycoonResearch.rs(s)["study"] = {"active": "", "progress": {}}
	s.changed.emit()
	return "estudos esquecidos"


## The lab's mission studies page.
func _a_study_screen(_arg: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	m.hud.open_screen("research", {"study": _study_type(m.state)})
	return "tela: estudos de missão"


## Puts a briefing on the board (any era, even solved) and opens the board on it.
func _a_briefing(id: Variant) -> String:
	var s := _state()
	var m := main()
	if s == null or m == null:
		return NO_CAMPAIGN
	if not BriefingDesk.spawn(s, String(id)):
		return "pedido não existe: %s" % id
	m.hud.open_screen("briefings", {"briefing_id": String(id)})
	return "pedido no quadro: %s" % TranslationServer.translate(BriefingDesk.title_key(String(id)))


func _paper_page(s: TycoonState) -> Dictionary:
	if not s.race.pages.is_empty():
		return s.race.pages[0]
	return {"kind": "first", "milestone": String(s.race.milestones[0]["id"]), "by": RaceDirector.PLAYER,
		"week": s.weeks, "issue": 1}


func _a_newspaper(_arg: Variant) -> String:
	return _a_screen("newspaper")


func _a_finale(_arg: Variant) -> String:
	return _a_screen("finale")


func _a_final_score(_arg: Variant) -> String:
	return _a_screen("final_score")


func _a_close_screen(_arg: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	var was := m.hud.current_screen()
	m.hud.close_screen()
	return "fechou: %s" % was if was != "" else "nenhuma tela aberta"


# --- Cometinhos
## The Cometlings the buttons act on: the followed one or all of them (campus); elsewhere
## every Cometling in the scene.
func targets() -> Array[Cometling]:
	var m := main()
	if m and creature_target == "followed":
		var out: Array[Cometling] = []
		var c := _creature_of(m.camera.followed())
		if c:
			out.append(c)
		return out
	return targets_all()


func targets_all() -> Array[Cometling]:
	return cometlings(false)


## Every Cometling of the scene (the campus crowd in the tycoon); `first_only` stops at one.
func cometlings(first_only: bool) -> Array[Cometling]:
	var out: Array[Cometling] = []
	var m := main()
	if m:
		for w in m.campus.cometlings():
			var c := _creature_of(w)
			if c:
				out.append(c)
				if first_only:
					break
		return out
	var cs := get_tree().current_scene
	if cs:
		_collect(cs, out, first_only)
	return out


func _collect(n: Node, out: Array[Cometling], first_only: bool) -> void:
	for c in n.get_children():
		if first_only and not out.is_empty():
			return
		if c is Cometling:
			out.append(c)
		_collect(c, out, first_only)


static func _creature_of(n: Node) -> Cometling:
	if n is Cometling:
		return n
	if n and "creature" in n:
		return n.get("creature") as Cometling
	return null


func _for_targets(what: String, f: Callable) -> String:
	var who := targets()
	if who.is_empty():
		return "ninguém: clique num Cometinho ou escolha Todos"
	for c in who:
		f.call(c)
	return "%s × %d" % [what, who.size()]


func _a_creature_target(v: Variant) -> String:
	creature_target = String(v)
	_save_cfg()
	return "agindo em: %s" % ("o seguido" if creature_target == "followed" else "todos")


func _s_creature_target(v: Variant) -> bool:
	return creature_target == String(v)


func _a_creature_action(a: Variant) -> String:
	return _for_targets(String(a), func(c: Cometling) -> void: c.play(String(a)))


func _a_creature_emote(e: Variant) -> String:
	return _for_targets(String(e), func(c: Cometling) -> void: c.show_emote(String(e), 2.5))


func _a_creature_expression(x: Variant) -> String:
	return _for_targets(String(x), func(c: Cometling) -> void: c.set_expression(String(x), 4.0))


func _a_creature_react(ev: Variant) -> String:
	return _for_targets(String(ev), func(c: Cometling) -> void: c.react(String(ev)))


func _a_spawn(_arg: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	var n := m.campus.dev_spawn_walkers(int((%SpawnCount as SpinBox).value)).size()
	return "+%d Cometinhos andando" % n


func _a_spawn_clear(_arg: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	return "%d extras removidos" % m.campus.dev_clear_walkers()


func _a_nav_debug(on: Variant) -> String:
	var m := main()
	if m == null:
		return NO_CAMPAIGN
	m.campus.dev_show_nav(bool(on))
	return "grade de caminhada %s" % ("visível" if on else "escondida")


func _s_nav_debug(_arg: Variant) -> bool:
	var m := main()
	return m != null and m.campus.dev_nav_shown()


# --- Log
func _a_collisions(on: Variant) -> String:
	get_tree().debug_collisions_hint = bool(on)
	return "formas de colisão %s (recarregue a cena)" % ("visíveis" if on else "escondidas")


func _s_collisions(_arg: Variant) -> bool:
	return get_tree().debug_collisions_hint


func _a_draw(v: Variant) -> String:
	if int(v) == Viewport.DEBUG_DRAW_WIREFRAME:
		RenderingServer.set_debug_generate_wireframes(true)
	get_viewport().debug_draw = int(v) as Viewport.DebugDraw
	return "debug draw %d%s" % [int(v), " (malhas já carregadas: recarregue a cena)" if int(v) == 4 else ""]


func _s_draw(v: Variant) -> bool:
	return int(get_viewport().debug_draw) == int(v)


func _a_log_clear(_arg: Variant) -> String:
	log_lines.clear()
	_log_dirty = true
	_drain_log()
	return "log limpo"


func _a_log_copy(_arg: Variant) -> String:
	var lines: PackedStringArray = []
	for l in log_lines:
		lines.append(_log_text(l))
	DisplayServer.clipboard_set("\n".join(lines))
	return "%d linhas copiadas" % lines.size()


## Takes the logger's new lines and redraws the list (newest first).
func _drain_log() -> void:
	if _logger:
		var fresh := _logger.take()
		if not fresh.is_empty():
			log_lines.append_array(fresh)
			while log_lines.size() > LOG_KEEP:
				log_lines.pop_front()
			_log_dirty = true
	if not _log_dirty:
		return
	_log_dirty = false
	var n := mini(log_lines.size(), LOG_SHOWN)
	var rows := _copies(%LogRowTemplate, %LogList, n)
	for i in n:
		var l: Dictionary = log_lines[log_lines.size() - 1 - i]
		var row := rows[i] as Label
		row.text = _log_text(l)
		row.add_theme_color_override("font_color", CwPalette.DANGER if l["kind"] == "error" else CwPalette.WARNING)
	%LogEmpty.visible = n == 0
	var errors := log_lines.filter(func(l: Dictionary) -> bool: return l["kind"] == "error").size()
	var log_tab := tabs.get_node_or_null("Log") as Control
	if log_tab:
		var title := "Log" if log_lines.is_empty() else "Log %d%s" % [log_lines.size(), "!" if errors > 0 else ""]
		tabs.set_tab_title(tabs.get_tab_idx_from_control(log_tab), title)


static func _log_text(l: Dictionary) -> String:
	var where := String(l.get("where", ""))
	return "%s %s %s%s" % [l.get("time", ""), "erro" if l["kind"] == "error" else "aviso",
		where + " · " if where != "" else "", l.get("text", "")]


# ------------------------------------------------------------ lists from data
## Fills every section whose Flow carries metadata `fill` with copies of ButtonTemplate.
func _fill_lists() -> void:
	for flow in panel.find_children("*", "HFlowContainer", true, false):
		if not flow.has_meta("fill"):
			continue
		var items: Array = call("_items_" + String(flow.get_meta("fill")))
		var keys := _copies(%ButtonTemplate, flow, items.size())
		for i in items.size():
			var b := keys[i] as Button
			b.text = String(items[i][0])
			b.set_meta("action", items[i][1])
			b.set_meta("arg", items[i][2])


func _items_cutscenes() -> Array:
	var out := []
	for id in Cutscenes.ALL:
		out.append([CUTSCENE_NAMES.get(id, id), "cutscene", id])
	return out


func _items_screens() -> Array:
	var names: Array[String] = []
	for f in DirAccess.get_files_at(SCREENS_DIR):
		var n := f.trim_suffix(".remap")
		if n.ends_with(".tscn"):
			names.append(n.get_basename())
	names.sort()
	var out := []
	for n in names:
		out.append([n, "screen", n])
	return out


func _items_briefings() -> Array:
	var out := []
	for b: Dictionary in BriefingDesk.briefings():
		out.append(["%d · %s" % [int(b.get("era", 1)), String(b["id"])], "briefing", String(b["id"])])
	return out


func _items_actions() -> Array:
	return Cometling.all_actions().map(func(a: String) -> Array: return [a, "creature_action", a])


func _items_emotes() -> Array:
	return Cometling.EMOTES.map(func(a: String) -> Array: return [a, "creature_emote", a])


func _items_expressions() -> Array:
	return Cometling.EXPRESSIONS.map(func(a: String) -> Array: return [a, "creature_expression", a])


func _items_reactions() -> Array:
	return Cometling.REACTIONS.map(func(a: String) -> Array: return [a, "creature_react", a])


## The launch replay's target list (data/tycoon/missions.json targets).
func _fill_targets() -> void:
	var opt := %LaunchTarget as OptionButton
	opt.clear()
	for t: Dictionary in TycoonState.load_json(TycoonState.MISSIONS_PATH).get("targets", []):
		opt.add_item(tr(String(t.get("name_key", t["id"]))))
		opt.set_item_metadata(opt.item_count - 1, String(t["id"]))
	for i in opt.item_count:
		if String(opt.get_item_metadata(i)) == "leo":
			opt.select(i)


## Keeps `count` visible copies of `template` (hidden in the scene) in `parent`.
static func _copies(template: Control, parent: Node, count: int) -> Array[Control]:
	var out: Array[Control] = []
	for c in parent.get_children():
		if c.has_meta("from_template"):
			out.append(c)
	while out.size() < count:
		var c := template.duplicate() as Control
		c.set_meta("from_template", true)
		c.unique_name_in_owner = false
		c.visible = true
		parent.add_child(c)
		out.append(c)
	while out.size() > count:
		out.pop_back().queue_free()
	return out


static func _num(v: float) -> String:
	return ("%.2f" % v).trim_suffix("0").trim_suffix("0").trim_suffix(".").replace(".", ",")
