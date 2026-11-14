class_name FocusView
extends RefCounted
## Texts and colours of what the agency knows about a mission type's bars (FocusStudy), shared by
## the project screens (phase, new project, team), the journal and the research lab's studies:
## the focus mark of a bar ("★ most", "▲ a lot", "40%", "?"), the knowledge line, how to learn
## more and the tier name. Strings only: every node they go into is authored in the scenes.

const MARK_COLORS := {"top": CwPalette.IGNITION, "high": CwPalette.IGNITION, "mid": CwPalette.INK_SOFT,
	"low": CwPalette.COMET_ICE, "bottom": CwPalette.COMET_ICE, "": CwPalette.TEXT_DIM}


static func _t(k: String) -> String:
	return TranslationServer.translate(k)


static func bar_name(b: int) -> String:
	return _t("TY_BAR_" + ProjectRules.BARS[b].to_upper())


static func type_name(s: TycoonState, type_id: String) -> String:
	return _t(String(s.mission_type(type_id).get("name_key", type_id)))


## The short mark of one bar_marks() row: "★ most" | "↓ least" | "▲ a lot" | "● some" |
## "▼ a little" | "40%" | "?" ("" for a tier-1 bar that is neither top nor bottom).
static func mark_text(m: Dictionary) -> String:
	if float(m.get("ideal", -1.0)) >= 0.0:
		return "%d%%" % roundi(float(m["ideal"]) * 100.0)
	var mark := String(m.get("mark", ""))
	if mark == "":
		return "?" if int(m.get("tier", 0)) == 0 else "·"
	return _t("TY_FS_MARK_" + mark.to_upper())


static func mark_color(m: Dictionary) -> Color:
	if float(m.get("ideal", -1.0)) >= 0.0:
		return CwPalette.TEXT
	return MARK_COLORS.get(String(m.get("mark", "")), CwPalette.TEXT_DIM)


static func tier_text(t: int) -> String:
	return _t("TY_FS_TIER") % t


## One line: what the agency knows of the type's balance at its tier.
static func know_text(s: TycoonState, type_id: String) -> String:
	var t := FocusStudy.tier(s, type_id)
	match t:
		0:
			return _t("TY_FS_KNOW_0")
		1:
			return _t("TY_FS_KNOW_1") % [_names(FocusStudy.top_bars(s, type_id)), _names(FocusStudy.bottom_bars(s, type_id))]
		2:
			var hi: Array[int] = []
			var lo: Array[int] = []
			for b in 4:
				var lv := FocusStudy.level(s, type_id, b)
				if lv == "high":
					hi.append(b)
				elif lv == "low":
					lo.append(b)
			return _t("TY_FS_KNOW_2") % [_names(hi), _names(lo)]
	return _t("TY_FS_KNOW_3")


## How to learn more: the study under way, or "study it in the lab or fly it (n/2 flights)".
static func how_text(s: TycoonState, type_id: String) -> String:
	var t := FocusStudy.tier(s, type_id)
	if t >= FocusStudy.MAX_TIER:
		return ""
	if FocusStudy.active(s) == type_id:
		var w := FocusStudy.weeks_left(s, type_id)
		return _t("TY_FS_HOW_STUDYING") % [t + 1, _t("TY_RS_NO_PP") if w < 0 else _t("TY_WEEKS") % w]
	var need := int(BriefingDesk.disc().get("reveal_ratio_after", 2))
	return _t("TY_FS_HOW") % [Discovery.attempts(s, type_id), need]


## "Engineering and Reliability" ("—" for none).
static func _names(bars: Array[int]) -> String:
	if bars.is_empty():
		return "—"
	var parts: Array[String] = []
	for b in bars:
		parts.append(bar_name(b))
	if parts.size() == 1:
		return parts[0]
	return _t("TY_FS_AND") % [", ".join(parts.slice(0, parts.size() - 1)), parts[-1]]
