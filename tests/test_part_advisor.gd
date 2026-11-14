extends SceneTree
## Headless test of the hangar part advisor (src/hangar/part_advisor.gd): pure rules over
## stage specs, no scene. Checks the empty vessel, propellant matching (a kerosene tank asks
## for kerosene engines, engines of another propellant are flagged), the missing flight
## computer, a tank-less engine, a rocket too heavy to lift off, a Δv short of the goal
## (upper stage + decoupler), the fairing for a payload, the crewed capsule, the problems
## list and the example rockets built with the real attach API.
## Run: godot --headless --path . --script res://tests/test_part_advisor.gd

var _failures := 0
var _checks := 0


func _initialize() -> void:
	await process_frame
	TranslationServer.set_locale("en")
	_test_empty()
	_test_tank_wants_engines()
	_test_engine_fit()
	_test_missing_core()
	_test_engine_wants_tank()
	_test_twr_low()
	_test_dv_short()
	_test_fairing_and_crew()
	_test_problems()
	_test_examples()
	print("checks: %d" % _checks)
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("  FAIL: " + msg)
	else:
		print("  ok: " + msg)


## One stage spec from part ids (core only).
func _stage(ids: Array) -> Dictionary:
	var core: Array = []
	for id in ids:
		var p := PartDB.get_part(id)
		assert(not p.is_empty(), "unknown part " + id)
		core.append(p)
	return {"core": core, "boosters": []}


func _ids(items: Array) -> Array:
	return items.map(func(it: Dictionary) -> String: return it["id"])


func _find(items: Array, id: String) -> Dictionary:
	for it in items:
		if it["id"] == id:
			return it
	return {}


func _with_reason(items: Array, reason: String) -> Array:
	return items.filter(func(it: Dictionary) -> bool: return it["reason"] == reason)


func _test_empty() -> void:
	var adv := PartAdvisor.advise([], PartAdvisor.free_goal())
	_check(adv.size() == 1 and PartDB.is_command(PartDB.get_part(adv[0]["id"])) and adv[0]["hint"] == "root",
		"empty vessel: start with a flight computer placed as the root (%s)" % [_ids(adv)])
	var crew := PartAdvisor.advise([], {"crewed": true})
	_check(not crew.is_empty() and PartAdvisor.is_crewed(PartDB.get_part(crew[0]["id"])),
		"empty vessel on a crewed mission: start with a capsule (%s)" % [_ids(crew)])


func _test_tank_wants_engines() -> void:
	# core + a kerosene tank, nothing burns it yet
	var specs := [_stage(["avionics_core_s", "tank_kerolox_s4"])]
	var adv := PartAdvisor.advise(specs, PartAdvisor.free_goal(), {"focus": "tank_kerolox_s4"})
	var engines := _with_reason(adv, "ADV_ENGINE_FOR")
	_check(not engines.is_empty(), "a kerosene tank asks for engines (%s)" % [_ids(adv)])
	var all_kero := true
	for it in engines:
		var e := PartDB.get_part(it["id"])
		all_kero = all_kero and PartDB.is_engine(e) and e["propellant"] == "kerolox"
	_check(all_kero, "every recommended engine burns kerosene/LOX")
	_check(not engines.is_empty() and PartDB.get_part(engines[0]["id"])["size"] == "S",
		"the first engine matches the tank size (S): %s" % [engines[0]["id"] if not engines.is_empty() else "-"])
	_check(not engines.is_empty() and float(PartDB.get_part(engines[0]["id"]).get("thrust_sl_kn", 0.0)) > 0.0,
		"the first stage gets an engine that works at the pad")
	_check(not engines.is_empty() and String(engines[0]["hint"]) == "below_tank:kerolox",
		"engine hint: below the kerosene tank")
	_check(not engines.is_empty() and PartAdvisor.reason_text(engines[0]).contains("Kerosene"),
		"the reason names the propellant: \"%s\"" % [PartAdvisor.reason_text(engines[0]) if not engines.is_empty() else ""])
	# hydrogen tank: hydrogen engines
	var h := PartAdvisor.advise([_stage(["avionics_core_m", "tank_hydrolox_m4"])], {})
	var he := _with_reason(h, "ADV_ENGINE_FOR")
	_check(not he.is_empty() and he.all(func(it: Dictionary) -> bool:
		return PartDB.get_part(it["id"])["propellant"] == "hydrolox"), "a hydrogen tank asks for hydrogen engines (%s)" % [_ids(he)])
	# held tank (not attached yet) on a vessel with no tank: still recommends its engines
	var held := PartAdvisor.advise([_stage(["avionics_core_m"])], {}, {"focus": "tank_methalox_m4"})
	var me := _with_reason(held, "ADV_ENGINE_FOR")
	_check(not me.is_empty() and PartDB.get_part(me[0]["id"])["propellant"] == "methalox",
		"the tank in hand asks for methane engines (%s)" % [_ids(me)])


func _test_engine_fit() -> void:
	var specs := [_stage(["avionics_core_s", "tank_kerolox_s4"])]
	_check(PartAdvisor.engine_fit("eng_falcao", specs) == 1, "Falcão (kerosene) fits a kerosene tank")
	_check(PartAdvisor.engine_fit("eng_hidra_rl", specs) == -1, "a hydrogen engine is flagged on a kerosene vessel")
	_check(PartAdvisor.engine_fit("eng_srb_s", specs) == 0, "solid boosters carry their own fuel (neutral)")
	_check(PartAdvisor.engine_fit("eng_hidra_rl", []) == 0, "no tanks yet: nothing to flag")
	_check(PartAdvisor.engine_fit("eng_hidra_rl", [_stage(["avionics_core_s"])], "tank_hydrolox_s4") == 1,
		"the focus tank counts for the match")
	# a mismatched engine on the stage: the advisor asks for the right tank and the right engine
	var mis := [_stage(["avionics_core_s", "tank_kerolox_s4", "eng_hidra_rl"])]
	var adv := PartAdvisor.advise(mis, {})
	var tank := _with_reason(adv, "ADV_TANK_FOR")
	var eng := _with_reason(adv, "ADV_ENGINE_FOR")
	_check(not tank.is_empty() and PartDB.get_part(tank[0]["id"])["propellant"] == "hydrolox",
		"mismatch: a hydrogen tank for the hydrogen engine (%s)" % [_ids(tank)])
	_check(not eng.is_empty() and PartDB.get_part(eng[0]["id"])["propellant"] == "kerolox",
		"mismatch: a kerosene engine for the kerosene tank (%s)" % [_ids(eng)])


func _test_missing_core() -> void:
	var specs := [_stage(["tank_kerolox_m4", "eng_metano_r", "tank_methalox_m4"])]
	var adv := PartAdvisor.advise(specs, {})
	var core := _with_reason(adv, "ADV_NO_CORE")
	_check(core.size() == 1 and PartDB.is_command(PartDB.get_part(core[0]["id"])), "no core: recommends a flight computer")
	_check(core.size() == 1 and PartDB.get_part(core[0]["id"])["size"] == "M" and core[0]["hint"] == "top",
		"the core matches the stack size (M) and goes on top")
	var with_core := PartAdvisor.advise([_stage(["avionics_core_m", "tank_methalox_m4", "eng_metano_r"])], {})
	_check(_with_reason(with_core, "ADV_NO_CORE").is_empty(), "with a core: no core advice")


func _test_engine_wants_tank() -> void:
	var specs := [_stage(["avionics_core_s", "eng_falcao"])]
	var adv := PartAdvisor.advise(specs, {})
	var tank := _with_reason(adv, "ADV_TANK_FOR")
	_check(not tank.is_empty(), "an engine without a tank asks for one (%s)" % [_ids(adv)])
	if not tank.is_empty():
		var t := PartDB.get_part(tank[0]["id"])
		_check(t["propellant"] == "kerolox" and t["size"] == "S", "the tank carries kerosene and matches the engine (S): %s" % t["id"])
		_check(String(tank[0]["hint"]) == "above_engine:eng_falcao", "tank hint: above the engine")


func _test_twr_low() -> void:
	# a big hydrogen stack on the tiny vacuum-ish Kestrel: heavy, weak
	var specs := [_stage(["avionics_core_s", "tank_kerolox_s8", "tank_kerolox_s8", "tank_kerolox_s8", "eng_kestrel"])]
	var a := VesselMath.analyze(specs)
	_check(a["liftoff_twr"] < 1.0, "test rocket really is too heavy (TWR %.2f)" % a["liftoff_twr"])
	var adv := PartAdvisor.advise(specs, PartAdvisor.free_goal())
	var more := _with_reason(adv, "ADV_MORE_THRUST")
	_check(not more.is_empty(), "TWR < 1: recommends more thrust (%s)" % [_ids(adv)])
	if not more.is_empty():
		var e := PartDB.get_part(more[0]["id"])
		var need := float(a["stages"][0]["m0_kg"]) * PartDB.G0 / 1000.0
		_check(e["propellant"] == "kerolox" and float(e["thrust_sl_kn"]) > need,
			"the stronger engine burns kerosene and lifts the rocket alone (%s, %.0f kN > %.0f kN)" % [e["id"], e["thrust_sl_kn"], need])
	_check(not _with_reason(adv, "ADV_BOOSTERS").is_empty(), "TWR < 1: solid boosters as the other way out")
	_check(_with_reason(adv, "ADV_UPPER_STAGE").is_empty(), "no staging advice while it cannot lift off")
	# vacuum engine at the pad
	var vac := PartAdvisor.advise([_stage(["avionics_core_s", "tank_kerolox_s4", "eng_falcao_v"])], {})
	var sl := _with_reason(vac, "ADV_SL_ENGINE")
	_check(not sl.is_empty() and float(PartDB.get_part(sl[0]["id"]).get("thrust_sl_kn", 0.0)) > 0.0,
		"a vacuum engine on the first stage: recommends a sea-level engine (%s)" % [_ids(vac)])


func _test_dv_short() -> void:
	var specs := [_stage(["avionics_core_s", "tank_kerolox_s4", "eng_falcao"])]
	var a := VesselMath.analyze(specs)
	_check(a["liftoff_twr"] >= 1.0 and a["ascent_dv"] < 9400.0, "single small stage flies but falls short (%.0f m/s)" % a["ascent_dv"])
	var adv := PartAdvisor.advise(specs, {"dv_needed": 9400.0})
	var up := _with_reason(adv, "ADV_UPPER_STAGE")
	_check(up.size() == 1 and PartDB.is_stack_decoupler(PartDB.get_part(up[0]["id"])), "Δv short: an upper stage via a decoupler (%s)" % [_ids(adv)])
	_check(up.size() == 1 and PartDB.get_part(up[0]["id"])["size"] == "S" and up[0]["hint"] == "bottom",
		"the decoupler matches the stack (S) and goes under it")
	var tank := _with_reason(adv, "ADV_MORE_TANK")
	_check(not tank.is_empty() and PartDB.get_part(tank[0]["id"])["propellant"] == "kerolox"
		and float(PartDB.get_part(tank[0]["id"])["prop_mass_kg"]) > 4550.0, "Δv short: a bigger kerosene tank (%s)" % [_ids(tank)])
	_check(not up.is_empty() and PartAdvisor.reason_text(up[0]).contains("m/s"), "the reason says how much is missing: \"%s\"" % [PartAdvisor.reason_text(up[0]) if not up.is_empty() else ""])
	# enough Δv for a small goal: no reach advice
	var easy := PartAdvisor.advise(specs, {"dv_needed": 1000.0})
	_check(_with_reason(easy, "ADV_UPPER_STAGE").is_empty() and _with_reason(easy, "ADV_MORE_TANK").is_empty(),
		"goal reached: no reach advice")
	# two stages already: more tank, no second decoupler
	var two := [_stage(["eng_falcao", "tank_kerolox_s4", "decoupler_s"]), _stage(["avionics_core_s", "tank_kerolox_s2", "eng_kestrel_v"])]
	var adv2 := PartAdvisor.advise(two, {"dv_needed": 20000.0})
	_check(_with_reason(adv2, "ADV_UPPER_STAGE").is_empty() and not _with_reason(adv2, "ADV_MORE_TANK").is_empty(),
		"two stages short of the goal: bigger tank, not another decoupler (%s)" % [_ids(adv2)])
	# an empty first stage under a decoupler asks for a tank
	var empty0 := [_stage(["decoupler_s"]), _stage(["avionics_core_s", "tank_kerolox_s4", "eng_falcao"])]
	var adv3 := PartAdvisor.advise(empty0, {"dv_needed": 9400.0})
	var first := _with_reason(adv3, "ADV_FIRST_STAGE")
	_check(not first.is_empty() and PartDB.get_part(first[0]["id"])["propellant"] == "kerolox" and first[0]["hint"] == "bottom",
		"empty first stage: a kerosene tank under the decoupler (%s)" % [_ids(adv3)])


func _test_fairing_and_crew() -> void:
	var specs := [_stage(["avionics_core_m", "tank_kerolox_m4", "eng_metano_r"])]
	var payload := PartAdvisor.advise(specs, {"payload_kg": 500.0})
	var f := _with_reason(payload, "ADV_FAIRING")
	_check(f.size() == 1 and PartDB.is_fairing(PartDB.get_part(f[0]["id"])) and PartDB.get_part(f[0]["id"])["size"] == "M",
		"a payload goal asks for a fairing of the stack size (%s)" % [_ids(payload)])
	var nosed := PartAdvisor.advise([_stage(["fairing_m", "avionics_core_m", "tank_kerolox_m4", "eng_metano_r"])], {"payload_kg": 500.0})
	_check(_with_reason(nosed, "ADV_FAIRING").is_empty(), "with a fairing: no fairing advice")
	var crew := PartAdvisor.advise(specs, {"crewed": true})
	var cap := _with_reason(crew, "ADV_CREW")
	_check(cap.size() == 1 and PartAdvisor.is_crewed(PartDB.get_part(cap[0]["id"])), "crewed mission without seats: a capsule (%s)" % [_ids(crew)])
	var unstable := PartAdvisor.advise(specs, {}, {"stable": 0})
	_check(not _with_reason(unstable, "ADV_FINS").is_empty(), "unstable rocket: fins")
	_check(_ids(PartAdvisor.advise(specs, {"dv_needed": 99999.0, "payload_kg": 500.0}, {"stable": 0})).size() <= PartAdvisor.MAX_ITEMS,
		"never more than %d recommendations" % PartAdvisor.MAX_ITEMS)


func _test_problems() -> void:
	_check(PartAdvisor.problems([], {}).is_empty(), "empty vessel: no problems")
	var bad := [_stage(["tank_kerolox_s4", "eng_hidra_rl"])]
	var pr := PartAdvisor.problems(bad, {"dv_needed": 9400.0, "budget_musd": 1.0}, {"cost": 5.0, "stable": 0})
	var keys := pr.map(func(p: Dictionary) -> String: return p["key"])
	for k in ["ADV_P_NO_CORE", "ADV_P_MISMATCH", "ADV_P_DV_SHORT", "ADV_P_OVER_BUDGET", "ADV_P_UNSTABLE"]:
		_check(keys.has(k), "problems list has %s (%s)" % [k, keys])
	_check(int(pr[0]["tone"]) == PartAdvisor.Tone.DANGER, "dangers come first")
	var mis := pr.filter(func(p: Dictionary) -> bool: return p["key"] == "ADV_P_MISMATCH")
	_check(not mis.is_empty() and PartAdvisor.problem_text(mis[0]).contains("Hydrogen") and PartAdvisor.problem_text(mis[0]).contains("Kerosene"),
		"mismatch line names both propellants: \"%s\"" % [PartAdvisor.problem_text(mis[0]) if not mis.is_empty() else ""])
	var heavy := [_stage(["avionics_core_s", "tank_kerolox_s8", "tank_kerolox_s8", "tank_kerolox_s8", "eng_kestrel"])]
	var hk := PartAdvisor.problems(heavy, {}).map(func(p: Dictionary) -> String: return p["key"])
	_check(hk.has("ADV_P_TWR_LOW"), "heavy rocket: TWR problem (%s)" % [hk])
	var bk := pr.map(func(p: Dictionary) -> String: return p["key"])
	_check(not bk.has("ADV_P_TWR_LOW"), "a dry engine is a fuel problem, not a thrust one (%s)" % [bk])
	var vac := PartAdvisor.problems([_stage(["avionics_core_s", "tank_kerolox_s4", "eng_falcao_v"])], {})
	_check(vac.any(func(p: Dictionary) -> bool: return p["key"] == "ADV_P_TWR_LOW"), "a vacuum engine at the pad cannot lift off")
	var dry := PartAdvisor.advise([_stage(["avionics_core_s", "eng_falcao"])], {})
	_check(_with_reason(dry, "ADV_BOOSTERS").is_empty() and _with_reason(dry, "ADV_MORE_THRUST").is_empty(),
		"a dry engine gets a tank, not boosters (%s)" % [_ids(dry)])
	var good := [_stage(["avionics_core_s", "tank_kerolox_s4", "eng_falcao"])]
	_check(PartAdvisor.problems(good, {"dv_needed": 1000.0}).is_empty(), "a sound little rocket has no problems")


## The example rockets (built with the real attach API) need no core / fuel / engine fixes.
func _test_examples() -> void:
	for id in ["andorinha", "condor", "garca"]:
		var v := Vessel.new()
		get_root().add_child(v)
		ExampleVessels.build(v, id)
		var st := v.compute_stages()
		var adv := PartAdvisor.advise(st["stages"], {"dv_needed": 9000.0, "payload_kg": ExampleVessels.PAYLOAD_KG[id]},
			{"fairing_kg": st["fairing_kg"]})
		var fixes := adv.filter(func(it: Dictionary) -> bool:
			return it["reason"] in ["ADV_NO_CORE", "ADV_TANK_FOR", "ADV_ENGINE_FOR", "ADV_MORE_THRUST", "ADV_FIRST_STAGE"])
		_check(fixes.is_empty(), "example %s needs no basic fixes (%s)" % [id, _ids(adv)])
		v.queue_free()
