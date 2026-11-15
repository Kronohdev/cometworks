class_name CometlingStyle
extends RefCounted
## Optional personal looks of a Cometling (Cometling.style, a look dictionary), built as voxel
## meshes in the head's space, in the chunky voxel style of the hats (LeaderHat):
##   "hair"              "" (none, the default), "short", "messy", "mullet" or "medium"
##                       (medium-long, down to the shoulders)
##   "hair_color"        "#rrggbb"
##   "hair_part"         "center" (default) or "side": where a medium fringe parts
##   "streak"            "#rrggbb": a lock of another colour at the front (none when absent)
##   "facial_hair"       ["moustache", "goatee", "chin_beard"] (any of them, symmetric: a thin
##                       moustache, fuller with a goatee that it joins; a full goatee; a small
##                       chin patch)
##   "facial_hair_color" "#rrggbb" (the hair colour when absent)
##   "eyes"              "#rrggbb": the iris colour (the species' violet when absent)
##   "glasses"           "#rrggbb": thin metal-frame glasses of that colour (none when absent)
##   "headphones"        "#rrggbb": headphones resting around the neck (none when absent)
##   "headphones_accent" "#rrggbb": the cups' centres (a lighter shade when absent)
## An empty dictionary adds nothing, so every existing Cometling stays as it was. The parts are
## children of Rig/Hips/Neck (named Style*, so they bob, tilt and squash with the head; the
## headphones ride on Rig/Hips) and use the Cometling's own skin material with fixed vertex
## colours. Built meshes are cached per look, so a crowd of the same look shares them.
## The hair's crown (StyleHairTop) hides while a hat, helmet or hard hat is on (headgear()).

const PREFIX := "Style"
const HAIR_STYLES: Array[String] = ["short", "messy", "mullet", "medium"]
const FACIAL_HAIR: Array[String] = ["moustache", "goatee", "chin_beard"]
const SKIN := "res://scenes/npc/creature_material.tres"

# head of scenes/npc/creature.tscn in the Neck pivot's space (tools/creature_gen.py)
const HEAD_C := Vector3(0.0, 0.255, 0.0)
const HEAD_R := Vector3(0.300, 0.265, 0.275)
const HEAD_P := 2.4
const EYE := Vector2(0.116, 0.232)
const EAR := Vector3(0.235, 0.395, -0.03)
const ANTENNA := Vector3(0.0, 0.505, 0.02)
## hair above this height is the crown a hat replaces
const CROWN_Y := 0.36

const HAIR_VOX := 0.024
const FACE_VOX := 0.0125
const GLASS_VOX := 0.0095
const PHONES_VOX := 0.016

static var _cache: Dictionary = {}


## True when `style` asks for anything at all.
static func is_styled(style: Dictionary) -> bool:
	for k in ["hair", "facial_hair", "eyes", "glasses", "headphones"]:
		var v: Variant = style.get(k, "")
		if (v is String and v != "") or (v is Array and not (v as Array).is_empty()) \
				or (v is PackedStringArray and not (v as PackedStringArray).is_empty()):
			return true
	return false


## (Re)builds the parts of `style` on Cometling `c` (removes the old ones first).
static func apply(c: Node3D, style: Dictionary) -> void:
	var neck := c.get_node_or_null("Rig/Hips/Neck") as Node3D
	var hips := c.get_node_or_null("Rig/Hips") as Node3D
	if neck == null or hips == null:
		return
	for parent: Node3D in [neck, hips]:
		for n in parent.get_children():
			if String(n.name).begins_with(PREFIX):
				parent.remove_child(n)
				n.queue_free()
	_set_iris(c, String(style.get("eyes", "")))
	if not is_styled(style):
		return
	var cull := float(c.get("cull_distance")) if "cull_distance" in c else 170.0
	var hair := String(style.get("hair", ""))
	if hair in HAIR_STYLES:
		var meshes := _cached("hair", style, func() -> Array: return _build_hair(style))
		_add(neck, "StyleHair", meshes[0], cull)
		_add(neck, "StyleHairTop", meshes[1], cull)
	var fh := _facial_list(style)
	if not fh.is_empty():
		_add(neck, "StyleFacialHair", _cached("face", style, func() -> Array: return [_build_facial(style, fh)])[0], cull)
	if String(style.get("glasses", "")) != "":
		_add(neck, "StyleGlasses", _cached("glasses", style, func() -> Array: return [_build_glasses(style)])[0], cull)
	if String(style.get("headphones", "")) != "":
		_add(hips, "StyleHeadphones", _cached("phones", style, func() -> Array: return [_build_phones(style)])[0], cull)
	headgear(c)


## Hides the hair's crown while a hat (LeaderHat), a helmet or a hard hat covers the head.
static func headgear(c: Node3D) -> void:
	var neck := c.get_node_or_null("Rig/Hips/Neck") as Node3D
	if neck == null:
		return
	var top := neck.get_node_or_null("StyleHairTop") as Node3D
	if top == null:
		return
	var covered := false
	for n in ["Helmet", "HardHat"]:
		var g := neck.get_node_or_null(n) as Node3D
		if g and g.visible:
			covered = true
	var hat := neck.get_node_or_null("LeaderHat") as Node3D
	if hat and hat.visible and String(hat.get("hat")) not in ["none", "role", ""]:
		covered = true
	top.visible = not covered


static func _facial_list(style: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var v: Variant = style.get("facial_hair", [])
	var list: Array = []
	if v is String:
		list = (v as String).split(",", false)
	elif v is Array or v is PackedStringArray:
		list = Array(v)
	for s in list:
		var k := String(s).strip_edges()
		if k in FACIAL_HAIR and not k in out:
			out.append(k)
	return out


static func _cached(part: String, style: Dictionary, build: Callable) -> Array:
	var key := part + ":" + JSON.stringify(style, "", true)
	if not _cache.has(key):
		_cache[key] = build.call()
	return _cache[key]


static func _add(parent: Node3D, node_name: String, mesh: Mesh, cull: float) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = load(SKIN) as Material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = cull
	mi.visibility_range_end_margin = 4.0
	parent.add_child(mi)


# ------------------------------------------------------------------ shapes
## Normalised radius of the head grown by `g` (1 = on that surface).
static func head_f(p: Vector3, g: float) -> float:
	var d := p - HEAD_C
	return pow(pow(absf(d.x) / (HEAD_R.x + g), HEAD_P) + pow(absf(d.y) / (HEAD_R.y + g), HEAD_P)
		+ pow(absf(d.z) / (HEAD_R.z + g), HEAD_P), 1.0 / HEAD_P)


## Like head_f, but below the head's middle the shape goes straight down (hanging hair).
static func drape_f(p: Vector3, g: float) -> float:
	return head_f(Vector3(p.x, maxf(p.y, HEAD_C.y), p.z), g)


## Front surface of the head (z) at (x, y).
static func face_z(x: float, y: float) -> float:
	var u := pow(absf(x) / HEAD_R.x, HEAD_P) + pow(absf(y - HEAD_C.y) / HEAD_R.y, HEAD_P)
	return HEAD_C.z + HEAD_R.z * pow(maxf(1.0 - u, 0.0), 1.0 / HEAD_P)


static func _hash(i: Vector3i, salt: int) -> float:
	var h := hash(Vector4i(i.x, i.y, i.z, salt))
	return float(absi(h) % 10007) / 10007.0


static func _qbez(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)


## Inside the root of a tail-ear or around the antenna stalk (hair leaves room there).
static func _in_ear_or_antenna(p: Vector3) -> bool:
	if Vector2(p.x - ANTENNA.x, p.z - ANTENNA.z).length() < 0.034 and p.y > ANTENNA.y - 0.12:
		return true
	for s: float in [1.0, -1.0]:
		var a := Vector3(EAR.x * s - s * 0.04, EAR.y - 0.01, EAR.z + 0.01)
		var b := Vector3(EAR.x * s + s * 0.15, EAR.y + 0.10, EAR.z - 0.12)
		var c := Vector3(EAR.x * s + s * 0.16, EAR.y - 0.17, EAR.z - 0.42)
		for k in 6:
			var q := _qbez(a, b, c, k * 0.06)
			var d := p - q
			if (d.x / 0.9) ** 2 + (d.y / 0.8) ** 2 + d.z ** 2 < 0.088 ** 2:
				return true
	return false


# ------------------------------------------------------------------ hair
static func _build_hair(style: Dictionary) -> Array:
	var kind := String(style.get("hair", "short"))
	var base := Color(String(style.get("hair_color", "#5a3a22")))
	var streak_s := String(style.get("streak", ""))
	var streak := Color(streak_s) if streak_s != "" else Color(0, 0, 0, 0)
	var side_part := String(style.get("hair_part", "center")) == "side"
	var v := HAIR_VOX
	var vox := {}
	var lo := Vector3i(floori(-0.42 / v), floori(-0.16 / v), floori(-0.44 / v))
	var hi := Vector3i(ceili(0.42 / v), ceili(0.64 / v), ceili(0.42 / v))
	for ix in range(lo.x, hi.x + 1):
		for iy in range(lo.y, hi.y + 1):
			for iz in range(lo.z, hi.z + 1):
				var key := Vector3i(ix, iy, iz)
				var p := (Vector3(key) + Vector3(0.5, 0.5, 0.5)) * v
				if p.y > 0.66:
					continue
				# cheap ellipsoid tests first (the head's super-ellipsoid lies between an
				# ellipsoid and the same one 1.1x larger): far outside any hair, or inside the head
				var d := p - HEAD_C
				var dd := Vector3(d.x, maxf(d.y, 0.0), d.z)
				if (dd / (HEAD_R + Vector3.ONE * 0.13)).length_squared() > 1.21:
					continue
				if (d / (HEAD_R - Vector3.ONE * 0.004)).length_squared() < 1.0:
					continue
				if head_f(p, -0.004) <= 1.0:
					continue   # inside the head
				if not _hair_at(kind, p, key, side_part):
					continue
				if _in_ear_or_antenna(p):
					continue
				vox[key] = _hair_shade(base, p, key)
	# the streak: one lock framing the face on the Cometling's left (+x), front to the tips
	if streak.a > 0.0:
		for key: Vector3i in vox:
			var p := (Vector3(key) + Vector3(0.5, 0.5, 0.5)) * v
			var xc := lerpf(0.10, 0.27, clampf((0.47 - p.y) / 0.25, 0.0, 1.0))
			if absf(p.x - xc) < 0.05 and p.z > 0.04:
				vox[key] = _hair_shade(streak, p, key)
	var low := {}
	var top := {}
	for key: Vector3i in vox:
		var y := (key.y + 0.5) * v
		if y > CROWN_Y:
			top[key] = vox[key]
		else:
			low[key] = vox[key]
	return [_mesh(low, v, vox), _mesh(top, v, vox)]


## Darker underneath, a soft shine across the crown and a little per-voxel grain.
static func _hair_shade(base: Color, p: Vector3, key: Vector3i) -> Color:
	var c := base
	var t := clampf((p.y + 0.1) / 0.62, 0.0, 1.0)
	c = c.darkened(0.22 * (1.0 - t))
	var shine := exp(-pow((p.y - 0.47) / 0.035, 2.0)) * clampf(p.z / 0.2 + 0.5, 0.0, 1.0)
	c = c.lerp(Color(1, 1, 1), 0.16 * shine)
	var j := (_hash(key, 7) - 0.5) * 0.08
	c = c.lightened(j) if j > 0.0 else c.darkened(-j)
	return c


## Is hair at point `p` for style `kind`? (a shell over the head of varying height and depth)
static func _hair_at(kind: String, p: Vector3, key: Vector3i, side_part: bool) -> bool:
	var a := atan2(p.x, p.z)            # 0 front, +-PI back
	var front := cos(a)
	var aa := absf(a)
	match kind:
		"short":
			var line := 0.27 + 0.135 * front
			if p.y < line:
				return false
			return head_f(p, 0.038) <= 1.0
		"messy":
			var line := 0.27 + 0.13 * front
			if aa < 0.75:   # strands of fringe falling onto the forehead
				var col := floori(p.x / 0.03)
				line = 0.345 + 0.05 * _hash(Vector3i(col, 0, 0), 3) + 0.06 * (aa / 0.75) ** 2
			if p.y < line:
				return false
			var g := 0.04
			if p.y > 0.4:   # tufts sticking up and out
				var cell := Vector3i(floori(p.x / 0.05), 0, floori(p.z / 0.05))
				g += 0.045 * _hash(cell, 11) * clampf((p.y - 0.4) / 0.1, 0.0, 1.0)
			return head_f(p, g) <= 1.0
		"mullet":
			# short curly top and sides, long at the back down past the head
			var line := 0.33 + 0.07 * front
			if aa < 0.6:
				var col := floori(p.x / 0.045)
				line = 0.365 + 0.045 * _hash(Vector3i(col, 1, 0), 5)   # curls falling on the forehead
			# the long back flares past the jaw, so it shows from the front too
			var back := aa > 1.95 and absf(p.x) < 0.29
			if back:
				line = -0.085 + 0.05 * _hash(Vector3i(floori(p.x / 0.05), 2, 0), 7)
			elif aa > 1.75:   # blend the sides into the back
				line = minf(line, 0.30 - 0.25 * (aa - 1.75) / 0.3)
			if p.y < line:
				return false
			# curls: a bumpy surface on top, the back flares out a little at the bottom
			var cell := Vector3i(floori(p.x / 0.06), floori(p.y / 0.06), floori(p.z / 0.06))
			var g := 0.034 + 0.05 * _hash(cell, 13) * clampf((p.y - 0.3) / 0.15, 0.0, 1.0)
			if back:
				g = 0.036 + 0.075 * clampf((0.16 - p.y) / 0.24, 0.0, 1.0) + 0.012 * _hash(cell, 17)
				return drape_f(p, g) <= 1.0
			return head_f(p, g) <= 1.0
		"medium":
			# fringe framing the forehead, long curtains at the sides and back to the shoulders
			var bottom := -0.10 + 0.02 * _hash(Vector3i(floori(a / 0.25), 0, 0), 19)
			var line := bottom
			if aa < 0.95:
				# the face stays clear: a fringe on the forehead...
				var part := (a + 0.12) if side_part else a
				var fringe := 0.40 + 0.06 * exp(-pow(part / 0.16, 2.0))
				if side_part:
					fringe -= 0.05 * clampf(-a / 0.6, 0.0, 1.0)   # swept over one side
				# ...that opens into the curtains past the eyes
				var open := clampf((aa - 0.72) / 0.23, 0.0, 1.0)
				line = lerpf(fringe, bottom, open)
			if p.y < line:
				return false
			var g := 0.036 + 0.012 * clampf((0.2 - p.y) / 0.3, 0.0, 1.0)
			if p.y < HEAD_C.y and aa < 0.95 and p.z > 0.0:
				# curtains hang beside the cheeks, not over the face
				if absf(p.x) < HEAD_R.x - 0.01:
					return false
			return drape_f(p, g) <= 1.0 and drape_f(p, -0.004) > 1.0
	return false


# ------------------------------------------------------------------ facial hair
static func _build_facial(style: Dictionary, kinds: Array[String]) -> Mesh:
	var col := Color(String(style.get("facial_hair_color", style.get("hair_color", "#3a2a20"))))
	var v := FACE_VOX
	var vox := {}
	for ix in range(floori(-0.2 / v), ceili(0.2 / v) + 1):
		for iy in range(floori(-0.02 / v), ceili(0.21 / v) + 1):
			var x := (ix + 0.5) * v
			var y := (iy + 0.5) * v
			var keep := false
			var ax := absf(x)
			var full := "goatee" in kinds   # a goatee makes the moustache fuller to join it
			if "moustache" in kinds:
				# a tidy line above the mouth, the ends a little lower (thicker with a goatee)
				var my := 0.181 - 0.012 * clampf((ax - 0.022) / 0.03, 0.0, 1.0)
				var half := 0.0135 if full else 0.0085
				if ax < (0.06 if full else 0.054) and absf(y - my) < half:
					keep = true
			if "goatee" in kinds:
				# a full chin goatee: a rounded block under the lip...
				var w := lerpf(0.05, 0.026, clampf((0.112 - y) / 0.07, 0.0, 1.0))
				if y > 0.04 and y < 0.118 and ax < w:
					keep = true
				if y >= 0.118 and y < 0.132 and ax < 0.016:
					keep = true   # the patch right under the lip
				# ...joined to the moustache by lines down the mouth's corners
				if y > 0.1 and y < 0.18 and absf(ax - 0.054) < 0.0105:
					keep = true
			if "chin_beard" in kinds and not keep:
				# a neat little chin patch just under the mouth, clean rounded edges
				var cw := lerpf(0.036, 0.018, clampf((0.112 - y) / 0.05, 0.0, 1.0))
				if y > 0.062 and y < 0.118 and ax < cw:
					keep = true
				if y >= 0.118 and y < 0.128 and ax < 0.011:
					keep = true
			if not keep:
				continue
			var z := face_z(x, y)
			if z < 0.05:
				continue
			# grain mirrored across the face, so both sides match
			var mirror := Vector3i(ix if ix >= 0 else -ix - 1, iy, 0)
			var iz := roundi(z / v + 0.6)
			vox[Vector3i(ix, iy, iz)] = col.lightened((_hash(mirror, 29) - 0.5) * 0.1)
			vox[Vector3i(ix, iy, iz - 1)] = col
	return _mesh(vox, v, vox)


# ------------------------------------------------------------------ glasses and headphones
static func _build_glasses(style: Dictionary) -> Mesh:
	var col := Color(String(style.get("glasses", "#b9bfcc")))
	var v := GLASS_VOX
	var vox := {}
	var r := Vector2(0.084, 0.094)
	for ix in range(floori(-0.32 / v), ceili(0.32 / v) + 1):
		for iy in range(floori(0.12 / v), ceili(0.34 / v) + 1):
			var x := (ix + 0.5) * v
			var y := (iy + 0.5) * v
			var on := false
			for s: float in [1.0, -1.0]:
				var e := Vector2((x - EYE.x * s) / r.x, (y - EYE.y) / r.y)
				var d := e.length()
				var t := v * 1.15 / minf(r.x, r.y)
				if absf(d - 1.0) < t:
					on = true
			if absf(x) < 0.036 and absf(y - 0.27) < v * 0.8:
				on = true   # the bridge
			if not on:
				continue
			var z := face_z(x, y) + 0.03
			vox[Vector3i(ix, iy, roundi(z / v))] = col
	# the arms run back along the sides of the head to the ears
	for iz in range(floori(-0.04 / v), ceili(0.2 / v)):
		var z := (iz + 0.5) * v
		var iy := roundi(0.255 / v)
		for s: float in [1.0, -1.0]:
			# x on the head's side at (y, z), a little outside
			var dz := pow(absf(z - HEAD_C.z) / (HEAD_R.z + 0.02), HEAD_P)
			var dy := pow(absf(0.255 - HEAD_C.y) / (HEAD_R.y + 0.02), HEAD_P)
			var x := (HEAD_R.x + 0.02) * pow(maxf(1.0 - dz - dy, 0.0), 1.0 / HEAD_P)
			if x < 0.18:
				continue
			vox[Vector3i(roundi(x * s / v), iy, iz)] = col.darkened(0.12)
	return _mesh(vox, v, vox)


static func _build_phones(style: Dictionary) -> Mesh:
	var col := Color(String(style.get("headphones", "#2b2d3a")))
	var accent := Color(String(style.get("headphones_accent", ""))) if style.has("headphones_accent") 		else col.lightened(0.45)
	var v := PHONES_VOX
	var vox := {}
	var y0 := 0.295   # Hips space: just under the head, around the neck
	for ix in range(floori(-0.24 / v), ceili(0.24 / v) + 1):
		for iy in range(floori(0.2 / v), ceili(0.36 / v) + 1):
			for iz in range(floori(-0.22 / v), ceili(0.2 / v) + 1):
				var p := (Vector3(ix, iy, iz) + Vector3(0.5, 0.5, 0.5)) * v
				# the band: an arc behind the neck
				var e := Vector2(p.x / 0.17, (p.z + 0.005) / 0.16).length()
				if absf(e - 1.0) < 0.1 and absf(p.y - (y0 + 0.012)) < 0.014 and p.z < 0.11:
					vox[Vector3i(ix, iy, iz)] = col
					continue
				# the cups resting on the chest under the chin, facing forward
				for s: float in [1.0, -1.0]:
					var q := p - Vector3(0.125 * s, y0 - 0.035, 0.125)
					var rr := Vector2(q.x / 0.06, q.y / 0.06).length()
					if absf(q.z) < 0.03 and rr <= 1.0:
						var outer := q.z > 0.012
						vox[Vector3i(ix, iy, iz)] = accent if outer and rr < 0.55 else col
	return _mesh(vox, v, vox)


# ------------------------------------------------------------------ eyes
## Recolours the irises of the eye meshes (the violet ones of the species); "" restores them.
static func _set_iris(c: Node3D, hex: String) -> void:
	for side in ["EyeL", "EyeR"]:
		var eye := c.get_node_or_null("Rig/Hips/Neck/" + side) as Node3D
		if eye == null:
			continue
		for mi in eye.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if not m.has_meta("style_iris_orig"):
				if hex == "":
					continue
				m.set_meta("style_iris_orig", m.mesh)
			var orig := m.get_meta("style_iris_orig") as Mesh
			if hex == "":
				m.mesh = orig
				continue
			m.mesh = _cached("iris:" + str(orig.get_rid().get_id()), {"eyes": hex},
				func() -> Array: return [_recolor_iris(orig, Color(hex))])[0]


## A copy of an eye mesh with its iris shades (the bright, blue-violet ones) in `iris`.
static func _recolor_iris(orig: Mesh, iris: Color) -> Mesh:
	var out := ArrayMesh.new()
	var lin := iris.srgb_to_linear()
	var lin_hi := iris.lightened(0.35).srgb_to_linear()
	for s in orig.get_surface_count():
		var arrays := orig.surface_get_arrays(s)
		var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		for i in cols.size():
			var k := cols[i]
			var bright := maxf(k.r, maxf(k.g, k.b))
			# violet iris: blue well above red and green, brighter than the ink, not the white sparkle
			if k.b > k.r * 1.5 and k.b > k.g * 1.5 and bright > 0.08 and k.r < 0.6:
				var hi := k.b > 0.35
				cols[i] = Color(lin_hi.r, lin_hi.g, lin_hi.b, k.a) if hi else Color(lin.r, lin.g, lin.b, k.a)
		if not cols.is_empty():
			arrays[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(orig.surface_get_primitive_type(s), arrays)
		var mat := orig.surface_get_material(s)
		if mat:
			out.surface_set_material(s, mat)
	return out


# ------------------------------------------------------------------ meshing
const _DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]


## One cube per voxel of `vox` ({Vector3i: Color}, sRGB), only the faces not touching another
## voxel of `solid`; vertex colours in linear with alpha 0 (a fixed colour for the skin shader).
static func _mesh(vox: Dictionary, v: float, solid: Dictionary) -> ArrayMesh:
	if vox.is_empty():
		return null
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for key: Vector3i in vox:
		var c: Color = (vox[key] as Color).srgb_to_linear()
		c.a = 0.0
		var o := Vector3(key) * v
		for d in _DIRS:
			if solid.has(key + d):
				continue
			var n := Vector3(d)
			# the face's four corners, counter-clockwise seen from outside
			var u := Vector3(absf(n.z), absf(n.x), absf(n.y))   # a side of the face
			var w := n.cross(u)
			var centre := o + Vector3(0.5, 0.5, 0.5) * v + n * (0.5 * v)
			var a := centre + (-u - w) * (0.5 * v)
			var b := centre + (u - w) * (0.5 * v)
			var cc := centre + (u + w) * (0.5 * v)
			var dd := centre + (-u + w) * (0.5 * v)
			var base := pos.size()
			pos.append_array([a, b, cc, dd])
			for i in 4:
				nrm.append(n)
				col.append(c)
			# Godot's front faces wind clockwise
			if (b - a).cross(cc - a).dot(n) > 0.0:
				idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
			else:
				idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
