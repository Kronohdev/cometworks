class_name CwButtonMotion
extends Node
## Hover, press and focus motion for buttons. Drop it under one button (scope PARENT) or under
## a panel / screen with scope SUBTREE to give every button below `root` the same feel,
## copies of list templates included (they are picked up when they enter the tree).
##   hover / focus  -> lifts `lift` px, grows to `hover_scale`, brightens by `glow`
##   press          -> squashes to `press_scale`, springs back with a small overshoot
##   wiggle         -> a short damped rotation on hover (the left rail icons)
##   focus sweep    -> a bright stroke runs once around the focus ring when focus (or the
##                     mouse, with sweep_on_hover) arrives
## Everything happens on events (tweens), nothing runs while the button is idle. A button
## that has its own CwButtonMotion child, or the meta "cw_no_motion", is skipped by a
## SUBTREE one. Disabled buttons stay still.
## Sound (CwSfx, names from the sound library): a tick when a button lights up (hover or
## focus), a click on press (toggles: on / off; Back / Close keys: back), a soft "denied" when
## a disabled button is clicked. Empty names stay silent; a button's meta "cw_sfx_press"
## overrides its press sound.

enum Scope { PARENT, SUBTREE }

@export var scope := Scope.PARENT
## SUBTREE: where to look for buttons (empty = this node's parent)
@export var root: NodePath
@export_group("Hover")
@export var hover := true
## drawing offset on hover, px (negative y = up)
@export var lift := Vector2(0, -2)
@export var hover_scale := Vector2(1.02, 1.02)
## brightness multiplier on hover (1 = none)
@export_range(1.0, 1.6, 0.01) var glow := 1.1
@export_range(0.01, 1.0, 0.01) var hover_seconds := 0.12
## also react to keyboard focus (menus, dialogs)
@export var hover_on_focus := true
@export_group("Press")
@export var press := true
@export var press_scale := Vector2(1.03, 0.92)
@export_range(0.01, 0.5, 0.01) var press_seconds := 0.06
@export_range(0.05, 1.5, 0.01) var release_seconds := 0.32
@export_group("Wiggle")
## degrees of the hover wiggle (0 = none)
@export_range(0.0, 30.0, 0.5) var wiggle_degrees := 0.0
@export_range(0.1, 2.0, 0.01) var wiggle_seconds := 0.5
@export_range(0.5, 6.0, 0.5) var wiggle_count := 2.5
@export_group("Focus sweep")
@export var sweep_on_focus := false
@export var sweep_on_hover := false
@export var sweep_color := Color("#7652e8")
## corner radius the sweep follows (px); < 0 = half the height (a pill key)
@export var sweep_radius := -1.0
## px outside the button (the theme's focus ring sits 2 px out)
@export var sweep_offset := 2.0
@export_range(0.05, 0.6, 0.01) var sweep_length := 0.22
@export_range(0.1, 2.0, 0.01) var sweep_seconds := 0.5
@export_range(0.5, 4.0, 0.5) var sweep_width := 1.5
@export_group("Sound")
@export var hover_sound: StringName = &"ui_hover"
@export var press_sound: StringName = &"ui_click"
@export var toggle_on_sound: StringName = &"ui_toggle_on"
@export var toggle_off_sound: StringName = &"ui_toggle_off"
@export var back_sound: StringName = &"ui_back"
@export var denied_sound: StringName = &"ui_denied"
## buttons with these names press with back_sound
@export var back_names: PackedStringArray = ["Back", "Close", "Cancel", "Quit"]
@export_group("")
@export var pivot := Vector2(0.5, 0.5)


class State:
	extends RefCounted
	var hover_t: Tween
	var press_t: Tween
	var wiggle_t: Tween
	var sweep_t: Tween
	var sweep_rid := RID()
	var hovered := false
	var focused := false
	var lit := false
	var base_self := Color.WHITE


var _states := {}   # Control -> State


func _ready() -> void:
	if scope == Scope.PARENT:
		var c := get_parent() as Control
		if c:
			_attach(c)
		return
	var r := get_node_or_null(root) if not root.is_empty() else get_parent()
	if r == null:
		return
	_scan(r)
	r.child_entered_tree.connect(_on_added)


func _exit_tree() -> void:
	for st: State in _states.values():
		if st.sweep_rid.is_valid():
			RenderingServer.free_rid(st.sweep_rid)
			st.sweep_rid = RID()


func _scan(n: Node) -> void:
	for c in n.get_children():
		if not c is Control:
			continue   # 3D views, viewports and plain nodes hold no buttons of ours
		if _has_own_subtree(c):
			continue   # an instanced panel with its own CwButtonMotion (the options panel)
		if c is BaseButton:
			_attach(c as Control)
		_scan(c)
		if not c.child_entered_tree.is_connected(_on_added):
			c.child_entered_tree.connect(_on_added)


func _on_added(n: Node) -> void:
	# template copies come in whole: their buttons are ready a moment later (held weakly: a
	# list refresh can free the copy before then)
	var ref: WeakRef = weakref(n)
	(func() -> void:
		var n2 := ref.get_ref() as Node
		# (a screen moved out to play its exit re-enters the tree: it no longer processes)
		if n2 == null or not n2.is_inside_tree() or not n2 is Control or not is_inside_tree() or not can_process():
			return
		if n2 is BaseButton:
			_attach(n2 as Control)
		_scan(n2)).call_deferred()


func _attach(c: Control) -> void:
	if _states.has(c) or c.has_meta("cw_no_motion"):
		return
	if _states.size() > 64:
		for k: Variant in _states.keys():
			if not is_instance_valid(k):
				_states.erase(k)
	if scope == Scope.SUBTREE:
		for k in c.get_children():
			if k is CwButtonMotion:
				return
	var st := State.new()
	_states[c] = st
	CwMotion.set_pivot(c, pivot)
	c.mouse_entered.connect(_on_hover.bind(c, true))
	c.mouse_exited.connect(_on_hover.bind(c, false))
	c.focus_entered.connect(_on_focus.bind(c, true))
	c.focus_exited.connect(_on_focus.bind(c, false))
	if c is BaseButton:
		(c as BaseButton).button_down.connect(_on_down.bind(c))
		(c as BaseButton).button_up.connect(_on_up.bind(c))
		(c as BaseButton).pressed.connect(_press_sound.bind(c))
		c.gui_input.connect(_denied_input.bind(c))
	c.tree_exiting.connect(func() -> void:
		if st.sweep_rid.is_valid():
			RenderingServer.free_rid(st.sweep_rid)
			st.sweep_rid = RID())


func _has_own_subtree(n: Node) -> bool:
	for k in n.get_children():
		if k != self and k is CwButtonMotion and (k as CwButtonMotion).scope == Scope.SUBTREE:
			return true
	return false


static func _disabled(c: Control) -> bool:
	return c is BaseButton and (c as BaseButton).disabled


# ------------------------------------------------------------------ hover
func _on_hover(c: Control, on: bool) -> void:
	var st: State = _states.get(c)
	if st == null:
		return
	st.hovered = on
	_update_lit(c, st)
	if on and not _disabled(c):
		if wiggle_degrees > 0.0:
			_wiggle(c, st)
		if sweep_on_hover:
			_sweep(c, st)


func _on_focus(c: Control, on: bool) -> void:
	var st: State = _states.get(c)
	if st == null:
		return
	st.focused = on
	_update_lit(c, st)
	if on and sweep_on_focus and not _disabled(c):
		_sweep(c, st)


func _update_lit(c: Control, st: State) -> void:
	var want := hover and (st.hovered or (hover_on_focus and st.focused)) and not _disabled(c)
	if want == st.lit:
		return
	st.lit = want
	if st.hover_t:
		st.hover_t.kill()
	if want:
		st.base_self = c.self_modulate
		if hover_sound != &"":
			CwSfx.play(hover_sound)
	var reduced := CwMotion.reduced()
	st.hover_t = create_tween()
	st.hover_t.tween_method(_hover_at.bind(c, st, reduced), _hover_k(c), 1.0 if want else 0.0,
		hover_seconds if want else hover_seconds * 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _hover_k(c: Control) -> float:
	return float(c.get_meta(&"_cw_hover_k", 0.0))


func _hover_at(k: float, c: Control, st: State, reduced: bool) -> void:
	if not is_instance_valid(c):
		return
	c.set_meta(&"_cw_hover_k", k)
	if not reduced:
		CwMotion.set_channel(c, &"hover", lift * k, Vector2.ONE.lerp(hover_scale, k))
	var g := lerpf(1.0, glow, k)
	c.self_modulate = Color(st.base_self.r * g, st.base_self.g * g, st.base_self.b * g, st.base_self.a)


# ------------------------------------------------------------------ sound
func _press_sound(c: Control) -> void:
	var b := c as BaseButton
	var snd := press_sound
	if c.has_meta("cw_sfx_press"):
		snd = StringName(c.get_meta("cw_sfx_press"))
	elif b.toggle_mode:
		snd = toggle_on_sound if b.button_pressed else toggle_off_sound
	elif String(c.name) in back_names:
		snd = back_sound
	if snd != &"":
		CwSfx.play(snd)


func _denied_input(event: InputEvent, c: Control) -> void:
	if denied_sound == &"" or not _disabled(c):
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		CwSfx.play(denied_sound)


# ------------------------------------------------------------------ press
func _on_down(c: Control) -> void:
	var st: State = _states.get(c)
	if st == null or not press or _disabled(c) or CwMotion.reduced():
		return
	if st.press_t:
		st.press_t.kill()
	st.press_t = create_tween()
	st.press_t.tween_method(_press_at.bind(c), 0.0, 1.0, press_seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_up(c: Control) -> void:
	var st: State = _states.get(c)
	if st == null or not press or CwMotion.reduced():
		return
	if st.press_t:
		st.press_t.kill()
	var k := float(c.get_meta(&"_cw_press_k", 0.0))
	st.press_t = create_tween()
	st.press_t.tween_method(_press_at.bind(c), k, 0.0, release_seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _press_at(k: float, c: Control) -> void:
	if not is_instance_valid(c):
		return
	c.set_meta(&"_cw_press_k", k)
	CwMotion.set_channel(c, &"press", Vector2.ZERO, Vector2.ONE.lerp(press_scale, k))


# ------------------------------------------------------------------ wiggle
func _wiggle(c: Control, st: State) -> void:
	if CwMotion.reduced():
		return
	if st.wiggle_t and st.wiggle_t.is_running():
		return
	st.wiggle_t = create_tween()
	var ref: WeakRef = weakref(c)
	st.wiggle_t.tween_method(func(t: float) -> void:
		var c2 := ref.get_ref() as Control
		if c2:
			var a := deg_to_rad(wiggle_degrees) * sin(t * TAU * wiggle_count) * (1.0 - t) * (1.0 - t)
			CwMotion.set_channel(c2, &"wiggle", Vector2.ZERO, Vector2.ONE, a), 0.0, 1.0, wiggle_seconds)


# ------------------------------------------------------------------ focus sweep
func _sweep(c: Control, st: State) -> void:
	if CwMotion.reduced():
		return
	if not st.sweep_rid.is_valid():
		st.sweep_rid = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(st.sweep_rid, c.get_canvas_item())
	if st.sweep_t:
		st.sweep_t.kill()
	st.sweep_t = create_tween()
	st.sweep_t.tween_method(_sweep_at.bind(c, st), 0.0, 1.0, sweep_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _sweep_at(t: float, c: Control, st: State) -> void:
	if not is_instance_valid(c) or not st.sweep_rid.is_valid():
		return
	var rid := st.sweep_rid
	RenderingServer.canvas_item_clear(rid)
	if t >= 1.0:
		return
	var r := Rect2(Vector2.ZERO, c.size).grow(sweep_offset)
	var rad := minf(r.size.y * 0.5 if sweep_radius < 0.0 else sweep_radius + sweep_offset, minf(r.size.x, r.size.y) * 0.5)
	var per := 2.0 * (r.size.x + r.size.y) - 8.0 * rad + TAU * rad
	if per <= 0.0:
		return
	var head := t * (1.0 + sweep_length) * per
	var tail := head - sweep_length * per
	var fade := 1.0 - smoothstep(0.75, 1.0, t)
	var n := 14
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in n + 1:
		var d := lerpf(tail, head, float(i) / n)
		if d < 0.0 or d > per:
			continue
		pts.append(_perimeter_round(r, rad, d))
		cols.append(Color(sweep_color.lerp(Color.WHITE, 0.35 * float(i) / n), sweep_color.a * fade * float(i) / n))
	if pts.size() >= 2:
		RenderingServer.canvas_item_add_polyline(rid, pts, cols, sweep_width, true)


## Point at distance d along a rounded rectangle (corner radius k), clockwise from the start of
## the top edge.
static func _perimeter_round(r: Rect2, k: float, d: float) -> Vector2:
	if k <= 0.5:
		return _perimeter(r, d)
	var sx := r.size.x - 2.0 * k
	var sy := r.size.y - 2.0 * k
	var arc := PI * 0.5 * k
	var segs := [sx, arc, sy, arc, sx, arc, sy, arc]
	var i := 0
	while i < 8 and d > segs[i]:
		d -= segs[i]
		i += 1
	i = mini(i, 7)
	var tl := r.position + Vector2(k, k)
	var tr := Vector2(r.end.x - k, r.position.y + k)
	var br := r.end - Vector2(k, k)
	var bl := Vector2(r.position.x + k, r.end.y - k)
	match i:
		0: return Vector2(tl.x + d, r.position.y)
		1: return tr + Vector2(sin(d / k), -cos(d / k)) * k
		2: return Vector2(r.end.x, tr.y + d)
		3: return br + Vector2(cos(d / k), sin(d / k)) * k
		4: return Vector2(br.x - d, r.end.y)
		5: return bl + Vector2(-sin(d / k), cos(d / k)) * k
		6: return Vector2(r.position.x, bl.y - d)
	return tl + Vector2(-cos(d / k), -sin(d / k)) * k


## Point at distance d along the rectangle, clockwise from the top-left corner.
static func _perimeter(r: Rect2, d: float) -> Vector2:
	var w := r.size.x
	var h := r.size.y
	if d <= w:
		return r.position + Vector2(d, 0)
	d -= w
	if d <= h:
		return r.position + Vector2(w, d)
	d -= h
	if d <= w:
		return r.position + Vector2(w - d, h)
	d -= w
	return r.position + Vector2(0, h - minf(d, h))
