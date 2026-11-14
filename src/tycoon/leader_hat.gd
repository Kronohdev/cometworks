@tool
class_name LeaderHat
extends Node3D
## The leader's hats (scenes/tycoon/leader/leader_hat.tscn): one child per hat, voxel boxes
## authored in the editor in the head's space (the Cometling's Rig/Hips/Neck pivot), so a
## hat bobs, tilts and squashes with the head. `wear()` puts the scene on a Cometling:
##   "role"  no hat, the profession's head gear (helmet, hard hat) as usual
##   "none"  bare head: no hat and no helmet or hard hat
##   other   the child named after it in PascalCase (crown -> Crown), helmet / hard hat hidden
## A hat child with the metadata `hides_antenna` (the beanies) also tucks the antenna away.
## One with `hides_goggles` (the glasses) takes the scientist goggles off the forehead.
## The propeller spins with the scene's AnimationPlayer ("Anim", animation "spin").

const SCENE := "res://scenes/tycoon/leader/leader_hat.tscn"
const NODE_NAME := "LeaderHat"
## head gear of the roles that a hat replaces (the goggles stay: they sit on the forehead)
const HEAD_GEAR := ["Helmet", "HardHat"]

@export var hat := "crown":
	set(v):
		hat = v
		_show()


func _ready() -> void:
	_show()


func _show() -> void:
	if get_child_count() == 0:
		return
	for c in get_children():
		if c is Node3D:
			(c as Node3D).visible = String(c.name).to_snake_case() == hat
	var anim := get_node_or_null("Anim") as AnimationPlayer
	if anim and not Engine.is_editor_hint() and is_inside_tree():
		if hat == "propeller" and anim.has_animation("spin"):
			anim.play("spin")
		else:
			anim.stop()


## True when the hat being worn covers the antenna (metadata `hides_antenna` on its node).
func hides_antenna() -> bool:
	for c in get_children():
		if c is Node3D and String(c.name).to_snake_case() == hat:
			return bool(c.get_meta("hides_antenna", false))
	return false


## True when the hat being worn sits where the scientist goggles do (metadata `hides_goggles`).
func hides_goggles() -> bool:
	for c in get_children():
		if c is Node3D and String(c.name).to_snake_case() == hat:
			return bool(c.get_meta("hides_goggles", false))
	return false


## Puts hat `hat_id` on a Cometling (see the class notes for "role" and "none").
static func wear(c: Cometling, hat_id: String) -> void:
	if c == null:
		return
	var neck := c.get_node_or_null("Rig/Hips/Neck") as Node3D
	if neck == null:
		return
	var node := neck.get_node_or_null(NODE_NAME) as LeaderHat
	var antenna := neck.get_node_or_null("Antenna") as Node3D
	if hat_id == "role" or hat_id == "":
		if node:
			node.visible = false
			node.hat = "none"
		if antenna:
			antenna.visible = true
		c.role = c.role   # shows the role's accessories again
		return
	if node == null:
		node = (load(SCENE) as PackedScene).instantiate() as LeaderHat
		node.name = NODE_NAME
		neck.add_child(node)
	node.visible = true
	node.hat = hat_id
	if antenna:
		antenna.visible = not node.hides_antenna()
	for n: String in HEAD_GEAR:
		var g := c.find_child(n, true, false) as Node3D
		if g:
			g.visible = false
	var goggles := c.find_child("Goggles", true, false) as Node3D
	if goggles:   # the scientist's goggles, unless the glasses take their place
		goggles.visible = c.role == "scientist" and not node.hides_goggles()
