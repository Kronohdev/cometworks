extends CwScreen
## The Conferência dos Cometinhos' invitation (scenes/tycoon/ui/screens/conference.tscn): opened
## by ConferenceFlow when a conference year's invitation is due. It says what the fair is, who will
## be there (ConferenceBook.attendees), what going gives (data/tycoon/conference.json reward) and
## when the next one is, with a word from the host (his own Cometling in the portrait). "Ir à
## feira" goes, "Fica para a próxima" (or Esc) skips; both answer through the flow. Opened from
## the dev menu it shows the invitation for the campaign as it is now.

var _dressed := false


func _ready() -> void:
	super()
	%Go.pressed.connect(func() -> void: _answer(true))
	%Skip.pressed.connect(func() -> void: _answer(false))


func _flow() -> ConferenceFlow:
	return get_tree().get_first_node_in_group(&"conference_flow") as ConferenceFlow if is_inside_tree() else null


func _answer(go: bool) -> void:
	var f := _flow()
	if f:
		f.answer(go)
	close_screen()


func refresh() -> void:
	if state == null:
		return
	%Title.text = tr("TY_CONF_TITLE")
	%Year.text = tr("TY_CONF_YEAR").format({"year": state.year()})
	%Body.text = tr("TY_CONF_INVITE_BODY").format({"agency": state.agency_name})
	var names: Array[String] = []
	for p in ConferenceBook.attendees(state):
		names.append(TycoonLegends.name_text(String(p["id"])))
	%Who.text = ", ".join(names)
	var rw: Dictionary = ConferenceBook.cfg("reward", {})
	%Reward.text = tr("TY_CONF_INVITE_REWARD").format({"rep": int(rw.get("reputation", 0)), "hype": int(rw.get("hype", 0)),
		"rival": int((ConferenceBook.cfg("rival_reward", {}) as Dictionary).get("hype", 0))})
	var nx := ConferenceBook.next_year(state, state.year() + 1)
	%Next.text = tr("TY_CONF_NEXT").format({"year": nx}) if nx > 0 else tr("TY_CONF_NEXT_NONE")
	var host := String(ConferenceBook.cfg("host", "keplerino"))
	%HostName.text = TycoonLegends.name_text(host)
	%HostLine.text = tr("TY_CONF_INVITE_HOST")
	if not _dressed:
		_dressed = true
		var c := %Portrait.get_node_or_null("Viewport/Creature") as Cometling
		if c:
			c = TycoonLeader.dress(c, TycoonLegends.look(host))
			c.play.call_deferred("wave")
