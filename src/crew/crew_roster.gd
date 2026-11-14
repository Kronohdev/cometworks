class_name CrewRoster
extends RefCounted
## The crew roster: hire, rename, dismiss Cometling astronauts, seat them in the
## crewed parts of a vessel and persist everything to user://crew_roster.json.
##
##   var roster := CrewRoster.shared()              # lazily loaded, no autoload
##   var seats := CrewRoster.seats_for_vessel(vessel) # [{part, path, seat, member}]
##   roster.assign(member, capsule_part, 0)           # -> bool
##   roster.unassign(member)
##   roster.bind_vessel(vessel)                       # auto-unseat when parts are removed
##   var mods := roster.mission_modifiers(vessel)     # data hooks for the mission sim
##
## Rules: a seat holds one member; a member sits in one seat (assigning again moves
## them); seat indices go from 0 to crew_seats(part) - 1, so a vessel can never carry
## more crew than seats; members whose part leaves the vessel are unassigned (prune).

signal changed
signal member_assigned(member: CrewMember, part: Node, seat: int)
signal member_unassigned(member: CrewMember)

const SAVE_PATH := "user://crew_roster.json"
const DEFAULT_SIZE := 6
## Seats of crewed parts that do not declare `crew_seats` in data/parts.json yet.
const FALLBACK_SEATS := {"crew_capsule": 3}

const SYL := ["bo", "pi", "zu", "mi", "ko", "lu", "ni", "ta", "fe", "ru", "po", "ki", "sa", "mo", "bu",
	"li", "no", "ze", "ka", "yo", "pa", "ti", "mu", "ro"]
const END := ["", "", "", "n", "p", "li", "bo", "ti", "x", "mi"]
const SUR_A := ["Star", "Moon", "Puff", "Zoom", "Glim", "Bloop", "Twink", "Pop", "Fizz", "Nova", "Orbi",
	"Coma", "Boop", "Comet", "Luma", "Dusty"]
const SUR_B := ["kin", "bean", "dot", "wick", "loo", "pip", "ster", "ling", "mo", "zoo", "puff", "nub"]

static var _shared: CrewRoster

var members: Array[CrewMember] = []
var save_path := SAVE_PATH
var autosave := true
var _next_id := 1
var _rng := RandomNumberGenerator.new()
var _bound: Array = []    # vessels whose `changed` we listen to


func _init() -> void:
	_rng.randomize()


static func shared() -> CrewRoster:
	if _shared == null:
		_shared = CrewRoster.new()
		if not _shared.load_from(SAVE_PATH):
			_shared.seed_default(DEFAULT_SIZE)
			_shared.save()
	return _shared


# ------------------------------------------------------------------ persistence
func save(path := "") -> bool:
	var p := path if path != "" else save_path
	var data := {"version": 1, "next_id": _next_id, "members": members.map(func(m: CrewMember) -> Dictionary: return m.to_dict())}
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		push_warning("CrewRoster: cannot write %s" % p)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	return true


func load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("members"):
		return false
	save_path = path
	members.clear()
	for d in data["members"]:
		if typeof(d) == TYPE_DICTIONARY:
			members.append(CrewMember.from_dict(d))
	_next_id = int(data.get("next_id", members.size() + 1))
	changed.emit()
	return true


func _touch() -> void:
	changed.emit()
	if autosave:
		save()


# ------------------------------------------------------------------ hiring
## Fills an empty roster with `n` members, two of each role first.
func seed_default(n := DEFAULT_SIZE, rng_seed := 2026) -> void:
	_rng.seed = rng_seed
	var was := autosave
	autosave = false
	for i in n:
		hire(CrewMember.ROLES[i % 3])
	autosave = was


static func generate_name(rng: RandomNumberGenerator) -> String:
	var first := String(SYL[rng.randi() % SYL.size()]) + String(SYL[rng.randi() % SYL.size()]) + String(END[rng.randi() % END.size()])
	var last := String(SUR_A[rng.randi() % SUR_A.size()]) + String(SUR_B[rng.randi() % SUR_B.size()])
	return first.capitalize() + " " + last


## Hires a new Cometling (random role if `role` is empty) and returns it.
func hire(role := "") -> CrewMember:
	var m := CrewMember.new()
	m.id = "cm%03d" % _next_id
	_next_id += 1
	m.role = role if role in CrewMember.ROLES else CrewMember.ROLES[_rng.randi() % 3]
	m.display_name = _unique_name()
	m.variant = _least_used_variant()
	m.portrait_seed = _rng.randi() % 100000 + 1
	m.courage = snappedf(_rng.randf_range(0.25, 0.95), 0.01)
	m.skill = snappedf(_rng.randf_range(0.25, 0.95), 0.01)
	m.curiosity = snappedf(_rng.randf_range(0.25, 0.95), 0.01)
	# the role's main stat leans high: they chose this job for a reason
	if m.role == "scientist":
		m.curiosity = maxf(m.curiosity, snappedf(_rng.randf_range(0.6, 0.98), 0.01))
	else:
		m.skill = maxf(m.skill, snappedf(_rng.randf_range(0.6, 0.98), 0.01))
	members.append(m)
	_touch()
	return m


## A colour nobody (or the fewest members) wears yet, so the roster stays colourful.
func _least_used_variant() -> int:
	var use: Array[int] = []
	use.resize(CometlingLooks.count())
	use.fill(0)
	for m in members:
		use[posmod(m.variant, use.size())] += 1
	var lowest: int = use.min()
	var pick: Array[int] = []
	for i in use.size():
		if use[i] == lowest:
			pick.append(i)
	return pick[_rng.randi() % pick.size()]


func _unique_name() -> String:
	for i in 20:
		var n := generate_name(_rng)
		if find_by_name(n) == null:
			return n
	return generate_name(_rng) + " " + str(_next_id)


func rename(m: CrewMember, new_name: String) -> bool:
	var n := new_name.strip_edges()
	if n.is_empty() or n.length() > 28:
		return false
	m.display_name = n
	_touch()
	return true


func dismiss(m: CrewMember) -> void:
	unassign(m)
	members.erase(m)
	_touch()


func find(id: String) -> CrewMember:
	for m in members:
		if m.id == id:
			return m
	return null


func find_by_name(n: String) -> CrewMember:
	for m in members:
		if m.display_name == n:
			return m
	return null


func available() -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	for m in members:
		if not m.is_assigned():
			out.append(m)
	return out


# ------------------------------------------------------------------ seats
## Number of crew seats of a part (PartInstance or part dictionary).
static func crew_seats(part: Variant) -> int:
	var data: Dictionary = {}
	if part is Dictionary:
		data = part
	elif part is Object and (part as Object).get("data") is Dictionary:
		data = (part as Object).get("data")
	var id := String(data.get("id", ""))
	if data.has("crew_seats"):
		return maxi(int(data["crew_seats"]), 0)
	return int(FALLBACK_SEATS.get(id, 0))


static func vessel_of(part: Node) -> Node:
	var n := part
	while n:
		if n.has_method("all_parts") and n.has_signal("changed"):
			return n
		n = n.get_parent()
	return null


static func part_path(vessel: Node, part: Node) -> String:
	if vessel == null or part == null or not vessel.is_ancestor_of(part):
		return ""
	return String(vessel.get_path_to(part))


static func _vessel_parts(vessel: Node) -> Array:
	if vessel and vessel.has_method("all_parts"):
		return vessel.call("all_parts")
	return []


## Every crew seat of the vessel in attach-tree order:
## [{part: PartInstance, path: String, seat: int, member: CrewMember or null}].
static func seats_for_vessel(vessel: Node, roster: CrewRoster = null) -> Array[Dictionary]:
	var r := roster if roster else shared()
	var out: Array[Dictionary] = []
	for p in _vessel_parts(vessel):
		var n := crew_seats(p)
		if n <= 0:
			continue
		var path := part_path(vessel, p)
		for s in n:
			out.append({"part": p, "path": path, "seat": s, "member": r.member_at(path, s)})
	return out


func member_at(path: String, seat: int) -> CrewMember:
	if path == "":
		return null
	for m in members:
		if m.is_assigned() and m.assigned_part == path and m.assigned_seat == seat:
			return m
	return null


## Seats `m` in `part` seat `seat`. Fails (false) when the part has no such seat or
## the seat is taken by someone else (unless replace = true, which unseats them).
## A member already seated elsewhere moves to the new seat.
func assign(m: CrewMember, part: Node, seat: int, replace := false) -> bool:
	if m == null or part == null or not (m in members):
		return false
	var v := vessel_of(part)
	var path := part_path(v, part)
	if path == "" or seat < 0 or seat >= crew_seats(part):
		return false
	var other := member_at(path, seat)
	if other == m:
		return true
	if other:
		if not replace:
			return false
		_unseat(other)
	if m.is_assigned():
		_unseat(m)
	m.status = "assigned"
	m.assigned_part = path
	m.assigned_seat = seat
	bind_vessel(v)
	member_assigned.emit(m, part, seat)
	_touch()
	return true


## First free seat of the vessel for `m` (prefers the given part). Returns false if full.
func assign_auto(m: CrewMember, vessel: Node, prefer: Node = null) -> bool:
	var seats := seats_for_vessel(vessel, self)
	for pass_i in 2:
		for s in seats:
			if s["member"] != null:
				continue
			if pass_i == 0 and prefer != null and s["part"] != prefer:
				continue
			return assign(m, s["part"], int(s["seat"]))
	return false


func unassign(m: CrewMember) -> void:
	if m and m.is_assigned():
		_unseat(m)
		_touch()


func _unseat(m: CrewMember) -> void:
	m.status = "available"
	m.assigned_part = ""
	m.assigned_seat = -1
	member_unassigned.emit(m)


func unassign_all() -> void:
	for m in members:
		if m.is_assigned():
			_unseat(m)
	_touch()


## Unseats members whose part is gone from `vessel` (or no longer has that seat).
## Returns how many were unseated.
func prune(vessel: Node) -> int:
	var valid := {}
	for s in seats_for_vessel(vessel, self):
		valid["%s#%d" % [s["path"], s["seat"]]] = true
	var n := 0
	for m in members:
		if m.is_assigned() and not valid.has("%s#%d" % [m.assigned_part, m.assigned_seat]):
			_unseat(m)
			n += 1
	if n > 0:
		_touch()
	return n


## Listen to the vessel and prune automatically when parts are removed.
func bind_vessel(vessel: Node) -> void:
	if vessel == null or vessel in _bound or not vessel.has_signal("changed"):
		return
	_bound.append(vessel)
	vessel.connect("changed", func() -> void:
		if is_instance_valid(vessel):
			# deferred: undo / load rebuild the vessel in several steps
			(func() -> void:
				if is_instance_valid(vessel):
					prune(vessel)).call_deferred())


func crew_of(vessel: Node) -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	for s in seats_for_vessel(vessel, self):
		if s["member"] != null:
			out.append(s["member"])
	return out


# ------------------------------------------------------------------ mission hooks
## Multipliers the mission simulation can read (1.0 = no crew effect):
##   attitude_control  pilots:     +8 % + 14 % x skill + 3 % per level each (cap 1.6)
##   reliability       engineers:  +4 % + 10 % x skill + 2 % per level each (cap 1.4)
##   science_return    scientists: +10 % + 25 % x curiosity + 5 % per level each (cap 2.0)
##   morale            mean courage of the crew (0..1, 0 without crew)
## plus crew_count and seats.
func mission_modifiers(vessel: Node) -> Dictionary:
	var att := 1.0
	var rel := 1.0
	var sci := 1.0
	var courage := 0.0
	var crew := crew_of(vessel)
	for m in crew:
		match m.role:
			"pilot":
				att += 0.08 + 0.14 * m.skill + 0.03 * m.level()
			"engineer":
				rel += 0.04 + 0.10 * m.skill + 0.02 * m.level()
			"scientist":
				sci += 0.10 + 0.25 * m.curiosity + 0.05 * m.level()
		courage += m.courage
	return {"attitude_control": minf(att, 1.6), "reliability": minf(rel, 1.4), "science_return": minf(sci, 2.0),
		"morale": courage / crew.size() if crew.size() > 0 else 0.0, "crew_count": crew.size(),
		"seats": seats_for_vessel(vessel, self).size()}


## Gives XP to the crew of `vessel` after a mission (more for success).
func award_mission(vessel: Node, success: bool) -> void:
	for m in crew_of(vessel):
		m.experience += 60.0 if success else 25.0
		m.missions += 1
	_touch()
