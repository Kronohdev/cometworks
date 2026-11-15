class_name SolarSystemOverlay
extends Control
## The panels of the standalone solar-system view (scenes/solar_system/solar_system_overlay.tscn),
## laid over the flight's map in its map-only mode, the same map the campus' Solar System map
## (SpaceMapOverlay) uses: the real date and its speed (pause, a day / week / month / year per
## second, back to today), the list of bodies (copies of the hidden RowTemplate) to fly the map's
## camera to, and the selected body's card: live distances, mean distance, period, size, day,
## tilt, gravity and a short text. Everything visual is in the scene; this fills it.

## simulated days per real second for the speed keys (pause, day, week, month, year)
@export var speeds: PackedFloat32Array = [0.0, 1.0, 7.0, 30.4375, 365.25]
## view distance in body radii when focusing (bigger for the Sun and the giants with rings)
@export var view_radii := {"sun": 6.0, "saturn": 9.0, "jupiter": 7.0, "mae_gelo": 400000.0}

signal leave_requested

var world: FlightWorld
var map: FlightMap
var sys: FlightSolar
## campaign-clock time on show (s after FlightSolar.EPOCH_DAYS) and the speed key
var t := 0.0
var speed := 2
var selected := ""

var _text_timer := 0.0


func _ready() -> void:
	var keys: Array = [%Pause, %Day, %Week, %Month, %Year]
	for i in keys.size():
		(keys[i] as Button).pressed.connect(set_speed.bind(i))
	%Today.pressed.connect(go_today)
	%Back.pressed.connect(func() -> void: leave_requested.emit())


## Called by SolarSystem once the flight (map only) is ready.
func bind(w: FlightWorld) -> void:
	world = w
	map = w.map
	sys = w.sys
	t = today_t()
	world.clock_source = func() -> float: return t
	world.time = t
	var hint := map.get_node_or_null("%Hint") as Control
	if hint:
		hint.visible = false
		var pill := hint.get_parent() as Control
		if pill and pill != map.overlay:
			pill.visible = false   # its pill too (it would sit there empty)
	map.set_readable(true)
	map.set_scale_mode(2, true)
	_fill_list()
	set_speed(speed)
	show_info("earth")


## Mission time of today's real date (the computer's clock).
static func today_t() -> float:
	var unix := Time.get_unix_time_from_system()
	var days := (unix - 946728000.0) / 86400.0   # 946728000 = 2000-01-01 12:00 UTC
	return (days - FlightSolar.EPOCH_DAYS) * FlightSolar.DAY


func go_today() -> void:
	t = today_t()


func set_speed(i: int) -> void:
	speed = clampi(i, 0, speeds.size() - 1)
	var keys: Array = [%Pause, %Day, %Week, %Month, %Year]
	for k in keys.size():
		(keys[k] as Button).set_pressed_no_signal(k == speed)


func toggle_pause() -> void:
	set_speed(2 if speed == 0 else 0)


func _process(delta: float) -> void:
	if world == null:
		return
	t += float(speeds[speed]) * FlightSolar.DAY * delta
	_text_timer -= delta
	if _text_timer <= 0.0:
		_text_timer = 0.2
		%DateValue.text = date_text(sys.date_at(t))
		_refresh_live()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_SPACE:
		toggle_pause()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------ the list and the card
func _order() -> Array[int]:
	# the Sun, then each planet followed by its moons, the comet last
	var out: Array[int] = [sys.sun]
	for i in sys.children[sys.sun]:
		if sys.kinds[i] == "comet":
			continue
		out.append(i)
		for m in sys.children[i]:
			out.append(m)
	if sys.comet >= 0:
		out.append(sys.comet)
	return out


func _fill_list() -> void:
	var order := _order()
	var rows := TycoonHUD._copies(%RowTemplate, order.size())
	for k in order.size():
		var i := order[k]
		var row := rows[k] as Button
		var id := sys.ids[i]
		row.set_meta("body_id", id)
		if not row.has_meta("wired"):
			row.set_meta("wired", true)
			row.pressed.connect(func() -> void: focus_body(String(row.get_meta("body_id", ""))))
		(row.get_node("HBox/Indent") as Control).custom_minimum_size.x = 18.0 if sys.kinds[i] == "moon" else 0.0
		(row.get_node("HBox/Icon") as TextureRect).texture = _icon(id)
		(row.get_node("HBox/Name") as Label).text = body_name(id)
		(row.get_node("HBox/Kind") as Label).text = tr("SS_KIND_" + id.to_upper())


func _icon(id: String) -> Texture2D:
	var path := "res://assets/voxel/planets/icons/%s.png" % id
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func body_name(id: String) -> String:
	var key := "SS_NAME_" + id.to_upper()
	var txt := tr(key)
	return txt if txt != key else sys.display_name(sys.index_of(id))


## Flies the map's camera to a body and shows its card.
func focus_body(id: String) -> void:
	var i := sys.index_of(id)
	if i < 0 or map == null:
		return
	map.set_focus(i)
	var r := sys.radius[i] * FlightMap.K
	map.dist = r * float(view_radii.get(id, 5.0)) * (map._body_scale[i] if map.readable else 1.0)
	map.pitch = 0.35
	show_info(id)


func show_info(id: String) -> void:
	var i := sys.index_of(id)
	if i < 0:
		return
	selected = id
	var d: Dictionary = sys.eph.data[sys.eph.index_of(id)]
	var up := id.to_upper()
	(%Icon as TextureRect).texture = _icon(id)
	%BodyName.text = body_name(id)
	%BodyKind.text = tr("SS_KIND_" + up)
	var r_km := float(d["radius_km"])
	%VRadius.text = tr("SS_FMT_KM") % num(r_km, 0 if r_km >= 100.0 else 1)
	var p := sys.parent[i]
	if p < 0:
		%VDistance.text = tr("SS_CENTER")
	elif p == sys.sun:
		var au := sys.sma[i] / 1.495978707e11
		%VDistance.text = tr("SS_FMT_AU") % [num(au, 3), num(au * 149.5978707, 1)]
	else:
		%VDistance.text = tr("SS_FMT_KM_FROM") % [num(sys.sma[i] / 1000.0, 0), body_name(sys.ids[p])]
	var per := sys.period(i) / FlightSolar.DAY
	if per == INF or per <= 0.0:
		%VPeriod.text = "-"
	elif per > 730.0:
		%VPeriod.text = tr("SS_FMT_YEARS") % num(per / 365.256, 2)
	else:
		%VPeriod.text = tr("SS_FMT_DAYS") % num(per, 2 if per < 100.0 else 1)
	var rot := float(d.get("rotation_period_hours", 0.0))
	var tilt := float(d.get("axial_tilt_deg", 0.0))
	var rot_s := tr("SS_FMT_HOURS") % num(absf(rot), 2) if absf(rot) < 72.0 else tr("SS_FMT_DAYS") % num(absf(rot) / 24.0, 1)
	if rot < 0.0 or tilt > 90.0:
		rot_s += " · " + tr("SS_RETROGRADE")
	if d.get("tidally_locked", false):
		rot_s += " · " + tr("SS_LOCKED")
	%VDay.text = rot_s
	%VTilt.text = tr("SS_FMT_DEG") % num(tilt, 2)
	var g := float(d.get("surface_gravity_ms2", 0.0))
	%VGravity.text = tr("SS_FMT_G") % [num(g, 2 if g >= 0.01 else 4), num(g / 9.80665, 2 if g >= 0.01 else 5)]
	%Desc.text = tr("SS_DESC_" + up)
	for c in %RowTemplate.get_parent().get_children():
		if c != %RowTemplate and c is Button:
			(c as Button).set_pressed_no_signal(String(c.get_meta("body_id", "")) == id)
	_refresh_live()


## The card's live lines: distance from the parent (or the Sun) and from the Earth, now.
func _refresh_live() -> void:
	var i := sys.index_of(selected)
	if i < 0:
		return
	var p := sys.parent[i]
	%LNow.visible = p >= 0
	%VNow.visible = p >= 0
	if p >= 0:
		%LNow.text = tr("SSM_NOW_FROM_PARENT") % body_name(sys.ids[p])
		%VNow.text = dist_text(sys.distance_at(i, t))
	var far := i != sys.earth and p != sys.earth
	%LEarth.visible = far
	%VEarth.visible = %LEarth.visible
	if %LEarth.visible:
		%VEarth.text = dist_text(FlightOrbit.length(sys.pos_rel(i, sys.earth, t)))


## "384.400 km", "1,52 UA" (locale-aware).
func dist_text(m: float) -> String:
	var km := m / 1000.0
	if km < 1.0e7:
		return tr("SS_FMT_KM") % num(km, 0)
	var au := m / 1.495978707e11
	return tr("SS_FMT_AU") % [num(au, 3), num(km / 1.0e6, 1)]


## "14 de novembro de 2026" / "November 14, 2026" (also the campus map's real date).
static func date_text(d: Dictionary) -> String:
	var tm := TranslationServer
	return String(tm.translate("SSM_DATE_FMT")).format({"d": int(d["day"]),
		"m": tm.translate("SSM_MONTH_%d" % int(d["month"])), "y": int(d["year"])})


## Locale-aware number: 149,597.9 (en) / 149.597,9 (pt).
static func num(x: float, decimals := 0) -> String:
	var pt := TranslationServer.get_locale().begins_with("pt")
	var txt := ("%." + str(decimals) + "f") % absf(x)
	var parts := txt.split(".")
	var ip: String = parts[0]
	var grouped := ""
	while ip.length() > 3:
		grouped = (("." if pt else ",") + ip.substr(ip.length() - 3)) + grouped
		ip = ip.substr(0, ip.length() - 3)
	grouped = ip + grouped
	if parts.size() > 1:
		grouped += ("," if pt else ".") + parts[1]
	return ("-" if x < 0.0 else "") + grouped
