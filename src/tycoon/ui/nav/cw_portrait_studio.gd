class_name CwPortraitStudio
extends SubViewport
## A small photo studio for Cometling portraits (scenes/tycoon/ui/cw_portrait_studio.tscn):
## one Cometling on a plinth, lit and outlined like the crew sheet's live visor. Lists of many
## Cometlings (the roster grid, the hiring market) ask it for a still instead of running one
## 3D viewport per card: portrait() returns the cached still, or null and queues a shot; when
## the shot is ready `shot` fires with the member's key. Stills are kept for the session,
## keyed by the look (variant, profession, leader colours and hat). Headless runs take no
## photos (the cards keep their profession badge).

signal shot(key: String, texture: Texture2D)

static var _cache := {}

var _queue: Array[Dictionary] = []
var _busy := false

@onready var creature: Cometling = $Creature


## The cache key of a member's look.
static func key_of(m: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s" % [m.get("id", ""), m.get("variant", 0), m.get("profession", ""),
		m.get("body", ""), m.get("spot", ""), m.get("hat", "")]


static func enabled() -> bool:
	return DisplayServer.get_name() != "headless"


## The still of `m` if it is ready (else null, and it is queued; `shot` tells when).
func portrait(m: Dictionary, glow := Color.WHITE) -> Texture2D:
	var k := key_of(m)
	if _cache.has(k):
		return _cache[k]
	if not enabled():
		return null
	for q in _queue:
		if q["key"] == k:
			return null
	_queue.append({"key": k, "m": m.duplicate(true), "glow": glow})
	if not _busy:
		_run.call_deferred()
	return null


func _run() -> void:
	if _busy or not is_inside_tree():
		return
	_busy = true
	while not _queue.is_empty():
		var q: Dictionary = _queue.pop_front()
		TycoonLeader.dress(creature, q["m"])
		creature.glow_color = q["glow"]
		creature.play("idle")
		# two frames: the new colours land, then the photo
		for i in 2:
			render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			if not is_instance_valid(self) or not is_inside_tree():
				return
		var img := get_texture().get_image()
		if img and not img.is_empty():
			var tex := ImageTexture.create_from_image(img)
			_cache[q["key"]] = tex
			shot.emit(String(q["key"]), tex)
	_busy = false
