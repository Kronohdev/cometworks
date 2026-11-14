extends CwScreen
## Contract board screen (scenes/tycoon/ui/screens/contracts.tscn): the month's offers as
## dossier strips (sponsor, mission type x target, minimum grades as bar chips, deadline,
## payment / bonus / penalty, sign or decline; Space Apps offers carry the real problem and
## an open-data pointer), the signed contracts with their deadline meters, and the government
## budget outlook. Visuals are in the scene; this script fills copies of its templates.

const KIND_COLOR := {"government": CwPalette.AURORA_TEAL, "commercial": CwPalette.IGNITION,
	"space_apps": CwPalette.AURORA_VIOLET}


func _bound() -> void:
	TycoonContracts.ensure_offers(state)


func refresh() -> void:
	if state == null:
		return
	var signed := TycoonContracts.accepted(state)
	var cap := TycoonContracts.max_active(state)
	%SlotsValue.text = tr("TY_CT_SLOTS") % [signed.size(), cap]
	(%SlotsBar as CwSegmentBar).segments = maxi(cap, 2)
	(%SlotsBar as CwSegmentBar).value = float(signed.size()) / cap
	%RenewValue.text = tr("TY_WEEKS") % _weeks_to_next_month()
	%RepValue.text = "%d" % roundi(state.reputation)
	var full := signed.size() >= cap
	%FullNote.visible = full
	%FullNote.text = tr("TY_CT_FULL") % cap
	_fill_offers(full, cap)
	_fill_signed(signed)
	var g := TycoonFinance.grant_amount(state)
	%GrantValue.text = cr(g)
	%GrantNote.text = tr("TY_CT_GRANT_NEXT") % [cr(g), roundi(state.reputation)]


func _weeks_to_next_month() -> int:
	var k := state._month_of(state.weeks)
	var n := 1
	while state._month_of(state.weeks + n) == k and n < 10:
		n += 1
	return n


func _num(v: float) -> String:
	var t := "%.1f" % v
	return t.replace(".", ",") if TranslationServer.get_locale().begins_with("pt") else t


func _mission_name(c: Dictionary) -> String:
	return tr(String(state.mission_type(String(c["type"])).get("name_key", "")))


func _target_name(c: Dictionary) -> String:
	return tr(String(state.mission_target(String(c["target"])).get("name_key", "")))


func _fill_offers(full: bool, cap: int) -> void:
	var offers := TycoonContracts.offers(state)
	# Space Apps first, then by payment
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := String(a["kind"]) == "space_apps"
		var sb := String(b["kind"]) == "space_apps"
		if sa != sb:
			return sa
		return float(a["reward"]) > float(b["reward"]))
	var cards := copies(%OfferTemplate, offers.size())
	%OffersEmpty.visible = offers.is_empty()
	for i in offers.size():
		var c: Dictionary = offers[i]
		var card := cards[i] as PanelContainer
		var kind := String(c["kind"])
		var col: Color = KIND_COLOR.get(kind, CwPalette.TEXT_DIM)
		var st := card.get_theme_stylebox("panel").duplicate() as CwPanelStyle
		if st:
			st.tab_color = col
			card.add_theme_stylebox_override("panel", st)
		var row := card.get_node("VBox/Row")
		var kl := row.get_node("Who/Kind") as Label
		kl.text = "%s · %s" % [tr("TY_CT_KIND_" + kind.to_upper()), tr(String(c["sponsor_key"]))]
		kl.add_theme_color_override("font_color", CwPalette.ink(col))
		(row.get_node("Who/Mission") as Label).text = _mission_name(c)
		(row.get_node("Who/Target") as Label).text = "→ " + _target_name(c)
		# minimum grades as bar chips
		var chips_box := row.get_node("Req/Chips")
		var mins: Dictionary = c.get("min_bars", {})
		var chips := copies(chips_box.get_node("ChipTemplate") as Control, mins.size())
		var j := 0
		for b: String in mins:
			(chips[j].get_node("HBox/Swatch") as ColorRect).color = CwPalette.BARS.get(b, CwPalette.TEXT_DIM)
			(chips[j].get_node("HBox/Label") as Label).text = "%s ≥ %s" % [tr("TY_CT_BAR_" + b.to_upper()), _num(float(mins[b]))]
			j += 1
		(row.get_node("Req/Deadline") as Label).text = tr("TY_WEEKS") % int(c["weeks_allowed"])
		(row.get_node("Money/Reward") as Label).text = "+ " + cr(float(c["reward"]))
		(row.get_node("Money/Bonus") as Label).text = tr("TY_CT_BONUS") % cr(float(c["bonus"]))
		(row.get_node("Money/Penalty") as Label).text = tr("TY_CT_PENALTY") % cr(float(c["penalty"]))
		var pp := float(c.get("pp", 0.0))
		var sci := row.get_node("Money/Science") as Label
		sci.visible = pp > 0.0
		sci.text = tr("TY_CT_SCIENCE") % roundi(pp)
		var sign_btn := row.get_node("Actions/Sign") as Button
		sign_btn.disabled = full
		sign_btn.tooltip_text = tr("TY_CT_FULL") % cap if full else ""
		var decline := row.get_node("Actions/Decline") as Button
		var id := String(c["id"])
		_rewire(sign_btn, func() -> void: TycoonContracts.accept(state, id))
		_rewire(decline, func() -> void: TycoonContracts.decline(state, id))
		# Space Apps: the real problem and where to find open data
		var sa := card.get_node("VBox/SpaceApps") as Control
		sa.visible = kind == "space_apps"
		if sa.visible:
			(sa.get_node("Problem") as Label).text = tr(String(c.get("problem_key", "")))
			(sa.get_node("Data") as Label).text = tr("TY_CT_OPEN_DATA") % tr(String(c.get("data_key", "")))


## Copies keep their connections: swap the handler instead of stacking new ones.
func _rewire(btn: Button, f: Callable) -> void:
	if btn.has_meta("handler"):
		var old: Callable = btn.get_meta("handler")
		if btn.pressed.is_connected(old):
			btn.pressed.disconnect(old)
	btn.set_meta("handler", f)
	btn.pressed.connect(f)


func _fill_signed(signed: Array[Dictionary]) -> void:
	var rows := copies(%SignedTemplate, signed.size())
	%SignedEmpty.visible = signed.is_empty()
	for i in signed.size():
		var c := signed[i]
		var r := rows[i]
		(r.get_node("Top/Mission") as Label).text = "%s → %s" % [_mission_name(c), _target_name(c)]
		(r.get_node("Top/Reward") as Label).text = cr(float(c["reward"]))
		(r.get_node("Sponsor") as Label).text = tr(String(c["sponsor_key"]))
		var total := maxf(float(c.get("weeks_allowed", 1)), 1.0)
		var left := int(c["deadline_week"]) - state.weeks
		var bar := r.get_node("Bar") as CwSegmentBar
		bar.value = clampf(float(left) / total, 0.0, 1.0)
		bar.color = CwPalette.DANGER if left <= 4 else (CwPalette.WARNING if left <= 10 else CwPalette.AURORA_TEAL)
		var ll := r.get_node("Left") as Label
		ll.text = tr("TY_CT_WEEKS_LEFT") % maxi(left, 0)
		ll.add_theme_color_override("font_color", CwPalette.ink(bar.color))
