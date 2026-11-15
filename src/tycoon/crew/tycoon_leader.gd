class_name TycoonLeader
extends RefCounted
## The player's own Cometling, the leader of the agency (the career's "you"): made in the
## leader creator (scenes/tycoon/ui/screens/leader_creator.tscn) before the campus opens.
## Pure data + rules on a TycoonState, numbers and choices in data/tycoon/leader.json.
##
## state.leader: {"name", "profession", "body" (#hex), "spot" (#hex), "hat", "strength"
##   (skill | curiosity | courage), "quirk", "agency_name", "agency_color" (#hex), "emblem"
##   (an icon in ui/cometworks/emblems/, shown in the HUD and on the race board), "seed"}
## The leader is also a staff member (id "leader", "leader": true, first in state.staff) with
## the same look fields, so the campus, the crew screen and the projects see them like any
## other Cometling. Founding the agency gives the profession's starting bonus once: its
## tier-1 specialisation already learned plus a little cash, reputation, hype or research.

const DATA_PATH := "res://data/tycoon/leader.json"
## the agency emblems: <id>.svg, white icons tinted with the agency colour
const EMBLEM_DIR := "res://ui/cometworks/emblems/"
const ID := "leader"
## look and identity fields copied from state.leader to the staff member
const LOOK_KEYS := ["body", "spot", "hat", "quirk"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(DATA_PATH)
	return _data


static func lang() -> String:
	return "pt" if TranslationServer.get_locale().begins_with("pt") else "en"


static func _list(key: String) -> Array:
	return data().get(key, [])


static func body_colors() -> Array:
	return _list("body_colors")


static func spot_colors() -> Array:
	return _list("spot_colors")


static func agency_colors() -> Array:
	return _list("agency_colors")


static func hats() -> Array:
	return _list("hats")


static func emblems() -> Array:
	return _list("emblems")


static func emblem_icon(id: String) -> Texture2D:
	var p := EMBLEM_DIR + id + ".svg"
	return load(p) as Texture2D if id != "" and ResourceLoader.exists(p) else null


## The player's agency emblem, null when the campaign has no leader (old saves, fair mode).
static func agency_emblem(s: TycoonState) -> Texture2D:
	return emblem_icon(String(s.leader.get("emblem", ""))) if not s.leader.is_empty() else null


static func strengths() -> Array:
	return _list("strengths")


static func quirks() -> Array:
	var out: Array = []
	for q: Dictionary in _list("quirks"):
		out.append(String(q["id"]))
	return out


static func quirk(id: String) -> Dictionary:
	for q: Dictionary in _list("quirks"):
		if q["id"] == id:
			return q
	return {"id": id, "emote": "happy", "shot": "cheer"}


## {"spec": tier-1 spec id, "start": {"cash" | "reputation" | "hype" | "research_points": amount}}
static func bonus(profession_id: String) -> Dictionary:
	return data().get("professions", {}).get(profession_id, {"spec": "", "start": {}})


static func professions() -> Array:
	return data().get("professions", {}).keys()


static func is_leader(m: Dictionary) -> bool:
	return bool(m.get("leader", false))


## The leader as a staff member, {} when the campaign has none (old saves, fair mode).
static func member(s: TycoonState) -> Dictionary:
	for m in s.staff:
		if is_leader(m):
			return m
	return {}


# ------------------------------------------------------------ names and randomness
static func random_name(rng: RandomNumberGenerator, language := "") -> String:
	var l := language if language != "" else lang()
	var first: Array = data().get("names", {}).get(l, ["Pip"])
	var last: Array = data().get("surnames", {}).get(l, [])
	var n := String(first[rng.randi() % first.size()])
	if not last.is_empty() and rng.randf() < 0.7:
		n += " " + String(last[rng.randi() % last.size()])
	return n


static func random_agency_name(rng: RandomNumberGenerator, language := "") -> String:
	var l := language if language != "" else lang()
	var names: Array = data().get("agency_names", {}).get(l, ["Cometworks"])
	return String(names[rng.randi() % names.size()])


static func _pick(a: Array, rng: RandomNumberGenerator) -> Variant:
	return a[rng.randi() % a.size()] if not a.is_empty() else null


## A whole new random leader (name, look, profession, personality, agency).
static func make_random(rng: RandomNumberGenerator) -> Dictionary:
	var d := {"name": random_name(rng), "profession": String(_pick(professions(), rng)),
		"body": String(_pick(body_colors(), rng)), "spot": String(_pick(spot_colors(), rng)),
		"hat": String(_pick(hats(), rng)), "strength": String(_pick(strengths(), rng)),
		"quirk": String(_pick(quirks(), rng)), "agency_name": random_agency_name(rng),
		"agency_color": String(_pick(agency_colors(), rng)), "emblem": String(_pick(emblems(), rng)),
		"seed": rng.randi() % 100000 + 1}
	return sanitize(d)


## The first leader the creator shows: Cometworks, an engineer in the classic sky colours.
static func make_default(rng: RandomNumberGenerator) -> Dictionary:
	var d := make_random(rng)
	d["profession"] = "systems_engineer"
	d["body"] = String(body_colors()[0]) if not body_colors().is_empty() else "#bfe9ff"
	d["spot"] = String(spot_colors()[0]) if not spot_colors().is_empty() else "#f59a36"
	d["hat"] = "role"
	d["agency_name"] = "Cometworks"
	d["agency_color"] = String(agency_colors()[0]) if not agency_colors().is_empty() else "#ff8a3d"
	d["emblem"] = String(emblems()[0]) if not emblems().is_empty() else ""
	return d


## Every field present and valid (unknown choices fall back to the first option).
static func sanitize(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	var nm := String(out.get("name", "")).strip_edges().left(24)
	out["name"] = nm if nm != "" else "Pip"
	var choices := {"profession": professions(), "hat": hats(), "strength": strengths(), "quirk": quirks(),
		"emblem": emblems()}
	for k: String in choices:
		var opts: Array = choices[k]
		var v := String(out.get(k, ""))
		out[k] = v if v in opts else (String(opts[0]) if not opts.is_empty() else "")
	var colors := {"body": "#bfe9ff", "spot": "#f59a36", "agency_color": "#ff8a3d"}
	for k: String in colors:
		var v := String(out.get(k, ""))
		out[k] = v if Color.html_is_valid(v) else String(colors[k])
	var an := String(out.get("agency_name", "")).strip_edges().left(28)
	out["agency_name"] = an if an != "" else "Cometworks"
	out["seed"] = int(out.get("seed", 1))
	return out


# ------------------------------------------------------------ the campaign
## Founds the agency with this leader (new campaign): stores state.leader, names the agency,
## puts the leader first in the staff and gives the profession's starting bonus once.
static func found(s: TycoonState, leader: Dictionary) -> void:
	var l := sanitize(leader)
	s.leader = l
	s.agency_name = String(l["agency_name"])
	var old := member(s)
	if not old.is_empty():
		s.staff.erase(old)
	var lv := int(data().get("level", 2))
	var strong := float(data().get("traits", {}).get("strong", 0.85))
	var other := float(data().get("traits", {}).get("other", 0.6))
	var b := bonus(String(l["profession"]))
	var m := {"id": ID, "leader": true, "name": l["name"], "profession": l["profession"], "level": lv,
		"xp": (lv - 1) * TycoonCrew.xp_per_level(), "morale": float(data().get("morale", 90)),
		"variant": nearest_variant(Color(String(l["body"]))), "assigned": "", "hidden": [],
		"specs": [String(b["spec"])] if String(b.get("spec", "")) != "" else [], "seed": int(l["seed"]),
		"hired_week": 0, "adapt_weeks": 0, "train_weeks": 0}
	for t: String in TycoonCrew.TRAITS:
		m[t] = strong if t == String(l["strength"]) else other
	for k: String in LOOK_KEYS:
		m[k] = l[k]
	m = s.normalize_staff(m, 0)
	s.staff.push_front(m)
	var start: Dictionary = b.get("start", {})
	s.cash += float(start.get("cash", 0.0))
	s.reputation += float(start.get("reputation", 0.0))
	s.hype += float(start.get("hype", 0.0))
	s.research_points += float(start.get("research_points", 0.0))
	s.news.push_front({"key": "TY_LEADER_NEWS_FOUNDED", "args": [String(l["name"]), String(l["agency_name"])]})
	s.changed.emit()


## Later edits (from the crew screen): name, look, personality and agency name / colour.
## The profession and the strength stay as founded (their bonuses were already given).
static func update(s: TycoonState, leader: Dictionary) -> void:
	if s.leader.is_empty():
		found(s, leader)
		return
	var l := sanitize(leader)
	l["profession"] = s.leader.get("profession", l["profession"])
	l["strength"] = s.leader.get("strength", l["strength"])
	l["seed"] = int(s.leader.get("seed", l["seed"]))
	s.leader = l
	s.agency_name = String(l["agency_name"])
	var m := member(s)
	if not m.is_empty():
		m["name"] = l["name"]
		m["variant"] = nearest_variant(Color(String(l["body"])))
		for k: String in LOOK_KEYS:
			m[k] = l[k]
	s.changed.emit()


## The race board colour of the player's agency.
static func agency_color(s: TycoonState, fallback: Color) -> Color:
	var c := String(s.leader.get("agency_color", ""))
	return Color(c) if Color.html_is_valid(c) else fallback


## The CometlingLooks variant closest to a body colour (for screens that only know variants).
static func nearest_variant(body: Color) -> int:
	var best := 0
	var best_d := INF
	for i in CometlingLooks.count():
		var c: Color = CometlingLooks.get_variant(i)["body"]
		var d := Vector3(c.r - body.r, c.g - body.g, c.b - body.b).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


# ------------------------------------------------------------ looks
## Dresses a Cometling as a staff member and returns the Cometling that shows them: a Lenda
## with a scene of its own (TycoonLegends.scene_path) stands in for `c` (swap_body: same place,
## name and settings) in its own outfit; the leader and the other Lendas get their own colours
## and hat, anyone else their variant colours and no hat. A body swapped in for a Lenda goes
## back to the shared Cometling when the next member is not one. Callers keep the returned node.
static func dress(c: Cometling, m: Dictionary) -> Cometling:
	var role := TycoonCrew.look_role(String(m.get("profession", "")))
	var own := TycoonLegends.scene_path(String(m.get("legend", ""))) if TycoonLegends.is_legend(m) else ""
	c = swap_body(c, own)
	if own != "":
		c.role = role   # the antenna colour; the outfit hides the profession gear
		return c
	if is_leader(m) or TycoonLegends.is_legend(m):
		apply_look(c, m, role)
	else:
		CometlingLooks.apply(c, int(m.get("variant", 0)), role)
		LeaderHat.wear(c, "role")
	return c


## Puts an instance of `scene` (a Cometling scene) where `c` is, with its name, transform,
## visibility and settings, frees `c` and returns the new one; scene "" brings back the shared
## Cometling a swap replaced (else returns `c` as it is). `c` already of that scene stays.
static func swap_body(c: Cometling, scene: String) -> Cometling:
	if c == null:
		return c
	var plain := String(c.get_meta("plain_scene", ""))
	if scene == "":
		if plain == "":
			return c
		scene = plain
	if c.scene_file_path == scene:
		return c
	var ps := load(scene) as PackedScene
	var n := ps.instantiate() as Cometling if ps else null
	if n == null:
		return c
	if scene != plain:
		n.set_meta("plain_scene", plain if plain != "" else c.scene_file_path)
	n.name = c.name
	n.transform = c.transform
	n.visible = c.visible
	for k in ["listen_to_events", "cull_distance", "lod_distance", "detail_distance", "habit_distance_factor",
			"paused", "glow_color", "process_mode"]:
		n.set(k, c.get(k))
	var parent := c.get_parent()
	if parent:
		var at := c.get_index()
		parent.remove_child(c)
		parent.add_child(n)
		parent.move_child(n, at)
		if c.owner:
			n.owner = c.owner
			n.unique_name_in_owner = c.unique_name_in_owner
	c.queue_free()
	return n


## Colours, role accessories and hat from a leader (or staff) dictionary.
static func apply_look(c: Cometling, look: Dictionary, role := "") -> void:
	c.role = role if role != "" else TycoonCrew.look_role(String(look.get("profession", "")))
	c.set_colors(Color(String(look.get("body", "#bfe9ff"))), Color(String(look.get("spot", "#f59a36"))), c.glow_color)
	LeaderHat.wear(c, String(look.get("hat", "role")))
