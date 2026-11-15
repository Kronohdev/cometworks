extends CwScreen
## Mission board (scenes/tycoon/ui/screens/briefings.tscn), the first step of a new project:
## the briefings on offer (BriefingDesk) as cards on the left; the chosen one on the right in
## story form, its goal, deadline, budget, reward and era, and what the staff can tell about
## it (curious scientists, seasoned engineers, veterans, the journal: Discovery.briefing_hints)
## and the Lendas who mentor the agency (TycoonLegends.mentor_hints: portrait, name, line, a
## key to their "Quem inspirou" card and "Conversar": a talk with them in the dialogue box).
## The briefing never says how to solve it. "Accept and plan" goes to New project (target and
## type) with the briefing; "Free project" goes there without one. Everything visual is in the
## scene; cards and hint rows are copies of its hidden templates.

const KIND_COLORS := {"science": CwPalette.COMET_ICE, "contract": CwPalette.IGNITION, "space_apps": CwPalette.AURORA_TEAL,
	"dream": CwPalette.AURORA_PINK, "race": CwPalette.AURORA_VIOLET}

var selected := ""


func _ready() -> void:
	super._ready()
	%Next.pressed.connect(_accept)
	%Free.pressed.connect(_free)
	%Studio.shot.connect(func(_k: String, _t: Texture2D) -> void: _fill_mentor_portraits())


func _bound() -> void:
	var offers := BriefingDesk.offers(state)
	if not offers.is_empty():
		selected = String(offers[0]["id"])


## args: {"briefing_id"} selects a briefing (dev menu, tests).
func open_with(args: Dictionary) -> void:
	if args.has("briefing_id"):
		selected = String(args["briefing_id"])
	refresh()


func _accept() -> void:
	if selected == "" or BriefingDesk.offer(state, selected).is_empty():
		return
	if hud:
		hud.open_screen("new_project", {"briefing_id": selected})


func _free() -> void:
	if hud:
		hud.open_screen("new_project", {"free": true})


func _select(id: String) -> void:
	selected = id
	refresh()


static func _wire(b: BaseButton, f: Callable) -> void:
	if not b.has_meta("wired"):
		b.set_meta("wired", true)
		b.pressed.connect(func() -> void: f.call(String(b.get_meta("id", ""))))


func refresh() -> void:
	if state == null:
		return
	%CashNow.text = cr(state.cash)
	%JournalCount.text = tr("TY_JN_COUNT") % Discovery.count(state)
	var offers := BriefingDesk.offers(state)
	if BriefingDesk.offer(state, selected).is_empty():
		selected = String(offers[0]["id"]) if not offers.is_empty() else ""
	var cards := copies(%CardTemplate, offers.size())
	for i in offers.size():
		var o: Dictionary = offers[i]
		var b := BriefingDesk.briefing(String(o["id"]))
		var card := cards[i] as Button
		card.set_meta("id", String(o["id"]))
		_wire(card, _select)
		card.set_pressed_no_signal(String(o["id"]) == selected)
		var kind := String(b.get("kind", "science"))
		var col: Color = KIND_COLORS.get(kind, CwPalette.COMET_ICE)
		(card.get_node("Box/VBox/Top/Swatch") as ColorRect).color = col
		var kl := card.get_node("Box/VBox/Top/Kind") as Label
		kl.text = tr(BriefingDesk.kind_key(kind))
		kl.add_theme_color_override("font_color", CwPalette.ink(col))
		(card.get_node("Box/VBox/Top/Reward") as Label).text = cr(float(o.get("reward", 0.0)))
		(card.get_node("Box/VBox/Title") as Label).text = tr(BriefingDesk.title_key(String(o["id"])))
		(card.get_node("Box/VBox/Client") as Label).text = BriefingDesk.client_text(o)
	%Empty.visible = offers.is_empty()
	_fill_detail()


func _fill_detail() -> void:
	var o := BriefingDesk.offer(state, selected)
	%Detail.visible = not o.is_empty()
	%Next.disabled = o.is_empty()
	%Error.text = "" if not o.is_empty() else tr("TY_BF_PICK")
	if o.is_empty():
		return
	var b := BriefingDesk.briefing(selected)
	var kind := String(b.get("kind", "science"))
	var col: Color = KIND_COLORS.get(kind, CwPalette.COMET_ICE)
	(%KindChip.get_node("HBox/Swatch") as ColorRect).color = col
	%KindText.text = tr(BriefingDesk.kind_key(kind))
	%Client.text = BriefingDesk.client_text(o)
	%BTitle.text = tr(BriefingDesk.title_key(selected))
	%Story.text = tr(BriefingDesk.story_key(selected))
	%Goal.text = tr(BriefingDesk.goal_key(selected))
	%Deadline.text = tr("TY_WEEKS") % int(o.get("deadline", 30))
	%Budget.text = cr(float(o.get("budget", 0.0)))
	%Reward.text = cr(float(o.get("reward", 0.0)))
	%Era.text = tr("TY_ERA_%d" % int(b.get("era", 1)))
	var hints := Discovery.briefing_hints(state, b)
	var rows := copies(%HintTemplate, hints.size())
	for i in hints.size():
		(rows[i].get_node("Row/Text") as Label).text = TycoonHUD.news_text(hints[i])
	# the mentors' voices after the team's
	var mentors := TycoonLegends.mentor_hints(state, b, hints.is_empty())
	var mrows := copies(%MentorTemplate, mentors.size())
	for i in mentors.size():
		var id := String(mentors[i]["legend"])
		var row := mrows[i]
		%Hints.move_child(row, -1)
		row.set_meta("legend", id)
		(row.get_node("Row/VBox/Head/Name") as Label).text = TycoonLegends.name_text(id)
		(row.get_node("Row/VBox/Head/Tag") as Label).text = tr(TycoonLegends.key(id, "ROLE"))
		(row.get_node("Row/VBox/Text") as Label).text = TycoonHUD.news_text(mentors[i])
		var who := row.get_node("Row/VBox/Head/Who") as LinkButton
		if not who.has_meta("wired"):
			who.set_meta("wired", true)
			who.pressed.connect(func() -> void: _open_legend(String(row.get_meta("legend"))))
		var talk := row.get_node("Row/VBox/Head/Talk") as LinkButton
		if not talk.has_meta("wired"):
			talk.set_meta("wired", true)
			talk.pressed.connect(func() -> void:
				if hud:
					hud.talk_to_legend(String(row.get_meta("legend")), "briefing"))
	_fill_mentor_portraits()
	%NoHints.visible = hints.is_empty() and mentors.is_empty()
	var card := String(b.get("card", ""))
	%Source.visible = card != ""
	if card != "":
		%Source.text = tr("TY_BF_SOURCE") % tr("TY_ENC_%s_TITLE" % card.to_upper())
	%Note.text = tr("TY_BF_NOTE")


func _fill_mentor_portraits() -> void:
	for row in %Hints.get_children():
		if not row.has_meta("from_template") or not row.has_meta("legend"):
			continue
		var tex := %Studio.portrait(TycoonLegends.look(String(row.get_meta("legend")))) as Texture2D
		(row.get_node("Row/Visor/Portrait") as TextureRect).texture = tex
		(row.get_node("Row/Visor/Fallback") as Control).visible = tex == null


## A mentor's "Quem inspirou" card in the encyclopedia.
func _open_legend(id: String) -> void:
	if hud and id != "":
		hud.open_screen("book", {"legend": id})
