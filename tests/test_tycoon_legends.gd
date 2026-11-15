extends SceneTree
## Headless checks for As Lendas (src/tycoon/crew/tycoon_legends.gd, data/tycoon/legends.json):
## the data and its texts in both languages, a legendary hire that comes to the market once on
## its year and leaves for good, hiring it (look, unique specialisation, team bonus), the
## mentors' lines on the briefings and their agency bonus, the rival leaders on the Tail Radio,
## the "Quem inspirou" cards, save / load and an old save without Lendas, and the scenes that
## show them (golden card, mentor bubble, race face, encyclopedia pages), and the Lendas' own
## Cometlings (legends.json `scene`: each loads as a LegendCometling with its outfit, and
## TycoonLeader.dress / swap_body put it where a Lenda shows and take it back).
## Run: godot --headless --path . --script res://tests/test_tycoon_legends.gd

const SLOT := "test_legends"

var _failures := 0
var _checks := 0


func _staff() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"id": "a", "name": "Ana", "profession": "systems_engineer", "level": 1},
		{"id": "b", "name": "Bia", "profession": "scientist", "level": 3},
		{"id": "c", "name": "Caio", "profession": "pilot", "level": 2, "xp": 100.0},
		{"id": "d", "name": "Duda", "profession": "flight_controller", "level": 1}]
	return out


func _initialize() -> void:
	_check_data()
	_check_market()
	_check_hire()
	_check_mentors()
	_check_rivals()
	_check_cards_and_save()
	_check_scenes()
	await _check_bodies()
	print("LEGENDS TESTS: %s (%d checks, %d failures)" % ["OK" if _failures == 0 else "FAIL", _checks, _failures])
	quit(1 if _failures else 0)


# ------------------------------------------------------------ data
func _check_data() -> void:
	var all := TycoonLegends.all()
	_check(all.size() == 19, "19 Lendas in the data (got %d)" % all.size())
	_check(TycoonLegends.of_kind("hire").size() == 9 and TycoonLegends.of_kind("mentor").size() == 7
		and TycoonLegends.of_kind("rival_leader").size() == 3, "9 hires, 7 mentors, 3 rival leaders")
	var hats := TycoonLeader.hats()
	var bad: Array[String] = []
	for loc in ["pt_BR", "en"]:
		TranslationServer.set_locale(loc)
		for l: Dictionary in all:
			var id := String(l["id"])
			var parts := ["NAME", "ROLE", "WAY", "SPEC", "SPEC_DESC", "REAL", "FACT"]
			if l["kind"] == "mentor":
				parts.append("HINT")
			if l["kind"] == "rival_leader":
				parts.append_array(["FIRST", "FAIL", "CHEER"])
			for part in parts:
				var k := TycoonLegends.key(id, part)
				if TranslationServer.translate(k) == k:
					bad.append("%s %s" % [loc, k])
	TranslationServer.set_locale("pt_BR")
	_check(bad.is_empty(), "every Lenda text exists in pt-BR and en %s" % ("" if bad.is_empty() else str(bad.slice(0, 6))))
	var looks := true
	var sources := true
	for l: Dictionary in all:
		var id := String(l["id"])
		looks = looks and String(TycoonLegends.look(id)["hat"]) in hats
		sources = sources and (not TycoonLegends.sources(id).is_empty() or TycoonLegends.is_original(id))
	_check(looks, "every Lenda wears a hat of the look options (leader.json hats)")
	_check(sources, "every Lenda homaging a real person cites a source")
	_check(String(TycoonLegends.look("albertinho")["hat"]) == "propeller", "Albertinho wears the propeller cap")
	for h in ["aviator", "headset", "glasses", "mortarboard", "coin"]:
		_check(TranslationServer.translate("TY_LEADER_HAT_" + h.to_upper()) != "TY_LEADER_HAT_" + h.to_upper(), "hat %s has a name" % h)


# ------------------------------------------------------------ hiring market
func _check_market() -> void:
	var s := TycoonState.new_campaign(42, _staff())
	TycoonCrew.ensure(s)
	_check(not _has_legend(TycoonCrew.candidates(s)), "no Lenda on the first market (year 1)")
	var katia := TycoonLegends.legend("katia")
	var arrival_week := (int(katia["year"]) - 1) * s.weeks_per_year()
	var first_seen := -1
	var appearances := 0
	var was_on := false
	var max_cands := 0
	while s.weeks < arrival_week + 3 * s.weeks_per_year():
		s.advance_week()
		var on := _has_legend(TycoonCrew.candidates(s), "katia")
		if on and not was_on:
			appearances += 1
			if first_seen < 0:
				first_seen = s.weeks
				max_cands = TycoonCrew.candidates(s).size()
		was_on = on
	_check(appearances == 1, "Kátia Jonsom comes to the market exactly once (%d)" % appearances)
	_check(first_seen >= arrival_week and first_seen < arrival_week + 6, "she comes on her year's first market (week %d)" % first_seen)
	_check(max_cands == 4, "a golden card on top of the 3 usual candidates (%d)" % max_cands)
	_check(TycoonLegends.seen(s, "katia") and int(TycoonLegends.st(s)["seen"]["katia"]) == first_seen, "the market remembers she came")
	_check(not TycoonLegends.hired(s, "katia"), "nobody hired her")
	var news := 0
	for n in s.news:
		news += 1 if String(n.get("key", "")) == "TY_LEG_NEWS_MARKET" else 0
	_check(news >= 1, "the Tail Radio announces the Lenda")
	# the same seed gives the same market, Lendas included
	var a := TycoonState.new_campaign(7, _staff())
	var b := TycoonState.new_campaign(7, _staff())
	for i in 70:
		a.advance_week()
		b.advance_week()
	_check(JSON.stringify(TycoonCrew.candidates(a)) == JSON.stringify(TycoonCrew.candidates(b)), "same seed, same market with Lendas")


# ------------------------------------------------------------ hiring one
func _check_hire() -> void:
	var s := TycoonState.new_campaign(42, _staff())
	s.cash = 5.0e6
	var c := TycoonLegends.dev_spawn(s, "albertinho")
	_check(String(c.get("legend", "")) == "albertinho" and TycoonCrew.candidates(s)[0] == c, "dev: Albertinho on top of the market")
	_check((c["hidden"] as Array).is_empty() and int(c["level"]) == 3, "a Lenda's traits are all known, level 3")
	_check(TycoonLegends.weeks_left(s, "albertinho") >= 1, "the golden card says how long it stays")
	_check(TycoonCrew.hire(s, String(c["id"])) == "", "hire the Lenda")
	var m: Dictionary = s.staff[s.staff.size() - 1]
	_check(String(m.get("legend", "")) == "albertinho" and String(m.get("hat", "")) == "propeller", "the staff member keeps the legend and its look")
	_check(TycoonLegends.hired(s, "albertinho"), "the Lenda is marked as hired")
	_check(is_equal_approx(TycoonCrew.spec_effect(m, "crew_risk"), -0.3), "unique specialisation: -30% crewed risk")
	_check((m.get("specs", []) as Array).is_empty() and TycoonCrew.spec_slots(s, m)[0]["chosen"] == "",
		"the regular specialisation slots stay free")
	# the team bonus: +10% Operations for the teammates
	var p := MissionProject.new()
	p.id = "p1"
	p.type_id = "sounding"
	p.target_id = "suborbital"
	p.staff_ids.assign(["a", String(m["id"])])
	_check(is_equal_approx(p.member_team_mult(s, TycoonCrew.find(s, "a"), ProjectRules.OPS), 1.1)
		and is_equal_approx(p.member_team_mult(s, m, ProjectRules.OPS), 1.0), "teammates get +10% Operations, not the Lenda itself")
	_check(TycoonLegends.dev_spawn(s, "albertinho").is_empty() == false, "dev can bring a Lenda back")
	var k := TycoonLegends.dev_spawn(s, "katia")
	_check(is_equal_approx(TycoonLegends.member_effect({"legend": "katia"}, "review_dv"), -0.5), "Kátia halves the Δv margin risk")
	_check(TycoonLegends.dev_spawn(s, "nobody").is_empty() and TycoonLegends.dev_spawn(s, "berta").is_empty(), "only hires go to the market")
	# the campus and the portraits dress a Lenda in its own look
	var look := TycoonLegends.look(String(k["legend"]))
	_check(TycoonLegends.is_legend(look) and String(look["hat"]) == "headset", "a Lenda's portrait look carries its hat")


# ------------------------------------------------------------ mentors
func _check_mentors() -> void:
	var s := TycoonState.new_campaign(42, _staff())
	TycoonLegends.dev_mentors = false
	var crop := BriefingDesk.briefing("crop_health")   # a government client (weather service)
	_check(TycoonLegends.active_mentors(s).size() == 1, "year 1: only Halleyzinho is around (%d)" % TycoonLegends.active_mentors(s).size())
	_check(TycoonLegends.mentor_hints(s, crop, true).is_empty(), "year 1: nobody comments the weather contract")
	_check(is_zero_approx(TycoonLegends.mentor_effect(s, "agency_xp")), "year 1: no mentor bonus yet")
	s.weeks = 2 * s.weeks_per_year()   # year 3
	var hints := TycoonLegends.mentor_hints(s, crop, false)
	_check(hints.size() == 1 and String(hints[0]["legend"]) == "berta" and String(hints[0]["key"]) == "TY_LEG_BERTA_HINT",
		"Berta Luzinha comments the government contract (%s)" % [hints])
	var line := TycoonHUD.news_text(hints[0]) if not hints.is_empty() else ""
	_check(line.contains("Berta") and not line.contains("TY_"), "her line reads well: %s" % line)
	var quiet := TycoonLegends.mentor_hints(s, crop, true)
	_check(quiet.size() == 2 and String(quiet[0]["legend"]) == "dora", "when the team has no hunch, Dora says which profession it needs")
	_check(TycoonLegends.mentor_hints(s, BriefingDesk.briefing("first_hop"), false).is_empty(), "a dream nobody mentors gets no line")
	_check(is_equal_approx(TycoonLegends.mentor_effect(s, "agency_xp"), 0.15) and is_equal_approx(TycoonLegends.mentor_effect(s, "gov_reward"), 0.1),
		"mentor bonus: +15% XP for everyone, +10% on government contracts")
	var xp0 := float(TycoonCrew.find(s, "a")["xp"])
	TycoonCrew.add_xp(s, "a", 100.0)
	_check(absf(float(TycoonCrew.find(s, "a")["xp"]) - xp0 - 115.0) < 0.01, "Dora teaches the campus: 100 XP become 115")
	# the board in the briefing screen uses the same lines; the dev menu brings every mentor
	TycoonLegends.dev_mentors = true
	_check(TycoonLegends.mentor_active(s, "sali"), "dev: every mentor around")
	var crewed := TycoonLegends.mentor_hints(s, BriefingDesk.briefing("earthrise"), false)
	_check(not crewed.is_empty() and String(crewed[0]["legend"]) == "sali" and (crewed[0]["args"] as Array).size() == 2,
		"Sali Carona tells the two bars a crewed client values most")
	TycoonLegends.dev_mentors = false


# ------------------------------------------------------------ rival leaders
func _check_rivals() -> void:
	_check(TycoonLegends.rival_leader_id("aurora") == "gagarinho" and TycoonLegends.rival_leader_id("nimbo") == "cifrinha"
		and TycoonLegends.rival_leader_id("quietude") == "herschelinha", "each rival agency has its leader")
	var s := TycoonState.new_campaign(42, _staff())
	_check(s.race.leader_of("aurora").get("id", "") == "gagarinho" and s.race.leader_of(RaceDirector.PLAYER).is_empty(),
		"the race knows the leaders (the player has none)")
	s.race.claim("suborbital", "aurora")
	_check(String(s.news[0]["key"]) == "TY_RACE_NEWS_FIRST" and String(s.news[1]["key"]) == "TY_RACE_LEADER_SAYS"
		and String(s.news[1]["args"][1]) == "TY_LEG_GAGARINHO_FIRST", "Gagarinho has a word on the Tail Radio under the headline")
	var said := TycoonHUD.news_text(s.news[1])
	_check(said.contains("Gagarinho") and not said.contains("TY_"), "the line reads well: %s" % said)
	s.race.claim("first_satellite", RaceDirector.PLAYER)
	var cheer := String(s.news[1]["key"])
	_check(cheer.begins_with("TY_LEG_") and cheer.ends_with("_CHEER"), "a rival leader cheers the player's first (%s)" % cheer)


# ------------------------------------------------------------ cards and saves
func _check_cards_and_save() -> void:
	var s := TycoonState.new_campaign(4242, _staff())
	TycoonLeader.found(s, {"name": "Jujuba", "profession": "pilot", "hat": "aviator"})
	_check(String(TycoonLeader.member(s)["hat"]) == "aviator", "the leader can wear a Lenda's hat")
	var cards := TycoonLegends.cards(s)
	var on := cards.filter(func(c: Dictionary) -> bool: return c["unlocked"])
	_check(cards.size() == 19, "a Quem inspirou card per Lenda (%d)" % cards.size())
	var ids: Array = on.map(func(c: Dictionary) -> String: return String(c["id"]))
	_check("gagarinho" in ids and "halleyzinho" in ids and not "katia" in ids and not "berta" in ids,
		"year 1: the rival leaders and Halleyzinho are known, hires and later mentors locked (%s)" % [ids])
	s.cash = 5.0e6
	var c := TycoonLegends.dev_spawn(s, "valentina")
	TycoonCrew.hire(s, String(c["id"]))
	TycoonLegends.dev_spawn(s, "mae")
	for i in 3:
		s.advance_week()
	_check(TycoonSave.save(s, SLOT) == OK, "save with Lendas")
	var l := TycoonSave.load_state(SLOT)
	_check(l != null, "load it back")
	if l == null:
		return
	_check(TycoonLegends.hired(l, "valentina") and TycoonLegends.seen(l, "mae"), "who came and who was hired survive")
	var v := {}
	for m in l.staff:
		if String(m.get("legend", "")) == "valentina":
			v = m
	_check(not v.is_empty() and String(v["hat"]) == "bow" and is_equal_approx(TycoonCrew.spec_effect(v, "overwork_weeks"), 4.0),
		"the legendary staff member keeps look and specialisation")
	_check(_has_legend(TycoonCrew.candidates(l), "mae"), "the golden card is still on the market")
	for i in 30:
		s.advance_week()
		l.advance_week()
	_check(_canon(s.to_dict()) == _canon(l.to_dict()), "30 weeks after loading equal 30 weeks without saving")
	# a campaign saved before the Lendas existed
	var d := s.to_dict()
	(d["crew"] as Dictionary).erase("legends")
	for m: Dictionary in d["staff"]:
		m.erase("legend")
	var old := TycoonSave.state_from(TycoonSave.decode(JSON.parse_string(JSON.stringify(TycoonSave.encode(d)))))
	_check(old != null and not TycoonLegends.seen(old, "valentina"), "an old save loads with no Lenda seen")
	for i in 60:
		old.advance_week()
	_check(old.weeks == s.weeks + 60, "and keeps running")
	TycoonSave.delete(SLOT)


# ------------------------------------------------------------ scenes
func _check_scenes() -> void:
	var crew := (load("res://scenes/tycoon/ui/screens/crew.tscn") as PackedScene).instantiate()
	_check(crew.get_node_or_null("%LegendCandTemplate") != null and crew.get_node_or_null("%LegendSpec") != null
		and crew.get_node_or_null("%WhoInspired") != null, "crew screen: golden card, unique specialisation and Quem inspirou key")
	var gold := crew.get_node("%LegendCandTemplate") as Button
	_check(gold.get_node_or_null("Box/Ribbon") != null and gold.get_node_or_null("Box/Spec") != null and gold.get_node_or_null("Box/Once") != null,
		"golden card: ribbon, specialisation and how long it stays")
	crew.free()
	var br := (load("res://scenes/tycoon/ui/screens/briefings.tscn") as PackedScene).instantiate()
	var mt := br.get_node_or_null("%MentorTemplate")
	_check(mt != null and mt.get_node_or_null("Row/Visor/Portrait") != null and mt.get_node_or_null("Row/VBox/Head/Name") != null,
		"briefing board: a mentor bubble with portrait and name")
	br.free()
	var race := (load("res://scenes/tycoon/ui/screens/race.tscn") as PackedScene).instantiate()
	_check(race.get_node_or_null("%LeaderBox") != null and race.get_node_or_null("%AgencyTemplate/Box/Head/Face") != null,
		"race board: the leader's face on the tile and the agency page")
	race.free()
	var book := (load("res://scenes/tycoon/ui/screens/book.tscn") as PackedScene).instantiate()
	_check(book.get_node_or_null("%LegendsTile") != null and book.get_node_or_null("%LegendTemplate") != null
		and book.get_node_or_null("%LSheet") != null and book.get_node_or_null("%LSourceTemplate") != null,
		"encyclopedia: the Quem inspirou shelf, cards and page")
	book.free()
	var hat := (load("res://scenes/tycoon/leader/leader_hat.tscn") as PackedScene).instantiate()
	var missing: Array[String] = []
	for h in TycoonLeader.hats():
		if not h in ["role", "none"] and hat.get_node_or_null(String(h).to_pascal_case()) == null:
			missing.append(h)
	_check(missing.is_empty(), "every hat option has its model in leader_hat.tscn %s" % [missing])
	hat.free()


# ------------------------------------------------------------ the Lendas' own Cometlings
## Lendas that must have their own scene already (the others may still be on the way: a scene
## path whose file is not there yet is only reported).
const MUST_HAVE_SCENE := ["katia", "albertinho", "cesinha", "valentina", "pontinha", "mariazinha", "margo", "nilo",
	"mae", "halleyzinho"]


func _check_bodies() -> void:
	var holder := Node3D.new()
	get_root().add_child(holder)
	await process_frame   # the tree runs from the first frame on (nodes get _ready from then)
	var bad: Array[String] = []
	var loaded := 0
	for l: Dictionary in TycoonLegends.all():
		var id := String(l["id"])
		var path := String(l.get("scene", ""))
		if path == "" or not ResourceLoader.exists(path):
			if id in MUST_HAVE_SCENE:
				bad.append("%s: no scene" % id)
			elif path != "":
				print("  note  %s: scene %s not there yet" % [id, path])
			continue
		_check(TycoonLegends.scene_path(id) == path, "%s: scene_path finds %s" % [id, path])
		var c := TycoonLegends.instance(id)
		if c == null:
			bad.append("%s: %s is not a LegendCometling" % [id, path])
			continue
		holder.add_child(c)
		loaded += 1
		if c.legend_id != id:
			bad.append("%s: legend_id is '%s'" % [id, c.legend_id])
		if c.habit_names.is_empty():
			bad.append("%s: no habits" % id)
		for h in c.habit_names:
			if not c.knows_habit(h) or not c.play_habit(h):
				bad.append("%s: habit %s does not play" % [id, h])
		c.stop_shot()
		# its outfit: meshes of its own that keep their own material, no profession gear
		var own := 0
		var skin := 0
		for mi in c.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.material_override == c.body_material or m.material_override == c.face_material 					or m.material_override == c.lid_material:
				skin += 1
			elif m.material_override != null:
				own += 1
		if own < 20 or skin < 10:
			bad.append("%s: outfit meshes %d, skin meshes %d" % [id, own, skin])
		for g in ["Rig/Hips/Neck/Helmet", "Rig/Hips/Neck/HardHat", "Rig/Hips/Neck/Goggles", "Rig/Hips/Vest",
				"Rig/Hips/Belt", "Rig/Hips/Backpack", "Rig/Hips/Scarf"]:
			var n := c.get_node_or_null(g) as Node3D
			if n and n.visible:
				bad.append("%s: shows %s" % [id, g])
		c.talk(true)
		if c.current_action() != "talk":
			bad.append("%s: talk(true) does not talk" % id)
		c.talk(false)
		c.advance(0.5)
	_check(bad.is_empty(), "%d Lenda scenes load as LegendCometlings with outfit, habits and talk %s" % [loaded, bad])
	await process_frame
	# dress / swap_body: a Lenda with a scene stands in for the shared Cometling and goes back
	var plain := (load("res://scenes/npc/creature.tscn") as PackedScene).instantiate() as Cometling
	plain.name = "Creature"
	plain.listen_to_events = false
	plain.position = Vector3(1, 0, 2)
	holder.add_child(plain)
	var lg := TycoonLegends.look("albertinho")
	var c2 := TycoonLeader.dress(plain, lg)
	_check(c2 is LegendCometling and c2.name == "Creature" and c2.get_parent() == holder and c2.position == Vector3(1, 0, 2)
		and not c2.listen_to_events, "dress: Albertinho's own body takes the Cometling's place, name and settings")
	var c3 := TycoonLeader.dress(c2, TycoonLegends.look("valentina"))
	_check(c3 is LegendCometling and (c3 as LegendCometling).legend_id == "valentina" and c3.name == "Creature",
		"dress: one Lenda's body swaps for another's")
	var c4 := TycoonLeader.dress(c3, {"id": "x", "profession": "pilot", "variant": 2})
	_check(not c4 is LegendCometling and c4.scene_file_path == "res://scenes/npc/creature.tscn" and c4.name == "Creature",
		"dress: a member who is no Lenda gets the shared Cometling back")
	var c5 := TycoonLeader.dress(c4, {"id": "y", "legend": "no_such_lenda", "profession": "pilot", "body": "#ffffff",
		"spot": "#000000", "hat": "bow"})
	_check(c5 == c4, "dress: a Lenda without a scene keeps the shared Cometling (colours and hat)")
	await process_frame
	# the campus walker: the Lenda walks in its own body, a reused walker gets the Cometling back
	var w := (load("res://scenes/tycoon/campus_cometling.tscn") as PackedScene).instantiate()
	holder.add_child(w)
	var m := {"id": "s9", "legend": "nilo", "profession": "pilot", "body": "#aeeeb6", "spot": "#ffffff", "hat": "aviator"}
	w.call("set_leader", m)
	var wc: Node = w.get("creature")
	_check(wc is LegendCometling and wc == w.get_node("Creature") and (wc as Node3D).scale.is_equal_approx(Vector3.ONE * 1.6),
		"campus: a Lenda on campus walks in its own body (same node, same size)")
	w.call("set_leader", {})
	wc = w.get("creature")
	_check(not wc is LegendCometling and wc == w.get_node("Creature"), "campus: the walker gets the shared Cometling back")
	holder.queue_free()
	await process_frame


# ------------------------------------------------------------ helpers
static func _canon(d: Dictionary) -> String:
	var j: Variant = JSON.parse_string(JSON.stringify(TycoonSave.encode(d), "", true, true))
	return JSON.stringify(j, "", true, true)


func _has_legend(cands: Array, id := "") -> bool:
	for c: Dictionary in cands:
		if TycoonLegends.is_legend(c) and (id == "" or String(c["legend"]) == id):
			return true
	return false


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1
