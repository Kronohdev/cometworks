class_name FlightComic
extends Control
## "O voo em quadrinhos": the comic-strip recap of one launch, told by Vovô Edmundo
## Halleyzinho (the Lenda "halleyzinho"), from the flight's own log (FlightLog: recorded while
## the flight was watched, or while "Simular até o fim" flew it at once). The look is all in
## scenes/tycoon/ui/screens/flight_comic.tscn: a comic page on a scrim, its panels copies of
## %PanelTemplate (the picture, FlightComicArt; a sound-effect word; the mission clock; the
## narrator box with Halley's portrait from %Studio and his caption bubble), then the last page
## (%Report): the outcome, the rewards and "Por que foi assim?" (FlightReport: the causes, one
## tip, the CML item it names).
## A page holds at most PER_PAGE panels, the flight's panels spread evenly over its pages (7 read
## 4 + 3, never 6 + 1), and the grid fits the page's count (page_columns): up to three panels in
## one tall row, four in two by two, five or six in two rows of three; no empty slot keeps room.
## Panels come in one by one (a pop, CwMotion); a click (or Space / Enter) brings the next one
## at once, turns the page or ends; "Pular" goes straight to the last page.
## Two ways in:
##   the launch watch   show_flight() over the 3D flight (after a skip, or "Relatório do voo"
##                      on the result card); `closed` tells the watch what the player chose
##   the HUD screen     "flight_comic" (open_with {"project_id"}; without one, the last launch):
##                      the entry's saved log, else what its track keeps (FlightLog.from_track)

signal closed(what: String)

const LEGEND := "halleyzinho"
const PER_PAGE := 6
## the most panels a flight gets (the final one included); the less telling events go first
const MAX_PANELS := 11
const REVEAL_S := 1.5
## how much an event matters (the panel budget keeps the most telling ones)
const PRIORITY := {"liftoff": 10, "crash": 10, "orbit": 9, "burn": 9, "capture": 9, "landing": 9, "rendezvous": 9,
	"high_orbit": 9, "flyby": 9, "splashdown": 9, "landed": 8, "apogee": 8, "rover": 8, "stage_sep": 7,
	"booster_sep": 6, "fairing": 5, "space": 4, "maxq": 3}
## caption variants per kind (TY_FC_CAP_<KIND>_<n>)
const VARIANTS := {"liftoff": 3, "maxq": 2, "booster_sep": 2, "stage_sep": 3, "fairing": 2, "space": 2, "orbit": 2,
	"orbit_partial": 1, "burn": 1, "burn_moon": 2, "burn_geo": 1, "burn_comet": 1, "high_orbit": 1, "capture": 2,
	"capture_partial": 1, "landing": 2, "landing_pole": 1, "flyby": 1, "rover": 1, "rendezvous": 1, "splashdown": 1,
	"landed": 1, "apogee": 1, "crash": 2, "end_exceptional": 1, "end_full": 2, "end_partial": 2, "end_fail": 2}
## a sound-effect word per kind (TY_FC_SFX_<KIND>), none for the quiet ones
const SFX := ["liftoff", "stage_sep", "booster_sep", "fairing", "crash", "landing", "burn", "splashdown", "orbit", "capture"]
const MOOD_COLORS := {"good": CwPalette.AURORA_TEAL, "meh": CwPalette.WARNING, "bad": CwPalette.DANGER}

var state: TycoonState
var hud: TycoonHUD
var entry: Dictionary = {}
var panels: Array = []
var report: Dictionary = {}
## the watch's buttons: "Ver no mapa" shows when the flight has a track to see
var can_see_map := false
var embedded := false
## the HUD screen to go back to on closing (the review that opened it), with this project
var back_screen := ""
var page := 0
var _revealed := 0
var _timer := 0.0
var _on_report := false
var _tweens: Array[Tween] = []


func _ready() -> void:
	%PanelTemplate.visible = false
	%ReasonTemplate.visible = false
	%RewardTemplate.visible = false
	%Next.pressed.connect(advance)
	%Skip.pressed.connect(show_report)
	%Close.pressed.connect(func() -> void: finish("done"))
	%Done.pressed.connect(func() -> void: finish("done"))
	%SeeMap.pressed.connect(func() -> void: finish("map"))
	%Page.gui_input.connect(_on_page_input)
	%Studio.shot.connect(func(_k: String, _t: Texture2D) -> void: _fill_portraits())
	%Report.visible = false
	%Grid.visible = true
	add_child(FlightComicAudio.new())   # page turns, pops, the words' sounds, the end sting


## The HUD screen's way in.
func bind(s: TycoonState, _c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	hud = h
	_open_default.call_deferred()


func open_with(args: Dictionary) -> void:
	var pid := String(args.get("project_id", ""))
	back_screen = String(args.get("back", ""))
	if state and pid != "":
		_open_entry(ProjectDesk.history_entry(state, pid))


func _open_default() -> void:
	if not panels.is_empty() or _on_report or state == null:
		return
	if not state.project_history.is_empty():
		_open_entry(state.project_history[-1])
	else:
		show_flight(state, {}, [], {})


func _open_entry(e: Dictionary) -> void:
	var lg := log_for(state, e)
	show_flight(state, e, lg["events"], lg["outcome"])


## The log of a launched project: the one saved with its entry (watched or skipped), else what
## its track keeps of it (FlightLog.from_track: no flight is flown again here). {"events", "outcome"}.
static func log_for(s: TycoonState, e: Dictionary) -> Dictionary:
	if e.has("flight_log") and not (e["flight_log"] as Dictionary).get("events", []).is_empty():
		return e["flight_log"]
	if s == null or e.is_empty():
		return {"events": [], "outcome": {}}
	SpaceTracking.sync(s)
	var tr := SpaceTracking.for_project(s, String(e.get("id", "")))
	if tr.is_empty():
		return {"events": [], "outcome": {}}
	return FlightLog.from_track(tr, String(e.get("cause_key", "")))


## Keeps a flight's log with its history entry (the comic can be read again later).
static func save_log(e: Dictionary, lg: FlightLog) -> Dictionary:
	var d := {"events": lg.events.duplicate(true), "outcome": lg.outcome()}
	if not e.is_empty():
		e["flight_log"] = d
	return d


## Shows the comic of a flight: its history entry ({} for a track with no project), its events
## (FlightLog.events) and how it ended (FlightLog.outcome()).
func show_flight(s: TycoonState, e: Dictionary, events: Array, flown: Dictionary, opts := {}) -> void:
	state = s
	entry = e
	can_see_map = bool(opts.get("see_map", false))
	embedded = bool(opts.get("embedded", hud == null))
	var target := String(e.get("target", opts.get("target", "leo")))
	var code := String(e.get("code", opts.get("code", "")))
	var outcome := String(e.get("outcome", opts.get("outcome", "full")))
	if bool(flown.get("lost", false)):
		outcome = "fail"
	var tname := tr(String(s.mission_target(target).get("name_key", target))) if s else target
	var rover := false
	if s and not e.is_empty():
		rover = RoverMissions.is_rover_mission(s, {"type": e.get("type", ""), "target": target, "project_id": e.get("id", "")})
	panels = panels_of(events, target, outcome, code, {"target_name": tname, "rover": rover})
	report = FlightReport.build(s, e, flown) if s else {}
	%Title.text = tr("TY_FC_TITLE").format({"code": code}) if code != "" else tr("TY_FC_TITLE_NONE")
	%Byline.text = tr("TY_FC_BYLINE")
	_fill_report(outcome)
	page = 0
	_on_report = false
	if panels.is_empty():
		show_report()
	else:
		_show_page(0)


func page_count() -> int:
	return maxi(ceili(panels.size() / float(PER_PAGE)), 1)


## How many panels a page holds: the flight's panels spread evenly over its pages.
func per_page() -> int:
	return maxi(ceili(panels.size() / float(page_count())), 1)


## The columns of a page of n panels: one row up to three, then two rows (2 x 2, 3 + 2, 3 x 2).
static func page_columns(n: int) -> int:
	if n <= 3:
		return maxi(n, 1)
	return 2 if n == 4 else 3


func _show_page(p: int) -> void:
	page = p
	_on_report = false
	%Grid.visible = true
	%Report.visible = false
	var per := per_page()
	var from := p * per
	var count := clampi(panels.size() - from, 0, per)
	(%Grid as GridContainer).columns = page_columns(count)
	var rows := TycoonHUD._copies(%PanelTemplate, PER_PAGE)
	for i in rows.size():
		# only the page's panels take room: the grid's rows grow to fill the page
		var row := rows[i]
		row.set_meta("used", i < count)
		row.visible = i < count
		row.modulate.a = 0.0
		if i < count:
			_fill_panel(row, panels[from + i], from + i)
	_revealed = 0
	_timer = 0.0
	# the first pop once the grid has laid the page out (its pivot is the panel's new centre)
	_first_reveal.call_deferred(p)
	_fill_portraits()
	_refresh_buttons()


func _first_reveal(p: int) -> void:
	if _revealed == 0 and not _on_report and page == p:
		_reveal_next()


func _fill_panel(row: Control, p: Dictionary, index: int) -> void:
	var art := row.get_node("VBox/Art") as FlightComicArt
	var a: Dictionary = (p["art"] as Dictionary).duplicate()
	a["seed"] = index + 1
	art.set_scene(a)
	(row.get_node("VBox/Art/Sfx") as Label).text = String(p.get("sfx", ""))
	(row.get_node("VBox/Art/Sfx") as Label).visible = String(p.get("sfx", "")) != ""
	(row.get_node("VBox/Art/Clock") as Label).text = String(p.get("time", ""))
	(row.get_node("VBox/Art/Clock") as Label).visible = String(p.get("time", "")) != ""
	(row.get_node("VBox/Art/Number") as Label).text = "%d" % (index + 1)
	(row.get_node("VBox/Narr/Bubble/Caption") as Label).text = String(p["caption"])


func _fill_portraits() -> void:
	var tex: Texture2D = %Studio.portrait(TycoonLegends.look(LEGEND)) as Texture2D
	for row in %Grid.get_children():
		var visor := row.get_node_or_null("VBox/Narr/Visor")
		if visor:
			(visor.get_node("Portrait") as TextureRect).texture = tex
			(visor.get_node("Fallback") as Control).visible = tex == null
	(%ReportVisor.get_node("Portrait") as TextureRect).texture = tex
	(%ReportVisor.get_node("Fallback") as Control).visible = tex == null


func _visible_panels() -> Array[Control]:
	var out: Array[Control] = []
	for c in %Grid.get_children():
		if c != %PanelTemplate and c.visible and bool(c.get_meta("used", false)):
			out.append(c)
	return out


## The next panel of the page pops in.
func _reveal_next() -> void:
	var rows := _visible_panels()
	if _revealed >= rows.size():
		return
	var row := rows[_revealed]
	_revealed += 1
	_timer = REVEAL_S
	if CwMotion.reduced():
		row.modulate.a = 1.0
	else:
		row.pivot_offset = row.size * 0.5
		row.scale = Vector2(0.92, 0.92)
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(row, "modulate:a", 1.0, 0.28)
		tw.tween_property(row, "scale", Vector2.ONE, 0.34)
		_tweens.append(tw)
	_refresh_buttons()


func _reveal_all() -> void:
	while _revealed < _visible_panels().size():
		_reveal_next()


## A click, Space or the Next key: the next panel, else the next page, else the last page, else out.
func advance() -> void:
	if _on_report:
		finish("done")
		return
	if _revealed < _visible_panels().size():
		_reveal_next()
	elif page + 1 < page_count():
		_show_page(page + 1)
	else:
		show_report()


func show_report() -> void:
	_on_report = true
	for tw in _tweens:
		if tw and tw.is_valid():
			tw.kill()
	_tweens.clear()
	%Grid.visible = false
	%Report.visible = true
	%Report.modulate.a = 1.0
	if not CwMotion.reduced():
		%Report.modulate.a = 0.0
		create_tween().tween_property(%Report, "modulate:a", 1.0, 0.3)
	_fill_portraits()
	_refresh_buttons()


func finish(what: String) -> void:
	closed.emit(what)
	if hud and not embedded and hud.current_screen() == "flight_comic":
		if back_screen != "" and not entry.is_empty():
			hud.open_screen(back_screen, {"project_id": String(entry.get("id", ""))})
		else:
			hud.close_screen()
	elif embedded:
		queue_free()


func _refresh_buttons() -> void:
	var last_page := page + 1 >= page_count()
	var all_in := _revealed >= _visible_panels().size()
	if _on_report:
		%Next.visible = false
		%Skip.visible = false
		%PageNo.text = tr("TY_FC_PAGE_REPORT")
	else:
		%Next.visible = true
		%Skip.visible = true
		%Next.text = tr("TY_FC_NEXT") if not all_in else (tr("TY_FC_NEXT_PAGE") if not last_page else tr("TY_FC_TO_REPORT"))
		%PageNo.text = tr("TY_FC_PAGE").format({"n": page + 1, "m": page_count()})
	%SeeMap.visible = can_see_map and embedded and _on_report
	%Done.visible = _on_report
	%Hint.text = "" if _on_report else tr("TY_FC_CLICK")
	%Close.visible = not _on_report
	%Done.text = tr("TY_FC_BACK") if embedded else tr("TY_FC_CLOSE")


func _process(delta: float) -> void:
	if _on_report or panels.is_empty():
		return
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0 and _revealed < _visible_panels().size():
			_reveal_next()


func _on_page_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		advance()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_RIGHT:
			advance()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _on_report:
				finish("done")
			else:
				show_report()
			get_viewport().set_input_as_handled()


## Esc on the HUD: the report first, then out (TycoonHUD.screen_back).
func go_back() -> bool:
	if not _on_report:
		show_report()
		return true
	return false


# ------------------------------------------------------------ the last page
func _fill_report(outcome: String) -> void:
	var mood := "good" if outcome in ["full", "exceptional"] else ("meh" if outcome == "partial" else "bad")
	%EndArt.set_scene({"scene": "end", "mood": mood})
	%EndTitle.text = tr(String(report.get("title_key", "TY_FC_END_FULL")))
	%EndTitle.add_theme_color_override("font_color", MOOD_COLORS[mood])
	%EndLine.text = caption_text("end_" + outcome, String(entry.get("code", "")), {"code": String(entry.get("code", ""))})
	var rw: Array = report.get("rewards", [])
	var rows := TycoonHUD._copies(%RewardTemplate, rw.size())
	for i in rows.size():
		rows[i].visible = i < rw.size()
		if i < rw.size():
			(rows[i].get_node("Label") as Label).text = tr(String(rw[i]["key"]))
			(rows[i].get_node("Value") as Label).text = String(rw[i]["value"])
	%Rewards.visible = not rw.is_empty()
	var reasons: Array = report.get("reasons", [])
	var rrows := TycoonHUD._copies(%ReasonTemplate, reasons.size())
	var tone := {"bad": CwPalette.DANGER, "good": CwPalette.AURORA_TEAL, "neutral": CwPalette.WARNING}
	for i in rrows.size():
		rrows[i].visible = i < reasons.size()
		if i < reasons.size():
			var r: Dictionary = reasons[i]
			(rrows[i].get_node("Dot") as ColorRect).color = tone.get(String(r.get("tone", "bad")), CwPalette.TEXT_DIM)
			(rrows[i].get_node("Text") as Label).text = tr(String(r["key"])).format(r.get("args", {}))
	var tip: Dictionary = report.get("tip", {})
	%TipText.text = tr(String(tip.get("key", "TY_FC_TIP_KEEP"))).format(tip.get("args", {}))
	var cml: Dictionary = report.get("cml", {})
	%CmlLine.visible = not cml.is_empty()
	if not cml.is_empty():
		%CmlLine.text = tr("TY_FC_TIP_CML").format({"level": cml["level"], "item": tr(String(cml["label_key"]))})


# ------------------------------------------------------------ panels from the log
## The comic's panels from a flight log: the most telling events (at most MAX_PANELS with the
## final one), each {"kind", "art" (FlightComicArt.set_scene), "caption", "sfx", "time"}.
## opts: "target_name" (the target in words), "rover" (a rover rides down after the landing).
static func panels_of(events: Array, target: String, outcome: String, code: String, opts := {}) -> Array:
	var picked: Array = []
	var seps := 0
	for e: Dictionary in events:
		var k := String(e["kind"])
		if not PRIORITY.has(k):
			continue
		if k == "stage_sep":
			seps += 1
			if seps > 2:
				continue
		if k == "landed" and target != "suborbital":
			continue
		picked.append(e)
		if k == "landing" and bool(opts.get("rover", false)):
			var r := e.duplicate()
			r["kind"] = "rover"
			picked.append(r)
	# the budget: drop the least telling (latest first among equals) until it fits
	while picked.size() > MAX_PANELS - 1:
		var worst := -1
		for i in picked.size():
			if worst < 0 or int(PRIORITY[String(picked[i]["kind"])]) <= int(PRIORITY[String(picked[worst]["kind"])]):
				worst = i
		picked.remove_at(worst)
	var out: Array = []
	var args := {"code": code, "target": String(opts.get("target_name", target))}
	for e: Dictionary in picked:
		out.append(_panel(e, target, outcome, code, args))
	var lost := events.any(func(x: Dictionary) -> bool: return String(x["kind"]) == "crash")
	var end_kind := "end_fail" if lost or outcome == "fail" else "end_" + outcome
	out.append({"kind": end_kind, "art": {"scene": "end", "mood": "good" if end_kind in ["end_full", "end_exceptional"] \
		else ("meh" if end_kind == "end_partial" else "bad")}, "caption": caption_text(end_kind, code, args), "sfx": "",
		"time": ""})
	return out


static func _panel(e: Dictionary, target: String, outcome: String, code: String, base_args: Dictionary) -> Dictionary:
	var k := String(e["kind"])
	var alt := float(e.get("alt", 0.0))
	var stages_left := maxi(int(e.get("stages", 2)) - int(e.get("stage", 0)), 1)
	var args := base_args.duplicate()
	args["alt"] = FlightHUD.fmt_dist(alt)
	args["met"] = FlightHUD.fmt_time(float(e.get("met", 0.0)))
	args["speed"] = "%s m/s" % FlightHUD._group(float(e.get("speed", 0.0)), 0)
	args["stage"] = "%d" % maxi(int((e.get("data", {}) as Dictionary).get("stage", e.get("stage", 1))), 1)
	var reason := String((e.get("data", {}) as Dictionary).get("reason", ""))
	var ck := String((e.get("data", {}) as Dictionary).get("cause_key", ""))
	args["cause"] = TranslationServer.translate(ck if ck != "" else (reason if reason != "" else "TY_FC_CAUSE_UNKNOWN"))
	var art := {"scene": "space", "stages": stages_left, "flame": false, "drop": "", "goal": "moon"}
	var cap_kind := k
	match k:
		"liftoff":
			art = {"scene": "pad", "stages": stages_left, "flame": true}
		"maxq":
			art = {"scene": "sky", "stages": stages_left, "flame": true}
		"booster_sep":
			art = {"scene": "sky" if alt < 30000.0 else "high", "stages": stages_left, "flame": true, "drop": "boosters"}
		"stage_sep":
			art = {"scene": "sky" if alt < 25000.0 else "high", "stages": stages_left, "flame": true, "drop": "stage"}
		"fairing":
			art = {"scene": "high", "stages": stages_left, "flame": true, "drop": "fairing"}
		"space":
			art = {"scene": "high", "stages": stages_left, "flame": true}
		"apogee":
			art = {"scene": "top", "stages": 1, "flame": false}
		"orbit":
			art = {"scene": "orbit", "stages": 1, "flame": false}
			if outcome == "partial" and target in ["leo", "sso"]:
				cap_kind = "orbit_partial"
		"burn":
			var goal := "comet" if target == "comet" else ("geo" if target == "geo" else "moon")
			art = {"scene": "transfer", "stages": 1, "flame": true, "goal": goal}
			cap_kind = "burn_" + goal if target in ["comet", "geo"] or target.begins_with("lunar") else "burn"
		"high_orbit":
			art = {"scene": "geo", "stages": 1}
		"capture":
			art = {"scene": "moon_orbit", "stages": 1, "flame": false}
			if outcome == "partial":
				cap_kind = "capture_partial"
		"landing":
			art = {"scene": "moon_surface", "stages": 1}
			if target == "lunar_pole":
				cap_kind = "landing_pole"
		"rover":
			art = {"scene": "rover", "stages": 1}
		"flyby":
			art = {"scene": "moon_orbit", "stages": 1}
		"rendezvous":
			art = {"scene": "comet", "stages": 1}
		"splashdown", "landed":
			art = {"scene": "splash", "stages": 1}
		"crash":
			art = {"scene": "boom", "mood": "low" if alt < 20000.0 else "high"}
	return {"kind": k, "art": art, "caption": caption_text(cap_kind, code, args),
		"sfx": TranslationServer.translate("TY_FC_SFX_" + k.to_upper()) if k in SFX else "",
		"time": clock_text(float(e.get("met", 0.0))) if float(e.get("met", 0.0)) > 0.0 or k == "liftoff" else ""}


## The mission clock of a panel: T+mm:ss, T+hh:mm:ss, or days and hours on a long trip.
static func clock_text(met: float) -> String:
	if met >= 86400.0:
		return "T+%dd %02dh" % [int(met / 86400.0), int(fmod(met, 86400.0) / 3600.0)]
	return "T+" + FlightHUD.fmt_time(met)


## Halley's words for a kind: one of its variants, picked by the mission code (so a flight reads
## the same each time it is read), with {code} {target} {alt} {met} {speed} {stage} {cause} filled.
static func caption_text(kind: String, code: String, args: Dictionary) -> String:
	var n := int(VARIANTS.get(kind, 1))
	var v := 1 + absi(hash(code + ":" + kind)) % n
	return TranslationServer.translate("TY_FC_CAP_%s_%d" % [kind.to_upper(), v]).format(args)
