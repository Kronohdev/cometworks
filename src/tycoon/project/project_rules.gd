class_name ProjectRules
extends RefCounted
## Balance numbers of the mission project loop (GDD sections 6.4-6.6 and Appendix C), read
## once from data/tycoon/projects.json. Nothing here touches a scene or the state; the
## other project classes ask this one for phases, sliders and constants.

const PATH := "res://data/tycoon/projects.json"
## the four quality bars, in the order every points array uses
const BARS: Array[String] = ["eng", "sci", "ops", "rel"]
const ENG := 0
const SCI := 1
const OPS := 2
const REL := 3

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(PATH)
	return _data


static func section(name: String) -> Dictionary:
	return data().get(name, {})


static func num(sect: String, key: String, fallback := 0.0) -> float:
	return float(section(sect).get(key, fallback))


static func phases() -> Array:
	return data().get("phases", [])


static func phase(k: int) -> Dictionary:
	var ph := phases()
	return ph[clampi(k, 0, ph.size() - 1)] if not ph.is_empty() else {}


## The 3 sliders of phase k: [{"id", "name_key", "feeds": {bar: weight}, ...}].
static func sliders(k: int) -> Array:
	return phase(k).get("sliders", [])


## How much of each bar one unit of slider time produces in phase k: Array of 4 floats per
## slider, in BARS order.
static func feed_matrix(k: int) -> Array:
	var out: Array = []
	for sl: Dictionary in sliders(k):
		var row: Array[float] = [0.0, 0.0, 0.0, 0.0]
		var feeds: Dictionary = sl.get("feeds", {})
		for b in BARS.size():
			row[b] = float(feeds.get(BARS[b], 0.0))
		out.append(row)
	return out


## foco(b, fase, sliders) of GDD 6.5: sum of the phase's sliders times their weight in b (0..1).
static func focus(k: int, values: Array) -> Array[float]:
	var f: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var m := feed_matrix(k)
	for s in mini(m.size(), values.size()):
		for b in 4:
			f[b] += float(values[s]) * float(m[s][b])
	return f


## Affinity of a profession for bar b (GDD 6.5): primary 1.0, secondary 0.4, others 0.15.
static func affinity(prof: Dictionary, bar: String, pdata: Dictionary) -> float:
	var a: Dictionary = pdata.get("affinity", {"primary": 1.0, "secondary": 0.4, "other": 0.15})
	if String(prof.get("primary", "")) == bar:
		return float(a.get("primary", 1.0))
	if String(prof.get("secondary", "")) == bar and bar != "":
		return float(a.get("secondary", 0.4))
	return float(a.get("other", 0.15))


## Compatibility multiplier of a mission type on a target: 1.15 great, 1.0 good, 0.75 poor,
## 0.0 impossible (the target is not in the type's compat table).
static func compat(mtype: Dictionary, target_id: String) -> float:
	return float(mtype.get("compat", {}).get(target_id, 0.0))


## "great" | "good" | "poor" | "impossible"
static func compat_tier(mult: float) -> String:
	if mult <= 0.0:
		return "impossible"
	var tiers := section("compat_tiers")
	if mult >= float(tiers.get("great", 1.15)) - 0.001:
		return "great"
	if mult >= float(tiers.get("good", 1.0)) - 0.001:
		return "good"
	return "poor"


static func expectation_era(era: int) -> float:
	var arr: Array = section("grade").get("expectation_era", [60])
	return float(arr[clampi(era - 1, 0, arr.size() - 1)])


static func week_cost(mtype: Dictionary, era: int) -> float:
	var c := section("cost")
	var ef: Array = c.get("era_factor", [1.0])
	return float(c.get("week_base", 6000)) * float(mtype.get("size", 1.0)) * float(ef[clampi(era - 1, 0, ef.size() - 1)])


static func launch_class(type_id: String) -> String:
	return String(section("launch").get("type_class", {}).get(type_id, "light"))


static func launch_cost(type_id: String) -> float:
	return float(section("launch").get("classes", {}).get(launch_class(type_id), 150000))


static func ops_weeks(type_id: String) -> int:
	return int(section("launch").get("ops_weeks", {}).get(type_id, 12))


static func is_crewed(type_id: String) -> bool:
	return type_id in section("launch").get("crewed_types", [])


## Last week index (exclusive) of phase k in a project of `weeks_total` weeks: each phase is
## a third of the weeks (rounded), never shorter than one week.
static func phase_end(weeks_total: int, k: int) -> int:
	if k >= 2:
		return weeks_total
	return clampi(roundi(weeks_total * (k + 1) / 3.0), k + 1, weeks_total - (2 - k))


## Moves slider `index` of a 3-slider set (integer percents summing to 100) to `value` and
## shares what is left between the other two in their previous proportion ("moving one pulls
## the others", GDD 22.4). Returns the new set.
static func rebalance(values: Array, index: int, value: int) -> Array[int]:
	var v := clampi(value, 0, 100)
	var out: Array[int] = [0, 0, 0]
	for i in 3:
		out[i] = int(values[i]) if i < values.size() else 0
	out[index] = v
	var a := (index + 1) % 3
	var b := (index + 2) % 3
	var rest := 100 - v
	var old := out[a] + out[b]
	if old <= 0:
		out[a] = rest / 2 + rest % 2
	else:
		out[a] = roundi(float(rest) * out[a] / old)
	out[b] = rest - out[a]
	return out
