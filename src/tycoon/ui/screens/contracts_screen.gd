extends CwScreen
## Contract board screen (scenes/tycoon/ui/screens/contracts.tscn), as pages (CwPageStack):
##   Offers  the month's offers as short cards (sponsor, mission x target, payment, deadline)
##   Signed  the signed contracts with their deadline meters, and how contracts work
##   Offer   one contract in full: minimum grades, deadline, payment / bonus / penalty /
##           science, the Space Apps problem and open-data pointer; sign or decline here
## The header keeps the slots, the board renewal, the government budget and reputation.
## Visuals are in the scene; this script fills copies of its templates.

const KIND_COLOR := {"government": CwPalette.AURORA_TEAL, "commercial": CwPalette.IGNITION,
	"space_apps": CwPalette.AURORA_VIOLET}

## the contract on the detail page
var selected := ""

@onready var pages: CwPageStack = %Pages


func _ready() -> void:
	super()
	%Sign.pressed.connect(func() -> void:
		if state and selected != "":
			TycoonContracts.accept(state, selected)
			pages.switch_to(&"Signed"))
	%Decline.pressed.connect(func() -> void:
		if state and selected != "":
			TycoonContracts.decline(state, selected)
			pages.back())
	pages.page_changed.connect(func(_p: StringName, _d: int) -> void: refresh())


func _bound() -> void:
	TycoonContracts.ensure_offers(state)


## Opens one contract's page: open_screen("contracts", {"contract": id}) or {"tab": "signed"}.
func open_with(args: Dictionary) -> void:
	if String(args.get("tab", "")) == "signed":
		pages.switch_to(&"Signed")
	if args.has("contract"):
		open_contract(String(args["contract"]))


## The first offer's page (tests, dev menu).
func open_detail() -> void:
	var offers := _sorted_offers()
	if not offers.is_empty():
		open_contract(String(offers[0]["id"]))


func open_contract(id: String) -> void:
	var c := _find(id)
	if c.is_empty():
		return
	selected = id
	pages.push(&"Offer", _mission_name(c))
	refresh()


func _find(id: String) -> Dictionary:
	for c in TycoonContracts.offers(state):
		if String(c["id"]) == id:
			return c
	for c in TycoonContracts.accepted(state):
		if String(c["id"]) == id:
			return c
	return {}


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
	var offers := _sorted_offers()
	%OffersTab.text = "%s · %d" % [tr("TY_CT_TAB_OFFERS"), offers.size()]
	%SignedTab.text = "%s · %d" % [tr("TY_CT_TAB_SIGNED"), signed.size()]
	_fill_offers(offers)
	_fill_signed(signed)
	var g := TycoonFinance.grant_amount(state)
	%GrantValue.text = cr(g)
	%Grant.tooltip_text = tr("TY_CT_GRANT_NEXT") % [cr(g), roundi(state.reputation)]
	if pages.current() == &"Offer":
		var c := _find(selected)
		if c.is_empty():
			pages.back()   # taken by a rival, or the board renewed
			return
		_fill_detail(c, full, cap)


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


func _kind_line(c: Dictionary) -> String:
	return "%s · %s" % [tr("TY_CT_KIND_" + String(c.get("kind", "government")).to_upper()), tr(String(c["sponsor_key"]))]


## Space Apps first, then by payment.
func _sorted_offers() -> Array:
	var offers := TycoonContracts.offers(state)
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := String(a["kind"]) == "space_apps"
		var sb := String(b["kind"]) == "space_apps"
		if sa != sb:
			return sa
		return float(a["reward"]) > float(b["reward"]))
	return offers


## The card's tab in the kind colour (the card's own CwPanelStyle, duplicated).
static func _tint(card: PanelContainer, col: Color) -> void:
	var st := card.get_theme_stylebox("panel").duplicate() as CwPanelStyle
	if st:
		st.tab_color = col
		card.add_theme_stylebox_override("panel", st)


func _fill_offers(offers: Array) -> void:
	var cards := copies(%OfferTemplate, offers.size())
	%OffersEmpty.visible = offers.is_empty()
	for i in offers.size():
		var c: Dictionary = offers[i]
		var card := cards[i] as PanelContainer
		var col: Color = KIND_COLOR.get(String(c["kind"]), CwPalette.TEXT_DIM)
		_tint(card, col)
		var row := card.get_node("Row")
		var kl := row.get_node("Who/Kind") as Label
		kl.text = _kind_line(c)
		kl.add_theme_color_override("font_color", CwPalette.ink(col))
		(row.get_node("Who/Mission") as Label).text = _mission_name(c)
		(row.get_node("Who/Target") as Label).text = "→ " + _target_name(c)
		(row.get_node("Brief/Reward") as Label).text = "+ " + cr(float(c["reward"]))
		(row.get_node("Brief/Deadline") as Label).text = "%s %s" % [tr("TY_CT_DEADLINE"), tr("TY_WEEKS") % int(c["weeks_allowed"])]
		_wire_card(card, String(c["id"]))


## The whole card (and its Open key) opens the contract's page.
func _wire_card(card: PanelContainer, id: String) -> void:
	card.set_meta("id", id)
	if card.has_meta("wired"):
		return
	card.set_meta("wired", true)
	card.get_node("Row/Open").pressed.connect(func() -> void: open_contract(String(card.get_meta("id"))))
	card.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			open_contract(String(card.get_meta("id"))))


func _fill_signed(signed: Array[Dictionary]) -> void:
	var rows := copies(%SignedTemplate, signed.size())
	%SignedEmpty.visible = signed.is_empty()
	for i in signed.size():
		var c := signed[i]
		var card := rows[i] as PanelContainer
		_tint(card, KIND_COLOR.get(String(c.get("kind", "government")), CwPalette.AURORA_TEAL))
		var r := card.get_node("Row")
		(r.get_node("Who/Mission") as Label).text = "%s → %s" % [_mission_name(c), _target_name(c)]
		(r.get_node("Who/Sponsor") as Label).text = tr(String(c["sponsor_key"]))
		(r.get_node("Time/Top/Reward") as Label).text = cr(float(c["reward"]))
		var left := int(c["deadline_week"]) - state.weeks
		var bar := r.get_node("Time/Bar") as CwSegmentBar
		_deadline(bar, r.get_node("Time/Top/Left") as Label, c, left)
		_wire_card(card, String(c["id"]))


func _deadline(bar: CwSegmentBar, ll: Label, c: Dictionary, left: int) -> void:
	var total := maxf(float(c.get("weeks_allowed", 1)), 1.0)
	bar.value = clampf(float(left) / total, 0.0, 1.0)
	bar.color = CwPalette.DANGER if left <= 4 else (CwPalette.WARNING if left <= 10 else CwPalette.AURORA_TEAL)
	ll.text = tr("TY_CT_WEEKS_LEFT") % maxi(left, 0)
	ll.add_theme_color_override("font_color", CwPalette.ink(bar.color))


func _fill_detail(c: Dictionary, full: bool, cap: int) -> void:
	var kind := String(c.get("kind", "government"))
	var col: Color = KIND_COLOR.get(kind, CwPalette.TEXT_DIM)
	_tint(%Main, col)
	pages.set_title(_mission_name(c))
	%DKind.text = _kind_line(c)
	%DKind.add_theme_color_override("font_color", CwPalette.ink(col))
	%DMission.text = _mission_name(c)
	%DTarget.text = "→ " + _target_name(c)
	var mins: Dictionary = c.get("min_bars", {})
	var chips := copies(%ChipTemplate, mins.size())
	var j := 0
	for b: String in mins:
		(chips[j].get_node("HBox/Swatch") as ColorRect).color = CwPalette.BARS.get(b, CwPalette.TEXT_DIM)
		(chips[j].get_node("HBox/Label") as Label).text = "%s ≥ %s" % [tr("TY_CT_BAR_" + b.to_upper()), _num(float(mins[b]))]
		j += 1
	%DDeadline.text = tr("TY_WEEKS") % int(c.get("weeks_allowed", 0))
	%SpaceApps.visible = kind == "space_apps"
	if %SpaceApps.visible:
		%Problem.text = tr(String(c.get("problem_key", "")))
		%Data.text = tr("TY_CT_OPEN_DATA") % tr(String(c.get("data_key", "")))
	%DReward.text = "+ " + cr(float(c["reward"]))
	%DBonus.text = tr("TY_CT_BONUS") % cr(float(c["bonus"]))
	%DPenalty.text = tr("TY_CT_PENALTY") % cr(float(c["penalty"]))
	var pp := float(c.get("pp", 0.0))
	%DScience.visible = pp > 0.0
	%DScience.text = tr("TY_CT_SCIENCE") % roundi(pp)
	var signed := String(c.get("status", "")) == "accepted"
	%DLeft.visible = signed
	%DBar.visible = signed
	if signed:
		_deadline(%DBar, %DLeft, c, int(c["deadline_week"]) - state.weeks)
	%Sign.visible = not signed
	%Decline.visible = not signed
	%Sign.disabled = full
	%Sign.tooltip_text = tr("TY_CT_FULL") % cap if full else ""
	%DFull.visible = full and not signed
	%DFull.text = tr("TY_CT_FULL") % cap
