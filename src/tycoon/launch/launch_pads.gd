class_name LaunchPads
extends RefCounted
## Which pad a mission leaves from, and the new rocket rolled out after each launch.
##
## Pads are the campus lots of kind "pad" (data/tycoon/buildings.json) with a built level. A pad
## lot may list the launch classes it serves ("launch_classes": ["heavy", "lunar"], the values of
## projects.json launch.type_class); a pad without the list takes any class. The pick, in order:
## a pad that lists the class, then one that takes any class; one with a rocket standing on it;
## one not being upgraded; the pad that launched longest ago (so two pads alternate); lot order.
##
## After a launch the pad stands empty while the next rocket is assembled, then it is rolled out
## onto the pad (CampusBuilding.set_rocket_progress shows it, scenes/tycoon/launch/pad_rollout.tscn
## is the look): projects.json launch.pad_rollout_weeks weeks in all.
## State, per pad in TycoonState.buildings[lot]: "last_launch" (week of the last launch),
## "launch_order" (1, 2, 3... over all pads: which launched last), "rocket_weeks" (weeks until
## the new rocket stands on the pad), "rocket_total", "last_rocket" (the parts of the rocket
## that left it, RocketDesigner). The rocket on a pad is the designed one (pad_rocket).


## Built pads in lot order.
static func pads(s: TycoonState) -> Array[String]:
	var out: Array[String] = []
	for lot: String in s.lot_ids():
		if s.lot_kind(lot) == "pad" and int(s.building(lot).get("level", 0)) > 0:
			out.append(lot)
	return out


## The pad a rocket of launch class `cls` leaves from ("pad" when none is built).
static func pick(s: TycoonState, cls: String) -> String:
	var best := ""
	var best_score := -INF
	for lot in pads(s):
		var b := s.building(lot)
		var classes: Array = s.bdata.get("lots", {}).get(lot, {}).get("launch_classes", [])
		var fit := 2 if cls in classes else (1 if classes.is_empty() else 0)
		var ready := 1 if int(b.get("rocket_weeks", 0)) <= 0 else 0
		var idle := 1 if int(b.get("weeks_left", 0)) <= 0 else 0
		var score := fit * 1.0e7 + ready * 1.0e6 + idle * 1.0e5 - float(int(b.get("launch_order", 0)))
		if score > best_score:
			best_score = score
			best = lot
	return best if best != "" else "pad"


## A rocket left `lot` (`parts`: its design): the pad stands empty and the next rocket's
## rollout starts.
static func launched(s: TycoonState, lot: String, parts := {}) -> void:
	if not s.buildings.has(lot):
		return
	var b: Dictionary = s.buildings[lot]
	var total := rollout_weeks()
	var order := 0
	for l: String in s.buildings:
		order = maxi(order, int(s.buildings[l].get("launch_order", 0)))
	b["last_launch"] = s.weeks
	b["launch_order"] = order + 1
	b["rocket_weeks"] = total
	b["rocket_total"] = total
	if not parts.is_empty():
		b["last_rocket"] = RocketDesigner.normalize(parts)


## The design of the rocket standing (or rolling out) on a pad: the rocket of the project in
## development that will leave from this pad, the furthest along first; else the one that last
## left it; {} for none yet (the pad shows the era's rocket).
static func pad_rocket(s: TycoonState, lot: String) -> Dictionary:
	return pad_launch(s, lot)["parts"]


## What stands on a pad, for its look: {"parts": pad_rocket's design, "payload": the module ids
## it carries (a rover rides on the rocket), "target": where it goes}. The rocket that last left
## a pad stands there without a payload ([] / "leo").
static func pad_launch(s: TycoonState, lot: String) -> Dictionary:
	var best: MissionProject = null
	for p: MissionProject in s.mission_projects:
		if p.rocket.is_empty():
			continue
		if pick(s, String(RocketDesigner.stats(p.rocket.get("parts", {}))["class"])) != lot:
			continue
		if best == null or p.progress() > best.progress():
			best = p
	if best:
		return {"parts": RocketDesigner.normalize(best.rocket.get("parts", {})), "payload": Array(best.payload),
			"target": best.target_id}
	var last: Dictionary = s.building(lot).get("last_rocket", {})
	return {"parts": last.duplicate(), "payload": [], "target": "leo"}


## One week of rollout on every pad.
static func advance_week(s: TycoonState) -> void:
	for lot: String in s.buildings:
		var b: Dictionary = s.buildings[lot]
		if int(b.get("rocket_weeks", 0)) > 0:
			b["rocket_weeks"] = int(b["rocket_weeks"]) - 1


## 0 = the rocket just left (empty pad) .. 1 = a rocket stands on the pad.
static func rocket_progress(s: TycoonState, lot: String) -> float:
	var b := s.building(lot)
	var left := int(b.get("rocket_weeks", 0))
	if left <= 0:
		return 1.0
	return clampf(1.0 - float(left) / maxf(float(b.get("rocket_total", left)), 1.0), 0.0, 1.0)


static func rollout_weeks() -> int:
	return maxi(int(ProjectRules.section("launch").get("pad_rollout_weeks", 6)), 1)
