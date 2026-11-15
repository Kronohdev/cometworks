extends CwScreen
## The rover workshop (scenes/tycoon/ui/screens/rover_builder.tscn): pick a chassis, power,
## instruments and an antenna (RoverDesign), see the voxel rover turn on its stand (the part
## scenes assembled in the screen's own SubViewport), its numbers in plain words for a body
## (mass against what the lander carries, energy, speed, range, climb, science, cost) and what
## the Cometlings say about it. Designs are saved in the career (RoverGarage).
## Opened from the payload planner of a rover mission ("Montar o rover": args carry the plan; "Usar
## na missão" puts the rover in the payload and goes back), from the dev menu, or standalone
## (state null: the sandbox garage). "Testar na superfície" drives it on the chosen body
## (TycoonModes.open_surface inside the campus, else the drive scene).
## Everything visual is in the scene; part rows and sentences are copies of its hidden templates.

const ICONS := "res://ui/cometworks/icons/%s.svg"
const TABS := ["chassis", "power", "instrument", "comms"]
const BODIES: Array[String] = ["moon", "mars", "mercury", "europa", "titan", "earth"]
const BODY_KEYS := {"moon": "PLANET_MOON", "mars": "PLANET_MARS", "mercury": "PLANET_MERCURY", "europa": "PLANET_EUROPA",
	"titan": "PLANET_TITAN", "earth": "PLANET_EARTH"}
const SAY_COLORS := {"good": CwPalette.SUCCESS, "warn": CwPalette.WARNING, "bad": CwPalette.DANGER, "info": CwPalette.COMET_ICE}
const SAY_ICONS := {"good": "check", "warn": "flame", "bad": "shield", "info": "star"}

var design: Dictionary = {}
var tab := "chassis"
var body := "moon"
## the plan of the payload planner that opened us ({} = no mission)
var plan_args: Dictionary = {}
var info_id := ""
var _spin := 0.0
var _drag := false
var _built_key := ""


func _ready() -> void:
	super._ready()
	%Back.pressed.connect(_back)
	%Use.pressed.connect(use_design)
	%Test.pressed.connect(test_drive)
	%Save.pressed.connect(save_design)
	%New.pressed.connect(new_design)
	%Delete.pressed.connect(delete_design)
	%Saved.item_selected.connect(_load_saved)
	%BodyPick.item_selected.connect(func(i: int) -> void:
		body = BODIES[i]
		refresh())
	%NameEdit.text_changed.connect(func(t: String) -> void: design["name"] = t)
	for t in TABS:
		var b := get_node("%Tab" + String(t).capitalize()) as Button
		b.pressed.connect(func() -> void: set_tab(t))
	%PreviewView.gui_input.connect(_preview_input)
	_ensure_design.call_deferred()


## Standalone (no bind): the starter rover.
func _ensure_design() -> void:
	if design.is_empty():
		design = RoverDesign.starter()
		refresh()


func _bound() -> void:
	if design.is_empty():
		var list := RoverGarage.designs(state)
		design = RoverDesign.normalize(list[-1]) if not list.is_empty() else RoverDesign.starter()


## args: the payload planner's {"type", "target", "contract_id", "briefing_id", "payload", "staff"},
## or {"design": dict, "body": id} from the dev menu.
func open_with(args: Dictionary) -> void:
	if args.has("payload") or args.has("type"):
		plan_args = args.duplicate(true)
		var d := RoverDesign.from_payload(args.get("payload", []))
		if not d.is_empty():
			design = d
		var b := String(SurfaceSession.body_for_target(String(args.get("target", ""))))
		if b != "":
			body = b
	if args.has("design"):
		design = RoverDesign.normalize(args["design"])
	if args.has("body") and String(args["body"]) in BODIES:
		body = String(args["body"])
	refresh()


func set_tab(t: String) -> void:
	tab = t
	refresh()


func toggle_part(id: String) -> void:
	design = RoverDesign.toggle(design, id)
	info_id = id
	refresh()


## Mass the lander takes for this mission (0 = no mission).
func allowance() -> float:
	if plan_args.is_empty() or state == null:
		return 0.0
	return PayloadRules.mass_allowance(state, String(plan_args.get("type", "rover")))


## The mass of the mission's whole payload with this rover in it.
func payload_mass() -> float:
	var t := 0.0
	for id in RoverDesign.apply_to_payload(plan_args.get("payload", []), design):
		t += float(PayloadRules.module(id).get("mass", 0.0))
	return t


func design_error() -> String:
	var errs := RoverDesign.validate(design, state)
	if not errs.is_empty():
		return errs[0]
	if allowance() > 0.0 and payload_mass() > allowance():
		return "RV_ERR_HEAVY"
	return ""


# ------------------------------------------------------------ fill
func refresh() -> void:
	if not is_node_ready() or design.is_empty():
		return
	%Caption.text = tr("RV_B_CAPTION")
	%Mission.visible = not plan_args.is_empty() and state != null
	if %Mission.visible:
		%MissionLine.text = "%s → %s" % [tr(String(state.mission_type(String(plan_args.get("type", ""))).get("name_key", ""))),
			tr(String(state.mission_target(String(plan_args.get("target", ""))).get("name_key", "")))]
	for t in TABS:
		(get_node("%Tab" + String(t).capitalize()) as Button).set_pressed_no_signal(t == tab)
	if %NameEdit.text != String(design.get("name", "")):
		%NameEdit.text = String(design.get("name", ""))
	_fill_body_pick()
	_fill_parts()
	_fill_stats()
	_fill_says()
	_fill_info()
	_fill_saved()
	_build_preview()
	var err := design_error()
	%Error.text = tr(err) if err != "" else ""
	%Use.disabled = err != ""
	%Use.text = tr("RV_B_USE") if not plan_args.is_empty() else tr("RV_B_DONE")
	%Test.disabled = not RoverDesign.validate(design, null).is_empty()


func _fill_body_pick() -> void:
	var pick := %BodyPick as OptionButton
	if pick.item_count != BODIES.size():
		pick.clear()
		for b in BODIES:
			pick.add_item(tr(String(BODY_KEYS[b])))
	for i in BODIES.size():
		pick.set_item_text(i, tr(String(BODY_KEYS[BODIES[i]])))
	pick.select(BODIES.find(body))


func _fill_parts() -> void:
	var list := RoverDesign.parts_of(tab)
	var rows := copies(%PartTemplate, list.size())
	for i in list.size():
		var p: Dictionary = list[i]
		var id := String(p["id"])
		var b := rows[i] as Button
		b.set_meta("id", id)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: toggle_part(String(b.get_meta("id", ""))))
			b.mouse_entered.connect(func() -> void:
				info_id = String(b.get_meta("id", ""))
				_fill_info())
		var ok := RoverDesign.is_available(state, id)
		b.disabled = not ok
		b.set_pressed_no_signal(RoverDesign.has_part(design, id))
		var ip := ICONS % String(p.get("icon", "build"))
		if ResourceLoader.exists(ip):
			(b.get_node("Box/Row/Icon") as TextureRect).texture = load(ip)
		(b.get_node("Box/Row/Names/Name") as Label).text = tr(RoverDesign.name_key(id))
		(b.get_node("Box/Row/Names/Stats") as Label).text = part_line(id)
		var lock := b.get_node("Box/Row/Lock") as Label
		lock.text = ""
		if not ok:
			var tech := RoverDesign.tech_for(id)
			lock.text = tr("RV_B_LOCKED") % tr("TY_TECH_" + tech.to_upper()) if tech != "" else tr("RV_B_LOCKED_PLAIN")
	var ch := RoverDesign.chassis(String(design.get("chassis", "")))
	%Slots.text = tr("RV_B_SLOTS") % [RoverDesign.parts_in(design, "instrument").size(), int(ch.get("bays", 0)),
		RoverDesign.parts_in(design, "power").size(), int(ch.get("power_bays", 0))]


## "30 kg · 5 m/s · sobe 32°" (what matters for the slot).
func part_line(id: String) -> String:
	var p := RoverDesign.part(id)
	var s := RoverDesign.part_stats(id)
	var bits: Array[String] = []
	match String(p.get("slot", "")):
		"chassis":
			bits.append(tr("TY_PL_KG") % int(p.get("mass", 0)))
			bits.append(tr("RV_B_V_SPEED") % RoverHUD.num(float(p.get("speed", 0.0)) * 3.6, 0))
			bits.append(tr("RV_B_V_CLIMB_SHORT") % int(p.get("climb", 0)))
			bits.append(tr("RV_B_V_BAYS") % int(p.get("bays", 0)))
		"power":
			bits.append(tr("TY_PL_KG") % int(s["mass"]))
			if s["gen"] > 0.0:
				bits.append(tr("TY_PL_GEN") % int(s["gen"]))
			if s["store"] > 0.0:
				bits.append(tr("TY_PL_STORE") % int(s["store"]))
		"instrument":
			bits.append(tr("TY_PL_KG") % int(s["mass"]))
			bits.append(tr("TY_PL_W") % int(s["power"]))
			if p.has("science"):
				bits.append(tr("RV_B_V_SCI_SHORT") % int(p["science"]))
		"comms":
			bits.append(tr("TY_PL_KG") % int(s["mass"]))
			bits.append(tr("TY_PL_GAIN") % s["gain"])
	return " · ".join(bits)


func _stat(row: String, frac: float, text: String, state_name := "info") -> void:
	var r := get_node("%" + row) as Control
	var bar := r.get_node("Bar") as CwSegmentBar
	bar.value = clampf(frac, 0.0, 1.0)
	bar.color = SAY_COLORS.get(state_name, CwPalette.COMET_ICE)
	(r.get_node("Value") as Label).text = text


func _fill_stats() -> void:
	var st := RoverDesign.stats(design, body)
	var allow := allowance()
	if allow > 0.0:
		var pm := payload_mass()
		_stat("StatMass", pm / allow, tr("RV_B_V_MASS_FIT") % [roundi(pm), roundi(allow)], "bad" if pm > allow else ("warn" if pm > allow * 0.85 else "good"))
	else:
		_stat("StatMass", float(st["mass"]) / 160.0, tr("TY_PL_KG") % roundi(float(st["mass"])))
	var drive := float(st["drive"])
	_stat("StatEnergy", float(st["gen_here"]) / maxf(drive, 1.0), tr("RV_B_V_ENERGY") % [roundi(float(st["gen_here"])), roundi(drive)],
		"good" if float(st["gen_here"]) >= drive else ("warn" if float(st["store"]) > 0.0 else "bad"))
	_stat("StatSpeed", float(st["speed"]) / 5.5, tr("RV_B_V_SPEED") % RoverHUD.num(float(st["speed"]) * 3.6, 0))
	var rk := float(st["range_km"])
	if rk < 0.0:
		_stat("StatRange", 1.0, tr("RV_B_V_RANGE_SUN"), "good")
	else:
		_stat("StatRange", rk / 20.0, tr("RV_B_V_RANGE") % RoverHUD.num(rk, 1), "warn" if rk < 3.0 else "info")
	_stat("StatClimb", float(st["climb"]) / 50.0, tr("RV_B_V_CLIMB") % roundi(float(st["climb"])))
	_stat("StatScience", float(st["science"]) / 70.0, tr("RV_B_V_SCIENCE") % roundi(float(st["science"])), "good" if float(st["science"]) > 0.0 else "bad")
	_stat("StatCost", float(st["cost"]) / 300000.0, cr(float(st["cost"])))


## The Cometlings' plain-language read of the design: [{"key", "args", "tone"}].
func says() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var st := RoverDesign.stats(design, body)
	var allow := allowance()
	if allow > 0.0 and payload_mass() > allow:
		out.append({"key": "RV_SAY_HEAVY", "args": [roundi(payload_mass()), roundi(allow)], "tone": "bad"})
	for e in RoverDesign.validate(design, state):
		out.append({"key": e, "args": [], "tone": "bad"})
	var bd := RoverDesign.body(body)
	if float(st["range_km"]) < 0.0:
		out.append({"key": "RV_SAY_ENDLESS", "args": [], "tone": "good"})
	elif float(st["store"]) > 0.0:
		out.append({"key": "RV_SAY_RANGE", "args": [RoverHUD.num(float(st["range_km"]), 1)], "tone": "info"})
	if float(bd.get("sun", 1.0)) < 0.6 and float(st["gen"]) - float(st["rtg"]) > 0.0:
		out.append({"key": "RV_SAY_WEAK_SUN", "args": [roundi(float(bd["sun"]) * 100.0)], "tone": "warn"})
	if body == "moon" and float(st["rtg"]) <= 0.0:
		out.append({"key": "RV_SAY_NIGHT", "args": [], "tone": "warn"})
	if bool(st["needs_air"]) and not bool(st["drone_ok"]):
		out.append({"key": "RV_SAY_DRONE_AIR", "args": [], "tone": "warn"})
	if not (st["hop"] as Dictionary).is_empty():
		var hopd: Dictionary = st["hop"]
		var ok := float(hopd.get("max_gravity", 4.0)) >= _gravity(body)
		out.append({"key": "RV_SAY_HOPPER" if ok else "RV_SAY_HOPPER_HEAVY", "args": [], "tone": "good" if ok else "bad"})
	if float(st["climb"]) >= 40.0:
		out.append({"key": "RV_SAY_CLIMBER", "args": [], "tone": "good"})
	if float(st["science"]) <= 0.0:
		out.append({"key": "RV_SAY_NO_SCIENCE", "args": [], "tone": "warn"})
	if out.filter(func(x: Dictionary) -> bool: return x["tone"] == "bad").is_empty():
		out.append({"key": "RV_SAY_READY", "args": [], "tone": "good"})
	return out


static func _gravity(b: String) -> float:
	var p := load("res://resources/planets/%s.tres" % b) as PlanetSurfaceProfile
	return p.gravity if p else 1.62


func _fill_says() -> void:
	var list := says()
	var rows := copies(%SayTemplate, list.size())
	for i in list.size():
		var s: Dictionary = list[i]
		var t := tr(String(s["key"]))
		if not (s["args"] as Array).is_empty():
			t = t % s["args"]
		(rows[i].get_node("Text") as Label).text = t
		var ic := rows[i].get_node("Icon") as TextureRect
		ic.texture = load(ICONS % String(SAY_ICONS.get(String(s["tone"]), "star")))
		ic.modulate = SAY_COLORS.get(String(s["tone"]), CwPalette.INK)


func _fill_info() -> void:
	if info_id == "":
		%InfoName.text = tr("RV_B_INFO")
		%InfoDesc.text = tr("RV_B_INFO_DESC")
		return
	%InfoName.text = tr(RoverDesign.name_key(info_id))
	%InfoDesc.text = tr(RoverDesign.name_key(info_id) + "_DESC")


func _fill_saved() -> void:
	var pick := %Saved as OptionButton
	pick.clear()
	var list := RoverGarage.designs(state)
	pick.add_item(tr("RV_B_SAVED_NONE") if list.is_empty() else tr("RV_B_SAVED_PICK"))
	for d: Dictionary in list:
		pick.add_item(String(d.get("name", "")))
	pick.select(0)
	%Delete.disabled = RoverGarage.find(state, String(design.get("name", ""))).is_empty()


func _build_preview() -> void:
	var key := JSON.stringify(design.get("chassis", "")) + JSON.stringify(design.get("parts", []))
	if key == _built_key:
		return
	_built_key = key
	RoverDesign.assemble(design, %Pivot)


func _process(delta: float) -> void:
	if not _drag:
		_spin += delta * 0.35
		(%Pivot as Node3D).rotation.y = _spin


func _preview_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = (e as InputEventMouseButton).pressed
	elif e is InputEventMouseMotion and _drag:
		_spin += (e as InputEventMouseMotion).relative.x * 0.01
		(%Pivot as Node3D).rotation.y = _spin


# ------------------------------------------------------------ commands
func save_design() -> Dictionary:
	if String(design.get("name", "")).strip_edges() == "":
		design["name"] = RoverGarage.free_name(state, tr("RV_STARTER_NAME"))
	var d := RoverGarage.save_design(state, design)
	if state:
		state.changed.emit()
	refresh()
	return d


func new_design() -> void:
	design = RoverDesign.starter(RoverGarage.free_name(state, tr("RV_STARTER_NAME")))
	info_id = ""
	refresh()


func delete_design() -> void:
	RoverGarage.delete(state, String(design.get("name", "")))
	refresh()


func _load_saved(i: int) -> void:
	var list := RoverGarage.designs(state)
	if i >= 1 and i - 1 < list.size():
		design = RoverDesign.normalize(list[i - 1])
		refresh()


## "Usar na missão": the rover goes into the plan's payload (saved in the garage too) and the
## payload planner comes back; without a mission it is just saved.
func use_design() -> void:
	if design_error() != "":
		return
	save_design()
	if plan_args.is_empty():
		close_screen()
		return
	var out := plan_args.duplicate(true)
	out["payload"] = RoverDesign.apply_to_payload(plan_args.get("payload", []), design)
	if hud:
		hud.open_screen("payload_planner", out)
	else:
		close_screen()


func _back() -> void:
	if not plan_args.is_empty() and hud:
		hud.open_screen("payload_planner", plan_args)
	else:
		close_screen()


## Drives this design on the chosen body (sandbox objectives); back here afterwards.
func test_drive() -> void:
	if not RoverDesign.validate(design, null).is_empty():
		return
	var s := SurfaceSession.start(StringName(body), design, RoverMissions.sandbox_objectives(StringName(body)),
		{"sandbox": true, "return": "builder"})
	var main := hud.owner as TycoonMain if hud else null
	if main and main.modes:
		var args := {"design": design.duplicate(true), "body": body}
		if not plan_args.is_empty():
			args = plan_args.duplicate(true)
			args["design"] = design.duplicate(true)
			args["body"] = body
		var h := hud
		main.modes.open_surface(s, func(_r: Dictionary) -> void: h.open_screen("rover_builder", args))
		return
	get_tree().change_scene_to_file(SurfaceSession.DRIVE_SCENE)
