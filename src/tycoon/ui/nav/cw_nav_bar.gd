class_name CwNavBar
extends HBoxContainer
## The title block of a screen with pages (scenes/tycoon/ui/cw_nav_bar.tscn): a back key, the
## breadcrumb of the levels above (each a link back to it) and the title of the page on show,
## with the screen's subtitle under it at the top level. Point `stack` at the screen's
## CwPageStack; the subtitle text is `subtitle` (a translation key). The look is the scene's:
## crumbs are copies of the hidden CrumbTemplate / SepTemplate.

## the CwPageStack this bar follows
@export var stack: NodePath
## shown under the title at the top level (translation key; empty = none)
@export var subtitle := ""
## the top level's title (translation key); empty = the page's own title
@export var root_title := ""

var _stack: CwPageStack


func _ready() -> void:
	_stack = get_node_or_null(stack) as CwPageStack
	%Back.pressed.connect(func() -> void:
		if _stack:
			_stack.back())
	if _stack:
		_stack.page_changed.connect(func(_p: StringName, _d: int) -> void: refresh())
	refresh.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh()


func refresh() -> void:
	if _stack == null or not is_inside_tree():
		return
	var trail := _stack.trail()
	if trail.is_empty():
		return
	if root_title != "":
		trail[0]["title"] = tr(root_title)
	var d := trail.size() - 1
	%Back.visible = d > 0
	%Title.text = String(trail[-1]["title"])
	%Sub.text = tr(subtitle)
	%Sub.visible = d == 0 and subtitle != ""
	%Crumbs.visible = d > 0
	# one crumb (link + separator) per level above the page on show
	var crumbs := TycoonHUD._copies(%CrumbTemplate, d)
	for i in d:
		var b := crumbs[i].get_node("Link") as Button
		b.text = String(trail[i]["title"])
		b.set_meta("level", i)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void:
				if _stack:
					_stack.back_to(int(b.get_meta("level"))))
