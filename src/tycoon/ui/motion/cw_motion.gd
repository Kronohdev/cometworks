class_name CwMotion
extends RefCounted
## Shared core of the Cometworks UI motion components (src/tycoon/ui/motion/). Each
## component is a node dropped into a scene next to the Control it moves, tuned with its
## exports; this file only holds what they share:
##
## * Visual channels. A component never moves a Control's layout (containers own position,
##   size and scale and would snap it back, and moving the hit area makes hover flicker).
##   It writes its own channel (offset px, scale, rotation, alpha) and the Control is drawn
##   with every channel combined through RenderingServer, on top of its real transform and
##   modulate. Channels survive relayouts and redraws (re-applied on `draw` and on
##   `item_rect_changed`), so a hover lift and an entrance slide on the same button compose.
## * Reduce motion (MenuSettings, user://settings.cfg): components keep short fades only.
## * poke(): event hook for scripts ("this label just changed"), so motion stays event-driven.

const META := &"_cw_vis"

static var _reduced := -1   # -1 = not read yet


## True when the player asked for reduced motion (options panel).
static func reduced() -> bool:
	if _reduced < 0:
		_reduced = 1 if MenuSettings.reduce_motion() else 0
	return _reduced == 1


static func set_reduced(on: bool) -> void:
	_reduced = 1 if on else 0


## Lets the motion children of `target` react to an event (CwAppear / CwPulse with on_poke).
static func poke(target: Node) -> void:
	if target == null:
		return
	for n in target.get_children():
		if n.has_method("_cw_poke"):
			n.call("_cw_poke")


## The first child of `target` with the given script class (e.g. CwScreenTransition).
static func child_of_type(target: Node, type: Script) -> Node:
	if target == null:
		return null
	for n in target.get_children():
		if is_instance_of(n, type):
			return n
	return null


# ------------------------------------------------------------------ visual channels
class Vis:
	extends RefCounted
	var channels := {}             # StringName -> [offset: Vector2, scale: Vector2, rot: float, alpha: float]
	var pivot := Vector2(0.5, 0.5) # fraction of the control's size
	var alpha_on := false          # an alpha channel below 1 is being pushed
	var queued := false
	var id := 0                    # the control it belongs to (duplicate() copies metas)


static func _vis(c: Control) -> Vis:
	if c.has_meta(META):
		var old := c.get_meta(META) as Vis
		if old and old.id == c.get_instance_id():
			return old
	var v := Vis.new()
	v.id = c.get_instance_id()
	c.set_meta(META, v)
	# the engine re-sends the control's own transform when it redraws or moves
	c.draw.connect(_redrawn.bind(c))
	c.item_rect_changed.connect(_queue.bind(c))
	c.visibility_changed.connect(_queue.bind(c))
	return v


## Sets one channel of the control's drawing (identity values remove it).
static func set_channel(c: Control, key: StringName, offset := Vector2.ZERO, scale := Vector2.ONE,
		rot := 0.0, alpha := 1.0) -> void:
	if c == null or not is_instance_valid(c):
		return
	var v := _vis(c)
	if offset == Vector2.ZERO and scale == Vector2.ONE and rot == 0.0 and alpha >= 1.0:
		if not v.channels.has(key):
			return
		v.channels.erase(key)
	else:
		v.channels[key] = [offset, scale, rot, alpha]
	_apply(c)


static func clear_channel(c: Control, key: StringName) -> void:
	set_channel(c, key)


static func set_pivot(c: Control, frac: Vector2) -> void:
	_vis(c).pivot = frac


static func _redrawn(c: Control) -> void:
	if is_instance_valid(c) and c.has_meta(META) and not (c.get_meta(META) as Vis).channels.is_empty():
		_apply(c)


static func _queue(c: Control) -> void:
	if not is_instance_valid(c) or not c.has_meta(META):
		return
	var v := c.get_meta(META) as Vis
	if v.channels.is_empty() or v.queued:
		return
	v.queued = true
	_apply_queued.call_deferred(c)


static func _apply_queued(c: Control) -> void:
	if is_instance_valid(c) and c.has_meta(META):
		(c.get_meta(META) as Vis).queued = false
		_apply(c)


static func _apply(c: Control) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree() or not c.has_meta(META):
		return
	var v := c.get_meta(META) as Vis
	var off := Vector2.ZERO
	var sc := Vector2.ONE
	var rot := 0.0
	var a := 1.0
	for ch: Array in v.channels.values():
		off += ch[0]
		sc *= ch[1]
		rot += ch[2]
		a *= ch[3]
	var t := c.get_transform()
	if off != Vector2.ZERO or sc != Vector2.ONE or rot != 0.0:
		var piv := c.size * v.pivot
		var local := Transform2D(rot, sc, 0.0, Vector2.ZERO)
		local.origin = piv - local.basis_xform(piv)
		t = t * local
		t.origin += off
	RenderingServer.canvas_item_set_transform(c.get_canvas_item(), t)
	if a < 1.0 or v.alpha_on:
		var m := c.modulate
		RenderingServer.canvas_item_set_modulate(c.get_canvas_item(), Color(m, m.a * clampf(a, 0.0, 1.0)))
		v.alpha_on = a < 1.0


# ------------------------------------------------------------------ helpers for components
## Tween.TransitionType from the components' easing presets.
enum Feel { SMOOTH, SNAPPY, OVERSHOOT, SPRING, LINEAR }


static func shape(tw: Tweener, curve: Feel, ease_in := false) -> Tweener:
	var pt := tw as PropertyTweener
	var mt := tw as MethodTweener
	var trans := Tween.TRANS_CUBIC
	match curve:
		Feel.SNAPPY:
			trans = Tween.TRANS_QUART
		Feel.OVERSHOOT:
			trans = Tween.TRANS_BACK
		Feel.SPRING:
			trans = Tween.TRANS_ELASTIC
		Feel.LINEAR:
			trans = Tween.TRANS_LINEAR
	var e := Tween.EASE_IN if ease_in else Tween.EASE_OUT
	if pt:
		pt.set_trans(trans).set_ease(e)
	elif mt:
		mt.set_trans(trans).set_ease(e)
	return tw


## The Control a component drives: `path` if set, else the component's parent.
static func resolve(owner_node: Node, path: NodePath) -> Control:
	if not path.is_empty():
		return owner_node.get_node_or_null(path) as Control
	return owner_node.get_parent() as Control
