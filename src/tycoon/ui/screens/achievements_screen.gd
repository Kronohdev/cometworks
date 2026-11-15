class_name AchievementsScreen
extends CwScreen
## Conquistas (scenes/tycoon/ui/screens/achievements.tscn): the badge book. A grid of every
## achievement of data/tycoon/achievements.json (Achievements): earned ones in their colour,
## locked ones greyed out, secret ones as "?" until earned; a badge with progress shows how far
## the player is (this campaign's number in the game, the profile's best from the main menu).
## The panel on the right tells the chosen badge: its name and description (or "???"), when
## it was earned (date, agency, campaign year) or how much is left, and whether this campaign
## earned it. "Estatísticas" opens this campaign's numbers (StatsScreen); from the main menu
## (no campaign: MainMenu instances the scene on its own) it hides. Badges are copies of the
## hidden BadgeTemplate.

const LOCKED_TINT := Color(0.62, 0.6, 0.7, 0.5)

var selected := ""
var _stats: Dictionary = {}


func _ready() -> void:
	super._ready()
	%Stats.pressed.connect(func() -> void:
		if hud:
			hud.open_screen("stats"))
	Achievements.events.unlocked.connect(_on_unlocked)
	Achievements.events.reset.connect(refresh)
	if state == null:
		refresh.call_deferred()   # the main menu: the profile only


func _exit_tree() -> void:
	super._exit_tree()
	if Achievements.events.unlocked.is_connected(_on_unlocked):
		Achievements.events.unlocked.disconnect(_on_unlocked)
	if Achievements.events.reset.is_connected(refresh):
		Achievements.events.reset.disconnect(refresh)


func _on_unlocked(_id: String, _first: bool) -> void:
	if is_inside_tree():
		refresh()


## Esc closes it when the main menu opened it (in the game the HUD's Esc does).
func _unhandled_input(event: InputEvent) -> void:
	if hud == null and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close_screen()


## args: {"id"} selects a badge.
func open_with(args: Dictionary) -> void:
	if args.has("id"):
		selected = String(args["id"])
	refresh()


func refresh() -> void:
	_stats = Achievements.stats(state) if state else {}
	var list := Achievements.all()
	if selected == "" and not list.is_empty():
		selected = String(list[0]["id"])
	var n := Achievements.unlocked_count()
	%Count.text = "%d / %d" % [n, list.size()]
	(%Total as CwSegmentBar).value = float(n) / maxf(float(list.size()), 1.0)
	%Stats.visible = state != null and hud != null
	var cards := copies(%BadgeTemplate, list.size())
	for i in list.size():
		_fill_badge(cards[i] as Button, list[i])
	_fill_detail()


func _fill_badge(card: Button, a: Dictionary) -> void:
	var id := String(a["id"])
	card.set_meta("id", id)
	if not card.has_meta("wired"):
		card.set_meta("wired", true)
		card.pressed.connect(func() -> void:
			selected = String(card.get_meta("id"))
			refresh())
	card.set_pressed_no_signal(id == selected)
	var got := Achievements.is_unlocked(id)
	var secret := bool(a.get("secret", false)) and not got
	_paint_medal(card.get_node("VBox/Medal/Disc"), card.get_node("VBox/Medal/Ring"), card.get_node("VBox/Medal/Icon"),
		card.get_node("VBox/Medal/Secret"), a, got, secret)
	(card.get_node("VBox/Medal/Here") as Control).visible = got and state != null and Achievements.campaign_unlocked(state).has(id)
	var name_l := card.get_node("VBox/Name") as Label
	name_l.text = tr("ACH_SECRET_NAME") if secret else tr(String(a.get("name_key", "")))
	name_l.modulate = Color.WHITE if got else Color(1, 1, 1, 0.7)
	var pg := _progress(a)
	var bar := card.get_node("VBox/Bar") as CwSegmentBar
	var prog := card.get_node("VBox/Prog") as Label
	bar.visible = not got and not pg.is_empty()
	prog.visible = bar.visible
	if bar.visible:
		bar.value = float(pg[0]) / maxf(float(pg[1]), 1.0)
		prog.text = progress_text(a, pg)
	card.tooltip_text = name_l.text


## The medal's look: earned in its colour, locked greyed out, secret as a "?".
func _paint_medal(disc: Control, ring: Control, icon: TextureRect, mark: Control, a: Dictionary, got: bool, secret: bool) -> void:
	var col := Achievements.color(a)
	icon.texture = Achievements.icon(a)
	icon.visible = not secret
	mark.visible = secret
	if got:
		disc.self_modulate = col.lerp(Color.WHITE, 0.55)
		ring.self_modulate = CwPalette.INK
		icon.modulate = Color.WHITE
	else:
		disc.self_modulate = CwPalette.WELL
		ring.self_modulate = CwPalette.HAIRLINE
		icon.modulate = LOCKED_TINT


## [value, goal] for a badge with progress: this campaign's numbers in the game, the profile's
## best from the main menu.
func _progress(a: Dictionary) -> Array:
	if not bool(a.get("progress", false)):
		return []
	if state:
		return Achievements.progress(a, _stats)
	var g := Achievements.goal(a, {"legends_total": TycoonLegends.of_kind("hire").size()})
	return [minf(Achievements.profile_best(String(a["id"])), g), g]


static func progress_text(a: Dictionary, pg: Array) -> String:
	var unit := String(a.get("unit", ""))
	return "%s / %s%s" % [_num(float(pg[0])), _num(float(pg[1])), " " + unit if unit != "" else ""]


static func _num(v: float) -> String:
	var s := str(roundi(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


## A date as the player reads it: dd/mm/yyyy in Portuguese, yyyy-mm-dd otherwise.
static func date_text(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var t := Time.get_datetime_dict_from_unix_time(unix + bias)
	if TranslationServer.get_locale().begins_with("pt"):
		return "%02d/%02d/%04d" % [t["day"], t["month"], t["year"]]
	return "%04d-%02d-%02d" % [t["year"], t["month"], t["day"]]


func _fill_detail() -> void:
	var a := Achievements.find(selected)
	%Detail.visible = not a.is_empty()
	if a.is_empty():
		return
	var got := Achievements.is_unlocked(selected)
	var secret := bool(a.get("secret", false)) and not got
	_paint_medal(%Disc, %Ring, %DIcon, %DSecret, a, got, secret)
	%DName.text = tr("ACH_SECRET_NAME") if secret else tr(String(a.get("name_key", "")))
	if secret:
		%DDesc.text = tr("ACH_SECRET_DESC")
	elif bool(a.get("hidden", false)) and not got:
		%DDesc.text = tr("ACH_HIDDEN_DESC")
	else:
		%DDesc.text = tr(String(a.get("desc_key", "")))
	var pg := _progress(a)
	%DBar.visible = not got and not pg.is_empty()
	if got:
		var rec := Achievements.profile_record(selected)
		var lines: PackedStringArray = [tr("ACH_UNLOCKED_ON") % date_text(int(rec.get("t", 0)))]
		if String(rec.get("agency", "")) != "":
			lines.append(tr("ACH_UNLOCKED_YEAR") % [String(rec["agency"]), int(rec.get("year", 1))])
		%DState.text = "\n".join(lines)
	elif not pg.is_empty():
		(%DBar as CwSegmentBar).value = float(pg[0]) / maxf(float(pg[1]), 1.0)
		%DState.text = "%s · %s" % [tr("ACH_LOCKED"), progress_text(a, pg)]
	else:
		%DState.text = tr("ACH_LOCKED")
	%DHere.visible = state != null and Achievements.campaign_unlocked(state).has(selected)
