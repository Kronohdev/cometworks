class_name LaunchWatch
extends Control
## The card over a career flight in the 3D view (scenes/tycoon/tracking/launch_watch_overlay.tscn),
## laid on the flight's HUD by TycoonModes. Nothing here flies: the flight is a CareerFlight (its
## autopilot flies the outcome the career already gave), this only says where it is and what
## happened:
##   live     the launch that just left the campus pad (the handoff of LaunchSequence, or the
##            map's "Acompanhar" while it flies): "Voltar ao campus" leaves the 3D view and the
##            flight goes on in the background, on the Solar System map
##   launch   a past launch seen again from the pad (the review's "Acompanhar o lançamento")
##   follow   a craft in space where its track has it now: "Voltar ao mapa"
## The result card names the outcome when it happens (lost with its cause, orbit, a partial
## orbit, the transfer leaving, a hop splashing down, arrival), with "Ver no mapa" (the Solar
## System map on this mission) and the way back. Camera, map (M) and warp (, and .) stay free.
## The speed key (%Speed, or V) steps the flight's warp through SPEEDS; the physics always steps
## FlightSim.DT, so the flight ends the same at any speed. "Simular até o fim" (%Skip) flies the
## rest at once (FlightLog.finish) and opens the comic recap told by Vovô Edmundo (FlightComic);
## the log is recorded all along (FlightLog.observe each frame), so the result card's "Relatório
## do voo" opens the same comic for a flight that was watched.

## seconds in orbit before the result card (a target in Earth orbit)
@export var orbit_hold := 4.0
## seconds after the departure burn before the result card
@export var burn_hold := 5.0

## px between the card and the map's bottom-left column when the map (M) is open
const CARD_GAP := 12.0
const PHASE_COLORS := {"lost": CwPalette.DANGER, "orbit": CwPalette.AURORA_TEAL, "transfer": CwPalette.COMET_ICE,
	"arrived": CwPalette.AURORA_VIOLET}
## the speed key's steps (warp levels of FlightWorld; 100 is its physics cap)
const SPEEDS: Array[int] = [1, 2, 4, 10, 100]
const COMIC := "res://scenes/tycoon/ui/screens/flight_comic.tscn"
## wall-clock ms of flight simulation per frame while skipping
const SKIP_BUDGET_MS := 70.0
## no-break space: glues a key cap to its label in the hint (key_caps)
const NBSP := "\u00a0"

var modes: TycoonModes
var world: FlightWorld
var run: CareerFlight
var mode := "live"
var track: Dictionary = {}
var entry: Dictionary = {}
var outcome := "full"
var target := "leo"
var _t := 0.0
var _result_at := -1.0
var _result_kind := ""
var _shown := {}
var _lost_met := -1.0
var _apogee := 0.0
## leaving goes back to the Solar System map (the live launch opened from it)
var back_to_map := false
## the card's own bottom (the scene's), over the 3D view
var _card_bottom := 0.0
## what the flight went through, written down as it flies (the comic's source)
var flog: FlightLog = null
## the flight was simulated to its end at once (no result card of its own then)
var skipped := false
## the comic on show (FlightComic), or null
var comic: Control = null
## "Simular até o fim" is flying the rest (a few frames: SKIP_BUDGET_MS of flight each)
var _skipping := false


func _ready() -> void:
	%Back.pressed.connect(go_back)
	%ResBack.pressed.connect(go_back)
	%Keep.pressed.connect(func() -> void: %Result.visible = false)
	%SeeMap.pressed.connect(see_map)
	%Speed.pressed.connect(cycle_speed)
	%Skip.pressed.connect(skip_to_end)
	%Report.pressed.connect(open_comic)
	%Result.visible = false
	_card_bottom = (%Card as Control).offset_bottom


## Called by TycoonModes once the flight is ready. args: {"mode", "track", "entry", "run"}.
func bind(m: TycoonModes, w: FlightWorld, args: Dictionary) -> void:
	modes = m
	world = w
	mode = String(args.get("mode", "live"))
	track = args.get("track", {})
	entry = args.get("entry", {})
	run = args.get("run") as CareerFlight
	back_to_map = bool(args.get("back_to_map", false))
	outcome = String(track.get("outcome", entry.get("outcome", "full")))
	target = String(track.get("target", entry.get("target", "leo")))
	world.flight_event.connect(_on_event)
	if mode == "follow" or (run and run.sim.in_orbit):
		_shown["orbit"] = true
	flog = FlightLog.new(run) if run else null
	_fill_static()


func _fill_static() -> void:
	var s := modes.main.state if modes and modes.main else null
	%Caption.text = tr("TY_TRK_FOLLOW_CAPTION") if mode == "follow" else tr("TY_TRK_WATCH_CAPTION")
	var code := String(track.get("code", entry.get("code", "")))
	var what := ""
	if s:
		var mt := s.mission_type(String(track.get("type", entry.get("type", ""))))
		what = "%s → %s" % [tr(String(mt.get("name_key", ""))), _target_name()]
	%Title.text = "%s · %s" % [code, what] if code != "" else what
	%Back.text = tr("TY_TRK_BACK_MAP") if mode == "follow" or back_to_map else tr("TY_TRK_BACK_CAMPUS")
	%ResBack.text = %Back.text
	%Hint.text = key_caps(tr("TY_LV_LEAVE_HINT") if mode == "live" else tr("TY_TRK_WARP_HINT"))
	_refresh_phase()


## The hint in BBCode with its keys drawn as key caps: a bare key is easy to miss, above all
## the warp's "," and "." (they read as punctuation). In each " · " part, a lone punctuation
## mark is a key, and so is a short first word starting in capitals (M, Esc, F2, C).
## A part with a key cap is one unit when the line wraps: its spaces (and the cap's padding)
## are no-break spaces, so a cap never ends a line away from the word it labels; the line
## breaks only after a " · " (or inside a part with no key, plain prose).
static func key_caps(text: String) -> String:
	var parts := text.replace("[", "[lb]").split(" · ")
	for i in parts.size():
		var words := parts[i].split(" ")
		var has_cap := false
		for j in words.size():
			var w := words[j]
			var mark := w.length() == 1 and w in ",.;/-=+"
			var word_key := j == 0 and w.length() <= 3 and w != "" and w[0] != w[0].to_lower()
			if mark or word_key:
				has_cap = true
				words[j] = "[bgcolor=#%s][color=#%s]%s%s%s[/color][/bgcolor]" % [CwPalette.LILAC_LIGHT.to_html(false),
					CwPalette.INK.to_html(false), NBSP, w, NBSP]
		parts[i] = (NBSP if has_cap else " ").join(words)
	# the dot sticks to the part before it; the break opportunity is the space after it
	return "[b]%s[/b]" % (NBSP + "· ").join(parts)   # bold like the other dim lines (CwDim)


## The card's place: its own over the 3D view; on the map (M) right above the map's
## bottom-left column (the map bar over its hint), so the three panels never overlap.
func _place_card() -> void:
	var card := %Card as Control
	var bottom := _card_bottom
	if world.map_view and world.map and world.map.visible:
		var top := get_global_transform().affine_inverse() * Vector2(0.0, world.map.corner_top())
		bottom = minf(_card_bottom, top.y - size.y - CARD_GAP)
	if not is_equal_approx(card.offset_bottom, bottom):
		var h := card.offset_bottom - card.offset_top
		card.offset_bottom = bottom
		card.offset_top = bottom - h


func _target_name() -> String:
	var s := modes.main.state if modes and modes.main else null
	return tr(String(s.mission_target(target).get("name_key", target))) if s else target


## Out: the campus (the flight goes on there, on the map) or the map (a followed craft).
func go_back() -> void:
	if world:
		world.revert_to_hangar()


func see_map() -> void:
	if modes == null:
		return
	var id := String(track.get("id", ""))
	var m := modes
	m.close_mode()
	m.open_space_map.call_deferred(id)


func _unhandled_input(event: InputEvent) -> void:
	if comic and is_instance_valid(comic):
		return   # the comic has the keys
	if %Result.visible and event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		%Result.visible = false
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_V \
			and world and not world.paused:
		cycle_speed()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------ speed, skip, the comic
## The next speed (1x 2x 4x 10x 100x, then 1x again): the flight's warp. A warp picked with , / .
## outside the steps goes back to 1x.
func cycle_speed() -> void:
	if world == null:
		return
	var i := SPEEDS.find(world.warp)
	world.warp = SPEEDS[(i + 1) % SPEEDS.size()] if i >= 0 else 1
	_refresh_speed()


func _refresh_speed() -> void:
	var w := world.current_warp() if world else 1
	var txt := "%d×" % w
	if (%Speed as Button).text != txt:
		(%Speed as Button).text = txt
	var done := flog != null and flog.done()
	var skip_txt := tr("TY_TRK_REPORT") if done or skipped else tr("TY_TRK_SKIP")
	if (%Skip as Button).text != skip_txt:
		(%Skip as Button).text = skip_txt


## "Simular até o fim": the rest of the flight at once (the same run, the same steps), then the
## comic of what happened. Once the flight is over the key opens the comic again.
func skip_to_end() -> void:
	if run == null or flog == null or (comic and is_instance_valid(comic)):
		return
	if skipped or flog.done():
		open_comic()
		return
	_skipping = true
	(%Skip as Button).disabled = true
	world.warp = 1


## One frame of the skip: as much flight as SKIP_BUDGET_MS of the frame allows (the physics is
## the same fixed step as watching), the view kept on the flight's time; done: the comic.
func _skip_frame() -> void:
	var ok := flog.finish(SKIP_BUDGET_MS)
	world.time = run.sim.t
	(%Skip as Button).text = "%s T+%s" % [tr("TY_TRK_SKIPPING"), FlightHUD.fmt_time(maxf(run.sim.met(), 0.0))]
	if not ok:
		return
	_skipping = false
	skipped = true
	for e: Dictionary in flog.events:
		if String(e["kind"]) == "crash":
			_lost_met = float(e["met"])
	_result_at = -1.0
	%Result.visible = false
	# the view catches up at once: its time is the flight's, the events of the way are the comic's
	world.time = run.sim.t
	world.warp = 1
	run.take_pending()
	run.take_dropped()
	(%Skip as Button).disabled = false
	open_comic()


## The comic recap of this flight so far (the whole of it after a skip).
func open_comic() -> void:
	if flog == null or (comic and is_instance_valid(comic)):
		return
	flog.observe()
	var s := modes.main.state if modes and modes.main else null
	FlightComic.save_log(entry, flog)
	var c := (load(COMIC) as PackedScene).instantiate() as FlightComic
	add_child(c)
	comic = c
	%Result.visible = false
	c.show_flight(s, entry, flog.events, flog.outcome(), {"embedded": true,
		"see_map": not String(track.get("id", "")).is_empty() and modes != null,
		"target": target, "code": String(track.get("code", entry.get("code", ""))), "outcome": outcome})
	c.closed.connect(_on_comic_closed)


func _on_comic_closed(what: String) -> void:
	comic = null
	if what == "map":
		see_map()
	elif skipped:
		show_result(_final_kind())
	elif _result_kind != "" and _result_at < 0.0:
		show_result(_result_kind)   # opened from the result card: back to it


## The result card's kind for a flight that has ended (after a skip).
func _final_kind() -> String:
	if run == null or run.sim.crashed:
		return "lost"
	if target == "suborbital":
		return "suborbital"
	if target.begins_with("lunar") or target == "comet":
		return "arrived"
	return "partial" if outcome == "partial" else "orbit"


func _process(delta: float) -> void:
	if world == null:
		return
	_place_card()
	_t += delta
	if flog:
		flog.observe()
	if _skipping:
		_skip_frame()
	else:
		_refresh_speed()
	if skipped or _skipping:
		_refresh_phase()
		return
	if run and target == "suborbital" and run.sim.launched and run.sim.vertical_speed() < 0.0 and not _shown.has("top") \
			and run.sim.altitude() > 50000.0:
		_shown["top"] = true
		_apogee = float(run.sim.stats.get("max_alt", 0.0))
		_result_soon("suborbital", 1.5)
	if run and run.phase == "transfer" and not _shown.has("transfer"):
		_shown["transfer"] = true
		world.hud.toast(tr("TY_TRK_PH_BURN"), CwPalette.IGNITION_HI)
		_result_soon("transfer", burn_hold)
	if _result_at >= 0.0 and _t >= _result_at:
		_result_at = -1.0
		show_result(_result_kind)
	_refresh_phase()


func _on_event(key: String, _data: Dictionary) -> void:
	match key:
		"EV_CRASH":
			_lost_met = world.mission_time()
			_result_soon("lost", 2.5)
		"EV_ORBIT":
			if not _shown.has("orbit"):
				_shown["orbit"] = true
				if target in ["leo", "sso"] or not (target == "geo" or target == "comet" or target.begins_with("lunar")):
					_result_soon("partial" if outcome == "partial" else "orbit", orbit_hold)
		"EV_LANDED":
			if target == "suborbital":
				_result_soon("suborbital", 0.5)


func _result_soon(kind: String, seconds: float) -> void:
	if _shown.has("res:" + kind):
		return
	_shown["res:" + kind] = true
	_result_kind = kind
	_result_at = _t + seconds


func _refresh_phase() -> void:
	var text := ""
	var col := CwPalette.TEXT
	var s := run.sim if run else null
	if s == null:
		%Phase.text = ""
		return
	if s.crashed:
		text = tr("TY_TRK_PH_LOST")
		col = PHASE_COLORS["lost"]
	elif mode == "follow":
		var st := modes.main.state if modes and modes.main else null
		if st and not track.is_empty():
			text = SpaceMapOverlay.where_text(st, track, world.time)
	elif not s.launched:
		text = tr("TY_TRK_PH_COUNTDOWN") % 0
		col = CwPalette.IGNITION
	else:
		match run.phase:
			"ascent", "pad":
				text = tr("TY_TRK_PH_ASCENT") % FlightHUD.fmt_dist(s.altitude())
				if target == "suborbital" and s.thrust_n <= 0.0:
					text = tr("TY_TRK_PH_COAST") % FlightHUD.fmt_dist(s.altitude()) if s.vertical_speed() > 0.0 \
						else tr("TY_TRK_PH_FALL")
			"orbit":
				var g := run.autopilot()
				if g and not g.burns.is_empty():
					text = tr("TY_TRK_PH_WAIT") % FlightHUD.fmt_time(maxf(float(g.burns[0]["t"]) - world.time, 0.0))
				else:
					text = tr("TY_TRK_PH_ORBIT")
					col = PHASE_COLORS["orbit"]
			"transfer":
				text = tr("TY_TRK_PH_TRANSFER") % _target_name()
				col = PHASE_COLORS["transfer"]
			"arrived":
				text = tr("TY_TRK_ST_ARRIVED")
				col = PHASE_COLORS["arrived"]
			"lost":
				text = tr("TY_TRK_PH_LOST")
				col = PHASE_COLORS["lost"]
	%Phase.text = text
	%Phase.add_theme_color_override("font_color", col)


## The result card: "lost", "orbit", "partial", "transfer" or "suborbital".
func show_result(kind: String) -> void:
	_result_kind = kind
	var code := String(track.get("code", entry.get("code", "")))
	var el := run.sim.elements() if run else {"ap_alt": 0.0, "pe_alt": 0.0}
	%ResCause.visible = false
	match kind:
		"lost":
			%ResTitle.text = tr("TY_TRK_RES_LOST")
			%ResText.text = tr("TY_TRK_RES_LOST_TEXT") % [code, FlightHUD.fmt_time(_lost_met if _lost_met >= 0.0 else world.mission_time())]
			var ck := String(entry.get("cause_key", run.cause_key if run else ""))
			if ck != "":
				%ResCause.text = tr("TY_TRK_RES_CAUSE") % tr(ck)
				%ResCause.visible = true
		"orbit":
			%ResTitle.text = tr("TY_TRK_RES_ORBIT")
			%ResText.text = tr("TY_TRK_RES_ORBIT_TEXT") % [code, FlightHUD.fmt_dist(float(el["ap_alt"])),
				FlightHUD.fmt_dist(float(el["pe_alt"]))]
		"partial":
			%ResTitle.text = tr("TY_TRK_RES_PARTIAL")
			%ResText.text = tr("TY_TRK_RES_PARTIAL_TEXT")
		"transfer":
			%ResTitle.text = tr("TY_TRK_RES_TRANSFER")
			%ResText.text = tr("TY_TRK_RES_TRANSFER_TEXT") % [code, _target_name()]
		"arrived":
			%ResTitle.text = tr("TY_TRK_RES_ARRIVED")
			%ResText.text = tr("TY_TRK_RES_ARRIVED_TEXT") % [code, _target_name()]
		"suborbital":
			%ResTitle.text = tr("TY_TRK_RES_SUBORBITAL")
			%ResText.text = tr("TY_TRK_RES_SUBORBITAL_TEXT") % [code, FlightHUD.fmt_dist(maxf(_apogee,
				float(run.sim.stats.get("max_alt", 0.0)) if run else 0.0))]
	var col: Color = CwPalette.DANGER if kind == "lost" else (CwPalette.WARNING if kind == "partial" else CwPalette.AURORA_TEAL)
	%ResTitle.add_theme_color_override("font_color", col)
	%SeeMap.visible = not String(track.get("id", "")).is_empty()
	%Result.visible = true
