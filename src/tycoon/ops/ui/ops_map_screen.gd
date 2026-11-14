class_name OpsMapScreen
extends Control
## Mission map ("mesa de controle", GDD section 14, step E5): scenes/tycoon/ui/screens/map.tscn.
## A 3D Earth–Moon system (the repo's voxel Earth and Moon, the solar-system orbit and map-line
## shaders) with the LEO / SSO / GEO rings, the Moon on its orbit, the comet Mother-Ice when it
## is near, the agency's ground stations and their coverage arcs, and the active missions as
## markers moving on the right orbit. Panels: mission cards (phase, recorder, data on the
## ground, health, science, link), the antenna network and the decision popup.
## Everything visual is authored in the scene; this script positions markers, fills panels
## by duplicating the hidden templates (TycoonHUD._copies) and drives the camera.

## seconds of real time per revolution (visual only: the orbits stay readable at any speed)
@export var earth_spin_seconds := 60.0
@export var leo_seconds := 7.0
@export var sso_seconds := 8.5
@export var lunar_orbit_seconds := 5.0
## the Moon moves with game time (27.32 days per orbit)
@export var moon_period_days := 27.32
@export var moon_phase0 := 2.2
## comet: direction it comes from and display distance (Earth radii) at 0 and 10 years left
@export var comet_from := Vector3(-0.8, 0.22, -0.55)
@export var comet_near := 14.0
@export var comet_far := 46.0
## era from which the comet shows on the map (always shown when a mission goes there)
@export var comet_era := 4
@export var coverage_points := 160

const TYPE_TAB := [CwPalette.ENG, CwPalette.SCI, CwPalette.OPS, CwPalette.REL]

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD

var selected := ""
var _view := "all"
var _dismissed := {}
var _t := 0.0
var _drag := false
var _cover_meshes: Dictionary = {}
var _transfers: Dictionary = {}
var _decision_id := ""

@onready var cam: OpsMapCamera = %Camera


func _ready() -> void:
	%Back.pressed.connect(close)
	%Pause.pressed.connect(func() -> void: _set_speed(0))
	%S1.pressed.connect(func() -> void: _set_speed(1))
	%S2.pressed.connect(func() -> void: _set_speed(2))
	%S3.pressed.connect(func() -> void: _set_speed(3))
	%ViewEarth.pressed.connect(func() -> void: set_view("earth"))
	%ViewMoon.pressed.connect(func() -> void: set_view("moon"))
	%ViewAll.pressed.connect(func() -> void: set_view("all"))
	%ViewComet.pressed.connect(func() -> void: set_view("comet"))
	%DecLater.pressed.connect(func() -> void:
		var m := MissionOps.find(state, _decision_id)
		if not m.is_empty():
			_dismissed[_decision_id] = int(m["decision"].get("since", 0))
		_fill_decision())
	%View.gui_input.connect(_on_view_input)
	for r in [%CoverLEO, %CoverSSO, %CoverGEO]:
		_cover_meshes[r] = ArrayMesh.new()
		(r as MeshInstance3D).mesh = _cover_meshes[r]
	set_view("all", true)


## Called by TycoonHUD.open_screen().
func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD = null) -> void:
	state = s
	clock = c
	hud = h
	state.changed.connect(refresh)
	if clock:
		clock.speed_changed.connect(_press_speed)
		_press_speed(clock.speed)
	refresh()
	_update_world(0.0)
	cam.snap()


func close() -> void:
	if hud:
		hud.close_screen()
	else:
		queue_free()


func _set_speed(sp: int) -> void:
	if clock:
		clock.set_speed(sp)


func _press_speed(sp: int) -> void:
	var btns: Array[Button] = [%Pause, %S1, %S2, %S3]
	for i in btns.size():
		btns[i].set_pressed_no_signal(i == clampi(sp, 0, 3))


# ------------------------------------------------------------ camera
func set_view(v: String, instant := false) -> void:
	_view = v
	if not v.begins_with("mission:"):
		selected = ""
	var keys := {"earth": %ViewEarth, "moon": %ViewMoon, "all": %ViewAll, "comet": %ViewComet}
	for k: String in keys:
		(keys[k] as Button).set_pressed_no_signal(k == v)
	match v:
		"earth":
			cam.frame(Vector3.ZERO, 8.5)
		"moon":
			cam.frame(%Moon.global_position, 4.2)
		"comet":
			cam.frame(%Comet.global_position, 9.0)
		"all":
			cam.frame(Vector3(1.5, 0.0, -1.0), 25.0)
	if instant:
		cam.snap()
	if state:
		_fill_cards()


func select_mission(id: String) -> void:
	selected = id
	_view = "mission:" + id
	for b: Button in [%ViewEarth, %ViewMoon, %ViewAll, %ViewComet]:
		b.set_pressed_no_signal(false)
	var m := MissionOps.find(state, id)
	if not m.is_empty():
		var cls := String(MissionOps.target_ops(String(m["target"])).get("class", "earth"))
		cam.distance = 8.5 if cls == "earth" else (4.2 if cls == "moon" else 9.0)
	_fill_cards()
	for c in %CardTemplate.get_parent().get_children():
		if c.visible and String(c.get_meta("mission_id", "")) == id:
			(%CardTemplate.get_parent().get_parent() as ScrollContainer).ensure_control_visible(c)


func _on_view_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam.zoom(0.88)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam.zoom(1.0 / 0.88)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_drag = mb.pressed
		accept_event()
	elif e is InputEventMouseMotion and _drag:
		cam.orbit((e as InputEventMouseMotion).relative)
		accept_event()


# ------------------------------------------------------------ per frame: the 3D world
func _process(delta: float) -> void:
	if state == null:
		return
	_update_world(delta)


func _frac() -> float:
	return clock.week_fraction() if clock else 0.0


## Game time in weeks, smooth between ticks.
func _tw() -> float:
	return float(state.weeks) + _frac()


func _update_world(delta: float) -> void:
	_t += delta
	%EarthSpin.rotation.y = fmod(_t * TAU / earth_spin_seconds, TAU)
	%MoonPivot.rotation.y = _moon_angle(_tw())
	var comet_on := _comet_visible()
	%Comet.visible = comet_on
	%ViewComet.visible = comet_on
	if comet_on:
		%Comet.global_position = _comet_pos()
	# the camera follows its subject
	match _view:
		"moon":
			cam.focus = %Moon.global_position
		"comet":
			cam.focus = %Comet.global_position
	if _view.begins_with("mission:"):
		var m := MissionOps.find(state, selected)
		if m.is_empty():
			set_view("all")
		else:
			cam.focus = mission_position(m)
	_update_coverage()
	_place_overlay()


func _moon_angle(tw: float) -> float:
	return moon_phase0 + tw * 7.0 / moon_period_days * TAU


func _comet_visible() -> bool:
	if state.era() >= comet_era:
		return true
	for m in state.active_missions:
		if String(m.get("target", "")) == "comet":
			return true
	return false


func _comet_pos() -> Vector3:
	var years_left := float(state.comet_weeks_left()) / state.weeks_per_year()
	return comet_from.normalized() * lerpf(comet_near, comet_far, clampf(years_left / 10.0, 0.0, 1.0))


func _stations() -> Array[Node3D]:
	var n := int(MissionOps.data().get("network", {}).get("stations", [1])[MissionOps.antenna_level(state)])
	var out: Array[Node3D] = []
	for c in %Stations.get_children():
		if c is Node3D and out.size() < n:
			out.append(c)
	return out


func _hash01(id: String) -> float:
	return float(hash(id) & 0xffff) / 65535.0


## Where a mission is drawn now (world space): on its transfer while cruising, then on the
## orbit or site of its target.
func mission_position(m: Dictionary) -> Vector3:
	var target := String(m.get("target", ""))
	var ph := _hash01(String(m.get("id", ""))) * TAU
	var tau := float(m.get("age", 0)) + _frac()
	var tops := MissionOps.target_ops(target)
	# missions launched this week are not initialised by the weekly step yet: use the defaults
	var cruise := float(m.get("cruise_weeks", tops.get("cruise_weeks", 0)))
	var ops := maxf(float(m.get("ops_weeks", MissionOps.type_ops(String(m.get("type", ""))).get("ops_weeks", 1))), 1.0)
	var cls := String(tops.get("class", "earth"))
	var p_ops := clampf((tau - cruise) / ops, 0.0, 1.0)
	if tau < cruise:
		var p := clampf(tau / cruise, 0.0, 1.0)
		match cls:
			"moon":
				return _lunar_transfer_point(m, smoothstep(0.0, 1.0, p))
			"comet":
				var a := Vector3(1.3, 0, 0).rotated(Vector3.UP, ph)
				var b := _comet_pos() + Vector3(0.6, 0.2, 0)
				return a.lerp(b, p) + Vector3(0, sin(p * PI) * 2.0, 0)
			_:
				var on_ring := _orbit_point(target, ph)
				var r := lerpf(1.02, on_ring.length(), smoothstep(0.0, 1.0, p))
				if target == "geo":
					var a2 := ph + p * 3.0 * PI
					return Vector3(cos(a2), 0.0, -sin(a2)) * lerpf(1.25, on_ring.length(), p)
				return on_ring.normalized() * r
	match target:
		"suborbital":
			var s := (%Station0 as Node3D).global_position
			return s * (1.0 + 0.22 * sin(PI * clampf(p_ops, 0.0, 1.0)) + 0.02)
		"lunar_orbit":
			return %RingLunar.global_transform * _ring_local(ph + _t * TAU / lunar_orbit_seconds)
		"lunar_flyby":
			var moon: Vector3 = %Moon.global_position
			var out := moon.normalized()
			var side := out.cross(%MoonPlane.global_transform.basis.y.normalized()).normalized()
			var phi := lerpf(-1.9, 1.9, p_ops)
			return moon + (out * cos(phi) + side * sin(phi)) * 1.1
		"lunar_surface":
			return (%SiteSurface as Node3D).global_transform * Vector3(0, 0, (_hash01(String(m["id"])) - 0.5) * 0.6)
		"lunar_pole":
			return (%SitePole as Node3D).global_position
		"comet":
			return _comet_pos() + Vector3(cos(ph + _t), 0.3, sin(ph + _t)) * 0.9
	return _orbit_point(target, ph)


func _ring_local(a: float) -> Vector3:
	return Vector3(cos(a), 0.0, -sin(a))


func _orbit_point(target: String, ph: float) -> Vector3:
	match target:
		"leo":
			return %RingLEO.global_transform * _ring_local(ph + _t * TAU / leo_seconds)
		"sso":
			return %RingSSO.global_transform * _ring_local(ph + _t * TAU / sso_seconds)
		"geo":
			# geostationary: fixed over a longitude near the first station, turning with the Earth
			var s: Vector3 = (%Station0 as Node3D).position
			var lon := atan2(-s.z, s.x) + (ph / TAU - 0.5) * 2.2
			return %RingGEO.global_transform * _ring_local(lon + %EarthSpin.rotation.y)
	return Vector3.ZERO


## Half an ellipse from a low Earth orbit (perigee) to the Moon at arrival (apogee), in the
## Moon's orbital plane: the translunar trajectory.
func _lunar_transfer_point(m: Dictionary, p: float) -> Vector3:
	var cruise := float(m.get("cruise_weeks", MissionOps.target_ops(String(m.get("target", ""))).get("cruise_weeks", 1)))
	var arrive := _moon_angle(float(m.get("start_week", state.weeks)) + cruise)
	var ra: float = (%Moon as Node3D).position.length()
	var rp := 1.3
	var e := (ra - rp) / (ra + rp)
	var a := (ra + rp) * 0.5
	var nu := PI * p
	var r := a * (1.0 - e * e) / (1.0 + e * cos(nu))
	var beta := arrive - PI + nu
	return %MoonPlane.global_transform * Vector3(r * cos(beta), 0.0, -r * sin(beta))


func _update_coverage() -> void:
	var st := _stations()
	var rings := {%CoverLEO: %RingLEO, %CoverSSO: %RingSSO, %CoverGEO: %RingGEO}
	for cover: MeshInstance3D in rings:
		var ring: MeshInstance3D = rings[cover]
		var pts := PackedVector3Array()
		var alphas := PackedFloat32Array()
		var n := coverage_points
		pts.resize(n + 1)
		alphas.resize(n + 1)
		for i in n + 1:
			var p := ring.global_transform * _ring_local(TAU * float(i) / n)
			pts[i] = p
			var best := -1.0
			for s in st:
				var sp := s.global_position
				best = maxf(best, (p - sp).normalized().dot(sp.normalized()))
			alphas[i] = smoothstep(0.0, 0.12, best)
		OpsLines.build(pts, alphas, true, _cover_meshes[cover])


func _transfer_mesh(id: String) -> MeshInstance3D:
	if _transfers.has(id):
		return _transfers[id]
	var tpl := %TransferTemplate as MeshInstance3D
	var mi := tpl.duplicate() as MeshInstance3D
	# per-instance shader parameters are not carried by duplicate(): copy the template's
	for k: StringName in [&"line_color", &"line_width", &"dash"]:
		mi.set_instance_shader_parameter(k, tpl.get_instance_shader_parameter(k))
	mi.mesh = ArrayMesh.new()
	mi.visible = true
	%TransferTemplate.get_parent().add_child(mi)
	_transfers[id] = mi
	return mi


func _update_transfers() -> void:
	var live := {}
	for m in state.active_missions:
		var cls := String(MissionOps.target_ops(String(m.get("target", ""))).get("class", ""))
		var tau := float(m.get("age", 0)) + _frac()
		var cruise := float(m.get("cruise_weeks", MissionOps.target_ops(String(m.get("target", ""))).get("cruise_weeks", 0)))
		if cls != "moon" or tau >= cruise:
			continue
		var id := String(m["id"])
		live[id] = true
		var mi := _transfer_mesh(id)
		var p := smoothstep(0.0, 1.0, clampf(tau / maxf(cruise, 0.01), 0.0, 1.0))
		var pts := PackedVector3Array()
		var alphas := PackedFloat32Array()
		for i in 49:
			var q := float(i) / 48.0
			pts.append(_lunar_transfer_point(m, q))
			alphas.append(0.3 if q < p else 0.95)
		OpsLines.build(pts, alphas, false, mi.mesh as ArrayMesh)
	for id: String in _transfers.keys():
		if not live.has(id):
			(_transfers[id] as Node).queue_free()
			_transfers.erase(id)


# ------------------------------------------------------------ per frame: the overlay
func _project(p: Vector3) -> Variant:
	if cam.is_position_behind(p):
		return null
	return cam.unproject_position(p)


## Is the point hidden behind the Earth (a sphere of radius 1 at the origin)?
func _behind_earth(p: Vector3) -> bool:
	var c := cam.global_position
	var d := p - c
	var b := c.dot(d)
	var a := d.dot(d)
	var disc := b * b - a * (c.dot(c) - 1.0)
	if disc <= 0.0:
		return false
	var t := (-b - sqrt(disc)) / a
	return t > 0.0 and t < 0.999


## Is a point on the Earth's surface facing the camera?
func _facing(p: Vector3) -> bool:
	return p.normalized().dot((cam.global_position - p).normalized()) > 0.05


func _place_overlay() -> void:
	_update_transfers()
	# body and orbit labels: each label names its 3D anchor in its metadata
	for l in %Labels.get_children():
		if not (l is Control) or not l.has_meta("anchor"):
			continue
		var node := l.get_node_or_null(l.get_meta("anchor")) as Node3D
		var c := l as Control
		if node == null or not node.is_visible_in_tree():
			c.visible = false
			continue
		var sp: Variant = _project(node.global_position)
		c.visible = sp != null and not _behind_earth(node.global_position)
		if sp != null:
			c.position = (sp as Vector2) + (l.get_meta("offset", Vector2.ZERO) as Vector2)
	if %LblComet.visible:
		%LblComet.text = tr("TY_OPS_COMET_DIST") % TycoonOpsFmt.int_str(state.comet_weeks_left())
	# ground stations
	var st := _stations()
	var deep: bool = MissionOps.data().get("network", {}).get("deep_space", [])[MissionOps.antenna_level(state)]
	var marks := TycoonHUD._copies(%StationTemplate, st.size())
	var station_screen: Array = []
	for i in st.size():
		var p := st[i].global_position
		var sp: Variant = _project(p)
		var vis := sp != null and _facing(p)
		marks[i].visible = vis
		(marks[i] as OpsMarker).radius = 5.0 if deep else 3.5
		if vis:
			marks[i].position = (sp as Vector2) - marks[i].size * 0.5
		station_screen.append(sp if vis else null)
	# missions and their links
	var missions := state.active_missions
	var ms := TycoonHUD._copies(%MarkerTemplate, missions.size())
	var links: Array = []
	var placed: Array[Rect2] = []
	for i in missions.size():
		var m: Dictionary = missions[i]
		var mk := ms[i] as OpsMarker
		var p := mission_position(m)
		var sp: Variant = _project(p)
		mk.visible = sp != null
		if sp == null:
			continue
		mk.position = (sp as Vector2) - mk.size * 0.5
		mk.modulate.a = 0.3 if _behind_earth(p) else 1.0
		# keep the code labels from piling up: slide a label down until it is clear
		var code := mk.get_node("Code") as Label
		if not code.has_meta("home"):
			code.set_meta("home", code.position)
		code.position = code.get_meta("home")
		for k in 5:
			var r := Rect2(mk.position + code.position, code.size)
			var hit := false
			for q: Rect2 in placed:
				hit = hit or q.intersects(r)
			if not hit:
				break
			code.position.y += 13.0
		placed.append(Rect2(mk.position + code.position, code.size))
		var pending := not (m.get("decision", {}) as Dictionary).is_empty()
		mk.color = _status_color(m).lightened(0.35)
		mk.alert = pending
		mk.selected = String(m["id"]) == selected
		(mk.get_node("Code") as Label).text = String(m.get("code", ""))
		mk.set_meta("mission_id", String(m["id"]))
		if not mk.has_meta("wired"):
			mk.set_meta("wired", true)
			mk.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
						and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
					select_mission(String(mk.get_meta("mission_id"))))
		# radio link to the best-placed station in view
		if String(m.get("status", "")) != "ops":
			continue
		var best := -1
		var best_el := 0.0
		for k in st.size():
			var s := st[k].global_position
			var el := (p - s).normalized().dot(s.normalized())
			if el > best_el:
				best_el = el
				best = k
		if best >= 0 and station_screen[best] != null:
			links.append({"from": sp, "to": station_screen[best], "color": CwPalette.MINT,
				"flowing": float(m.get("last_down", 0.0)) > 0.0})
	%Links.links = links


func _status_color(m: Dictionary) -> Color:
	if not (m.get("decision", {}) as Dictionary).is_empty():
		return CwPalette.IGNITION
	match String(m.get("status", "")):
		"cruise":
			return CwPalette.COMET_ICE
		"lost":
			return CwPalette.DANGER
	return CwPalette.AURORA_TEAL


func _status_text(m: Dictionary) -> String:
	if not (m.get("decision", {}) as Dictionary).is_empty():
		return tr("TY_OPS_ST_DECISION")
	return tr("TY_OPS_ST_%s" % String(m.get("status", "ops")).to_upper())


# ------------------------------------------------------------ panels
func refresh() -> void:
	if state == null:
		return
	%DateValue.text = "%02d · %02d" % [state.year(), state.week()]
	_fill_network()
	_fill_cards()
	_fill_decision()


func _fill_network() -> void:
	var lv := MissionOps.antenna_level(state)
	var net: Dictionary = MissionOps.data().get("network", {})
	%NetLevel.text = tr("TY_OPS_NET_LEVEL") % [lv, tr(String(net.get("name_keys", [""])[lv]))]
	(%NetLevelBar as CwSegmentBar).value = lv / 3.0
	var rows := {%RowLEO: "leo", %RowGEO: "geo", %RowMoon: "lunar_orbit", %RowComet: "comet"}
	for row: Control in rows:
		var probe := {"target": rows[row], "type": "", "antenna_gain": 1.0}
		var now := MissionOps.downlink_rate_at(probe, lv)
		var top := MissionOps.downlink_rate_at(probe, 3)
		(row.get_node("Bar") as CwSegmentBar).value = now / top if top > 0.0 else 0.0
		(row.get_node("Value") as Label).text = tr("TY_OPS_NET_RATE") % now
	if lv < 3:
		var probe2 := {"target": "lunar_orbit", "type": "", "antenna_gain": 1.0}
		var ratio := MissionOps.downlink_rate_at(probe2, lv + 1) / maxf(MissionOps.downlink_rate_at(probe2, lv), 0.001)
		%NetNext.text = tr("TY_OPS_NET_NEXT") % ("%.1f" % ratio)
	else:
		%NetNext.text = tr("TY_OPS_NET_MAX")


func _fill_cards() -> void:
	if state == null:
		return
	var missions := state.active_missions
	%Empty.visible = missions.is_empty()
	%Count.text = "%d" % missions.size()
	var cards := TycoonHUD._copies(%CardTemplate, missions.size())
	for i in missions.size():
		_fill_card(cards[i] as PanelContainer, missions[i])


func _fill_card(card: PanelContainer, m: Dictionary) -> void:
	var id := String(m.get("id", ""))
	card.set_meta("mission_id", id)
	if not card.has_meta("wired"):
		card.set_meta("wired", true)
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
					and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				select_mission(String(card.get_meta("mission_id"))))
	var ty := state.mission_type(String(m.get("type", "")))
	var tg := state.mission_target(String(m.get("target", "")))
	var tops := MissionOps.target_ops(String(m.get("target", "")))
	# tab in the colour of the type's leading bar; engraved border lights up when selected
	var ratio: Array = ty.get("ratio", [0.25, 0.25, 0.25, 0.25])
	var lead := 0
	for k in ratio.size():
		if float(ratio[k]) > float(ratio[lead]):
			lead = k
	var base := card.get_theme_stylebox("panel", "CwStrip") as CwPanelStyle
	if base:
		var stl := base.duplicate() as CwPanelStyle
		stl.tab_color = TYPE_TAB[lead]
		if id == selected:
			stl.border_color = CwPalette.COMET_ICE
			stl.bg_color = CwPalette.PANEL_RAISED
		card.add_theme_stylebox_override("panel", stl)
	var v := card.get_node("VBox")
	(v.get_node("Head/Code") as Label).text = String(m.get("code", ""))
	(v.get_node("Head/Type") as Label).text = tr(String(ty.get("name_key", "")))
	var status := v.get_node("Head/Status") as Label
	status.text = _status_text(m)
	status.add_theme_color_override("font_color", CwPalette.ink(_status_color(m)))
	(v.get_node("Target") as Label).text = "%s · %s" % [tr(String(tg.get("name_key", ""))),
		tr("TY_OPS_KM") % TycoonOpsFmt.int_str(int(tops.get("distance_km", 0)))]
	var total := maxi(int(m.get("weeks_total", 1)), 1)
	var age := int(m.get("age", 0))
	var pb := v.get_node("Phase/Bar") as CwSegmentBar
	pb.value = float(age) / total
	pb.marker = float(m.get("cruise_weeks", 0)) / total if int(m.get("cruise_weeks", 0)) > 0 else -1.0
	pb.color = _status_color(m)
	(v.get_node("Phase/Weeks") as Label).text = tr("TY_OPS_WEEK_OF") % [age, total]
	var cap := float(m.get("storage", 1.0)) * float(m.get("buffer_mult", 1.0))
	var stored := float(m.get("data_stored", 0.0))
	var sb := v.get_node("Data/StoredBar") as CwSegmentBar
	sb.value = stored / cap if cap > 0.0 else 0.0
	sb.color = CwPalette.WARNING if sb.value > 0.8 else CwPalette.SCI
	(v.get_node("Data/StoredVal") as Label).text = tr("TY_OPS_GB") % [stored, cap]
	var gen := float(m.get("data_gen", 0.0))
	var down := float(m.get("data_down", 0.0))
	var db := v.get_node("Data/DownBar") as CwSegmentBar
	db.value = down / gen if gen > 0.0 else 0.0
	(v.get_node("Data/DownVal") as Label).text = "%.0f Gb · %d%%" % [down, roundi(db.value * 100.0)]
	var hb := v.get_node("Data/HealthBar") as CwSegmentBar
	var health := float(m.get("health", 1.0))
	hb.value = health
	hb.color = CwPalette.SUCCESS if health > 0.6 else (CwPalette.WARNING if health > 0.3 else CwPalette.DANGER)
	(v.get_node("Data/HealthVal") as Label).text = "%d%%" % roundi(health * 100.0)
	(v.get_node("Foot/Science") as Label).text = "%.1f" % float(m.get("science", 0.0))
	var link := v.get_node("Foot/Link") as Label
	if String(m.get("status", "")) == "cruise":
		link.text = tr("TY_OPS_LINK_CRUISE")
		link.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
	elif float(m.get("last_down", 0.0)) > 0.0:
		link.text = tr("TY_OPS_LINK_ON") % MissionOps.downlink_rate(state, m)
		link.add_theme_color_override("font_color", CwPalette.AURORA_TEAL)
	else:
		link.text = tr("TY_OPS_LINK_OFF")
		link.add_theme_color_override("font_color", CwPalette.WARNING)


func _fill_decision() -> void:
	var m: Dictionary = {}
	for c in MissionOps.pending_decisions(state):
		var since := int(c["decision"].get("since", 0))
		if int(_dismissed.get(String(c["id"]), -1)) != since:
			m = c
			break
	%Decision.visible = not m.is_empty()
	if m.is_empty():
		_decision_id = ""
		return
	_decision_id = String(m["id"])
	var ev := String(m["event"])
	var EV := ev.to_upper()
	%DecCaption.text = tr("TY_OPS_DECISION") % String(m.get("code", ""))
	%DecTitle.text = tr("TY_OPS_EV_%s_TITLE" % EV)
	%DecText.text = tr("TY_OPS_EV_%s_TEXT" % EV)
	var left := int(MissionOps.data().get("decision_timeout_weeks", 3)) - (int(m.get("age", 0)) - int(m["decision"].get("since", 0)))
	%DecTimer.text = tr("TY_OPS_DEFAULT_IN") % maxi(left, 1)
	var choices: Array = MissionOps.event_def(ev).get("choices", [])
	var btns := TycoonHUD._copies(%ChoiceTemplate, choices.size())
	var reveal := MissionOps.reveals_risk(state)
	var dflt := MissionOps.default_choice(ev)
	for i in choices.size():
		var b := btns[i] as Button
		var key := String(choices[i]["key"])
		(b.get_node("HBox/Index") as Label).text = "%d" % (i + 1)
		(b.get_node("HBox/Text/Name") as Label).text = tr(key) + ("  · " + tr("TY_OPS_DEFAULT") if i == dflt else "")
		(b.get_node("HBox/Text/Fx") as Label).text = tr(key + "_FX")
		var risk := MissionOps.choice_risk(ev, i)
		var rl := b.get_node("HBox/Risk") as Label
		if risk <= 0.0:
			rl.text = tr("TY_OPS_RISK_NONE")
			rl.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
		elif reveal:
			rl.text = tr("TY_OPS_RISK") % roundi(risk * 100.0)
			rl.add_theme_color_override("font_color", CwPalette.DANGER if risk >= 0.15 else CwPalette.WARNING)
		else:
			rl.text = tr("TY_OPS_RISK_HIDDEN")
			rl.add_theme_color_override("font_color", CwPalette.WARNING)
		b.set_meta("choice", i)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void:
				MissionOps.decide(state, _decision_id, int(b.get_meta("choice"))))
