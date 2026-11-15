class_name LegendProps
## Small helpers shared by the Lenda character scripts (src/npc/legends/<id>.gd): props held
## in a paw that stay upright (they follow the paw, not the arm's swing), and a few easing
## curves for the habits. Static only; the props themselves are authored in the scenes.


## Keeps `prop` (authored under a HandL / HandR node) at the paw but turned like the body:
## `rest` is the prop's transform as authored in the scene (relative to the paw, the arm at rest).
static func hold_upright(prop: Node3D, rest: Transform3D, hand: Node3D, body: Node3D, extra := Basis.IDENTITY) -> void:
	if prop == null or not prop.is_inside_tree():
		return
	var b := body.global_basis
	prop.global_transform = Transform3D(b * extra * rest.basis, hand.global_position + b * rest.origin)


## 0 -> 1 -> 0 over u in 0..1, with the rise in `a` and the fall in `b` (fractions of u).
static func env(u: float, a := 0.2, b := 0.2) -> float:
	return _sm(u / maxf(a, 0.001)) * _sm((1.0 - u) / maxf(b, 0.001))


static func _sm(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
