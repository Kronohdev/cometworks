@tool
class_name CampusScatterMask
extends Resource
## Where nothing may be scattered on the campus (src/tycoon/campus_scatter.gd): the lots, the
## roads, the plaza, the lamps. Rectangles in world XZ (x, z, width, depth). Edit them in the
## inspector (assets/campus/nature/campus_mask.tres) and press "Scatter now" on the scatter
## nodes to refresh them.

@export var avoid: Array[Rect2] = []
