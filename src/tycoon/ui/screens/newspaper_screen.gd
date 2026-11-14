class_name NewspaperScreen
extends Control
## Front page of "O Eco da Cauda" (scenes/tycoon/ui/screens/newspaper.tscn), the one paper
## element of the UI (GDD section 22.4: a clipping taped over the panel). Opened by
## TycoonRaceFlow with open_with({"page": page}) for each page the RaceDirector prints: a
## first in the race (player or rival) or a rival's spectacular miss. Fills the masthead,
## headline, deck, quote, the real-science box and the race board; the look is the scene's.

var state: TycoonState
var clock: TycoonClock
var hud: TycoonHUD
var page: Dictionary = {}

@onready var paper: Control = %Paper


func _ready() -> void:
	%Continue.pressed.connect(close)
	# entry: the clipping slides 8 px and fades in (140 ms, cubic ease-out), unless the
	# scene's CwScreenTransition drops it in
	if CwScreenTransition.of(self) == null:
		var home := paper.position
		paper.modulate.a = 0.0
		paper.position.y = home.y + 8.0
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(paper, "modulate:a", 1.0, 0.14)
		tw.tween_property(paper, "position:y", home.y, 0.14)
	(func() -> void:
		if is_inside_tree():
			%Continue.grab_focus()).call_deferred()


func bind(s: TycoonState, c: TycoonClock, h: TycoonHUD) -> void:
	state = s
	clock = c
	hud = h


func open_with(args: Dictionary) -> void:
	page = args.get("page", {})
	fill()


func close() -> void:
	if hud:
		hud.close_screen()
	else:
		queue_free()


func fill() -> void:
	if state == null or page.is_empty():
		return
	var r := state.race
	var m := r.milestone(String(page.get("milestone", "")))
	var by := String(page.get("by", ""))
	var who := r.agency_name(by) if by == RaceDirector.PLAYER else tr(r.agency_name(by))
	var w := int(page.get("week", state.weeks))
	%Dateline.text = tr("TY_PAPER_DATELINE") % [w / state.weeks_per_year() + 1, w % state.weeks_per_year() + 1, int(page.get("issue", 1))]
	%Issue.text = "Nº %03d" % int(page.get("issue", 1))
	var short := tr(String(m.get("short_key", m.get("name_key", ""))))
	var prize := TycoonHUD.fmt_cr(float(m.get("prize", 0)))
	if String(page.get("kind", "")) == "launch_fail":
		_fill_launch_fail(who)
		return
	if String(page.get("kind", "first")) == "fail":
		%Kicker.text = tr("TY_PAPER_KICKER_FAIL")
		%Headline.text = tr("TY_PAPER_FAIL_H") % [who, short]
		%Deck.text = tr("TY_PAPER_FAIL_DECK") % int(page.get("months", 3))
	else:
		%Kicker.text = tr("TY_PAPER_KICKER_FIRST") % int(m.get("era", 1))
		%Headline.text = tr(String(m.get("name_key", "")) + "_H") % who
		if bool(m.get("victory", false)):
			%Deck.text = tr("TY_PAPER_DECK_VICTORY")
		elif by == RaceDirector.PLAYER:
			%Deck.text = tr("TY_PAPER_DECK_PLAYER") % prize
		else:
			%Deck.text = tr("TY_PAPER_DECK_RIVAL") % [who, prize]
	var lead := r.leader_of(by)   # a rival's leader Lenda speaks for it (TycoonLegends)
	if by == RaceDirector.PLAYER:
		%Quote.text = tr("TY_PAPER_PLAYER_QUOTE")
	elif not lead.is_empty():
		var part := "FAIL" if String(page.get("kind", "")) == "fail" else "FIRST"
		%Quote.text = tr(TycoonLegends.key(String(lead["id"]), part))
	else:
		%Quote.text = tr(String(r.rival(by).get("taunt_key", "")))
	if lead.is_empty():
		%QuoteBy.text = tr("TY_PAPER_QUOTE_BY") % who
	else:
		%QuoteBy.text = tr("TY_PAPER_QUOTE_BY_LEADER") % [TycoonLegends.name_text(String(lead["id"])), who]
	%Fact.text = tr(String(m.get("name_key", "")) + "_FACT")
	%PhotoCaption.text = "%s · %s" % [who, tr(String(m.get("name_key", "")))]
	var mk := %PhotoMarker as CwMarker
	mk.fill = r.agency_color(by) if String(page.get("kind", "")) != "fail" else Color(0, 0, 0, 0)
	mk.outline = r.agency_color(by)
	mk.star = bool(m.get("victory", false))
	(%PhotoTrail as Line2D).default_color = Color(r.agency_color(by), 0.8)
	_fill_board()
	_fill_also()


## The player's rocket failed (RaceDirector.report_launch_failure): the headline says what
## broke, from the Design Review's risks.
func _fill_launch_fail(who: String) -> void:
	var r := state.race
	var cause := tr(String(page.get("cause_key", ""))) if String(page.get("cause_key", "")) != "" else tr("TY_PAPER_LF_UNKNOWN")
	var target := tr(String(state.mission_target(String(page.get("target", ""))).get("name_key", "")))
	%Kicker.text = tr("TY_PAPER_LF_KICKER")
	%Headline.text = tr("TY_PAPER_LF_H") % [String(page.get("code", "")), cause]
	%Deck.text = tr("TY_PAPER_LF_DECK") % [String(page.get("rocket", "")), roundi(float(page.get("p_success", 0.0)) * 100.0)]
	%Quote.text = tr("TY_PAPER_LF_QUOTE")
	%QuoteBy.text = tr("TY_PAPER_QUOTE_BY") % who
	%Fact.text = tr("TY_PAPER_LF_FACT")
	%PhotoCaption.text = "%s · %s" % [String(page.get("code", "")), target]
	var mk := %PhotoMarker as CwMarker
	mk.fill = Color(0, 0, 0, 0)
	mk.outline = r.agency_color(RaceDirector.PLAYER)
	mk.star = false
	(%PhotoTrail as Line2D).default_color = Color(r.agency_color(RaceDirector.PLAYER), 0.8)
	_fill_board()
	_fill_also()


## "Also in this issue": the latest Tail Radio lines after the headline's own.
func _fill_also() -> void:
	var lines: Array[String] = []
	for n: Dictionary in state.news:
		var t := TycoonHUD.news_text(n)
		if lines.size() >= 3:
			break
		if lines.is_empty() and String(n.get("key", "")) in ["TY_RACE_NEWS_FIRST", "TY_RACE_NEWS_FAIL"] \
				and String(page.get("milestone", "")) != "" and t.contains(tr(String(state.race.milestone(page["milestone"]).get("name_key", "")))):
			continue
		lines.append(t)
	var rows := TycoonHUD._copies(%AlsoTemplate, lines.size())
	for i in lines.size():
		(rows[i] as Label).text = "■  " + lines[i]


func _fill_board() -> void:
	var r := state.race
	var ids := r.agencies()
	ids.sort_custom(func(a: String, b: String) -> bool: return r.claims_of(a).size() > r.claims_of(b).size())
	var rows := TycoonHUD._copies(%BoardRowTemplate, ids.size())
	for k in ids.size():
		var id := ids[k]
		var row := rows[k]
		(row.get_node("Swatch") as ColorRect).color = r.agency_color(id)
		(row.get_node("Name") as Label).text = r.agency_name(id) if id == RaceDirector.PLAYER else tr(r.agency_name(id))
		(row.get_node("Count") as Label).text = "%d" % r.claims_of(id).size()
