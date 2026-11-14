class_name TycoonOpsFmt
extends RefCounted
## Number formatting shared by the mission map and the archive.


## 384400 -> "384 400" (thin spaces between groups of three).
static func int_str(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("−" if v < 0 else "") + s + out


## Campaign week index -> [year, week] (1-based).
static func year_week(state: TycoonState, w: int) -> Array:
	return [w / state.weeks_per_year() + 1, w % state.weeks_per_year() + 1]
