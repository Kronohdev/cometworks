class_name MissionPhotos
extends RefCounted
## Photos sent home by missions: the data side (pure state, runs headless). A mission whose
## payload carries a camera (data/tycoon/mission_photos.json "cameras": the camera or the
## infrared camera) and that launches with a partial / full / exceptional outcome sends home
## one to three photos of its target. Each photo is a record in TycoonState.photos:
##   {"id": "<project_id>_<n>", "project_id", "code", "type", "target", "shot" (a shot of
##    mission_photos.json), "filter" ("" or "ir"), "outcome", "week" (state.weeks when it
##    arrived), "seed" (int: the shot's small variations), "file" (user:// PNG path),
##    "pinned" (bool: on the campus mural)}
## The pictures themselves are rendered off-screen by MissionPhotoStudio
## (scenes/tycoon/photos/photo_studio.tscn) in the windowed game, into "file". A record whose
## file is missing (headless runs, a save copied to another computer, a cleared user://) is
## simply rendered again the next time the studio runs: the record holds everything the shot
## needs. Old saves without photos load with an empty album.
##
## For other features (the comic recap...): MissionPhotos.photos_for(state, project_id) gives a
## project's photos, oldest first, each record a copy with "path" (the PNG, absolute user://
## path), "has_image" (the PNG is on disk), "subject_key" and "date" filled in;
## MissionPhotos.texture(photo) loads one as a Texture2D (null when not rendered yet).
## Hooked on the state's mission_launched (attach), so it needs no change in the launch code.

const DATA_PATH := "res://data/tycoon/mission_photos.json"

static var _data: Dictionary = {}
## path -> {"mtime": int, "tex": ImageTexture}: textures loaded from user://
static var _tex_cache: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = TycoonState.load_json(DATA_PATH)
	return _data


## Listens to the state's launches (called by TycoonState.new_campaign / from_dict).
static func attach(state: TycoonState) -> void:
	if state.has_meta("mission_photos"):
		return
	state.set_meta("mission_photos", true)
	var ref: WeakRef = weakref(state)
	state.mission_launched.connect(func(r: Dictionary) -> void:
		var s := ref.get_ref() as TycoonState
		if s:
			on_launch(s, r))


## The camera modules in a payload (module ids), in mission_photos.json order.
static func cameras_in(payload: Array) -> Array[String]:
	var out: Array[String] = []
	for c in data().get("cameras", []):
		if String(c) in payload:
			out.append(String(c))
	return out


## How many photos a launch with this outcome sends home.
static func count_for(outcome: String) -> int:
	return int((data().get("count", {}) as Dictionary).get(outcome, 0))


## The shots a mission of `type_id` to `target_id` takes, in order (may be empty).
static func shots_for(type_id: String, target_id: String) -> Array[String]:
	var out: Array[String] = []
	var bt: Dictionary = (data().get("by_type", {}) as Dictionary).get(type_id, {})
	var list: Array = []
	if not bt.is_empty() and (not bt.has("targets") or target_id in bt["targets"]):
		list = bt.get("shots", [])
	else:
		list = (data().get("by_target", {}) as Dictionary).get(target_id, [])
	for s in list:
		if (data().get("shots", {}) as Dictionary).has(String(s)):
			out.append(String(s))
	return out


static func shot(shot_id: String) -> Dictionary:
	return (data().get("shots", {}) as Dictionary).get(shot_id, {})


## A launch result (TycoonState.mission_launched): records the photos it sends home and
## returns them (empty when it had no camera or failed). Pure data; the studio renders them.
static func on_launch(state: TycoonState, result: Dictionary) -> Array[Dictionary]:
	var made: Array[Dictionary] = []
	if not bool(result.get("success", false)):
		return made
	var pid := String(result.get("project_id", ""))
	if pid == "" or not photos_for(state, pid).is_empty():
		return made
	var entry := ProjectDesk.history_entry(state, pid)
	var payload: Array = entry.get("payload", result.get("payload", []))
	var cams := cameras_in(payload)
	if cams.is_empty():
		return made
	var outcome := String(result.get("outcome", entry.get("outcome", "partial")))
	var n := count_for(outcome)
	var type_id := String(result.get("type", ""))
	var target_id := String(result.get("target", ""))
	var shots := shots_for(type_id, target_id)
	if n <= 0 or shots.is_empty():
		return made
	# a plain camera takes plain pictures; with only the infrared one they come out in false colours
	var filter := String((data().get("filters", {}) as Dictionary).get(cams[0], ""))
	# the next shots of a target already pictured, so a second mission there brings new views
	var before := 0
	for ph: Dictionary in state.photos:
		if String(ph.get("target", "")) == target_id:
			before += 1
	var code := String(result.get("code", entry.get("code", "")))
	for i in n:
		var id := "%s_%d" % [pid, i + 1]
		var ps := absi(hash([state.campaign_seed, pid, i, state.weeks])) % 1000000
		var ph := {"id": id, "project_id": pid, "code": code, "type": type_id, "target": target_id,
			"shot": shots[(before + i) % shots.size()], "filter": filter, "outcome": outcome, "week": state.weeks,
			"seed": ps, "file": file_for(state, id, ps), "pinned": false}
		state.photos.append(ph)
		made.append(ph)
	state.news.push_front({"key": "TY_PH_NEWS", "args": [code, made.size()]})
	return made


## Where a photo's PNG goes: the campaign's seed and a per-photo token keep two careers with
## the same project ids apart.
static func file_for(state: TycoonState, id: String, p_seed: int) -> String:
	var token := "%x" % (absi(hash([state.campaign_seed, id, p_seed, Time.get_ticks_usec(), state.agency_name])) % 0xFFFFFF)
	return "%s/%d/%s_%s.png" % [String(data().get("dir", "user://mission_photos")), state.campaign_seed, id, token]


## A photo's record with "path", "has_image", "subject_key" and "date" filled in (a copy).
static func describe(state: TycoonState, ph: Dictionary) -> Dictionary:
	var out := ph.duplicate()
	out["path"] = String(ph.get("file", ""))
	out["has_image"] = has_image(ph)
	out["subject_key"] = String(shot(String(ph.get("shot", ""))).get("subject_key", ""))
	out["date"] = date_text(state, int(ph.get("week", 0)))
	return out


## Every photo of a project, oldest first (described). The comic recap and other features
## read the photos from here: see the class doc for the keys.
static func photos_for(state: TycoonState, project_id: String) -> Array:
	var out: Array = []
	for ph: Dictionary in state.photos:
		if String(ph.get("project_id", "")) == project_id:
			out.append(describe(state, ph))
	return out


## Every photo of the agency, newest first (described).
static func album(state: TycoonState) -> Array:
	var out: Array = []
	for i in range(state.photos.size() - 1, -1, -1):
		out.append(describe(state, state.photos[i]))
	return out


static func find(state: TycoonState, photo_id: String) -> Dictionary:
	for ph: Dictionary in state.photos:
		if String(ph.get("id", "")) == photo_id:
			return ph
	return {}


static func has_image(ph: Dictionary) -> bool:
	var f := String(ph.get("file", ""))
	return f != "" and FileAccess.file_exists(f)


## The photos whose PNG is not on disk yet (the studio's queue), oldest first.
static func missing(state: TycoonState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ph: Dictionary in state.photos:
		if not has_image(ph):
			out.append(ph)
	return out


## Pins a photo on the campus mural, or takes it down.
static func set_pinned(state: TycoonState, photo_id: String, on: bool) -> void:
	var ph := find(state, photo_id)
	if ph.is_empty():
		return
	ph["pinned"] = on
	state.changed.emit()


## The photos on the campus mural: the pinned ones (newest first), then the best by outcome
## and the newest, up to mural_max.
static func mural(state: TycoonState) -> Array[Dictionary]:
	var rank: Dictionary = data().get("outcome_rank", {})
	var list: Array[Dictionary] = []
	list.assign(state.photos)
	var order := {}
	for i in list.size():
		order[list[i]["id"]] = i
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := 1 if a.get("pinned", false) else 0
		var pb := 1 if b.get("pinned", false) else 0
		if pa != pb:
			return pa > pb
		var ra := int(rank.get(String(a.get("outcome", "")), 0))
		var rb := int(rank.get(String(b.get("outcome", "")), 0))
		if ra != rb:
			return ra > rb
		return int(order[a["id"]]) > int(order[b["id"]]))
	var out: Array[Dictionary] = []
	for ph in list:
		if out.size() >= int(data().get("mural_max", 3)):
			break
		# one picture per mission on the wall, so it tells more stories
		var dup := false
		for o in out:
			if o["project_id"] == ph["project_id"]:
				dup = true
		if not dup:
			out.append(ph)
	return out


## "Year 3 · week 14" for week index `w`.
static func date_text(state: TycoonState, w: int) -> String:
	var wpy := state.weeks_per_year()
	return TranslationServer.translate("TY_PH_DATE") % [w / wpy + 1, w % wpy + 1]


## The short stamp printed on the picture: "A03·S14" in Portuguese, "Y03·W14" in English.
static func stamp_text(state: TycoonState, w: int) -> String:
	var wpy := state.weeks_per_year()
	return TranslationServer.translate("TY_PH_STAMP") % [w / wpy + 1, w % wpy + 1]


## The picture of a photo as a texture (cached; reloaded when the file changes), null when it
## was not rendered yet.
static func texture(ph: Dictionary) -> Texture2D:
	var f := String(ph.get("file", ph.get("path", "")))
	if f == "" or not FileAccess.file_exists(f):
		return null
	var mt := FileAccess.get_modified_time(f)
	var c: Dictionary = _tex_cache.get(f, {})
	if not c.is_empty() and int(c["mtime"]) == mt:
		return c["tex"]
	var img := Image.load_from_file(f)
	if img == null or img.is_empty():
		return null
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[f] = {"mtime": mt, "tex": tex}
	return tex


## Drops a cached texture (the studio rewrote the file).
static func forget(path: String) -> void:
	_tex_cache.erase(path)


## Reads TycoonState.photos from a save (old saves: none). JSON numbers come back as floats.
static func restore(d: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not d is Array:
		return out
	for ph in d:
		if ph is Dictionary and String((ph as Dictionary).get("id", "")) != "":
			var p := (ph as Dictionary).duplicate()
			p["week"] = int(p.get("week", 0))
			p["seed"] = int(p.get("seed", 0))
			p["pinned"] = bool(p.get("pinned", false))
			out.append(p)
	return out
