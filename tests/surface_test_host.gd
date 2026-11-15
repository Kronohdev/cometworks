extends Node
## tests/test_surface_explore.gd: stands in for TycoonMain (a node with the career `state` and
## `clock` above a surface, a Campus and a UI to put to sleep), so SurfaceExplore,
## SurfaceCampusButton and SurfaceViewer find the career the way they do in the campus.

var state: TycoonState
var clock: TycoonClock


func open_space_map() -> void:
	pass
