class_name CrewMember
extends Resource
## One Cometling astronaut in the crew roster (CrewRoster). Plain data: stats are
## 0..1, experience is in XP points (CrewRoster.award_mission adds them), the seat
## assignment is stored as the part's path relative to the Vessel node + seat index.

const ROLES := ["pilot", "engineer", "scientist"]
const XP_PER_LEVEL := 100.0
const MAX_LEVEL := 5

@export var id := ""
@export var display_name := ""
@export_enum("pilot", "engineer", "scientist") var role: String = "pilot"
## Colour variant (CometlingLooks.VARIANTS index).
@export var variant := 0
@export_range(0.0, 1.0) var courage := 0.5
@export_range(0.0, 1.0) var skill := 0.5
@export_range(0.0, 1.0) var curiosity := 0.5
@export var experience := 0.0
@export var missions := 0
@export_enum("available", "assigned") var status: String = "available"
## Path of the crewed PartInstance relative to its Vessel ("" when not seated).
@export var assigned_part := ""
@export var assigned_seat := -1
## Personality seed for the 3D portrait / NPC animation rhythm.
@export var portrait_seed := 0


func level() -> int:
	return mini(int(experience / XP_PER_LEVEL), MAX_LEVEL)


## 0..1 progress toward the next level.
func level_progress() -> float:
	if level() >= MAX_LEVEL:
		return 1.0
	return fposmod(experience, XP_PER_LEVEL) / XP_PER_LEVEL


func is_assigned() -> bool:
	return status == "assigned" and assigned_part != "" and assigned_seat >= 0


## Main stat of the role (pilot: skill, engineer: skill, scientist: curiosity).
func role_stat() -> float:
	return curiosity if role == "scientist" else skill


func to_dict() -> Dictionary:
	return {"id": id, "name": display_name, "role": role, "variant": variant, "courage": courage, "skill": skill,
		"curiosity": curiosity, "experience": experience, "missions": missions, "status": status,
		"assigned_part": assigned_part, "assigned_seat": assigned_seat, "seed": portrait_seed}


static func from_dict(d: Dictionary) -> CrewMember:
	var m := CrewMember.new()
	m.id = String(d.get("id", ""))
	m.display_name = String(d.get("name", "?"))
	var r := String(d.get("role", "pilot"))
	m.role = r if r in ROLES else "pilot"
	m.variant = int(d.get("variant", 0))
	m.courage = clampf(float(d.get("courage", 0.5)), 0.0, 1.0)
	m.skill = clampf(float(d.get("skill", 0.5)), 0.0, 1.0)
	m.curiosity = clampf(float(d.get("curiosity", 0.5)), 0.0, 1.0)
	m.experience = maxf(float(d.get("experience", 0.0)), 0.0)
	m.missions = int(d.get("missions", 0))
	m.status = String(d.get("status", "available"))
	m.assigned_part = String(d.get("assigned_part", ""))
	m.assigned_seat = int(d.get("assigned_seat", -1))
	m.portrait_seed = int(d.get("seed", 0))
	if not m.is_assigned():
		m.status = "available"
		m.assigned_part = ""
		m.assigned_seat = -1
	return m
