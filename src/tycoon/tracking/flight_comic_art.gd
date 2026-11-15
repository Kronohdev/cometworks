class_name FlightComicArt
extends Control
## The little picture of one comic panel (FlightComic): a stylised scene drawn in the theme's
## inks (CwPalette) with comic outlines, from what the flight log says happened at that moment:
## where the craft was (the pad, the sky, high up, in orbit, on its way, at the Moon, the comet),
## how many stages it still had, whether its engine burned, what it dropped (a stage, the
## boosters, the fairing), and the endings (a break-up, a landing, a rover, a splashdown, the
## final page's burst). set_scene() takes the panel's "art" dictionary (FlightComic.panels_of).

const INK := CwPalette.INK
const OUTLINE := 2.0

## "pad", "sky", "high", "space", "orbit", "transfer", "geo", "moon_orbit", "moon_surface",
## "rover", "comet", "boom", "splash", "top", "end"
@export var scene := "pad"
## stages still on the rocket (1 = the last one)
@export_range(1, 6) var stages := 2
@export var flame := true
## what leaves the rocket in this panel: "", "stage", "boosters", "fairing"
@export var drop := ""
## "good", "meh", "bad" (the final burst and the break-up's sky)
@export var mood := "good"
## the craft's target in the transfer scene: "moon", "geo", "comet"
@export var goal := "moon"
## seed of the stars and the craters
@export var seed_value := 1


func set_scene(d: Dictionary) -> void:
	scene = String(d.get("scene", "pad"))
	stages = clampi(int(d.get("stages", 2)), 1, 6)
	flame = bool(d.get("flame", false))
	drop = String(d.get("drop", ""))
	mood = String(d.get("mood", "good"))
	goal = String(d.get("goal", "moon"))
	seed_value = int(d.get("seed", 1))
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0:
		return
	var c := size * 0.5
	var u := minf(w, h)
	match scene:
		"pad":
			_sky(Color("#bfe6ff"), Color("#fff1d6"))
			_hill(h * 0.78, Color("#8fdcb4"))
			_tower(Vector2(w * 0.5 - u * 0.2, h * 0.78), u * 0.55)
			_smoke(Vector2(w * 0.5, h * 0.78), u * 0.16, 7)
			_rocket(Vector2(w * 0.5, h * 0.78 - u * 0.28), u * 0.42, 0.0, flame)
		"sky":
			_sky(Color("#7cc8ff"), Color("#d9ccff"))
			_clouds(h * 0.72, u)
			_rocket(c + Vector2(0, -u * 0.02), u * 0.46, deg_to_rad(18.0), flame)
		"high", "top":
			_sky(Color("#3a3478"), Color("#9b8cf0"))
			_stars(26, h * 0.6)
			_earth_limb(Vector2(w * 0.5, h + u * 1.15), u * 1.45)
			var ang := deg_to_rad(62.0 if scene == "high" else 90.0)
			_rocket(c + Vector2(0, -u * 0.06), u * 0.44, ang, flame and scene == "high")
		"space", "orbit":
			_sky(CwPalette.SPACE, Color("#2c2a6a"))
			_stars(40, h)
			_earth_limb(Vector2(w * 0.25, h + u * 0.85), u * 1.25)
			if scene == "orbit":
				_dashed_ellipse(Vector2(w * 0.25, h + u * 0.85), Vector2(u * 1.55, u * 1.42), CwPalette.MINT)
			_rocket(c + Vector2(u * 0.08, -u * 0.1), u * 0.4, deg_to_rad(90.0), flame)
		"transfer":
			_sky(CwPalette.SPACE, Color("#262463"))
			_stars(40, h)
			var e := Vector2(w * 0.16, h * 0.7)
			_planet(e, u * 0.13, CwPalette.COMET_ICE, true)
			var tgt := Vector2(w * 0.84, h * 0.3)
			if goal == "comet":
				_comet(tgt, u * 0.08)
			elif goal == "geo":
				tgt = Vector2(w * 0.8, h * 0.45)
				_dashed_ellipse(e, Vector2(u * 0.72, u * 0.5), CwPalette.MINT)
			else:
				_moon(tgt, u * 0.1)
			_dashed_arc(e, tgt, u * 0.35, CwPalette.BUTTER)
			_rocket(e.lerp(tgt, 0.42) + Vector2(0, -u * 0.2), u * 0.3, (tgt - e).angle() + PI * 0.5 - 0.35, flame)
		"geo":
			_sky(CwPalette.SPACE, Color("#262463"))
			_stars(36, h)
			_planet(c, u * 0.2, CwPalette.COMET_ICE, true)
			_dashed_ellipse(c, Vector2(u * 0.46, u * 0.3), CwPalette.MINT)
			_satellite(c + Vector2(u * 0.46, 0) * Vector2(cos(-0.6), 1.0) + Vector2(0, -u * 0.17), u * 0.12)
		"moon_orbit":
			_sky(CwPalette.SPACE, Color("#2a285f"))
			_stars(36, h)
			var m := Vector2(w * 0.62, h * 0.95)
			_moon(m, u * 0.55)
			_dashed_ellipse(m, Vector2(u * 0.78, u * 0.66), CwPalette.MINT)
			_rocket(Vector2(w * 0.3, h * 0.36), u * 0.3, deg_to_rad(100.0), flame)
		"moon_surface", "rover":
			_sky(CwPalette.SPACE, Color("#2a285f"))
			_stars(30, h * 0.6)
			_planet(Vector2(w * 0.8, h * 0.2), u * 0.08, CwPalette.COMET_ICE, true)
			_ground(h * 0.74, Color("#c9c4d8"))
			if scene == "rover":
				_rover(Vector2(w * 0.55, h * 0.74), u * 0.3)
				_lander(Vector2(w * 0.22, h * 0.74), u * 0.24)
			else:
				_lander(Vector2(w * 0.5, h * 0.74), u * 0.34)
				_dust(Vector2(w * 0.5, h * 0.74 + u * 0.03), u * 0.1)
		"comet":
			_sky(CwPalette.SPACE, Color("#23215c"))
			_stars(44, h)
			_comet(Vector2(w * 0.62, h * 0.48), u * 0.2)
			_satellite(Vector2(w * 0.25, h * 0.32), u * 0.12)
		"boom":
			if mood == "low":
				_sky(Color("#7cc8ff"), Color("#ffd9c2"))
				_clouds(h * 0.78, u)
			else:
				_sky(Color("#3a3478"), Color("#c99cf0"))
				_stars(16, h * 0.5)
			_burst(c, u * 0.34, u * 0.2, 12, CwPalette.BUTTER, CwPalette.IGNITION)
			_debris(c, u)
		"splash":
			_sky(Color("#9fd8ff"), Color("#fff1d6"))
			_sea(h * 0.72)
			_capsule(Vector2(w * 0.5, h * 0.42), u * 0.2)
		"end":
			var a := CwPalette.BUTTER if mood == "good" else (Color("#e9e2ff") if mood == "meh" else Color("#ffd9df"))
			var b := CwPalette.PEACH if mood == "good" else (CwPalette.LILAC if mood == "meh" else CwPalette.PINK)
			_rays(c, maxf(w, h), a, b)
			if mood == "bad":
				_rocket(c, u * 0.5, deg_to_rad(-12.0), false, true)
			else:
				_star(c, u * 0.36, u * 0.17, CwPalette.BUTTER if mood == "good" else CwPalette.PEACH.lerp(Color.WHITE, 0.35))
		_:
			_sky(CwPalette.SPACE, Color("#2c2a6a"))


# ------------------------------------------------------------ backgrounds
func _sky(top: Color, bottom: Color) -> void:
	var pts := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value * 7919 + hash(scene)
	return r


func _stars(n: int, max_y: float) -> void:
	var r := _rng()
	for i in n:
		var p := Vector2(r.randf() * size.x, r.randf() * max_y)
		var s := r.randf_range(0.8, 2.2)
		var col := Color(1, 1, 1, r.randf_range(0.5, 1.0))
		if r.randf() < 0.18:
			_twinkle(p, s * 2.6, col)
		else:
			draw_circle(p, s, col)


func _twinkle(p: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0
		pts.append(p + Vector2(cos(a), sin(a)) * (s if i % 2 == 0 else s * 0.3))
	draw_colored_polygon(pts, col)


func _hill(y: float, col: Color) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(0, size.y))
	for i in 17:
		var x := size.x * i / 16.0
		pts.append(Vector2(x, y + sin(i * 0.9) * 4.0))
	pts.append(Vector2(size.x, size.y))
	_shape(pts, col)


func _ground(y: float, col: Color) -> void:
	_hill(y, col)
	var r := _rng()
	for i in 5:
		var p := Vector2(r.randf() * size.x, y + 8.0 + r.randf() * (size.y - y - 10.0))
		var rad := r.randf_range(4.0, 10.0)
		draw_set_transform(p, 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, rad, col.darkened(0.15))
		draw_arc(Vector2.ZERO, rad, 0.0, TAU, 20, INK, 1.4)
		draw_set_transform(Vector2.ZERO)


func _sea(y: float) -> void:
	_hill(y, CwPalette.ICE)
	for i in 6:
		var x := size.x * (0.1 + i * 0.16)
		draw_arc(Vector2(x, y + 14.0), 7.0, PI, TAU, 8, Color(1, 1, 1, 0.8), 2.0)


func _clouds(y: float, u: float) -> void:
	var r := _rng()
	for i in 3:
		var p := Vector2(size.x * (0.15 + 0.35 * i) + r.randf_range(-10, 10), y - r.randf() * u * 0.15)
		for k in 3:
			var cp := p + Vector2((k - 1) * u * 0.09, -absf(k - 1.0) * -u * 0.02)
			draw_circle(cp, u * (0.07 if k != 1 else 0.095), Color(1, 1, 1, 0.92))


func _earth_limb(c: Vector2, r: float) -> void:
	draw_circle(c, r * 1.04, Color(0.49, 0.78, 1.0, 0.35))
	draw_circle(c, r, CwPalette.COMET_ICE)
	var rng := _rng()
	for i in 4:
		var a := -PI * 0.5 + rng.randf_range(-0.5, 0.5)
		var p := c + Vector2(cos(a), sin(a)) * r * rng.randf_range(0.8, 0.97)
		draw_circle(p, r * rng.randf_range(0.06, 0.12), CwPalette.MINT)
	draw_arc(c, r, 0.0, TAU, 96, INK, OUTLINE + 0.5)


func _planet(c: Vector2, r: float, col: Color, land: bool) -> void:
	draw_circle(c, r * 1.12, Color(col.r, col.g, col.b, 0.25))
	draw_circle(c, r, col)
	if land:
		draw_circle(c + Vector2(-r * 0.3, -r * 0.2), r * 0.35, CwPalette.MINT)
		draw_circle(c + Vector2(r * 0.35, r * 0.3), r * 0.25, CwPalette.MINT)
	draw_arc(c, r, 0.0, TAU, 48, INK, OUTLINE)


func _moon(c: Vector2, r: float) -> void:
	draw_circle(c, r, Color("#d9d5e6"))
	var rng := _rng()
	for i in 6:
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * r * rng.randf_range(0.1, 0.7)
		var cr := r * rng.randf_range(0.08, 0.18)
		draw_circle(p, cr, Color("#b9b3cc"))
		draw_arc(p, cr, 0.0, TAU, 16, INK, 1.2)
	draw_arc(c, r, 0.0, TAU, 64, INK, OUTLINE)


func _comet(c: Vector2, r: float) -> void:
	var tail := PackedVector2Array([c + Vector2(0, -r * 0.7), c + Vector2(r * 4.0, -r * 1.6), c + Vector2(r * 4.4, r * 0.4),
		c + Vector2(0, r * 0.7)])
	draw_polygon(tail, PackedColorArray([Color(0.8, 0.93, 1, 0.9), Color(0.7, 0.85, 1, 0.0), Color(0.7, 0.85, 1, 0.0),
		Color(0.8, 0.93, 1, 0.9)]))
	draw_circle(c, r, Color("#eaf6ff"))
	draw_circle(c + Vector2(-r * 0.3, -r * 0.2), r * 0.25, Color("#bfe6ff"))
	draw_arc(c, r, 0.0, TAU, 32, INK, OUTLINE)


func _rays(c: Vector2, r: float, a: Color, b: Color) -> void:
	_sky(a, a)
	for i in 16:
		if i % 2 == 0:
			continue
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]), b)


func _dashed_ellipse(c: Vector2, radii: Vector2, col: Color) -> void:
	var n := 48
	for i in n:
		if i % 2 == 1:
			continue
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		draw_line(c + Vector2(cos(a0), sin(a0)) * radii, c + Vector2(cos(a1), sin(a1)) * radii, col, 2.0, true)


func _dashed_arc(a: Vector2, b: Vector2, lift: float, col: Color) -> void:
	var mid := (a + b) * 0.5 + Vector2(0, -lift)
	var prev := a
	for i in range(1, 25):
		var t := i / 24.0
		var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
		if i % 2 == 0:
			draw_line(prev, p, col, 2.0, true)
		prev = p


# ------------------------------------------------------------ things
func _shape(pts: PackedVector2Array, fill: Color, width := OUTLINE) -> void:
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, INK, width, true)


func _rect(r: Rect2, fill: Color) -> void:
	_shape(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), fill)


## The rocket, nose up before `angle` (rad, clockwise from up), its base-to-nose length `len`,
## `pos` its middle; stages drawn as bands, the dropped piece beside it.
func _rocket(pos: Vector2, length: float, angle: float, burning: bool, sad := false) -> void:
	draw_set_transform(pos, angle, Vector2.ONE)
	var bw := length * 0.2
	var n := stages
	var nose := length * 0.26
	var body := length - nose
	var seg := body / float(n)
	var top := -length * 0.5
	var base := top + nose + body
	if burning:
		_flame(Vector2(0, base), bw)
	# the piece that leaves (behind the rocket, drifting off)
	if drop == "stage":
		var gap := seg * 0.55
		var r := Rect2(-bw * 0.5, base + gap, bw, seg * 0.9)
		_rect(r, CwPalette.PEACH.lerp(Color.WHITE, 0.35))
		_puffs(Vector2(0, base + gap * 0.5), bw * 0.5)
	elif drop == "boosters":
		# the pair drifts off sideways and backwards, tilting away, a puff where each let go
		var bh := minf(seg * 1.1, length * 0.38)
		for sx in [-1.0, 1.0]:
			var at := Vector2(sx * bw * 1.25, base - bh * 0.15)
			_puffs(Vector2(sx * bw * 0.62, base - bh * 0.55), bw * 0.22)
			draw_set_transform(pos + at.rotated(angle), angle + sx * 0.45, Vector2.ONE)
			var bwid := bw * 0.42
			_rect(Rect2(-bwid * 0.5, -bh * 0.5, bwid, bh), CwPalette.PAPER)
			_shape(PackedVector2Array([Vector2(-bwid * 0.5, -bh * 0.5), Vector2(0, -bh * 0.5 - bwid * 0.9),
				Vector2(bwid * 0.5, -bh * 0.5)]), CwPalette.PEACH)
			draw_set_transform(pos, angle, Vector2.ONE)
	# fins
	for sx in [-1.0, 1.0]:
		_shape(PackedVector2Array([Vector2(sx * bw * 0.5, base - seg * 0.55), Vector2(sx * bw * 0.95, base + bw * 0.1),
			Vector2(sx * bw * 0.5, base)]), CwPalette.LILAC)
	# stages, bottom to top
	for i in n:
		var y0 := base - seg * (i + 1)
		var col := CwPalette.PAPER if i % 2 == 0 else CwPalette.PEACH.lerp(Color.WHITE, 0.25)
		_rect(Rect2(-bw * 0.5, y0, bw, seg), col)
	# nose (open halves for the fairing panel)
	var nose_base := top + nose
	if drop == "fairing":
		for sx in [-1.0, 1.0]:
			_shape(PackedVector2Array([Vector2(sx * bw * 0.15, nose_base - nose * 0.1), Vector2(sx * bw * 1.1, top - nose * 0.1),
				Vector2(sx * bw * 0.9, nose_base - nose * 0.2)]), CwPalette.PINK)
		_satellite(Vector2(0, nose_base - nose * 0.35), bw * 0.9)
	else:
		_shape(PackedVector2Array([Vector2(-bw * 0.5, nose_base), Vector2(0, top), Vector2(bw * 0.5, nose_base)]), CwPalette.PINK)
	# the window (a Cometling face for the sad rocket)
	var wpos := Vector2(0, nose_base + seg * 0.45 if n > 0 else nose_base)
	draw_circle(wpos, bw * 0.22, CwPalette.ICE)
	draw_arc(wpos, bw * 0.22, 0.0, TAU, 20, INK, OUTLINE)
	if sad:
		draw_line(Vector2(-bw * 0.3, base - seg * 0.3), Vector2(bw * 0.3, base - seg * 0.6), CwPalette.WELL_LINE, bw * 0.18)
		draw_arc(wpos + Vector2(0, bw * 0.12), bw * 0.08, PI, TAU, 8, INK, 1.5)
	draw_set_transform(Vector2.ZERO)


func _flame(at: Vector2, bw: float) -> void:
	var outer := PackedVector2Array([at + Vector2(-bw * 0.42, 0), at + Vector2(0, bw * 2.0), at + Vector2(bw * 0.42, 0)])
	_shape(outer, CwPalette.IGNITION_HI, 1.6)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-bw * 0.22, 0), at + Vector2(0, bw * 1.1),
		at + Vector2(bw * 0.22, 0)]), CwPalette.BUTTER)


func _puffs(at: Vector2, r: float) -> void:
	for k in 5:
		var a := TAU * k / 5.0
		draw_circle(at + Vector2(cos(a), sin(a) * 0.5) * r * 1.6, r * 0.55, Color(1, 1, 1, 0.9))


func _smoke(at: Vector2, r: float, n: int) -> void:
	for k in n:
		var x := (k - (n - 1) * 0.5) * r * 0.55
		var p := at + Vector2(x, -absf(x) * 0.15)
		draw_circle(p, r * (0.7 - absf(x) / (r * n) * 0.6), Color(1, 1, 1, 0.95))
		draw_arc(p, r * (0.7 - absf(x) / (r * n) * 0.6), PI * 1.05, TAU * 0.98, 12, CwPalette.WELL_LINE, 1.4)


func _tower(base: Vector2, hgt: float) -> void:
	var w := hgt * 0.12
	_rect(Rect2(base.x - w * 0.5, base.y - hgt, w, hgt), CwPalette.WARNING.lerp(Color.WHITE, 0.25))
	for i in 5:
		var y := base.y - hgt * (i + 0.5) / 5.0
		draw_line(Vector2(base.x - w * 0.5, y), Vector2(base.x + w * 0.5, y - hgt * 0.1), INK, 1.4)
	_rect(Rect2(base.x - w * 0.9, base.y - 4.0, hgt * 0.6, 6.0), CwPalette.INK_SOFT)


func _satellite(c: Vector2, s: float) -> void:
	_rect(Rect2(c.x - s * 1.25, c.y - s * 0.2, s * 0.8, s * 0.4), CwPalette.COMET_ICE)
	_rect(Rect2(c.x + s * 0.45, c.y - s * 0.2, s * 0.8, s * 0.4), CwPalette.COMET_ICE)
	_rect(Rect2(c.x - s * 0.35, c.y - s * 0.35, s * 0.7, s * 0.7), CwPalette.BUTTER)
	draw_line(c + Vector2(0, -s * 0.35), c + Vector2(0, -s * 0.7), INK, 1.6)
	draw_circle(c + Vector2(0, -s * 0.72), s * 0.1, CwPalette.PINK)


func _lander(base: Vector2, s: float) -> void:
	for sx in [-1.0, 1.0]:
		draw_line(base + Vector2(sx * s * 0.2, -s * 0.35), base + Vector2(sx * s * 0.45, 0), INK, 2.4)
		draw_line(base + Vector2(sx * s * 0.55, 0), base + Vector2(sx * s * 0.35, 0), INK, 3.0)
	_rect(Rect2(base.x - s * 0.28, base.y - s * 0.62, s * 0.56, s * 0.32), CwPalette.BUTTER)
	_shape(PackedVector2Array([base + Vector2(-s * 0.2, -s * 0.62), base + Vector2(0, -s * 0.85),
		base + Vector2(s * 0.2, -s * 0.62)]), CwPalette.PAPER)
	draw_circle(base + Vector2(0, -s * 0.47), s * 0.07, CwPalette.ICE)
	# a little flag
	draw_line(base + Vector2(s * 0.62, 0), base + Vector2(s * 0.62, -s * 0.55), INK, 1.8)
	_shape(PackedVector2Array([base + Vector2(s * 0.62, -s * 0.55), base + Vector2(s * 0.86, -s * 0.47),
		base + Vector2(s * 0.62, -s * 0.39)]), CwPalette.PINK, 1.4)


func _rover(base: Vector2, s: float) -> void:
	for k in 3:
		var p := base + Vector2((k - 1) * s * 0.32, -s * 0.12)
		draw_circle(p, s * 0.12, CwPalette.INK_SOFT)
		draw_arc(p, s * 0.12, 0.0, TAU, 16, INK, OUTLINE)
	_rect(Rect2(base.x - s * 0.45, base.y - s * 0.42, s * 0.9, s * 0.22), CwPalette.MINT)
	draw_line(base + Vector2(s * 0.3, -s * 0.42), base + Vector2(s * 0.3, -s * 0.7), INK, 1.8)
	draw_circle(base + Vector2(s * 0.3, -s * 0.72), s * 0.07, CwPalette.BUTTER)
	draw_arc(base + Vector2(s * 0.3, -s * 0.72), s * 0.07, 0.0, TAU, 12, INK, 1.4)
	# tracks behind it
	for k in 4:
		draw_line(base + Vector2(-s * (0.6 + k * 0.18), s * 0.02), base + Vector2(-s * (0.52 + k * 0.18), s * 0.02),
			CwPalette.INK_SOFT, 2.0)


func _dust(at: Vector2, r: float) -> void:
	for k in 6:
		var x := (k - 2.5) * r * 0.5
		draw_circle(at + Vector2(x, -r * 0.15), r * 0.32, Color(0.92, 0.9, 0.97, 0.9))


func _capsule(c: Vector2, s: float) -> void:
	# the parachute
	var top := c + Vector2(0, -s * 1.5)
	var dome := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		dome.append(top + Vector2(cos(a) * s * 1.1, sin(a) * s * 0.7))
	_shape(dome, CwPalette.PINK)
	for sx in [-1.0, 0.0, 1.0]:
		draw_line(top + Vector2(sx * s * 1.1, 0), c + Vector2(sx * s * 0.25, -s * 0.3), INK, 1.2)
	_shape(PackedVector2Array([c + Vector2(-s * 0.4, s * 0.3), c + Vector2(-s * 0.2, -s * 0.3), c + Vector2(s * 0.2, -s * 0.3),
		c + Vector2(s * 0.4, s * 0.3)]), CwPalette.PAPER)


func _burst(c: Vector2, r_out: float, r_in: float, n: int, outer: Color, inner: Color) -> void:
	var pts := PackedVector2Array()
	for i in n * 2:
		var a := TAU * i / (n * 2.0)
		pts.append(c + Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	_shape(pts, outer)
	var pts2 := PackedVector2Array()
	for i in n * 2:
		var a := TAU * i / (n * 2.0) + 0.2
		pts2.append(c + Vector2(cos(a), sin(a)) * (r_out * 0.6 if i % 2 == 0 else r_in * 0.55))
	draw_colored_polygon(pts2, inner)


func _star(c: Vector2, r_out: float, r_in: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * i / 10.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r_out if i % 2 == 0 else r_in))
	_shape(pts, col, OUTLINE + 1.0)
	draw_circle(c + Vector2(-r_in * 0.3, -r_in * 0.1), r_in * 0.08, INK)
	draw_circle(c + Vector2(r_in * 0.3, -r_in * 0.1), r_in * 0.08, INK)
	draw_arc(c + Vector2(0, r_in * 0.1), r_in * 0.25, 0.2, PI - 0.2, 10, INK, 2.0)


func _debris(c: Vector2, u: float) -> void:
	var r := _rng()
	for i in 7:
		var a := r.randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * u * r.randf_range(0.36, 0.46)
		var s := u * r.randf_range(0.025, 0.05)
		draw_set_transform(p, a, Vector2.ONE)
		_rect(Rect2(-s, -s * 0.5, s * 2.0, s), CwPalette.PAPER if i % 2 == 0 else CwPalette.PEACH)
		draw_set_transform(Vector2.ZERO)
