class_name CwPageTabs
extends HBoxContainer
## A row of tab keys for a CwPageStack (src/tycoon/ui/nav/): each Button child opens the
## top-level page named in its metadata `page` (or, without it, the page named like the
## button) and stays lit while that page, or any page opened from it, is on show.

## the CwPageStack the tabs switch
@export var stack: NodePath

var _stack: CwPageStack


func _ready() -> void:
	_stack = get_node_or_null(stack) as CwPageStack
	if _stack == null:
		return
	for b in buttons():
		var pg := page_of(b)
		b.toggle_mode = true
		b.pressed.connect(func() -> void:
			_stack.switch_to(pg)
			_light())
	_stack.page_changed.connect(func(_p: StringName, _d: int) -> void: _light())
	_light.call_deferred()


func buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in get_children():
		if c is Button:
			out.append(c)
	return out


static func page_of(b: Button) -> StringName:
	return StringName(b.get_meta("page", b.name))


## The tab key that opens `page_name`, or null.
func tab(page_name: StringName) -> Button:
	for b in buttons():
		if page_of(b) == page_name:
			return b
	return null


func _light() -> void:
	if _stack == null:
		return
	var root := _stack.root_page()
	for b in buttons():
		b.set_pressed_no_signal(page_of(b) == root)
