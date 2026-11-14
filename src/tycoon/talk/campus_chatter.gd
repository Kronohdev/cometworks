class_name CampusChatter
extends Control
## Speech bubbles over the Cometlings on the campus (scenes/tycoon/talk/campus_chatter.tscn, on
## its own CanvasLayer under the HUD in tycoon_main.tscn, so the HUD always draws on top). The
## look is in the scene: BubbleTemplate is a paper sticker with a tail, copied for each bubble.
## This script picks who talks and what (ChatterBook, data/tycoon/chatter.json) and keeps each
## bubble over its speaker's head:
##   - the speakers are the campus Cometlings (Campus.cometlings()) and any visible node in the
##     "talkers" group (Vovô on his bench, a Lenda's own scene...); the bubble hangs from the
##     node's head (ChatterBook.head_point), so any Cometling-like node works
##   - every few seconds (the rate setting: Poucos / Normal / Muitos) one Cometling on screen and
##     near enough says a line that fits them (profession, mood, tiredness, what they are doing
##     and where, era, time of day, money, recent events), shows an emote, or two Cometlings
##     close to each other trade a line and an answer; at most `max` bubbles at once, each
##     speaker rests a while after talking, recent lines are not repeated
##   - launches, milestones, a rival's first, a new hire and a new era make a few Cometlings
##     react at once (emotes and a pose) and colour the lines for a while
##   - bubbles pop in and out, shrink and fade with distance, push each other up instead of
##     overlapping, stay inside the safe area (clear of the HUD) and hide while a screen, the
##     hangar or flight, a cutscene, a lesson or a conversation is up, or when the player turned
##     them off
## Randomness comes from this node's own RNG, never from the campaign's.

## no new bubbles for Cometlings farther than this from the camera (m); bubbles fade out there
@export var max_distance := 220.0
## bubbles start fading at this distance (m)
@export var fade_start := 165.0
## bubbles have their full size up to this distance (m) and shrink beyond it
@export var near_distance := 50.0
## the smallest a far bubble gets
@export_range(0.3, 1.0, 0.01) var far_scale := 0.78
## the bubble's tail tip sits this high above the head point (m, scaled with the Cometling)
@export var head_lift := 0.28
## screen margins bubbles keep clear of (left, top, right, bottom, px): the HUD's bars
@export var safe_margin := Vector4(90.0, 96.0, 300.0, 120.0)
## text wider than this wraps (px)
@export var wrap_width := 250.0
## seconds of the pop-in / pop-out
@export var pop_seconds := 0.22
## gap kept between two stacked bubbles (px)
@export var stack_gap := 4.0

var main: Node
var campus: Campus
var camera: Camera3D
var state: TycoonState
## the bubbles' own RNG (never the campaign's)
var rng := RandomNumberGenerator.new()
## tests: >= 0 forces the setting (1 on, 0 off) instead of the player's
var force_enabled := -1
## tests: a rate id instead of the player's ("" = the setting)
var force_rate := ""
## every line said (text keys, newest last; tests)
var said: Array[String] = []

var _bubbles: Array[Dictionary] = []   # {"node", "who", "age", "life", "key", "dying", "out"}
var _gap := 1.5
var _cool := {}             # speaker instance id -> seconds of rest left
var _events := {}           # event -> seconds left
var _queue: Array[Dictionary] = []   # {"t", "who", "key", "vars"} (answers of a pair, reactions)
var _recent: Array[String] = []
var _staff_n := -1
var _hidden := false

@onready var layer_root: Control = %Bubbles
@onready var template: Control = %BubbleTemplate


func _ready() -> void:
	rng.randomize()
	template.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Hooks the bubbles to the main screen (TycoonMain calls this once the state is bound).
func bind(m: Node) -> void:
	main = m
	campus = m.get("campus")
	camera = m.get("camera")
	state = m.get("state")
	if state == null:
		return
	_staff_n = state.staff.size()
	state.mission_launched.connect(func(r: Dictionary) -> void:
		event("launch_success" if bool(r.get("success", false)) else "launch_failure"))
	state.milestone_claimed.connect(func(_id: String, by: String) -> void:
		event("milestone" if by == RaceDirector.PLAYER else "rival_first"))
	state.era_changed.connect(func(_e: int) -> void: event("new_era"))
	state.changed.connect(_on_state_changed)


func _on_state_changed() -> void:
	if state.staff.size() > _staff_n and _staff_n >= 0:
		event("new_hire")
	_staff_n = state.staff.size()


func is_enabled() -> bool:
	return force_enabled == 1 if force_enabled >= 0 else ChatterBook.enabled()


func rate_cfg() -> Dictionary:
	return ChatterBook.rate_cfg(force_rate)


## Bubbles on show (not counting those popping out).
func active_count() -> int:
	var n := 0
	for b in _bubbles:
		if not b["dying"]:
			n += 1
	return n


## The speakers of the bubbles on show.
func speaking() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for b in _bubbles:
		if not b["dying"] and is_instance_valid(b["who"]):
			out.append(b["who"])
	return out


## The events going on now (ChatterBook context "events").
func events() -> Array:
	return _events.keys()


## Something happened: lines lean to it for a while and a few Cometlings react at once.
func event(e: String) -> void:
	_events[e] = float(ChatterBook.chatter().get("event_seconds", 80.0))
	if not is_enabled() or _blocked():
		return
	var r: Dictionary = (ChatterBook.chatter().get("reactions", {}) as Dictionary).get(e, {})
	if r.is_empty():
		return
	var who := _candidates()
	for i in range(who.size() - 1, 0, -1):   # shuffled with our own RNG
		var j := rng.randi() % (i + 1)
		var tmp: Dictionary = who[i]
		who[i] = who[j]
		who[j] = tmp
	var emotes: Array = r.get("emotes", ["exclaim"])
	for i in mini(int(r.get("count", 3)), who.size()):
		_queue.append({"t": 0.15 + i * 0.35, "who": who[i]["node"], "emote": String(emotes[rng.randi() % emotes.size()]),
			"pose": String(r.get("pose", ""))})
	_gap = minf(_gap, 0.8)


## The world context of the campus now: recent events and the time of day.
func world() -> Dictionary:
	var t := "golden"
	var dc := main.get_node_or_null("DayCycle") if main else null
	if dc and dc.get("phase") != null:
		var p := float(dc.get("phase"))
		t = "night" if p >= 0.3 and p < 0.72 else ("dawn" if p >= 0.72 and p < 0.9 else "golden")
	return {"events": events(), "time": t}


## The context of one speaker (ChatterBook.context plus "who": a talker's own id).
func context_of(n: Node3D) -> Dictionary:
	var m := _member(n)
	var act: Dictionary = n.call("activity") if n.has_method("activity") else {}
	var ctx := ChatterBook.context(state, m, act, world())
	ctx["who"] = String(n.get_meta("talk_id", "")) if n.has_meta("talk_id") else ""
	return ctx


## Shows `text` over `who` right now (a conversation's farewell, tests). The oldest bubble
## makes room when the limit is reached.
func say(who: Node3D, text: String, seconds := -1.0, key := "") -> void:
	if who == null or text == "" or not is_enabled():
		return
	for b in _bubbles:
		if b["who"] == who and not b["dying"]:
			_pop_out(b)
	if active_count() >= int(rate_cfg().get("max", 3)):
		for b in _bubbles:
			if not b["dying"]:
				_pop_out(b)
				break
	var node := template.duplicate() as Control
	node.visible = true
	layer_root.add_child(node)
	var label := node.get_node("Panel/Text") as Label
	label.text = text
	var panel := node.get_node("Panel") as Control
	var sb := panel.get_theme_stylebox("panel")
	if sb:   # each bubble moves its own tail
		panel.add_theme_stylebox_override("panel", sb.duplicate())
	_fit(node, label)
	var life := seconds if seconds > 0.0 else _seconds_for(text)
	_bubbles.append({"node": node, "who": who, "age": 0.0, "life": life, "key": key, "dying": false, "out": 0.0})
	_cool[who.get_instance_id()] = float(ChatterBook.chatter().get("speaker_cooldown", 16.0)) + life
	if key != "":
		said.append(key)
		_recent.append(key)
		if _recent.size() > 14:
			_recent.pop_front()
	_place(0.0)


## Says a line from the data that fits `who` (tests and the scheduler). Returns its key.
func say_line(who: Node3D) -> String:
	var ctx := context_of(who)
	var lines := _lines_for(ctx)
	var l := ChatterBook.pick(lines, ctx, rng, _recent)
	if l.is_empty():
		return ""
	var key := String(l.get("text_key", ""))
	say(who, ChatterBook.text(key, _vars(who)), -1.0, key)
	return key


## Two Cometlings trade a line and an answer (`a` speaks first). Returns the pair's first key,
## "" when no exchange fits them.
func say_pair(a: Node3D, b: Node3D) -> String:
	var ca := context_of(a)
	var cb := context_of(b)
	var ok: Array = []
	for p: Dictionary in ChatterBook.chatter().get("pairs", []):
		if ChatterBook.matches(p.get("if", {}), ca) and ChatterBook.matches(p.get("b_if", {}), cb):
			ok.append(p)
	var p := ChatterBook.pick(ok, ca, rng, _recent, "a_key")
	if p.is_empty():
		return ""
	var va := _vars(a)
	var vb := _vars(b)
	va["other"] = vb.get("name", "")
	vb["other"] = va.get("name", "")
	var key := String(p["a_key"])
	say(a, ChatterBook.text(key, va), -1.0, key)
	_queue.append({"t": float(ChatterBook.chatter().get("pair_reply_delay", 1.5)), "who": b,
		"key": String(p["b_key"]), "vars": vb, "look": a})
	_cool[b.get_instance_id()] = 6.0
	_face(a, b)
	return key


## A short reaction instead of a line. Returns the emote.
func emote(who: Node3D) -> String:
	var ctx := context_of(who)
	var e := ChatterBook.pick(ChatterBook.chatter().get("emotes", []), ctx, rng, [], "emote")
	var c := ChatterBook.find_creature(who)
	if e.is_empty() or c == null:
		return ""
	c.show_emote(String(e["emote"]), 2.0)
	_cool[who.get_instance_id()] = float(ChatterBook.chatter().get("speaker_cooldown", 16.0)) * 0.5
	return String(e["emote"])


## Removes every bubble at once.
func clear() -> void:
	for b in _bubbles:
		if is_instance_valid(b["node"]):
			(b["node"] as Node).queue_free()
	_bubbles.clear()
	_queue.clear()


# ------------------------------------------------------------ frame
func _process(delta: float) -> void:
	tick(delta)


## One step of the bubbles (the frame runs it; tests call it with their own delta).
func tick(delta: float) -> void:
	for e in _events.keys():
		_events[e] = float(_events[e]) - delta
		if _events[e] <= 0.0:
			_events.erase(e)
	for k in _cool.keys():
		_cool[k] = float(_cool[k]) - delta
		if _cool[k] <= 0.0:
			_cool.erase(k)
	var hide := not is_enabled() or _blocked()
	if hide != _hidden:
		_hidden = hide
		if hide:
			for b in _bubbles:
				_pop_out(b)
			_queue.clear()
	if not hide and state != null and camera != null:
		_run_queue(delta)
		_gap -= delta
		if _gap <= 0.0:
			var g: Array = rate_cfg().get("gap", [3.5, 7.5])
			_gap = rng.randf_range(float(g[0]), float(g[1]))
			if active_count() < int(rate_cfg().get("max", 3)):
				_spawn()
	_place(delta)


func _run_queue(delta: float) -> void:
	for q in _queue.duplicate():
		q["t"] = float(q["t"]) - delta
		if q["t"] > 0.0:
			continue
		_queue.erase(q)
		var who: Node3D = q["who"] if is_instance_valid(q["who"]) else null
		if who == null or not who.is_visible_in_tree():
			continue
		if q.has("key"):
			say(who, ChatterBook.text(String(q["key"]), q.get("vars", {})), -1.0, String(q["key"]))
			if q.has("look") and is_instance_valid(q["look"]):
				_face(who, q["look"])
		var c := ChatterBook.find_creature(who)
		if c and q.has("emote"):
			c.show_emote(String(q["emote"]), 2.2)
		if c and String(q.get("pose", "")) != "" and who.get("napping") != true:
			c.play(String(q["pose"]))


## Picks who talks next and how (a line, an emote or an exchange).
func _spawn() -> void:
	var cands := _candidates()
	if cands.is_empty():
		return
	var total := 0.0
	for c in cands:
		total += float(c["w"])
	var r := rng.randf() * total
	var pick: Dictionary = cands[cands.size() - 1]
	for c in cands:
		r -= float(c["w"])
		if r <= 0.0:
			pick = c
			break
	var who: Node3D = pick["node"]
	var cfg := rate_cfg()
	if rng.randf() < float(cfg.get("pair", 0.25)):
		var mate := _mate(who, cands)
		if mate and say_pair(who, mate) != "":
			return
	if rng.randf() < float(ChatterBook.chatter().get("emote_chance", 0.28)) and emote(who) != "":
		return
	say_line(who)


## Speakers that may talk now: visible, on screen, near the camera, not resting, not talking.
## [{"node", "w" (weight: nearer and the followed one talk more), "d"}]
func _candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if camera == null:
		return out
	var busy := speaking()
	var view := get_viewport_rect().size
	var followed: Node3D = camera.call("followed") if camera.has_method("followed") else null
	for n in _speakers():
		if n in busy or _cool.has(n.get_instance_id()):
			continue
		var head := ChatterBook.head_point(n)
		if camera.is_position_behind(head):
			continue
		var d := camera.global_position.distance_to(head)
		if d > max_distance:
			continue
		var sp := camera.unproject_position(head)
		if not _safe_rect(view).has_point(sp):
			continue
		var w := 1.0 + 2.0 * (1.0 - d / max_distance) + (2.0 if n == followed else 0.0)
		out.append({"node": n, "w": w, "d": d})
	return out


## A Cometling near `who` to trade lines with (or null).
func _mate(who: Node3D, cands: Array[Dictionary]) -> Node3D:
	var best: Node3D = null
	var best_d := float(ChatterBook.chatter().get("pair_distance", 5.0))
	for c in cands:
		var n: Node3D = c["node"]
		if n == who or n.has_meta("talk_id") or who.has_meta("talk_id"):
			continue
		var d := n.global_position.distance_to(who.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func _speakers() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if campus:
		out.append_array(campus.cometlings())
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group(&"talkers"):
			if n is Node3D and (n as Node3D).is_visible_in_tree() and not n in out:
				out.append(n)
	return out


func _member(n: Node3D) -> Dictionary:
	return ChatterBook.member_of(state, campus, n)


func _vars(n: Node3D) -> Dictionary:
	var m := _member(n)
	var v := ChatterBook.vars_for(state, m)
	if m.is_empty() and n.has_meta("talk_name"):
		v["name"] = tr(String(n.get_meta("talk_name")))
	return v


## The lines a speaker may say: a talker with its own id only says its own lines.
func _lines_for(ctx: Dictionary) -> Array:
	var who := String(ctx.get("who", ""))
	var out: Array = []
	for l: Dictionary in ChatterBook.chatter().get("lines", []):
		var own := String((l.get("if", {}) as Dictionary).get("who", ""))
		if (who == "" and own == "") or (who != "" and own == who):
			out.append(l)
	return out


func _blocked() -> bool:
	if main == null:
		return true
	var hud: Node = main.get("hud")
	if hud and String(hud.call("current_screen")) != "":
		return true
	var modes: Node = main.get("modes")
	if modes and bool(modes.call("is_open")):
		return true
	if Cutscenes.is_playing():
		return true
	var tut: Node = main.get("tutorial")
	if tut and bool(tut.call("is_showing")):
		return true
	var talk: Node = main.get("talk")
	if talk and bool(talk.call("is_open")):
		return true
	if camera and camera.has_method("is_cinematic") and bool(camera.call("is_cinematic")):
		return true
	return false


func _face(a: Node3D, b: Node3D) -> void:
	var ca := ChatterBook.find_creature(a)
	if ca and is_instance_valid(b):
		ca.look_at_point(ChatterBook.head_point(b), 0.7)
		var wr: WeakRef = weakref(ca)
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			var c := wr.get_ref() as Cometling
			if c:
				c.clear_look())


func _seconds_for(text: String) -> float:
	var s: Dictionary = ChatterBook.chatter().get("seconds", {})
	return clampf(float(s.get("base", 1.8)) + float(s.get("per_char", 0.055)) * text.length(),
		float(s.get("min", 2.8)), float(s.get("max", 6.5)))


func _safe_rect(view: Vector2) -> Rect2:
	return Rect2(Vector2(safe_margin.x, safe_margin.y),
		(view - Vector2(safe_margin.x + safe_margin.z, safe_margin.y + safe_margin.w)).max(Vector2.ONE))


## Short lines stay on one line; long ones wrap at wrap_width.
func _fit(node: Control, label: Label) -> void:
	var font := label.get_theme_font("font")
	var fs := label.get_theme_font_size("font_size")
	var w := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font else 999.0
	if w > wrap_width:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = wrap_width
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size.x = 0.0
	var panel := node.get_node("Panel") as Control
	panel.reset_size()
	panel.size = panel.get_combined_minimum_size()


func _pop_out(b: Dictionary) -> void:
	if not b["dying"]:
		b["dying"] = true
		b["out"] = 0.0


## Keeps every bubble over its speaker: size and fade by distance, pop motion, no overlap,
## inside the safe area.
func _place(delta: float) -> void:
	var view := get_viewport_rect().size
	var safe := _safe_rect(view)
	var reduced := CwMotion.reduced()
	var placed: Array[Rect2] = []
	# nearest first: their bubbles keep their spot, farther ones move up
	var order := _bubbles.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("dist", 0.0)) < float(b.get("dist", 0.0)))
	for b in order:
		var node: Control = b["node"]
		var who: Node3D = b["who"] if is_instance_valid(b["who"]) else null
		b["age"] = float(b["age"]) + delta
		if not b["dying"] and float(b["age"]) >= float(b["life"]):
			_pop_out(b)
		if b["dying"]:
			b["out"] = float(b["out"]) + delta
		var gone: bool = b["dying"] and float(b["out"]) >= pop_seconds
		if who == null or not who.is_visible_in_tree() or camera == null:
			gone = true
		if gone:
			_bubbles.erase(b)
			node.queue_free()
			continue
		var head := ChatterBook.head_point(who) + Vector3.UP * head_lift * who.global_basis.get_scale().y
		if camera.is_position_behind(head):
			node.visible = false
			continue
		var d := camera.global_position.distance_to(head)
		b["dist"] = d
		var tip := camera.unproject_position(head)
		var k := clampf(near_distance / maxf(d, 0.01), far_scale, 1.0)
		var fade := 1.0 - clampf((d - fade_start) / maxf(max_distance - fade_start, 1.0), 0.0, 1.0)
		if not safe.grow(24.0).has_point(tip):
			fade = 0.0
		var pop := 1.0
		var a := 1.0
		if b["dying"]:
			var t := clampf(float(b["out"]) / pop_seconds, 0.0, 1.0)
			pop = 1.0 - 0.4 * t
			a = 1.0 - t
		else:
			var t2 := clampf(float(b["age"]) / pop_seconds, 0.0, 1.0)
			pop = _back(t2)
			a = clampf(t2 * 2.0, 0.0, 1.0)
		if reduced:
			pop = 1.0
		node.visible = fade > 0.01
		node.modulate.a = a * fade
		node.scale = Vector2.ONE * k * pop
		# the panel above the tail, kept inside the safe area and clear of nearer bubbles
		var panel := node.get_node("Panel") as Control
		var sb := panel.get_theme_stylebox("panel")
		var ts := float(sb.get("tail_size")) if sb and sb.get("tail_size") != null else 12.0
		var home := Vector2(-panel.size.x * 0.5, -panel.size.y - ts)
		var rect := Rect2(tip + home * k, panel.size * k)
		var shift := Vector2.ZERO
		if rect.position.x < safe.position.x:
			shift.x = safe.position.x - rect.position.x
		elif rect.end.x > safe.end.x:
			shift.x = safe.end.x - rect.end.x
		rect.position += shift
		for r in placed:
			if r.grow(stack_gap).intersects(rect):
				var up := rect.end.y - (r.position.y - stack_gap)
				rect.position.y -= up
				shift.y -= up
		if rect.position.y < safe.position.y or rect.end.y > safe.end.y + 24.0:
			node.visible = false   # it would run under the HUD's bars: wait until it fits
		if node.visible:
			placed.append(rect)
		node.position = tip
		panel.position = home + shift / maxf(k * pop, 0.01)
		_aim_tail(sb, -panel.position.x - ts * 0.15, absf(shift.y) < 1.0)


## Points the bubble's tail (CwPanelStyle tail_side / tail_offset) at the head below it, or
## hides it while the bubble is pushed up over another one.
static func _aim_tail(sb: StyleBox, x: float, on: bool) -> void:
	if sb == null or sb.get("tail_offset") == null:
		return
	var side := 2 if on else 0
	if int(sb.get("tail_side")) != side:
		sb.set("tail_side", side)
	if absf(float(sb.get("tail_offset")) - x) > 0.5:
		sb.set("tail_offset", x)


static func _back(t: float) -> float:
	var c := 1.70158
	var u := t - 1.0
	return 1.0 + (c + 1.0) * u * u * u + c * u * u
