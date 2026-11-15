extends CwScreen
## Research screen (scenes/tycoon/ui/screens/research.tscn), as pages (CwPageStack):
##   Tree  the tech tree as a tree that grows: era 1 at the roots, each era a band above the last,
##         the limbs left to right (rocketry, comms, the core trunk, science, crew, exploration),
##         every prerequisite a branch from the card below to the card above (TechTreeLayout works
##         the places out from research.json). Done branches are lit, the one into the research
##         being funded runs with sap, open ones are ink, far ones faint; available techs pulse,
##         the one being researched has a progress ring and sparks, eras out of reach are misty.
##         Wheel / pinch zooms, dragging pans, Tudo fits it. Hover a card: its path of
##         prerequisites lights up. Click: the inspector on the right shows the tech (cost in PP and
##         money, time, ETA, what it unlocks, what it needs) with fund / queue; double-click funds
##   Tech  one tech's full sheet: branch, era, state, description, cost / time / ETA, progress,
##         what it unlocks and needs and leads to, who sits in the lab; fund / queue / stop and
##         license here
##   Studies  the mission studies (FocusStudy, a tab): the mission types with their tier pips on
##         the left; on the right what the agency knows of the chosen type's bars, what the next
##         level reveals, its cost (PP, money, weeks), ETA and progress, and study / pause
## The lab readouts stay in the header. The scene holds every visual (the card, the branch line
## styles EdgeLocked / EdgeOpen / EdgeDone / EdgeActive, the trunk, the era band, the mist, the
## limb sign, the card's AnimationPlayer); this script places copies of the hidden templates and
## bends the copied lines along the branches.

const NODE_STYLE := {"done": &"CwNodeDone", "researching": &"CwNodeActive", "queued": &"CwNodeAvailable",
	"available": &"CwNodeAvailable", "locked": &"CwNodeLocked"}
const KIND_COLOR := {"type": CwPalette.IGNITION, "target": CwPalette.COMET_ICE, "option": CwPalette.AURORA_TEAL,
	"spec": CwPalette.AURORA_VIOLET, "part": CwPalette.TEXT_DIM, "effect": CwPalette.WARNING,
	"rocket": CwPalette.IGNITION}
const ST_COLOR := {"done": CwPalette.AURORA_TEAL, "researching": CwPalette.AURORA_VIOLET, "queued": CwPalette.WARNING,
	"available": CwPalette.COMET_ICE, "locked": CwPalette.INK_SOFT}
## branch state -> its template in %Edges, drawn in this order (the sap last, on top)
const EDGE_TEMPLATE := {"locked": "EdgeLocked", "open": "EdgeOpen", "done": "EdgeDone", "active": "EdgeActive"}
const EDGE_ORDER: Array[String] = ["locked", "open", "done", "active"]
const ICONS := "res://ui/cometworks/icons/%s.svg"
const CURVE_POINTS := 22
## the opening growth: the trunk, then the branches era by era
const INTRO_TRUNK := 0.45
const INTRO_ERA_STEP := 0.16
const INTRO_BRANCH := 0.4

var selected := ""
## the mission type on the studies page
var study_type := ""
## TechTreeLayout.compute() of the data (tree pixels)
var layout: Dictionary = {}
## tech id -> its card (a copy of %NodeTemplate)
var cards: Dictionary = {}
## "prereq>tech" (or ">tech" for a root, from the trunk) -> the branch (a copy of an Edge* template)
var edges: Dictionary = {}
## the hovered tech and its whole path of prerequisites (id -> true), {} when nothing is hovered
var hover_path: Dictionary = {}
var min_zoom := 0.45
var max_zoom := 1.8

var _opts: Dictionary = {}
var _curves: Dictionary = {}
var _grow: Dictionary = {}
var _growing: Dictionary = {}   # branch key -> seconds its growth takes
var _last_state: Dictionary = {}
var _trunk_grow := 1.0
var _trunk_top := 0.0
var _user_view := false
var _drag := false
var _dragged := false
var _press_at := Vector2.ZERO
var _intro := false
var _intro_time := 0.0

@onready var pages: CwPageStack = %Pages
@onready var world: Control = %World
@onready var canvas: Control = %Canvas


func _ready() -> void:
	super()
	%Fund.pressed.connect(_on_fund)
	%IFund.pressed.connect(_on_fund)
	%IMore.pressed.connect(func() -> void: open_tech(selected))
	%SStudy.pressed.connect(_on_study)
	pages.page_changed.connect(func(_p: StringName, _d: int) -> void: _sync_subtitle())
	%License.pressed.connect(func() -> void:
		if state and selected != "":
			TycoonResearch.license(state, selected))
	canvas.gui_input.connect(_on_canvas_input)
	canvas.resized.connect(func() -> void:
		if state and not layout.is_empty():
			if _user_view:
				_clamp_pan()
			else:
				fit_view())
	%ZoomIn.pressed.connect(func() -> void: zoom_at(canvas.size * 0.5, 1.2))
	%ZoomOut.pressed.connect(func() -> void: zoom_at(canvas.size * 0.5, 1.0 / 1.2))
	%ZoomFit.pressed.connect(func() -> void:
		_user_view = false
		fit_view())
	set_process(false)


func _bound() -> void:
	selected = TycoonResearch.active(state)
	if selected == "":
		for t: Dictionary in TycoonResearch.techs():
			if TycoonResearch.can_research(state, String(t["id"])):
				selected = String(t["id"])
				break
	if selected == "":
		for t: Dictionary in TycoonResearch.techs():
			if not TycoonResearch.is_done(state, String(t["id"])):
				selected = String(t["id"])
				break
	if selected == "":
		selected = String(TycoonResearch.techs()[0]["id"])
	_build_tree()
	# the tree grows in when the screen opens (reduce motion: there at once)
	_intro = not CwMotion.reduced()
	if _intro:
		_trunk_grow = 0.0
		for k: String in _grow:
			_grow[k] = 0.0
		_intro_time = 0.0
		set_process(true)
	fit_view.call_deferred()


## Opens a tech's page: open_screen("research", {"tech": id}); the mission studies on a type:
## {"study": type id} ("" picks one).
func open_with(args: Dictionary) -> void:
	if args.has("tech"):
		open_tech(String(args["tech"]))
	elif args.has("study"):
		open_studies(String(args["study"]))


## The mission studies tab, on a type.
func open_studies(type_id := "") -> void:
	if type_id != "":
		study_type = type_id
	pages.switch_to(&"Studies")
	refresh()


## The selected tech's page (tests, dev menu).
func open_detail() -> void:
	open_tech(selected)


## Selects a tech: the inspector shows it.
func select(id: String) -> void:
	if TycoonResearch.tech(id).is_empty():
		return
	selected = id
	refresh()


## Selects a tech and opens its full sheet.
func open_tech(id: String) -> void:
	if TycoonResearch.tech(id).is_empty():
		return
	selected = id
	pages.push(&"Tech", tr("TY_TECH_" + id.to_upper()))
	refresh()


func refresh() -> void:
	if state == null:
		return
	%PoolValue.text = "%d PP" % floori(state.research_points)
	%RateValue.text = "+%.1f" % TycoonResearch.pp_per_week(state)
	var seats := TycoonResearch.lab_seats(state)
	var used := TycoonResearch.seated(state).size()
	var lv := TycoonResearch.lab_level(state)
	%LabValue.text = (tr("TY_RS_LAB_BENCH") if lv == 0 else tr("TY_LEVEL") % lv) + " · %d/%d" % [used, seats]
	(%SeatsBar as CwSegmentBar).segments = maxi(seats, 2)
	(%SeatsBar as CwSegmentBar).value = float(used) / maxf(seats, 1)
	if layout.is_empty():
		_build_tree()
	_fill_tree()
	_fill_queue()
	_fill_inspector()
	_fill_detail()
	_fill_studies()


# ------------------------------------------------------------ the tree: building
## Lays the tree out from the data and makes its pieces: an era band per era, a sign per limb, a
## card per tech, the curve of every branch. The branches themselves are made by _fill_tree
## (their look follows their state).
func _build_tree() -> void:
	var techs := TycoonResearch.techs()
	_opts = TechTreeLayout.opts_from(TycoonResearch.db())
	layout = TechTreeLayout.compute(techs, _opts)
	var size: Vector2 = layout["size"]
	world.size = size
	# era bands
	var eras: Array = layout["eras"]
	var bands := copies(%EraTemplate, eras.size())
	for i in eras.size():
		var e: Dictionary = eras[i]
		bands[i].position = Vector2(0, float(e["y"]))
		bands[i].size = Vector2(size.x, float(e["h"]))
		bands[i].set_meta("era", int(e["era"]))
	# limb signs at the crown
	var lanes: Array = layout["lanes"]
	var limbs := TechTreeLayout.limbs(_opts)
	var signs := copies(%LimbTemplate, lanes.size())
	for i in lanes.size():
		var l := signs[i] as Label
		l.size = Vector2(float(_opts["lane_w"]) - 8.0, 22.0)
		l.position = Vector2(float(lanes[i]["x"]) - l.size.x * 0.5, 6.0)
		l.text = tr(String((limbs[i] as Dictionary).get("name_key", "")))
	# ground
	var ground := %Ground as Control
	ground.position = Vector2(0, float(layout["ground_y"]))
	ground.size = Vector2(size.x, size.y - float(layout["ground_y"]))
	# cards
	var list := copies(%NodeTemplate, techs.size())
	cards.clear()
	var icons: Dictionary = _opts.get("icons", {})
	for i in techs.size():
		var t: Dictionary = techs[i]
		var id := String(t["id"])
		var n := list[i]
		var r: Rect2 = layout["rects"][id]
		n.position = r.position
		n.size = r.size
		n.pivot_offset = r.size * 0.5
		# a sticker slapped on a little crooked
		n.rotation = deg_to_rad(float(absi(hash(id)) % 25 - 12) / 10.0)
		n.set_meta("tech", id)
		var path := ICONS % String(t.get("icon", icons.get(String(t.get("branch", "")), "research")))
		(n.get_node("Card/HBox/Badge/Icon") as TextureRect).texture = load(path) if ResourceLoader.exists(path) else null
		var br := TycoonResearch.branch(String(t.get("branch", "")))
		(n.get_node("Card/HBox/Badge/Bg") as CanvasItem).self_modulate = \
			Color(String(br.get("color", "#ffffff"))).lerp(Color.WHITE, 0.45)
		if not n.has_meta("wired"):
			n.set_meta("wired", true)
			n.gui_input.connect(_on_card_input.bind(n))
			n.mouse_entered.connect(func() -> void: hover_tech(String(n.get_meta("tech", ""))))
			n.mouse_exited.connect(func() -> void:
				if not _drag:
					hover_tech(""))
		cards[id] = n
	_make_curves()


## The curve of every branch: from the top of the prerequisite's card to the bottom of the card
## that needs it (sockets spread so parallel branches stay apart); a root grows from the trunk.
func _make_curves() -> void:
	_curves.clear()
	var rects: Dictionary = layout["rects"]
	var outs := {}
	var ins := {}
	for e: Dictionary in layout["edges"]:
		outs[e["from"]] = outs.get(e["from"], []) + [e]
		ins[e["to"]] = ins.get(e["to"], []) + [e]
	var sock := {}
	for gi in 2:
		var group: Dictionary = outs if gi == 0 else ins
		var other := "to" if gi == 0 else "from"
		for id: String in group:
			var ls: Array = group[id]
			ls.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
				return (rects[x[other]] as Rect2).get_center().x < (rects[y[other]] as Rect2).get_center().x)
			for i in ls.size():
				var k := "%s>%s" % [ls[i]["from"], ls[i]["to"]]
				sock[k + ("|a" if gi == 0 else "|b")] = (i - (ls.size() - 1) * 0.5) * 12.0
	for e: Dictionary in layout["edges"]:
		var k := "%s>%s" % [e["from"], e["to"]]
		var ra: Rect2 = rects[e["from"]]
		var rb: Rect2 = rects[e["to"]]
		var a := Vector2(ra.get_center().x + float(sock.get(k + "|a", 0.0)), ra.position.y + 6.0)
		var b := Vector2(rb.get_center().x + float(sock.get(k + "|b", 0.0)), rb.end.y - 6.0)
		_curves[k] = _bezier(a, b)
	var tx := float(layout["trunk_x"])
	var era_h := float(_opts["era_h"])
	for id: String in layout["roots"]:
		var rb: Rect2 = rects[id]
		var b := Vector2(rb.get_center().x, rb.end.y - 6.0)
		var a := Vector2(tx, minf(rb.end.y + era_h * 0.3, float(layout["ground_y"]) + 4.0))
		_curves[">" + id] = _bezier(a, b)
	for k: String in _curves:
		if not _grow.has(k):
			_grow[k] = 1.0


## A branch that leaves upwards and arrives upwards (vertical tangents at both ends).
static func _bezier(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var dy := maxf(absf(a.y - b.y) * 0.5, 24.0)
	var c1 := a - Vector2(0, dy)
	var c2 := b + Vector2(0, dy)
	for i in CURVE_POINTS + 1:
		var t := float(i) / CURVE_POINTS
		var u := 1.0 - t
		pts.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)
	return pts


# ------------------------------------------------------------ the tree: filling
func _fill_tree() -> void:
	var techs := TycoonResearch.techs()
	var la := int(TycoonResearch.db().get("era_lookahead", 1))
	var open_era := state.era() + la
	# era bands and the mist over the eras out of reach
	var misty: Array[Control] = []
	for b in (%EraTemplate as Control).get_parent().get_children():
		if b == %EraTemplate or not b.has_meta("from_template"):
			continue
		var era := int(b.get_meta("era", 1))
		var y0 := (era - 1) * 5 + 1
		var name_l := b.get_node("Sign/VBox/Name") as Label
		name_l.text = tr("RT_ERA_N") % era
		(b.get_node("Sign/VBox/Title") as Label).text = tr("TY_ERA_%d" % era)
		var years := b.get_node("Sign/VBox/Years") as Label
		var band := b.get_node("Band") as ColorRect
		if era == state.era():
			years.text = tr("TY_RS_NOW") % [y0, y0 + 4]
			name_l.add_theme_color_override("font_color", CwPalette.IGNITION)
			band.color = Color(CwPalette.IGNITION_HI, 0.12)
		elif era > open_era:
			years.text = tr("TY_RS_OPENS") % ((era - la - 1) * 5 + 1)
			name_l.add_theme_color_override("font_color", CwPalette.INK_SOFT)
			band.color = Color(CwPalette.LILAC, 0.06)
			misty.append(b)
		else:
			years.text = tr("TY_RS_YEARS") % [y0, y0 + 4]
			name_l.add_theme_color_override("font_color", CwPalette.TEXT_DIM)
			band.color = Color(CwPalette.LILAC, 0.06) if era % 2 == 0 else Color(0, 0, 0, 0)
	var mists := copies(%MistTemplate, misty.size())
	var ml := float(_opts["margin_left"]) - 6.0
	for i in misty.size():
		var b := misty[i]
		var era := int(b.get_meta("era", 1))
		mists[i].position = b.position + Vector2(ml, 0)
		mists[i].size = Vector2(b.size.x - ml, b.size.y)
		var lbl := mists[i].get_node("MistLabel") as Label
		lbl.text = tr("RT_MIST") % ((era - la - 1) * 5 + 1)
		lbl.position = Vector2((mists[i].size.x - lbl.size.x) * 0.5, 4.0)
	# the trunk reaches up to the highest era within reach
	var top_era := mini(open_era, (layout["eras"] as Array).size())
	for e: Dictionary in layout["eras"]:
		if int(e["era"]) == top_era:
			_trunk_top = float(e["y"]) + float(e["h"]) * 0.35
	_apply_trunk()
	# cards
	for t: Dictionary in techs:
		var id := String(t["id"])
		var st := TycoonResearch.node_state(state, id)
		var was := String(_last_state.get(id, st))
		_fill_card(cards[id], t, st)
		if st == "done" and was != "done":
			_celebrate(id)
		_last_state[id] = st
	# branches: one per prerequisite and one from the trunk per root, styled by state
	for t: Dictionary in techs:
		var id := String(t["id"])
		var st := TycoonResearch.node_state(state, id)
		var any := false
		for p in t.get("prereq", []):
			if not cards.has(String(p)):
				continue
			any = true
			var ls := "locked"
			if st == "done":
				ls = "done"
			elif st == "researching" and TycoonResearch.is_done(state, String(p)):
				ls = "active"
			elif TycoonResearch.is_done(state, String(p)):
				ls = "open"
			_edge("%s>%s" % [p, id], ls)
		if not any:
			var root_st := "locked"
			if st == "done":
				root_st = "done"
			elif st == "researching":
				root_st = "active"
			elif TycoonResearch.era_open(state, id):
				root_st = "open"
			_edge(">" + id, root_st)
	_sort_edges()
	_apply_hover()


func _fill_card(n: Control, t: Dictionary, st: String) -> void:
	var id := String(t["id"])
	var card := n.get_node("Card") as PanelContainer
	card.theme_type_variation = NODE_STYLE[st]
	var name_l := card.get_node("HBox/Text/Name") as Label
	name_l.text = tr("TY_TECH_" + id.to_upper())
	name_l.add_theme_color_override("font_color", CwPalette.TEXT_DIM if st == "locked" else CwPalette.TEXT)
	var cost := card.get_node("HBox/Text/Bottom/Cost") as Label
	cost.text = "%d PP" % int(t["cost"])
	cost.add_theme_color_override("font_color", Color(CwPalette.INK_SOFT, 0.6) if st == "locked" else CwPalette.COMET_ICE)
	var st_l := card.get_node("HBox/Text/Bottom/State") as Label
	var q := TycoonResearch.queue(state).find(id)
	st_l.text = tr("TY_RS_QUEUED_N") % (q + 1) if st == "queued" else tr("TY_RS_ST_" + st.to_upper())
	st_l.add_theme_color_override("font_color", Color(CwPalette.INK_SOFT, 0.6) if st == "locked" else CwPalette.ink(ST_COLOR[st]))
	(card.get_node("HBox/Badge/Icon") as CanvasItem).modulate = Color(CwPalette.INK, 0.45 if st == "locked" else 1.0)
	var ring := card.get_node("HBox/Badge/Progress") as CwProgressRing
	var frac := TycoonResearch.fraction(state, id)
	ring.visible = st == "researching" or (st in ["queued", "available"] and frac > 0.0)
	ring.value = frac
	ring.spark = st == "researching"
	ring.color = CwPalette.AURORA_VIOLET if st == "researching" else CwPalette.WARNING
	(n.get_node("Check") as Control).visible = st == "done"
	(n.get_node("Ring") as Control).visible = id == selected
	(n.get_node("Sparks") as CPUParticles2D).emitting = st == "researching" and not CwMotion.reduced()
	n.tooltip_text = tr("RT_CARD_TIP") % tr("TY_TECH_" + id.to_upper())
	var anim := n.get_node("Anim") as AnimationPlayer
	if anim.is_playing() and anim.current_animation == "pop":
		return
	var want := "RESET"
	if not CwMotion.reduced():
		if st == "researching":
			want = "research"
		elif st == "available":
			want = "pulse"
	if anim.current_animation != want or not anim.is_playing():
		anim.play(want)
		if want == "RESET":
			anim.advance(0.0)


## A tech just finished: its card pops and its branches grow lit from the prerequisites up.
func _celebrate(id: String) -> void:
	if CwMotion.reduced():
		return
	(cards[id].get_node("Anim") as AnimationPlayer).play("pop")
	for k: String in _curves:
		if k.get_slice(">", 1) == id:
			_grow[k] = 0.0
			_growing[k] = 0.7
	set_process(true)


## The branch `key` in style `st`: a fresh copy of that style's template when the state changed.
func _edge(key: String, st: String) -> Node2D:
	var cur: Node2D = edges.get(key)
	if cur != null and is_instance_valid(cur):
		if String(cur.get_meta("state", "")) == st:
			return cur
		cur.queue_free()
	var tmpl := (%Edges as Node).get_node(String(EDGE_TEMPLATE[st])) as Node2D
	var n := tmpl.duplicate() as Node2D
	n.visible = true
	n.set_meta("state", st)
	n.set_meta("from_template", true)
	%Edges.add_child(n)
	edges[key] = n
	_apply_grow(key)
	return n


## Draw order: faint branches first, the sap on top; the hovered path above all.
func _sort_edges() -> void:
	var box := %Edges as Node
	var order: Array[Node2D] = []
	for st: String in EDGE_ORDER:
		for k: String in edges:
			var n: Node2D = edges[k]
			if is_instance_valid(n) and String(n.get_meta("state", "")) == st and not (not hover_path.is_empty() and _on_path(k)):
				order.append(n)
	if not hover_path.is_empty():
		for k: String in edges:
			if is_instance_valid(edges[k]) and _on_path(k):
				order.append(edges[k])
	for n in order:
		box.move_child(n, -1)


## Bends the branch's lines along its curve, cut where it has grown to.
func _apply_grow(key: String) -> void:
	var n: Node2D = edges.get(key)
	if n == null or not is_instance_valid(n) or not _curves.has(key):
		return
	var pts: PackedVector2Array = _curves[key]
	var g := clampf(float(_grow.get(key, 1.0)), 0.0, 1.0)
	var cut := pts
	if g < 1.0:
		var f := g * (pts.size() - 1)
		var i := floori(f)
		cut = pts.slice(0, i + 1)
		if i + 1 < pts.size():
			cut.append(pts[i].lerp(pts[i + 1], f - i))
		if cut.size() < 2:
			cut = PackedVector2Array([pts[0], pts[0] + Vector2(0, -0.5)])
	for c in n.get_children():
		if c is Line2D:
			(c as Line2D).points = cut


func _apply_trunk() -> void:
	var tx := float(layout["trunk_x"])
	var y0 := float(layout["ground_y"]) + 18.0
	var y1 := lerpf(y0, _trunk_top, _trunk_grow)
	var pts := PackedVector2Array()
	var n := 14
	for i in n + 1:
		var t := float(i) / n
		pts.append(Vector2(tx + sin(t * 5.0 + 0.6) * 4.0 * t, lerpf(y0, y1, t)))
	for c in (%Trunk as Node).get_children():
		if c is Line2D:
			var p2 := pts.duplicate()
			if c.name == &"Bark":
				for i in p2.size():
					p2[i].x -= 4.0
			(c as Line2D).points = p2


func _process(delta: float) -> void:
	var busy := false
	if _intro:
		_intro_time += delta
		var tg := clampf(_intro_time / INTRO_TRUNK, 0.0, 1.0)
		_trunk_grow = 1.0 - pow(1.0 - tg, 3.0)
		_apply_trunk()
		for k: String in _curves:
			if _growing.has(k):
				continue
			var era := int(TycoonResearch.tech(k.get_slice(">", 1)).get("era", 1))
			var g := clampf((_intro_time - INTRO_TRUNK * 0.6 - (era - 1) * INTRO_ERA_STEP) / INTRO_BRANCH, 0.0, 1.0)
			_grow[k] = 1.0 - pow(1.0 - g, 2.0)
			_apply_grow(k)
		if _intro_time >= INTRO_TRUNK + 5.0 * INTRO_ERA_STEP + INTRO_BRANCH:
			_intro = false
		busy = true
	for k: String in _growing.keys():
		_grow[k] = minf(float(_grow[k]) + delta / float(_growing[k]), 1.0)
		_apply_grow(k)
		if float(_grow[k]) >= 1.0:
			_growing.erase(k)
		busy = true
	if not busy:
		set_process(false)


# ------------------------------------------------------------ hover: the path of prerequisites
## Lights up a tech and every tech it needs (and the branches between them), dims the rest.
## "" puts everything back.
func hover_tech(id: String) -> void:
	hover_path = {}
	if id != "" and cards.has(id):
		var by_id := {}
		for t: Dictionary in TycoonResearch.techs():
			by_id[String(t["id"])] = t
		hover_path = TechTreeLayout.ancestors(by_id, id)
		hover_path[id] = true
	for k: String in cards:
		var n := cards[k] as Control
		(n.get_node("Veil") as Control).visible = not hover_path.is_empty() and not hover_path.has(k)
		n.scale = Vector2.ONE * (1.06 if k == id else 1.0)
	_apply_hover()
	_sort_edges()


func _on_path(key: String) -> bool:
	var a := key.get_slice(">", 0)
	return hover_path.has(key.get_slice(">", 1)) and (a == "" or hover_path.has(a))


func _apply_hover() -> void:
	for k: String in edges:
		var n: Node2D = edges[k]
		if is_instance_valid(n):
			n.modulate = Color(1, 1, 1, 1.0 if hover_path.is_empty() or _on_path(k) else 0.28)


# ------------------------------------------------------------ pan and zoom
## Fits the whole tree in the view (at most 1:1), centred.
func fit_view() -> void:
	if layout.is_empty() or canvas.size.x < 8.0:
		return
	var size: Vector2 = layout["size"]
	var f := clampf(minf(canvas.size.x / size.x, canvas.size.y / size.y), 0.3, 1.0)
	min_zoom = minf(0.45, f)
	world.scale = Vector2.ONE * f
	world.position = ((canvas.size - size * f) * 0.5).round()


## Zooms by `factor` keeping the point under `at` (canvas space) still.
func zoom_at(at: Vector2, factor: float) -> void:
	var old := world.scale.x
	var z := clampf(old * factor, min_zoom, max_zoom)
	if is_equal_approx(z, old):
		return
	world.position = at - (at - world.position) * (z / old)
	world.scale = Vector2.ONE * z
	_user_view = true
	_clamp_pan()


func pan_by(d: Vector2) -> void:
	world.position += d
	_user_view = true
	_clamp_pan()


## Keeps the tree in view: centred on an axis where it is smaller than the view, else never
## further than a margin past either edge.
func _clamp_pan() -> void:
	if layout.is_empty():
		return
	var sz: Vector2 = (layout["size"] as Vector2) * world.scale.x
	var p := world.position
	var m := 40.0
	for ax in 2:
		if sz[ax] <= canvas.size[ax]:
			p[ax] = (canvas.size[ax] - sz[ax]) * 0.5
		else:
			p[ax] = clampf(p[ax], canvas.size[ax] - sz[ax] - m, m)
	world.position = p


func _on_canvas_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb:
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(mb.position, 1.1)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(mb.position, 1.0 / 1.1)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_drag = mb.pressed
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm and _drag and mm.button_mask != 0:
		pan_by(mm.relative)
		accept_event()
		return
	var mg := event as InputEventMagnifyGesture
	if mg:
		zoom_at(mg.position, mg.factor)
		accept_event()
		return
	var pg := event as InputEventPanGesture
	if pg:
		pan_by(-pg.delta * 8.0)
		accept_event()


## A card: click selects it (the inspector), double-click funds it, dragging pans the tree.
func _on_card_input(event: InputEvent, n: Control) -> void:
	var id := String(n.get_meta("tech", ""))
	var mb := event as InputEventMouseButton
	if mb:
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var at := canvas.get_global_transform().affine_inverse() * mb.global_position
			zoom_at(at, 1.1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1)
			accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_drag = true
			_dragged = false
			_press_at = mb.global_position
			if mb.double_click and TycoonResearch.node_state(state, id) in ["available", "queued", "researching"]:
				_dragged = true
				TycoonResearch.fund(state, id)
				select(id)
		else:
			_drag = false
			if not _dragged:
				select(id)
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm and _drag and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if _dragged or mm.global_position.distance_to(_press_at) > 6.0:
			_dragged = true
			pan_by(mm.relative)
		accept_event()


# ------------------------------------------------------------ the inspector
func _fill_inspector() -> void:
	var t := TycoonResearch.tech(selected)
	if t.is_empty():
		return
	var id := selected
	var st := TycoonResearch.node_state(state, id)
	var br := TycoonResearch.branch(String(t["branch"]))
	var bst := %Inspector.get_theme_stylebox("panel").duplicate() as CwPanelStyle
	if bst:
		bst.tab_color = Color(String(br.get("color", "#8c9ab5")))
		%Inspector.add_theme_stylebox_override("panel", bst)
	%IBranch.text = tr(String(br.get("name_key", "")))
	%IBranch.add_theme_color_override("font_color", CwPalette.ink(Color(String(br.get("color", "#8c9ab5")))))
	%IName.text = tr("TY_TECH_" + id.to_upper())
	%IState.text = "%s · %s" % [tr("TY_RS_ERA_N") % int(t["era"]), tr("TY_RS_ST_" + st.to_upper())]
	%IState.add_theme_color_override("font_color", CwPalette.ink(ST_COLOR[st]))
	%IDesc.text = tr("TY_TECH_" + id.to_upper() + "_DESC")
	%ICost.text = "%d PP" % int(t["cost"])
	var money := TycoonResearch.cash_cost(id)
	if money <= 0.0:
		%IMoney.text = tr("RT_NO_MONEY")
	elif TycoonResearch.cash_paid(state, id):
		%IMoney.text = tr("RT_MONEY_PAID")
	else:
		%IMoney.text = cr(money)
	%ITime.text = tr("TY_WEEKS") % int(t["weeks"])
	%IEta.text = "—" if st in ["done", "locked"] else _eta_text(TycoonResearch.weeks_left(state, id))
	(%IBar as CwSegmentBar).value = TycoonResearch.fraction(state, id)
	(%IBar as CwSegmentBar).color = CwPalette.AURORA_TEAL if st == "done" else CwPalette.AURORA_VIOLET
	%IProgress.text = "%d / %d PP" % [floori(TycoonResearch.progress(state, id)), int(t["cost"])]
	var rows := TycoonResearch.unlock_list(id)
	var lines := copies(%IUnlockTemplate, rows.size())
	for i in rows.size():
		_fill_unlock_row(lines[i], rows[i])
	var pre: Array = t.get("prereq", [])
	var keys := copies(%INeedTemplate, pre.size())
	for i in pre.size():
		var tid := String(pre[i])
		var b := keys[i] as Button
		b.text = ("✓ " if TycoonResearch.is_done(state, tid) else "") + tr("TY_TECH_" + tid.to_upper())
		b.set_meta("tech", tid)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: select(String(b.get_meta("tech"))))
			b.mouse_entered.connect(func() -> void: hover_tech(String(b.get_meta("tech"))))
			b.mouse_exited.connect(func() -> void: hover_tech(""))
	%IRequires.text = _requires_text(t)
	%IRequires.visible = %IRequires.text != ""
	_fund_button(%IFund, st, id)


func _fill_unlock_row(row: Control, r: Dictionary) -> void:
	var kind := String(r["kind"])
	var kl := row.get_node("Kind") as Label
	kl.text = tr("TY_RS_K_" + kind.to_upper())
	kl.add_theme_color_override("font_color", CwPalette.ink(KIND_COLOR.get(kind, CwPalette.TEXT_DIM)))
	var nl := row.get_node("Name") as Label
	if kind == "effect":
		nl.text = tr(String(r["key"])) % (float(r["value"]) * 100.0 if String(r["id"]) != "contract_slots" else float(r["value"]))
	elif r.has("name"):
		nl.text = String(r["name"])
	else:
		nl.text = tr(String(r["key"]))


func _requires_text(t: Dictionary) -> String:
	var la := int(TycoonResearch.db().get("era_lookahead", 1))
	var req: Array[String] = []
	if int(t["era"]) > state.era() + la:
		req.append(tr("TY_RS_NEEDS_ERA") % ((int(t["era"]) - la - 1) * 5 + 1))
	elif (t.get("prereq", []) as Array).is_empty():
		req.append(tr("TY_RS_NO_REQ"))
	var id := String(t["id"])
	if not TycoonResearch.cash_paid(state, id) and state.cash < TycoonResearch.cash_cost(id):
		req.append(tr("RT_NO_CASH") % cr(TycoonResearch.cash_cost(id)))
	return "\n".join(req)


## The one primary action of a tech, on the inspector and on the sheet.
func _fund_button(fund: Button, st: String, id: String) -> void:
	fund.disabled = false
	match st:
		"researching":
			fund.text = tr("TY_RS_STOP")
		"queued":
			fund.text = tr("TY_RS_UNQUEUE")
		"available":
			fund.text = tr("TY_RS_FUND") if TycoonResearch.active(state) == "" else tr("TY_RS_QUEUE_IT")
			fund.disabled = TycoonResearch.active(state) == "" and not TycoonResearch.cash_paid(state, id) \
				and state.cash < TycoonResearch.cash_cost(id)
		"done":
			fund.text = tr("TY_RS_ST_DONE")
			fund.disabled = true
		_:
			fund.text = tr("TY_RS_ST_LOCKED")
			fund.disabled = true


func _fill_queue() -> void:
	var act := TycoonResearch.active(state)
	if act == "":
		%QueueLabel.text = tr("TY_RS_IDLE")
		%QueueLabel.add_theme_color_override("font_color", CwPalette.WARNING)
		return
	%QueueLabel.remove_theme_color_override("font_color")
	var eta := TycoonResearch.weeks_left(state, act)
	var parts: Array[String] = ["%s (%s)" % [tr("TY_TECH_" + act.to_upper()), _eta_text(eta)]]
	for q in TycoonResearch.queue(state):
		parts.append(tr("TY_TECH_" + String(q).to_upper()))
	%QueueLabel.text = "  →  ".join(parts)


func _eta_text(w: int) -> String:
	return tr("TY_RS_NO_PP") if w < 0 else tr("TY_WEEKS") % w


func _fill_detail() -> void:
	var t := TycoonResearch.tech(selected)
	if t.is_empty():
		return
	var id := selected
	var st := TycoonResearch.node_state(state, id)
	var br := TycoonResearch.branch(String(t["branch"]))
	if pages.current() == &"Tech":
		pages.set_title(tr("TY_TECH_" + id.to_upper()))
	var bst := %Main.get_theme_stylebox("panel").duplicate() as CwPanelStyle
	if bst:
		bst.tab_color = Color(String(br.get("color", "#8c9ab5")))
		%Main.add_theme_stylebox_override("panel", bst)
	%DBranch.text = tr(String(br.get("name_key", "")))
	%DBranch.add_theme_color_override("font_color", CwPalette.ink(Color(String(br.get("color", "#8c9ab5")))))
	%DName.text = tr("TY_TECH_" + id.to_upper())
	%DState.text = "%s · %s" % [tr("TY_RS_ERA_N") % int(t["era"]), tr("TY_RS_ST_" + st.to_upper())]
	%DDesc.text = tr("TY_TECH_" + id.to_upper() + "_DESC")
	%DCost.text = "%d PP" % int(t["cost"])
	%DTime.text = tr("TY_WEEKS") % int(t["weeks"])
	var eta := TycoonResearch.weeks_left(state, id)
	%DEta.text = "—" if st in ["done", "locked"] else _eta_text(eta)
	(%DBar as CwSegmentBar).value = TycoonResearch.fraction(state, id)
	(%DBar as CwSegmentBar).color = CwPalette.AURORA_TEAL if st == "done" else CwPalette.AURORA_VIOLET
	%DProgress.text = "%d / %d PP" % [floori(TycoonResearch.progress(state, id)), int(t["cost"])]
	# unlocks
	var rows := TycoonResearch.unlock_list(id)
	var lines := copies(%UnlockTemplate, rows.size())
	for i in rows.size():
		_fill_unlock_row(lines[i], rows[i])
	# the path: what it needs and what it leads to, each a key to that tech's page
	var pre: Array = t.get("prereq", [])
	_tech_keys(%NeedTemplate, pre)
	var next: Array = []
	for o: Dictionary in TycoonResearch.techs():
		if id in Array(o.get("prereq", [])):
			next.append(String(o["id"]))
	_tech_keys(%NextTemplate, next)
	%NextNone.visible = next.is_empty()
	%Requires.text = _requires_text(t)
	%Requires.visible = %Requires.text != ""
	_fill_bench()
	# actions: the screen's one primary button
	_fund_button(%Fund, st, id)
	var lic: Button = %License
	lic.visible = st == "done"
	if TycoonResearch.can_license(state, id):
		lic.text = tr("TY_RS_LICENSE") % cr(TycoonResearch.license_value(id))
		lic.disabled = false
	else:
		lic.text = tr("TY_RS_LICENSED")
		lic.disabled = true


## Keys for a list of techs (copies of `template`): done ones ticked, each opens its page.
func _tech_keys(template: Control, ids: Array) -> void:
	var keys := copies(template, ids.size())
	for i in ids.size():
		var tid := String(ids[i])
		var b := keys[i] as Button
		b.text = ("✓ " if TycoonResearch.is_done(state, tid) else "") + tr("TY_TECH_" + tid.to_upper())
		b.set_meta("tech", tid)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void: open_tech(String(b.get_meta("tech"))))


func _on_fund() -> void:
	if state and selected != "":
		TycoonResearch.fund(state, selected)


## Who sits in the lab this week and what each adds.
func _fill_bench() -> void:
	var seated := TycoonResearch.seated(state)
	var rows := copies(%SeatTemplate, seated.size())
	var mult := TycoonResearch.lab_mult(state)
	for i in seated.size():
		var m: Dictionary = seated[i]["member"]
		var prof := state.profession(String(m.get("profession", "")))
		(rows[i].get_node("Dot") as ColorRect).color = Color(String(prof.get("color", "#8e7cff")))
		(rows[i].get_node("Name") as Label).text = String(m.get("name", ""))
		(rows[i].get_node("Prof") as Label).text = tr(String(prof.get("name_key", "")))
		(rows[i].get_node("PP") as Label).text = "+%.1f PP" % (float(seated[i]["pp"]) * mult)
	%BenchEmpty.visible = seated.is_empty()


# ------------------------------------------------------------ mission studies
## The title block's subtitle follows the tab (the tree's facts, or what studies are for).
func _sync_subtitle() -> void:
	var nb := %NavBar as CwNavBar
	var sub := "TY_ST_SUB" if pages.current() == &"Studies" else "TY_RS_SUB"
	if nb.subtitle != sub:
		nb.subtitle = sub
		nb.refresh()


## The types the lab can tell about: the ones the agency can fly or has flown.
func study_types() -> Array[String]:
	var out: Array[String] = []
	for t: Dictionary in state.mdata.get("types", []):
		var id := String(t["id"])
		if state.mission_type_available(id) or Discovery.attempts(state, id) > 0:
			out.append(id)
	return out


func _fill_studies() -> void:
	var types := study_types()
	if not study_type in types:
		study_type = FocusStudy.active(state)
		if not study_type in types:
			study_type = ""
			for id in types:
				if FocusStudy.tier(state, id) < FocusStudy.MAX_TIER:
					study_type = id
					break
			if study_type == "" and not types.is_empty():
				study_type = types[0]
	var rows := copies(%StudyTemplate, types.size())
	for i in types.size():
		var id := types[i]
		var b := rows[i] as Button
		b.set_meta("id", id)
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func() -> void:
				study_type = String(b.get_meta("id", ""))
				refresh())
		b.text = FocusView.type_name(state, id)
		b.set_pressed_no_signal(id == study_type)
		var t := FocusStudy.tier(state, id)
		(b.get_node("Pips") as CwSegmentBar).value = float(t) / 3.0
		var tag := b.get_node("Tag") as Label
		if FocusStudy.active(state) == id:
			tag.text = tr("TY_ST_TAG_ACTIVE")
			tag.add_theme_color_override("font_color", CwPalette.AURORA_VIOLET)
		elif t >= FocusStudy.MAX_TIER:
			tag.text = tr("TY_ST_TAG_KNOWN")
			tag.add_theme_color_override("font_color", CwPalette.AURORA_TEAL)
		else:
			tag.text = ""
	if study_type == "":
		return
	_fill_study_detail()


func _fill_study_detail() -> void:
	var id := study_type
	var t := FocusStudy.tier(state, id)
	var active := FocusStudy.active(state) == id
	%SName.text = FocusView.type_name(state, id)
	var n := Discovery.attempts(state, id)
	%SState.text = "%s · %s" % [FocusView.tier_text(t), tr("TY_JN_FLIGHTS") % n if n > 0 else tr("TY_JN_NEVER")]
	var marks := FocusStudy.bar_marks(state, id)
	var coarse := FocusStudy.coarse_ideal(state, id)
	var rows: Array[Node] = [%SEng, %SSci, %SOps, %SRel]
	for b in 4:
		var m: Dictionary = marks[b]
		var v := float(m["ideal"]) if t >= FocusStudy.MAX_TIER else (float(coarse[b]) if t == 2 else 0.0)
		(rows[b].get_node("Bar") as CwSegmentBar).value = v / 0.5
		var ml := rows[b].get_node("Mark") as Label
		ml.text = FocusView.mark_text(m)
		ml.add_theme_color_override("font_color", FocusView.mark_color(m))
	%SKnow.text = FocusView.know_text(state, id)
	var done := t >= FocusStudy.MAX_TIER
	%Next.visible = not done
	%Stats.visible = not done
	%SBar.visible = not done
	%SProgress.visible = not done
	%SFlight.text = tr("TY_ST_FLIGHT") % [int(BriefingDesk.disc().get("reveal_ratio_after", 2)), n]
	var sb: Button = %SStudy
	%SError.text = ""
	if done:
		sb.text = tr("TY_ST_ALL_KNOWN")
		sb.disabled = true
		return
	var nt := t + 1
	var c := FocusStudy.cost(state, id, nt)
	%SNextCaption.text = tr("TY_ST_NEXT") % nt
	%SNextText.text = tr("TY_ST_REVEAL_%d" % nt)
	%SCost.text = "%d PP" % int(c["pp"])
	%SMoney.text = tr("TY_ST_PAID") if FocusStudy.paid(state, id) else cr(float(c["cash"]))
	%STime.text = tr("TY_WEEKS") % int(c["weeks"])
	%SEta.text = _eta_text(FocusStudy.weeks_left(state, id))
	(%SBar as CwSegmentBar).value = FocusStudy.fraction(state, id)
	%SProgress.text = "%d / %d PP" % [floori(FocusStudy.progress(state, id)), int(c["pp"])]
	sb.disabled = false
	if active:
		sb.text = tr("TY_ST_STOP")
		return
	sb.text = tr("TY_ST_RESUME") if FocusStudy.paid(state, id) else tr("TY_ST_START")
	var err := FocusStudy.start_error(state, id)
	sb.disabled = err != ""
	if err != "":
		%SError.text = tr(err)
	elif FocusStudy.active(state) != "":
		%SError.text = tr("TY_ST_PAUSES") % FocusView.type_name(state, FocusStudy.active(state))


func _on_study() -> void:
	if state == null or study_type == "":
		return
	if FocusStudy.active(state) == study_type:
		FocusStudy.stop(state)
	else:
		FocusStudy.start(state, study_type)
