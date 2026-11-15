extends CwScreen
## The card of a story sign (scenes/tycoon/ui/screens/sign.tscn), opened by a click on a sign
## on the campus island (TycoonMain.open_sign, args {"id"}): a painted wooden board hanging from
## two ropes, with the sign's number on its plaque, the kind (lore, space history, campus
## notice) in its medallion colour, painted face and little picture, the title and the text,
## and for real history the fact with its source in a "Real science" box, with the count of
## signs read. The card has a fixed size; the text scrolls inside it if it ever gets longer
## than the board (font sizes come from the theme). Everything visual is in the scene; this
## script fills the texts and switches the kind's face, badge and picture. Esc
## (TycoonHUD.screen_back), × or Close shuts it.

const ICONS := "res://ui/cometworks/icons/%s.svg"
const KIND_KEYS := {"lore": "SIGN_KIND_LORE", "history": "SIGN_KIND_HISTORY", "joke": "SIGN_KIND_JOKE"}

var sign_id := ""


func _bound() -> void:
	var done := get_node_or_null("%Done") as Button
	if done and not done.pressed.is_connected(close_screen):
		done.pressed.connect(close_screen)
	if sign_id == "":
		# opened without a sign (the dev menu, tests): the first uncovered one
		for id in StorySigns.ids():
			if StorySigns.is_unlocked(state, id):
				sign_id = id
				break


func open_with(args: Dictionary) -> void:
	sign_id = String(args.get("id", sign_id))
	refresh()


func refresh() -> void:
	var d := StorySigns.find(sign_id)
	if d.is_empty():
		return
	var kind := String(d.get("kind", "lore"))
	%Kicker.text = tr(String(KIND_KEYS.get(kind, "SIGN_KIND_LORE")))
	%Title.text = tr(String(d.get("title_key", "")))
	%Body.text = tr(String(d.get("text_key", "")))
	var icon := ICONS % String(d.get("icon", "star"))
	%Icon.texture = load(icon) if ResourceLoader.exists(icon) else null
	for k: String in KIND_KEYS:
		for part in ["Badge", "Face", "Art"]:
			var n := get_node_or_null("%%%s%s" % [part, k.capitalize()]) as Control
			if n:
				n.visible = k == kind
	var number := get_node_or_null("%Number") as Label
	if number:
		number.text = tr("SIGN_PLAQUE") % (StorySigns.ids().find(sign_id) + 1)
	var scroll := get_node_or_null("%Scroll") as ScrollContainer
	if scroll:
		scroll.scroll_vertical = 0
	var fact_key := String(d.get("fact_key", ""))
	%FactBox.visible = fact_key != ""
	if fact_key != "":
		%Fact.text = tr(fact_key)
		%Source.text = tr("SIGN_SOURCE") % tr(String(d.get("source_key", "")))
	%Count.text = tr("SIGN_READ_COUNT") % [StorySigns.read_count(state), StorySigns.total()]
