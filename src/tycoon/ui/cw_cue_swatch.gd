@tool
class_name CwCueSwatch
extends ColorRect
## A colour swatch (an agency's, a briefing kind's) that, in colour-blind mode, draws the shape
## cue of its colour on top (CwPalette.cue_of / draw_cue), so the swatch never speaks by hue
## alone; thin bar swatches grow to CUE_SIZE then so the shape has room. Set as the script of
## the swatches' ColorRects in the scenes.

const CUE_SIZE := 12.0

var _authored_min := Vector2(-1, -1)


func _ready() -> void:
	add_to_group(CwAccess.CUE_GROUP)
	refresh_cue()


## Sizes the swatch for the current mode and redraws it (CwAccess calls it on a mode change).
func refresh_cue() -> void:
	if _authored_min.x < 0.0:
		_authored_min = custom_minimum_size
	custom_minimum_size = _authored_min.max(Vector2(CUE_SIZE, CUE_SIZE)) if CwPalette.colorblind \
		and not Engine.is_editor_hint() else _authored_min
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAW:
		CwPalette.draw_cue(self, CwPalette.cue_of(color), size * 0.5, minf(size.x, size.y) * 0.4, color)
