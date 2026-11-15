class_name FlightComicAudio
extends Node
## The flight comic's sounds (FlightComic, scenes/tycoon/ui/screens/flight_comic.tscn): a child
## the comic adds to itself, that only watches it, so the comic's layout code stays free of
## sound code:
##   - a page turn when the comic turns a page (and when it opens on the last page, the report)
##   - a soft pop as each panel comes in
##   - under each sound-effect word, a matching soft sound: VRUUUM a cushioned engine swell,
##     CLAC wooden clacks, KABUM a pillowy thud, the burns and orbits an airy whoosh, the
##     landings and splashdowns a round bloop
##   - on the last page, a sting for how the flight went (good / partial / lost), on the Music
##     bus like the other jingles
## A panel is known by its own "Number" label (its place in the flight), so a new page layout
## does not change what plays.

## panel kind -> library sound under its word (kinds without a word stay quiet)
@export var word_sounds := {
	"liftoff": &"comic_vroom", "stage_sep": &"comic_clac", "booster_sep": &"comic_clac", "fairing": &"comic_clac",
	"crash": &"comic_boom", "burn": &"comic_whoosh", "orbit": &"comic_whoosh", "capture": &"comic_whoosh",
	"landing": &"comic_splash", "splashdown": &"comic_splash", "landed": &"comic_splash"}
## mood of the last page -> sting
@export var end_stings := {"good": &"comic_end_good", "meh": &"comic_end_meh", "bad": &"comic_end_bad"}
@export var page_sound: StringName = &"comic_page"
@export var pop_sound: StringName = &"comic_pop"
## seconds between a panel's pop and its word's sound
@export_range(0.0, 1.0, 0.01) var word_delay := 0.09

var comic: FlightComic
## what played, in order (tests): "page", "pop", "word:<sound>", "end:<mood>"
var heard: PackedStringArray = []
var _page := -1
var _revealed := 0
var _on_report := false
var _seen_rows := {}


func _init() -> void:
	name = "ComicAudio"


func _ready() -> void:
	comic = get_parent() as FlightComic


func _process(_delta: float) -> void:
	if comic == null or not comic.is_visible_in_tree():
		return
	var rep := bool(comic.get("_on_report"))
	if rep != _on_report:
		_on_report = rep
		if rep:
			_play(page_sound, "page")
			_end_sting()
		else:
			_page = -1
	if rep:
		return
	if comic.page != _page:
		if _page >= 0:
			_play(page_sound, "page")
		_page = comic.page
		_revealed = 0
		_seen_rows.clear()
	var now := int(comic.get("_revealed"))
	if now > _revealed:
		_reveal(now)
	_revealed = now


## Panels came in since the last frame: a pop and, for the newest one, its word.
func _reveal(now: int) -> void:
	var rows: Array = comic.call("_visible_panels")
	var newest: Control = null
	for i in range(_revealed, mini(now, rows.size())):
		newest = rows[i]
	if newest == null or _seen_rows.has(newest):
		return
	_seen_rows[newest] = true
	_play(pop_sound, "pop")
	var snd := _word_sound(newest)
	if snd != &"":
		if word_delay <= 0.0:
			_play(snd, "word:%s" % snd)
		else:
			get_tree().create_timer(word_delay).timeout.connect(func() -> void:
				if is_instance_valid(comic) and not bool(comic.get("_on_report")):
					_play(snd, "word:%s" % snd))


func _word_sound(row: Control) -> StringName:
	var sfx := row.get_node_or_null("VBox/Art/Sfx") as Label
	if sfx == null or not sfx.visible or sfx.text == "":
		return &""
	var num := row.get_node_or_null("VBox/Art/Number") as Label
	var idx := (int(num.text) - 1) if num else -1
	if idx < 0 or idx >= comic.panels.size():
		return &""
	return StringName(word_sounds.get(String((comic.panels[idx] as Dictionary).get("kind", "")), &""))


## The last page's mood: the final panel's (it knows about a crash), else the report's outcome.
func mood() -> String:
	if not comic.panels.is_empty():
		var art: Dictionary = (comic.panels[-1] as Dictionary).get("art", {})
		if art.has("mood") and String(art["mood"]) in end_stings:
			return String(art["mood"])
	var o := String(comic.report.get("outcome", comic.entry.get("outcome", "full")))
	return "good" if o in ["full", "exceptional"] else ("meh" if o == "partial" else "bad")


func _end_sting() -> void:
	var m := mood()
	var snd: StringName = StringName(end_stings.get(m, &""))
	if snd != &"":
		CwSfx.stinger(snd)
		heard.append("end:%s" % m)


func _play(snd: StringName, what: String) -> void:
	CwSfx.play(snd)
	heard.append(what)
