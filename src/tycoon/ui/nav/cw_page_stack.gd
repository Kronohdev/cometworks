class_name CwPageStack
extends Container
## The pages of a screen, one on show at a time (src/tycoon/ui/nav/). Every Control child is
## a page, laid out to fill the stack; the editor shows them all, the game only the current
## one. A page's title (for the breadcrumb, CwNavBar) is its metadata `title` (a translation
## key), or the title given when it is opened (a Cometling's name, a tech).
##   push(page)       goes one level down (an overview -> its detail): slides in from the right
##   back()           one level up: slides in from the left; false at the top level
##   switch_to(page)  a new top level (tabs): the trail starts over
## Esc on the campus calls TycoonHUD.screen_back(), which steps up the deepest stack showing a
## sub page before it closes the screen (CwPageStack.back_in).
## Motion: the incoming page slides `slide` px and fades in (CwMotion channel "page"); with
## reduce motion it only fades.

signal page_changed(page: StringName, depth: int)

## the page on show first (empty = the first child)
@export var first_page: StringName
## the stack asks for the size of its largest page, so a centred panel keeps its size when
## the page changes (off: the size of the page on show)
@export var keep_largest := false
@export_group("Motion")
@export var slide := 40.0
@export_range(0.0, 1.0, 0.01) var seconds := 0.24

## [{"page": StringName, "title": String}], the top level first
var _trail: Array[Dictionary] = []
var _tween: Tween


func _ready() -> void:
	add_to_group(&"cw_page_stack")
	var p := first_page
	if p == &"":
		var all := pages()
		p = StringName(all[0].name) if not all.is_empty() else &""
	if p != &"":
		_trail = [{"page": p, "title": ""}]
		_show(p, 0, false)


## The deepest stack under `root` that shows a sub page steps up one level; false when none
## does (the screen is at its top level and Esc may close it).
static func back_in(root: Node) -> bool:
	if root == null or not root.is_inside_tree():
		return false
	var best: CwPageStack = null
	var best_depth := -1
	for n in root.get_tree().get_nodes_in_group(&"cw_page_stack"):
		var st := n as CwPageStack
		if st == null or not root.is_ancestor_of(st) or not st.is_visible_in_tree() or st.depth() == 0:
			continue
		var d := st.get_path().get_name_count()
		if d > best_depth:
			best = st
			best_depth = d
	return best != null and best.back()


func pages() -> Array[Control]:
	var out: Array[Control] = []
	for c in get_children():
		if c is Control and not (c as Control).top_level:
			out.append(c)
	return out


func page(page_name: StringName) -> Control:
	return get_node_or_null(NodePath(String(page_name))) as Control


func current() -> StringName:
	return StringName(_trail[-1]["page"]) if not _trail.is_empty() else &""


func current_page() -> Control:
	return page(current())


## 0 at the top level, 1 on a detail page, ...
func depth() -> int:
	return maxi(_trail.size() - 1, 0)


func root_page() -> StringName:
	return StringName(_trail[0]["page"]) if not _trail.is_empty() else &""


## The trail as [{"page", "title"}] (titles already translated), the top level first.
func trail() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in _trail:
		out.append({"page": e["page"], "title": title_of(e)})
	return out


func title_of(e: Dictionary) -> String:
	var t := String(e.get("title", ""))
	if t == "":
		var pg := page(StringName(e["page"]))
		t = String(pg.get_meta("title", pg.name)) if pg else String(e["page"])
	return tr(t)


## Opens `page_name` one level down (an overview's detail). Opening the page already on show
## only changes its title.
func push(page_name: StringName, title := "") -> void:
	if current() == page_name:
		set_title(title)
		return
	_trail.append({"page": page_name, "title": title})
	_show(page_name, 1)


## A new top level (a tab): the trail starts over at `page_name`.
func switch_to(page_name: StringName, title := "") -> void:
	if _trail.size() == 1 and current() == page_name:
		set_title(title)
		return
	var old := root_page()
	var all := pages()
	var dir := 0
	if old != &"" and old != page_name:
		dir = 1 if all.find(page(page_name)) > all.find(page(old)) else -1
	_trail = [{"page": page_name, "title": title}]
	_show(page_name, dir)


## One level up; false at the top level.
func back() -> bool:
	if _trail.size() <= 1:
		return false
	_trail.pop_back()
	_show(current(), -1)
	return true


## Back to the level `level` of the trail (0 = the top level).
func back_to(level: int) -> void:
	if level < 0 or level >= _trail.size() - 1:
		return
	_trail.resize(level + 1)
	_show(current(), -1)


## The title of the page on show (a Cometling's name once their data is known).
func set_title(title: String) -> void:
	if _trail.is_empty() or title == "" or String(_trail[-1]["title"]) == title:
		return
	_trail[-1]["title"] = title
	page_changed.emit(current(), depth())


func _show(page_name: StringName, dir: int, animate := true) -> void:
	var target := page(page_name)
	if target == null:
		push_warning("CwPageStack %s: no page '%s'" % [name, page_name])
		return
	for pg in pages():
		pg.visible = pg == target
	update_minimum_size()
	queue_sort()
	if _tween:
		_tween.kill()
	if animate and is_inside_tree() and seconds > 0.0:
		var reduced := CwMotion.reduced()
		var off := Vector2.ZERO if reduced or dir == 0 else Vector2(slide * dir, 0)
		CwMotion.set_channel(target, &"page", off, Vector2.ONE, 0.0, 0.0)
		_tween = create_tween()
		CwMotion.shape(_tween.tween_method(func(k: float) -> void:
			CwMotion.set_channel(target, &"page", off * (1.0 - k), Vector2.ONE, 0.0, clampf(k * 1.4, 0.0, 1.0)),
			0.0, 1.0, minf(seconds, 0.12) if reduced else seconds), CwMotion.Feel.SMOOTH)
	else:
		CwMotion.clear_channel(target, &"page")
	page_changed.emit(page_name, depth())


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for pg in pages():
			fit_child_in_rect(pg, Rect2(Vector2.ZERO, size))


func _get_minimum_size() -> Vector2:
	var pg := current_page()
	if pg == null or not is_inside_tree() or keep_largest:
		# in the editor (or before ready) the largest page
		var m := Vector2.ZERO
		for c in pages():
			m = m.max(c.get_combined_minimum_size())
		return m
	return pg.get_combined_minimum_size()
