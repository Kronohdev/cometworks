extends SceneTree
## UI fit: the HUD and every full screen stay inside the visible rect at the window sizes
## players use (the project stretches canvas_items / expand from 1600x900, so the logical
## viewport is 1600x900 or larger: wider on ultrawide, taller on 16:10 and 4:3).
## For each size and language:
##   - every visible Control (clipped by its clipping ancestors, e.g. ScrollContainers) lies
##     inside the viewport, within TOLERANCE px
##   - the HUD's top bar sits at the top, whole, and the HUD blocks do not overlap each other
##   - docked screens (DOCK) keep clear of the top bar and the left rail; the others (covers
##     and modals with their own scrim) may cover the HUD but still have to fit
##   - the race track's milestone labels do not overlap each other nor the planet / Moon art
## The logical size is set with the root's content scale (aspect ignore) so this runs headless.
## Run: godot --headless --path . --script res://tests/test_ui_fit.gd
##        [-- --sizes=1600x900,1024x768 --screens=race,crew@spec --verbose]

const BASE := Vector2(1600, 900)
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(1280, 800), Vector2i(1024, 768), Vector2i(2560, 1080), Vector2i(1100, 650)]
const LOCALES: Array[String] = ["pt_BR", "en"]
const TOLERANCE := 4.0
## screens docked between the top bar and the rail (they must not cover either)
const DOCK: Array[String] = ["crew", "research", "contracts", "finance", "race", "settings"]
## screens that may cover the HUD (full-screen views, modals over a scrim)
const COVER: Array[String] = ["book", "map", "newspaper", "new_project", "rocket_designer", "project_phase",
	"design_review", "project_review", "final_score", "finale", "briefings", "payload_planner", "project_team", "journal",
	"launch_choice", "library", "sign", "emergency_loan", "bankrupt"]
## screens whose detail page is checked too (open_detail(): the first item's page)
const DETAILS: Array[String] = ["contracts", "research", "final_score", "book", "race", "map"]
## [screen, page] of the tabs past the first one
const TABS: Array = [["contracts", "Signed"], ["finance", "Flow"], ["finance", "Budget"], ["settings", "Save"], ["settings", "Image"], ["settings", "Sound"],
	["research", "Studies"]]
## nodes that are backdrops (they may span the whole screen, under the HUD too)
const BACKDROPS: Array[String] = ["Scrim", "Shade", "Backdrop", "Sky", "Comet", "View"]

var _fails := 0
var _checks := 0
var _verbose := false
var main: TycoonMain
var hud: TycoonHUD
var _args := {}
var _only: PackedStringArray = []


func _initialize() -> void:
	var sizes := SIZES.duplicate()
	for a in OS.get_cmdline_user_args():
		if a == "--verbose":
			_verbose = true
		elif a.begins_with("--screens="):
			_only = a.trim_prefix("--screens=").split(",")
		elif a.begins_with("--sizes="):
			sizes.clear()
			for t in a.trim_prefix("--sizes=").split(","):
				var wh := t.split("x")
				sizes.append(Vector2i(int(wh[0]), int(wh[1])))
	CwMotion.set_reduced(true)
	main = (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	get_root().add_child(main)
	await _frames(3)
	hud = main.hud
	main.clock.set_speed(0)
	main.race_flow.autosave = false
	await _prepare_state()
	# logical sizes repeat (1280x720 and 1920x1080 are both 1600x900): test each once
	var done := {}
	for loc in LOCALES:
		TranslationServer.set_locale(loc)
		for phys: Vector2i in sizes:
			var logical := logical_size(phys)
			var key := "%s %dx%d" % [loc, logical.x, logical.y]
			if done.has(key):
				print("%s %dx%d -> %dx%d: same as %s" % [loc, phys.x, phys.y, logical.x, logical.y, done[key]])
				continue
			done[key] = "%dx%d" % [phys.x, phys.y]
			print("%s %dx%d -> logical %dx%d" % [loc, phys.x, phys.y, logical.x, logical.y])
			await _wait(0.5)   # the last screen's exit ends before the window changes
			_set_logical(logical)
			await _frames(4)
			await _check_hud(logical)
			await _check_tutorial(logical)
			for c: Dictionary in cases():
				if _only.is_empty() or String(c["key"]) in _only:
					await _check_screen(c, logical)
	main.queue_free()
	await _frames(2)
	if _only.is_empty() or "menu" in _only:
		await _check_menu(sizes)
	_set_logical(Vector2i(BASE))
	print("%d checks" % _checks)
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


## The main menu (scenes/menu/main_menu.tscn) at every size: inside the view, and the menu
## card, the logo and the footer apart.
func _check_menu(sizes: Array[Vector2i]) -> void:
	var menu := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	get_root().add_child(menu)
	await _frames(3)
	var ui := menu.get_node("UI/Root") as Control
	var done := {}
	for loc in LOCALES:
		TranslationServer.set_locale(loc)
		for phys: Vector2i in sizes:
			var logical := logical_size(phys)
			var key := "%s %dx%d" % [loc, logical.x, logical.y]
			if done.has(key):
				continue
			done[key] = true
			_set_logical(logical)
			await _wait(0.6)
			var tag := "%dx%d menu (%s)" % [logical.x, logical.y, loc]
			_inside(ui, Rect2(Vector2.ZERO, Vector2(logical)), tag, [ui.get_node("Transition"), ui.get_node("Fade")])
			var card := (ui.get_node("MenuPanel") as Control).get_global_rect().grow(-2.0)
			for n in ["Footer", "Logo", "Readout"]:
				var other := ui.get_node(n) as Control
				_check(not other.is_visible_in_tree() or not card.intersects(other.get_global_rect().grow(-2.0)),
					"%s: menu card clear of %s (%s / %s)" % [tag, n, card, other.get_global_rect()])
	menu.queue_free()
	await _frames(2)


## canvas_items + expand: the smaller side keeps the base size, the other grows.
static func logical_size(phys: Vector2i) -> Vector2i:
	var s := minf(phys.x / BASE.x, phys.y / BASE.y)
	return Vector2i(roundi(phys.x / s), roundi(phys.y / s))


func _set_logical(sz: Vector2i) -> void:
	var r := get_root()
	r.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	r.content_scale_size = sz


func _frames(k: int) -> void:
	for i in k:
		await process_frame


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("  FAIL  " + what)
	elif _verbose:
		print("  ok    " + what)


# ------------------------------------------------------------ state
## A campaign in year 13 with rivals spread on the race track, staff, contracts, a project in
## development, one waiting at its design review and one launched (for its review screen).
func _prepare_state() -> void:
	var flow: ProjectFlow = null
	for c in main.get_children():
		if c is ProjectFlow:
			flow = c
			flow.launch_cinematic = false
	var s := main.state
	s.cash = 4.0e6
	TycoonCrew.ensure(s)
	TycoonResearch.complete(s, "orbital_rocketry")
	TycoonResearch.complete(s, "small_sat_bus")
	s.contracts.append({"id": "C-104", "type": "sounding", "target": "suborbital", "sponsor_key": "Instituto do Vento",
		"reward": 60000, "bonus": 15000, "penalty": 20000, "deadline_week": 30, "min_bars": {"sci": 5.0},
		"status": "accepted"})
	# a launched project (history) and one waiting at its design review
	var launched := _run_project(s, "sounding", "suborbital", true)
	_worst_review(s, launched)
	var waiting := _run_project(s, "sounding", "suborbital", false)
	# one in development
	var free := ProjectDesk.free_staff(s)
	var team: Array[String] = []
	for k in mini(2, free.size()):
		team.append(String(free[k]["id"]))
	var dev := ProjectDesk.start_project(s, "demo_sat", "leo", team)
	_args["project_phase"] = {"project_id": dev.id if dev else ""}
	_args["design_review"] = {"project_id": waiting}
	_args["project_review"] = {"project_id": launched}
	_args["rocket_designer"] = {"type": "demo_sat", "target": "leo", "staff": team}
	# the mission flow: a briefing on the board, a lunar payload (the busiest planner), the team
	BriefingDesk.spawn(s, "moonquakes")
	_args["briefings"] = {"briefing_id": "moonquakes"}
	_args["payload_planner"] = {"type": "lander", "target": "lunar_surface", "briefing_id": "moonquakes",
		"payload": ["seismometer", "camera", "omni", "solar_wing", "battery", "battery_l", "heater"]}
	_args["project_team"] = {"type": "demo_sat", "target": "leo", "briefing_id": "moonquakes", "payload": ["camera", "omni", "battery"]}
	_args["journal"] = {"type": "sounding", "target": "suborbital"}
	# years pass: the rivals spread along the track
	for i in 12 * 52 + 30:
		s.advance_week()
		if i % 26 == 0 and flow:
			flow._queue.clear()
	s.mission_launched.emit({"type": "sounding", "target": "suborbital", "success": true, "outcome": "full"})
	s.mission_launched.emit({"type": "demo_sat", "target": "leo", "success": true, "outcome": "full"})
	s.mission_completed.emit({"type": "comms", "target": "geo", "success": true, "outcome": "full", "science": 80.0})
	# missions in space for the map, finished ones for the book
	s.buildings["antenna"] = {"kind": "antenna", "level": 2, "target": 2, "weeks_left": 0}
	for m in [["DEM-04", "demo_sat", "leo"], ["EOB-02", "earth_obs", "sso"], ["COM-01", "comms", "geo"],
			["ORB-01", "orbiter", "lunar_orbit"], ["LND-01", "lander", "lunar_surface"], ["ROV-01", "rover", "lunar_pole"]]:
		s.active_missions.append({"id": m[0], "code": m[0], "type": m[1], "target": m[2], "start_week": s.weeks,
			"weeks_total": 0, "data_stored": 0.0, "data_down": 0.0, "science": 0.0, "status": "cruise",
			"grade": 7.0, "outcome": "full"})
	for i in 3:
		s.advance_week()
	_archive(s)
	# a Cometling at level 3 choosing a specialisation (the tallest crew card)
	s.buildings["training"] = {"kind": "training", "level": 1, "target": 1, "weeks_left": 0}
	if s.staff.size() > 2:
		TycoonCrew.add_xp(s, String(s.staff[2]["id"]), 230.0)
		_args["crew@spec"] = {"staff_id": String(s.staff[2]["id"])}
	var cands := TycoonCrew.candidates(s)
	if not cands.is_empty():
		_args["crew@cand"] = {"cand_id": String(cands[0]["id"])}
	# a Lenda on the market (the golden card and its sheet) and a briefing a mentor comments on
	var lg := TycoonLegends.dev_spawn(s, "mariazinha")
	_args["crew@legend"] = {"cand_id": String(lg.get("id", ""))}
	BriefingDesk.spawn(s, "crop_health")
	_args["briefings@mentor"] = {"briefing_id": "crop_health"}
	var page := {"kind": "first", "milestone": "robotic_landing", "by": "aurora", "week": s.weeks, "issue": 9}
	_args["newspaper"] = {"page": page}
	s.race.pending_pages.clear()
	if flow:
		flow._queue.clear()
	hud.close_screen()
	await _wait(0.4)
	_check(ProjectDesk.history_entry(s, launched).size() > 0, "state: a launched project for its review (%s)" % launched)
	var wp := ProjectDesk.find(s, waiting)
	_check(wp != null and wp.review_state == "waiting", "state: a project waits at its design review (%s)" % waiting)
	_check(dev != null, "state: a project in development")


## The launched project's review at its tallest: a failed launch with its cause, the rocket
## line, the novelty line, the most feedback lines a review keeps (long ones), the briefing's
## result (late and over budget) and new journal entries.
static func _worst_review(s: TycoonState, project_id: String) -> void:
	var e := ProjectDesk.history_entry(s, project_id)
	if e.is_empty():
		return
	e["success"] = false
	e["outcome"] = "fail"
	e["cause"] = "stage2"
	e["cause_key"] = "TY_RK_CAUSE_STAGE2"
	e["novelty"] = true
	e["grade_project"] = 9.6
	e["grade"] = 9.6 * ProjectDesk.outcome_grade("fail")
	var rk: Dictionary = e.get("rocket", {})
	rk["name"] = "Andorinha Pesada Bloco II"
	e["rocket"] = rk
	var lines: Array[Dictionary] = [{"key": "TY_FB_LAUNCH_FAIL", "args": [], "tone": "bad", "topic": "launch"},
		{"key": "TY_FB_TARGET_OFF", "args": [String(s.mission_target("suborbital").get("name_key", ""))], "tone": "bad", "topic": "objective"},
		{"key": "TY_FB_TYPE_OFF", "args": [String(s.mission_type("sounding").get("name_key", ""))], "tone": "bad", "topic": "objective"},
		{"key": "TY_FB_NIGHT_MOON", "args": [], "tone": "bad", "topic": "power"},
		{"key": "TY_FB_MISSING_ANTENNA", "args": ["TY_PL_M_OMNI"], "tone": "bad", "topic": "instrument"},
		{"key": "TY_FB_OPS_OVERLOAD", "args": [], "tone": "bad", "topic": "team"},
		{"key": "TY_FB_DATA_STUCK", "args": [], "tone": "bad", "topic": "data"}]
	e["feedback"] = lines.slice(0, maxi(int(BriefingDesk.disc().get("feedback_max", 5)), 1))
	e["briefing"] = {"id": "moonquakes", "met": "missed", "reward": 0.0, "late": true, "over_budget": true}
	e["learned"] = [{"key": "TY_JN_NOTE_RATIO", "args": []}, {"key": "TY_JN_NOTE_COMBO_GOOD", "args": []},
		{"key": "TY_JN_NOTE_INSTR_USELESS", "args": []}, {"key": "TY_JN_NOTE_ENV_NIGHT", "args": []}]


## A few short missions run to the end on another campaign, so the book's archive has entries.
static func _archive(s: TycoonState) -> void:
	var t := TycoonState.new_campaign(99)
	t.weeks = 2 * 52
	for p in [["SND-01", "sounding", "suborbital", 0], ["DEM-01", "demo_sat", "leo", 0], ["DEM-02", "demo_sat", "leo", 1],
			["EOB-01", "earth_obs", "sso", 1], ["IMP-01", "impactor", "lunar_pole", 2]]:
		t.buildings["antenna"] = {"kind": "antenna", "level": p[3], "target": p[3], "weeks_left": 0}
		t.active_missions.append({"id": p[0], "code": p[0], "type": p[1], "target": p[2], "start_week": t.weeks,
			"weeks_total": 0, "data_stored": 0.0, "data_down": 0.0, "science": 0.0, "status": "cruise",
			"grade": 7.0, "outcome": "full"})
		for i in 6:
			t.advance_week()
	for i in 30:
		t.advance_week()
	s.mission_archive.assign(t.mission_archive)


## Runs a project to its design review; with `launch` confirms it and flies it. Returns its id.
func _run_project(s: TycoonState, type_id: String, target_id: String, launch: bool) -> String:
	var free := ProjectDesk.free_staff(s)
	var team: Array[String] = []
	for k in mini(3, free.size()):
		team.append(String(free[k]["id"]))
	var p := ProjectDesk.start_project(s, type_id, target_id, team)
	if p == null:
		return ""
	var id := p.id
	for k in 40:
		var q := ProjectDesk.find(s, id)
		if q == null:
			break
		if q.review_state == "waiting":
			if not launch:
				break
			ProjectDesk.confirm_review(s, id, [])
		ProjectDesk.set_sliders(s, id, [40, 25, 35])
		s.advance_week()
	return id


# ------------------------------------------------------------ checks
func _check_hud(vp: Vector2i) -> void:
	var tag := "%dx%d hud" % [vp.x, vp.y]
	var view := Rect2(Vector2.ZERO, Vector2(vp))
	var top := hud.get_node("TopStrip") as Control
	var tr := top.get_global_rect()
	_check(tr.position.y >= 0.0 and tr.end.y <= 96.0, "%s: top bar whole at the top (%s)" % [tag, tr])
	_check(top.get_combined_minimum_size().x <= view.size.x - 24.0,
		"%s: top bar content fits the width (%.0f of %.0f)" % [tag, top.get_combined_minimum_size().x, view.size.x])
	# (screens still playing their exit sit under the HUD for a moment: not part of it)
	var skip: Array = [hud.get_node("%Screens")]
	for c in hud.get_children():
		if c.has_meta("screen_name"):
			skip.append(c)
	_inside(hud, view, tag, skip)
	var blocks: Array[Control] = []
	for n in ["TopStrip", "Rail", "Side/Race", "Bottom", "HintBox"]:
		var c := hud.get_node(n) as Control
		if c.is_visible_in_tree():
			blocks.append(c)
	for i in blocks.size():
		for j in range(i + 1, blocks.size()):
			var a := blocks[i].get_global_rect().grow(-2.0)
			var b := blocks[j].get_global_rect().grow(-2.0)
			_check(not a.intersects(b), "%s: %s and %s do not overlap (%s / %s)" % [tag, blocks[i].name, blocks[j].name, a, b])
	# the lot panel next to the race board and above the bottom row
	hud.show_lot("lab")
	await _frames(2)
	var lot := (hud.get_node("%LotPanel") as Control).get_global_rect().grow(-2.0)
	for n in ["Side/Race", "Bottom", "TopStrip", "HintBox"]:
		_check(not lot.intersects((hud.get_node(n) as Control).get_global_rect().grow(-2.0)),
			"%s: lot panel clear of %s (%s / %s)" % [tag, n, lot, (hud.get_node(n) as Control).get_global_rect()])
	_inside(hud.get_node("%LotPanel"), view, tag)
	hud.close_lot()


## The screens to check: every DOCK and COVER screen, and the busier pages of some of them.
func cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n: String in DOCK + COVER:
		out.append({"key": n, "screen": n, "args": _args.get(n, {})})
	out.append({"key": "crew@spec", "screen": "crew", "args": _args.get("crew@spec", {})})
	out.append({"key": "crew@hire", "screen": "crew", "args": {"tab": "hire"}})
	out.append({"key": "book@cards", "screen": "book", "page": "cards"})
	out.append({"key": "crew@cand", "screen": "crew", "args": _args.get("crew@cand", {"tab": "hire"})})
	out.append({"key": "race@agency", "screen": "race", "call": ["open_agency", "aurora"]})
	out.append({"key": "race@you", "screen": "race", "call": ["open_agency", RaceDirector.PLAYER]})
	out.append({"key": "book@card", "screen": "book", "call": ["open_first_card"]})
	# As Lendas: the golden card's sheet, a mentor on the board, the Quem inspirou pages
	out.append({"key": "crew@legend", "screen": "crew", "args": _args.get("crew@legend", {"tab": "hire"})})
	out.append({"key": "briefings@mentor", "screen": "briefings", "args": _args.get("briefings@mentor", {})})
	out.append({"key": "book@legends", "screen": "book", "page": "legends"})
	out.append({"key": "book@legend", "screen": "book", "call": ["open_first_legend"]})
	out.append({"key": "book@legend_rival", "screen": "book", "args": {"legend": "herschelinha"}})
	# the phase screen with what a mission study tells (FocusStudy): arrows, the suggestion and
	# two advice lines at tier 2, the ideal ticks and lever bands at tier 3
	out.append({"key": "project_phase@study2", "screen": "project_phase", "args": _args.get("project_phase", {}), "study": ["demo_sat", 2]})
	out.append({"key": "project_phase@study3", "screen": "project_phase", "args": _args.get("project_phase", {}), "study": ["demo_sat", 3]})
	# the other tabs
	for t: Array in TABS:
		out.append({"key": "%s@%s" % [t[0], String(t[1]).to_lower()], "screen": t[0], "page": t[1]})
	# the detail page of every screen with pages (open_detail(): the first item's page)
	for n: String in DETAILS:
		out.append({"key": n + "@detail", "screen": n, "args": _args.get(n, {}), "detail": true})
	return out


## Opens a case's screen and waits for its transition.
func open_case(c: Dictionary) -> bool:
	if c.has("study"):
		FocusStudy.studied(main.state, String(c["study"][0]))
		(Discovery.d(main.state)["study"] as Dictionary)[String(c["study"][0])] = int(c["study"][1])
	if not hud.open_screen(String(c["screen"]), c.get("args", {})):
		return false
	await _frames(2)
	var layer := hud.get_node("%Screens")
	if c.has("page") and layer.get_child_count() > 0:
		var scr: Node = layer.get_child(0)
		if scr.has_method("show_page"):
			scr.call("show_page", c["page"])
		else:
			# a tab of the screen's page stack
			for st in get_nodes_in_group(&"cw_page_stack"):
				if scr.is_ancestor_of(st):
					(st as CwPageStack).switch_to(StringName(String(c["page"])))
					break
	if c.get("detail", false) and layer.get_child_count() > 0 and layer.get_child(0).has_method("open_detail"):
		layer.get_child(0).call("open_detail")
	# another page opened by a call on the screen: [method, args...]
	if c.has("call") and layer.get_child_count() > 0 and layer.get_child(0).has_method(String(c["call"][0])):
		layer.get_child(0).callv(String(c["call"][0]), (c["call"] as Array).slice(1))
	await _wait(0.45 if c["screen"] != "finale" else 1.2)
	return true


func _check_screen(c: Dictionary, vp: Vector2i) -> void:
	var screen_name := String(c["screen"])
	var tag := "%dx%d %s" % [vp.x, vp.y, c["key"]]
	var ok: bool = await open_case(c)
	_check(ok, "%s opens" % tag)
	if not ok:
		return
	await _frames(2)
	var layer := hud.get_node("%Screens")
	var scr := layer.get_child(0) as Control if layer.get_child_count() > 0 else null
	_check(scr != null and hud.current_screen() == screen_name, "%s stays open" % tag)
	if scr == null or hud.current_screen() != screen_name:
		hud.close_screen()
		return
	var view := Rect2(Vector2.ZERO, Vector2(vp))
	_inside(scr, view, tag)
	if screen_name in DOCK:
		var top := (hud.get_node("TopStrip") as Control).get_global_rect()
		var rail := (hud.get_node("Rail") as Control).get_global_rect()
		var bad: PackedStringArray = []
		for ctl in _visible_controls(scr):
			if _is_backdrop(ctl, scr):
				continue
			var r := _clipped_rect(ctl)
			if r.size.x <= 0.5 or r.size.y <= 0.5:
				continue
			if r.position.y < top.end.y - 2.0:
				bad.append("%s %s" % [scr.get_path_to(ctl), r])
			elif r.intersects(rail.grow(-2.0)):
				bad.append("%s %s (rail)" % [scr.get_path_to(ctl), r])
			if bad.size() > 4:
				break
		_check(bad.is_empty(), "%s: clear of the top bar and the rail %s" % [tag, "" if bad.is_empty() else str(bad)])
	if screen_name == "race":
		_check_race(scr, tag)
	if screen_name == "project_review":
		_check_review(scr, tag, view)
	hud.close_screen()
	if c.has("study"):
		(Discovery.d(main.state)["study"] as Dictionary).erase(String(c["study"][0]))
	await _frames(2)


## Every visible control under `root` (clipped by its clipping ancestors) inside `view`.
func _inside(root: Node, view: Rect2, tag: String, skip: Array = []) -> void:
	var bad: PackedStringArray = []
	var grown := view.grow(TOLERANCE)
	for c in _visible_controls(root, skip):
		var r := _clipped_rect(c)
		if r.size.x <= 0.5 or r.size.y <= 0.5:
			continue
		if not grown.encloses(r):
			bad.append("%s %s" % [root.get_path_to(c), r])
			if bad.size() > 5:
				break
	_check(bad.is_empty(), "%s: inside the %dx%d view %s" % [tag, view.size.x, view.size.y,
		"" if bad.is_empty() else str(bad)])


## Vovô Edmundo's lesson bubble (src/tycoon/tutorial/tycoon_tutorial.gd) stays inside the view
## with its longest lines, at the bottom (no target) and at the top (a target low on screen).
func _check_tutorial(logical: Vector2i) -> void:
	var tut := main.tutorial
	if tut == null or (not _only.is_empty() and not "tutorial" in _only):
		return
	var view := Rect2(Vector2.ZERO, Vector2(logical))
	var longest := ["", 0, 0]
	for l: Dictionary in TutorialBook.lessons():
		var st: Array = l.get("steps", [])
		for i in st.size():
			var n := tr(String(st[i].get("line", ""))).length()
			if n > int(longest[2]):
				longest = [String(l["id"]), i, n]
	for case in [["campus", 0], ["campus", 7], [longest[0], longest[1]]]:
		tut.start(String(case[0]), true)
		while tut.is_showing() and tut.current_step() < int(case[1]):
			if tut._typing:
				tut.next()      # the typewriter first (off with reduced motion)
			tut.next()
		tut._finish_typing()
		await _frames(3)
		var tag := "%dx%d lesson %s step %d" % [logical.x, logical.y, case[0], int(case[1]) + 1]
		_inside(tut.bubble, view, tag)
		var top := (hud.get_node("TopStrip") as Control).get_global_rect()
		_check(not top.intersects(tut.bubble.get_global_rect().grow(-2.0)), "%s: bubble clear of the top bar" % tag)
		tut.skip()
	await _frames(2)


## The review (worst-case entry, _worst_review): it really is the busy one, the panel stays
## whole on screen, and the title, the results and Back are never scrolled away.
func _check_review(scr: Control, tag: String, view: Rect2) -> void:
	_check((scr.get_node("%Debrief") as Control).is_visible_in_tree() and (scr.get_node("%CauseLine") as Control).visible
		and (scr.get_node("%RocketLine") as Control).visible and (scr.get_node("%Novelty") as Control).visible
		and (scr.get_node("%GradeProject") as Control).visible and (scr.get_node("%BriefLine") as Control).visible,
		"%s: the worst-case review shows every optional line" % tag)
	var panel := (scr.get_node("Panel") as Control).get_global_rect()
	_check(view.grow(TOLERANCE).encloses(panel), "%s: review panel whole on screen (%s)" % [tag, panel])
	var scroll := (scr.get_node("%Scroll") as Control).get_global_rect()
	for n in ["%Title", "%Outcome", "%RwCash", "%RwCost", "%Back"]:
		var r := (scr.get_node(n) as Control).get_global_rect()
		_check(view.grow(TOLERANCE).encloses(r) and not r.intersects(scroll.grow(-1.0)),
			"%s: %s on screen outside the scrolling middle (%s)" % [tag, n, r])
	if _verbose:
		print("    review middle %.0f px in a %.0f px scroll" % [(scr.get_node("%Middle") as Control).get_combined_minimum_size().y, scroll.size.y])


## The race track: milestone labels apart from each other and off the planet / Moon art.
func _check_race(scr: Control, tag: String) -> void:
	var track := scr.get_node_or_null("%Track") as CwRaceTrack
	if track == null:
		return
	var rects: Array[Rect2] = []
	var names: PackedStringArray = []
	for st in track.get_node("%StationTemplate").get_parent().get_children():
		if not (st is Control) or not (st as Control).visible or not st.has_meta("from_template"):
			continue
		var info := st.get_node_or_null("Info") as Control
		if info == null or not info.is_visible_in_tree():
			continue
		var name_l := info.get_node_or_null("Name") as Label
		if name_l == null or name_l.text == "" or not name_l.is_visible_in_tree():
			continue
		rects.append(_text_rect(name_l))
		names.append(name_l.text)
	var overlaps: PackedStringArray = []
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].grow(-1.0).intersects(rects[j].grow(-1.0)):
				overlaps.append("%s / %s" % [names[i], names[j]])
	_check(overlaps.is_empty(), "%s: milestone names apart %s" % [tag, "" if overlaps.is_empty() else str(overlaps)])
	var on_art: PackedStringArray = []
	for k in rects.size():
		var local := Rect2(rects[k].position - track.global_position, rects[k].size)
		if track.has_method("art_overlaps") and bool(track.call("art_overlaps", local)):
			on_art.append(names[k])
	_check(on_art.is_empty(), "%s: milestone names off the planet and the Moon %s" % [tag, "" if on_art.is_empty() else str(on_art)])


## The rect the label's text actually covers (centred / wrapped text is narrower than the label).
static func _text_rect(l: Label) -> Rect2:
	var r := l.get_global_rect()
	var font := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var w := 0.0
	var lines := maxi(l.get_line_count(), 1)
	if l.max_lines_visible > 0:
		lines = mini(lines, l.max_lines_visible)
	for i in lines:
		w = maxf(w, font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, fs).x)
	w = minf(w, r.size.x)
	var h := minf(r.size.y, lines * font.get_height(fs) + 2.0)
	var x := r.position.x
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			x += (r.size.x - w) * 0.5
		HORIZONTAL_ALIGNMENT_RIGHT:
			x += r.size.x - w
	return Rect2(x, r.position.y + (r.size.y - h) * 0.5, w, h)


static func _is_backdrop(c: Control, root: Control) -> bool:
	var n: Node = c
	while n != null and n != root:
		if String(n.name) in BACKDROPS and n.get_parent() == root:
			return true
		n = n.get_parent()
	return false


static func _visible_controls(root: Node, skip: Array = []) -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n in skip:
			continue
		if n is SubViewport or n is Window or n is CanvasLayer:
			continue
		if n is CanvasItem and not (n as CanvasItem).visible:
			continue
		# the root and bare layout Controls draw nothing themselves (their children are checked)
		if n is Control and n != root and not (n.get_class() == "Control" and n.get_script() == null):
			var c := n as Control
			if c.modulate.a > 0.01 and c.self_modulate.a > 0.0:
				out.append(c)
		for ch in n.get_children():
			stack.append(ch)
	return out


## The control's global rect cut by every ancestor that clips its children.
static func _clipped_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p != null:
		if p is Control and ((p as Control).clip_contents or p is ScrollContainer):
			r = r.intersection((p as Control).get_global_rect())
			if r.size.x <= 0.0 or r.size.y <= 0.0:
				return Rect2()
		p = p.get_parent()
	return r
