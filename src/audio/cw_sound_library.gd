@tool
class_name CwSoundLibrary
extends Resource
## Every named sound of the game (assets/audio/cw_sound_library.tres): UI blips, music, the
## ambience beds, Cometling voices and the launch. Scripts only ask CwSfx for a name; what it
## sounds like, how loud, on which bus and how often is edited here. The waves come from
## tools/build_audio.py (assets/audio/).

@export var sounds: Array[CwSound] = []

var _by_name := {}


func find(sound_name: StringName) -> CwSound:
	if _by_name.size() != sounds.size():
		_by_name.clear()
		for s in sounds:
			if s:
				_by_name[s.name] = s
	return _by_name.get(sound_name)


func has(sound_name: StringName) -> bool:
	return find(sound_name) != null
