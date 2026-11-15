class_name CwUiFit
extends RefCounted
## Keeps the big layout blocks on screen at any text size (CwAccess: the root's
## content_scale_factor). The layouts are drawn for a logical view of at least 1600x900; at
## 115 / 130 % the view is smaller (1391x783 / 1231x692), so a block that no longer fits its
## region (the view, or the room a docked screen has between the HUD's top bar and rail) is
## scaled down around its anchor until it does and moved inside it; one that fits is left as
## authored. Blocks are anchored Controls whose parent is not a Container (a screen's Panel,
## Frame or Layout, the HUD's top bar, rail and side column, the menu card). A block anchored
## to fill its parent keeps filling the region: it gets the size region / scale.
## fit() is cheap and idempotent (the authored offsets are kept in metadata and put back
## first), so hosts call it again whenever the view or the block changes size (watch()).

const META := &"_cw_fit_offsets"
const LAST := &"_cw_fit_last"
const MARGIN := 6.0
## children of a screen that are its backdrop (they may span the whole view)
const BACKDROPS: Array[String] = ["Scrim", "Shade", "Backdrop", "Sky", "Comet", "View", "Fade"]


## Scales and moves `c` so it lies inside `region` (global, logical px), or puts it back as
## authored when it fits.
static func fit(c: Control, region: Rect2) -> void:
	if c == null or not is_instance_valid(c) or not c.is_inside_tree() or c.get_parent() is Container:
		return
	_restore(c)
	var own := c.get_global_rect()
	# a plain Control may hold children larger than itself (the newspaper's page): fit them all
	var r := own
	if not c is Container:
		for ch in c.get_children():
			if ch is Control and (ch as Control).visible and not (ch as Control).top_level:
				r = r.merge((ch as Control).get_global_rect())
	if region.size.x <= 1.0 or region.size.y <= 1.0 or region.grow(0.5).encloses(r):
		return
	var parent_size := (c.get_parent() as Control).size if c.get_parent() is Control else c.get_viewport_rect().size
	var fills_x := is_equal_approx(c.anchor_left, 0.0) and is_equal_approx(c.anchor_right, 1.0)
	var fills_y := is_equal_approx(c.anchor_top, 0.0) and is_equal_approx(c.anchor_bottom, 1.0)
	var need := c.get_combined_minimum_size()
	var cur := Vector2(need.x if fills_x else r.size.x, need.y if fills_y else r.size.y)
	var s := minf(1.0, minf(region.size.x / maxf(cur.x, 1.0), region.size.y / maxf(cur.y, 1.0)))
	# a filling block gets a new width, and wrapped text makes its minimum size depend on it:
	# within one region its scale only ever shrinks, so the fit settles instead of swinging
	if fills_x or fills_y:
		var last: Array = c.get_meta(LAST, [])
		if not last.is_empty() and (last[0] as Rect2).is_equal_approx(region):
			s = minf(s, float(last[1]))
		c.set_meta(LAST, [region, s])
	c.set_meta(META, [c.offset_left, c.offset_top, c.offset_right, c.offset_bottom])
	c.pivot_offset = Vector2.ZERO
	c.scale = Vector2(s, s)
	# the unscaled size: a filling block takes the whole region (in unscaled px), others keep theirs
	var size := Vector2(region.size.x / s if fills_x else own.size.x, region.size.y / s if fills_y else own.size.y)
	# where the scaled content lands with the block's corner kept, then the shift into the region
	var shown_pos := own.position + (r.position - own.position) * s
	var shown := r.size * s
	var want := r.get_center() - shown * 0.5
	want = Vector2(clampf(want.x, region.position.x, region.end.x - shown.x),
		clampf(want.y, region.position.y, region.end.y - shown.y))
	var pos := own.position + (want - shown_pos)
	if fills_x:
		pos.x = region.position.x
	if fills_y:
		pos.y = region.position.y
	var origin := (c.get_parent() as CanvasItem).get_global_transform().affine_inverse() * pos 		if c.get_parent() is CanvasItem else pos
	c.offset_left = origin.x - c.anchor_left * parent_size.x
	c.offset_top = origin.y - c.anchor_top * parent_size.y
	c.offset_right = origin.x + size.x - c.anchor_right * parent_size.x
	c.offset_bottom = origin.y + size.y - c.anchor_bottom * parent_size.y


## Puts `c` back as authored (scale 1, its own offsets).
static func _restore(c: Control) -> void:
	if not c.has_meta(META):
		return
	var o: Array = c.get_meta(META)
	c.remove_meta(META)
	c.scale = Vector2.ONE
	c.offset_left = o[0]
	c.offset_top = o[1]
	c.offset_right = o[2]
	c.offset_bottom = o[3]


## Whether `c` was scaled down to fit.
static func is_fitted(c: Control) -> bool:
	return c != null and c.has_meta(META)


## The view of `c`'s viewport, `MARGIN` px in.
static func view_of(c: Control) -> Rect2:
	return c.get_viewport_rect().grow(-MARGIN)


## Fits every block of a screen (its direct children but the backdrops) into `region`.
static func fit_screen(scr: Control, region: Rect2) -> void:
	if scr == null or not is_instance_valid(scr) or not scr.is_inside_tree():
		return
	for c in scr.get_children():
		if c is Control and (c as Control).visible and String(c.name) not in BACKDROPS:
			fit(c as Control, region)


## Calls `refit` (deferred, once per frame at most) whenever one of `blocks` changes its size
## or minimum size, or the view changes.
static func watch(blocks: Array, refit: Callable) -> void:
	for b in blocks:
		var c := b as Control
		if c == null or c.has_meta(&"_cw_fit_watch"):
			continue
		c.set_meta(&"_cw_fit_watch", true)
		c.minimum_size_changed.connect(_queue.bind(refit))
		c.resized.connect(_queue.bind(refit))
		c.visibility_changed.connect(_queue.bind(refit))


static var _queued := {}
## true while a refit runs: the size changes it makes itself do not queue another one
static var _busy := false


## Runs `refit` now, its own size changes not queueing another one.
static func now(refit: Callable) -> void:
	if _busy or not refit.is_valid():
		return
	_busy = true
	refit.call()
	_busy = false


static func _queue(refit: Callable) -> void:
	var key := refit.hash()
	if _busy or _queued.has(key):
		return
	_queued[key] = true
	# on the next frame, not deferred: a refit that makes a container sort again would else
	# run again in the same flush of deferred calls
	var tree := Engine.get_main_loop() as SceneTree
	var run := _run.bind(refit, key)
	if not tree.process_frame.is_connected(run):
		tree.process_frame.connect(run, CONNECT_ONE_SHOT)


static func _run(refit: Callable, key: int) -> void:
	_queued.erase(key)
	if refit.is_valid():
		_busy = true
		refit.call()
		_busy = false
