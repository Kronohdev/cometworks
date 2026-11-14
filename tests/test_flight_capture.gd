extends SceneTree
## Headless checks for the automatic orbit insertion (src/flight/flight_capture.gd):
## from a 200 km LEO with a trans-lunar injection node, plan a capture around the Moon
## for several wanted orbits (altitude, apoapsis, inclination incl. polar and retrograde)
## and check the predicted orbit after the capture node.
## Run: godot --headless --path . --script res://tests/test_flight_capture.gd

const R := FlightOrbit.R
const MU := FlightOrbit.MU

var _failures := 0
var sys: FlightSolar


func _initialize() -> void:
	sys = FlightSolar.get_system()
	var t0 := Time.get_ticks_msec()
	var r1 := R + 200000.0
	var r2 := sys.sma[sys.moon]
	var at := (r1 + r2) * 0.5
	var t_tr := PI * sqrt(at * at * at / MU)
	var n_leo := sqrt(MU / (r1 * r1 * r1))
	var t_node := 1200.0
	# off-target on purpose (a few degrees late): the correction has work to do
	var th := sys.phase[sys.moon] + sys.rate[sys.moon] * (t_node + t_tr) - PI - n_leo * t_node + deg_to_rad(4.0)
	var s := _leo(200000.0, th)
	var tli := FlightManeuverNode.new(t_node, Vector3(sqrt(MU * (2.0 / r1 - 1.0 / at)) - sqrt(MU / r1), 0.0, 0.0))
	var nodes: Array[FlightManeuverNode] = [tli]
	var cases := [
		[100000.0, 100000.0, NAN, "100 km circular, plane kept"],
		[60000.0, 600000.0, 90.0, "60 x 600 km polar"],
		[250000.0, 250000.0, 160.0, "250 km circular retrograde (160°)"],
		[30000.0, 30000.0, 20.0, "30 km circular, 20°"],
	]
	for c in cases:
		var cap := FlightCapture.new(sys, sys.earth, s[0], s[1], 0.0, nodes, 60.0)
		var tg := cap.target()
		var t1 := Time.get_ticks_msec()
		var res := cap.plan(c[0], c[1], c[2])
		var ms := Time.get_ticks_msec() - t1
		print("%s: %s" % [c[3], _fmt(res)])
		print("    target %s, %d ms" % [str(tg), ms])
		_check(res["ok"] and int(res["body"]) == sys.moon, "%s: planned around the Moon" % c[3])
		if not res["ok"]:
			continue
		var pe: float = res["pe"]
		var ap: float = res["ap"]
		_check(absf(pe - c[0]) < maxf(c[0] * 0.03, 2000.0), "%s: Pe %.1f km (want %.0f)" % [c[3], pe / 1000.0, c[0] / 1000.0])
		_check(absf(ap - c[1]) < maxf(c[1] * 0.05, 5000.0), "%s: Ap %.1f km (want %.0f)" % [c[3], ap / 1000.0, c[1] / 1000.0])
		if not is_nan(c[2]):
			_check(absf(float(res["inc"]) - c[2]) < 1.5, "%s: inclination %.2f° (want %.0f)" % [c[3], res["inc"], c[2]])
		_check(float(res["dv_corr"]) < 300.0 and float(res["dv_capt"]) < 1500.0, "%s: Δv sane (corr %.1f, capture %.1f m/s)" % [
			c[3], res["dv_corr"], res["dv_capt"]])
	# nothing to capture: LEO without nodes
	var none := FlightCapture.new(sys, sys.earth, s[0], s[1], 0.0, [] as Array[FlightManeuverNode]).plan(100000.0, 100000.0, NAN)
	_check(not none["ok"] and none["msg"] == "FL_CAPT_NO_ENCOUNTER", "no encounter -> refused")
	print("time %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("RESULT: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(1 if _failures else 0)


func _fmt(res: Dictionary) -> String:
	if not res["ok"]:
		return "refused (%s)" % res["msg"]
	return "Pe %.1f km, Ap %.1f km, inc %.2f°, corr %.2f m/s, capture %.1f m/s, %d nodes %s" % [float(res["pe"]) / 1000.0,
		float(res["ap"]) / 1000.0, res["inc"], res["dv_corr"], res["dv_capt"], res["nodes"].size(), res["msg"]]


func _check(ok: bool, msg: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + msg)
	if not ok:
		_failures += 1


func _leo(alt: float, th: float) -> Array[PackedFloat64Array]:
	var r := R + alt
	var p := sys.plane_p[sys.moon]
	var q := sys.plane_q[sys.moon]
	var vc := sqrt(MU / r)
	var pos := PackedFloat64Array([r * (cos(th) * p[0] + sin(th) * q[0]), r * (cos(th) * p[1] + sin(th) * q[1]),
		r * (cos(th) * p[2] + sin(th) * q[2])])
	var vel := PackedFloat64Array([vc * (-sin(th) * p[0] + cos(th) * q[0]), vc * (-sin(th) * p[1] + cos(th) * q[1]),
		vc * (-sin(th) * p[2] + cos(th) * q[2])])
	return [pos, vel]
