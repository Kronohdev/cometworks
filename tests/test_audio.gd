extends SceneTree
## Audio pass: the buses of default_bus_layout.tres exist; every entry of the sound library
## loads (streams present, buses known, loops looping); the volume options scale the buses;
## the sound player (CwSfx) plays and counts; the UI motion components make their sounds
## (hover, click, toggle, back, denied, screen open / close, number blips); a Cometling's
## emote chirps once and then keeps quiet for its cooldown; the music crossfades; the launch
## audio follows the sequence's AnimationPlayer and stays silent over a skip; the campus
## soundscape follows the day cycle and chimes on news and milestones; the menu shots carry
## their ambience. Runs with the Dummy audio driver: nothing here needs a sound card.
## Run: godot --headless --path . --script res://tests/test_audio.gd

const LIB := "res://assets/audio/cw_sound_library.tres"
const BUSES := ["Music", "SFX", "UI", "Ambience"]
const LOOPS := ["music_menu", "music_campus", "amb_day", "amb_night", "amb_space", "launch_rumble"]

var _fails := 0


func _initialize() -> void:
	_buses()
	_library()
	await _frames(2)
	_settings()
	await _player()
	await _ui_hooks()
	await _voices()
	await _music()
	await _launch()
	await _campus()
	_scenes()
	print("RESULT: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait(s: float) -> void:
	await create_timer(s).timeout


# ------------------------------------------------------------------ buses and library
func _buses() -> void:
	print("buses")
	for b in BUSES:
		var i := AudioServer.get_bus_index(b)
		_check(i > 0 and AudioServer.get_bus_send(i) == &"Master", "bus %s exists and sends to Master" % b)


func _library() -> void:
	print("sound library")
	var lib := load(LIB) as CwSoundLibrary
	_check(lib != null and lib.sounds.size() >= 30, "library loads (%d sounds)" % (lib.sounds.size() if lib else 0))
	if lib == null:
		return
	var bad: PackedStringArray = []
	var names := {}
	for s in lib.sounds:
		if s == null or s.name == &"" or s.streams.is_empty():
			bad.append(str(s.name if s else "null"))
			continue
		if names.has(s.name):
			bad.append("%s twice" % s.name)
		names[s.name] = true
		if AudioServer.get_bus_index(s.bus) < 0:
			bad.append("%s: bus %s" % [s.name, s.bus])
		for st in s.streams:
			if st == null or st.get_length() <= 0.0:
				bad.append("%s: empty stream" % s.name)
	_check(bad.is_empty(), "every entry has streams that load, on a known bus %s" % ("" if bad.is_empty() else str(bad)))
	for n in ["ui_hover", "ui_click", "ui_back", "ui_open", "ui_close", "ui_toggle_on", "ui_toggle_off", "ui_denied",
			"cash_up", "cash_down", "news_chime", "menu_hover", "menu_select", "music_menu", "music_campus",
			"stinger_milestone", "stinger_finale", "amb_day", "amb_night", "workshop_clank", "voice_happy",
			"voice_snore"]:
		_check(lib.has(n), "library has %s" % n)
	for n in LOOPS:
		var s := lib.find(n)
		var w := s.streams[0] as AudioStreamWAV if s else null
		_check(w != null and w.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops (smpl chunk picked up on import)" % n)
	var one := lib.find(&"ui_click").streams[0] as AudioStreamWAV
	_check(one != null and one.loop_mode == AudioStreamWAV.LOOP_DISABLED, "one-shots do not loop")


# ------------------------------------------------------------------ settings
func _settings() -> void:
	print("volume settings")
	var keep := [MenuSettings.volume(), MenuSettings.music_volume(), MenuSettings.sfx_volume()]
	MenuSettings.apply_audio()
	var base_music := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(maxf(keep[1], 0.0001))
	MenuSettings.set_music_volume(0.5)
	var m := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	_check(is_equal_approx(snappedf(m, 0.01), snappedf(base_music + linear_to_db(0.5), 0.01)),
		"music 50 %% sets the Music bus to %.2f dB (got %.2f)" % [base_music + linear_to_db(0.5), m])
	_check(is_equal_approx(MenuSettings.music_volume(), 0.5), "music volume is stored")
	MenuSettings.set_sfx_volume(0.0)
	var muted := true
	for b in ["SFX", "UI", "Ambience"]:
		muted = muted and AudioServer.is_bus_mute(AudioServer.get_bus_index(b))
	_check(muted, "effects 0 %% mutes SFX, UI and Ambience")
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "...but not the music")
	MenuSettings.set_sfx_volume(1.0)
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("UI")), "effects back up unmutes them")
	MenuSettings.set_volume(0.3)
	var master := AudioServer.get_bus_volume_db(0)
	_check(master < -6.0, "master 30 %% turns Master down (%.1f dB)" % master)
	# the options panel has the three sliders and drives the same settings
	var panel := (load("res://scenes/menu/options_panel.tscn") as PackedScene).instantiate() as MenuOptionsPanel
	root.add_child(panel)
	_check(panel.music_volume != null and panel.sfx_volume != null, "options panel has Music and Effects sliders")
	panel.music_volume.value = 35.0
	_check(is_equal_approx(MenuSettings.music_volume(), 0.35), "the Music slider sets the music volume")
	panel.sfx_volume.value = 60.0
	_check(is_equal_approx(MenuSettings.sfx_volume(), 0.6), "the Effects slider sets the effects volume")
	panel.free()
	MenuSettings.set_volume(keep[0])
	MenuSettings.set_music_volume(keep[1])
	MenuSettings.set_sfx_volume(keep[2])


# ------------------------------------------------------------------ player
func _player() -> void:
	print("sound player")
	var sfx := CwSfx.get_instance()
	await _frames(2)
	_check(sfx != null and sfx.is_inside_tree(), "CwSfx is up (autoload %s)" % (root.get_node_or_null("CwAudio") != null))
	_check(sfx.library != null, "it has the library")
	var n := CwSfx.count(&"ui_click")
	CwSfx.play(&"ui_click")
	_check(CwSfx.count(&"ui_click") == n + 1, "play() plays and counts")
	CwSfx.play(&"ui_click")
	_check(CwSfx.count(&"ui_click") == n + 1, "the cooldown keeps a double click to one sound")
	await _wait(0.1)
	CwSfx.play(&"ui_click")
	_check(CwSfx.count(&"ui_click") == n + 2, "after the cooldown it plays again")
	CwSfx.play(&"no_such_sound")
	_check(CwSfx.count(&"no_such_sound") == 0, "an unknown name is silent (a warning, no error)")


# ------------------------------------------------------------------ UI hooks
func _ui_hooks() -> void:
	print("UI hooks")
	var box := VBoxContainer.new()
	root.add_child(box)
	var b := Button.new()
	b.name = "Plain"
	box.add_child(b)
	var t := Button.new()
	t.name = "Toggle"
	t.toggle_mode = true
	box.add_child(t)
	var back := Button.new()
	back.name = "Back"
	box.add_child(back)
	var off := Button.new()
	off.name = "Off"
	off.disabled = true
	box.add_child(off)
	var motion := CwButtonMotion.new()
	motion.scope = CwButtonMotion.Scope.SUBTREE
	box.add_child(motion)
	await _frames(2)
	await _wait(0.2)   # past every cooldown of the sounds played above
	var c := _counts(["ui_hover", "ui_click", "ui_toggle_on", "ui_toggle_off", "ui_back", "ui_denied", "ui_open",
		"ui_close", "cash_up", "cash_down"])
	b.mouse_entered.emit()
	_check(CwSfx.count(&"ui_hover") == c["ui_hover"] + 1, "hover ticks")
	b.focus_entered.emit()
	_check(CwSfx.count(&"ui_hover") == c["ui_hover"] + 1, "focus on a hovered button does not tick twice")
	b.pressed.emit()
	_check(CwSfx.count(&"ui_click") == c["ui_click"] + 1, "press clicks")
	t.button_pressed = true
	t.pressed.emit()
	_check(CwSfx.count(&"ui_toggle_on") == c["ui_toggle_on"] + 1, "a toggle switched on plays toggle-on")
	await _wait(0.1)
	t.button_pressed = false
	t.pressed.emit()
	_check(CwSfx.count(&"ui_toggle_off") == c["ui_toggle_off"] + 1, "...and off plays toggle-off")
	back.pressed.emit()
	_check(CwSfx.count(&"ui_back") == c["ui_back"] + 1, "a Back key plays back")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	off.gui_input.emit(click)
	_check(CwSfx.count(&"ui_denied") == c["ui_denied"] + 1, "clicking a disabled button plays denied")
	box.free()
	# screen transition
	var screen := Control.new()
	var pnl := Control.new()
	pnl.name = "Panel"
	screen.add_child(pnl)
	var trans := CwScreenTransition.new()
	trans.panel = NodePath("../Panel")
	screen.add_child(trans)
	root.add_child(screen)
	await _frames(2)
	_check(CwSfx.count(&"ui_open") == c["ui_open"] + 1, "a screen coming in whooshes open")
	trans.play_out()
	_check(CwSfx.count(&"ui_close") == c["ui_close"] + 1, "...and whooshes closed when it leaves")
	screen.free()
	# number ticker
	var l := Label.new()
	var tk := CwNumberTicker.new()
	l.add_child(tk)
	root.add_child(l)
	await _frames(1)
	var fmt := func(v: float) -> String: return str(roundi(v))
	CwNumberTicker.show(l, 1000.0, fmt)
	_check(CwSfx.count(&"cash_up") == c["cash_up"], "the first value is set silently")
	CwNumberTicker.show(l, 50000.0, fmt)
	_check(CwSfx.count(&"cash_up") == c["cash_up"] + 1, "a rise blips up")
	await _wait(0.3)
	CwNumberTicker.show(l, 100.0, fmt)
	_check(CwSfx.count(&"cash_down") == c["cash_down"] + 1, "a drop blips down")
	tk.flash_strength = 0.0
	await _wait(0.3)
	CwNumberTicker.show(l, 9000.0, fmt)
	_check(CwSfx.count(&"cash_up") == c["cash_up"] + 1, "a ticker without a flash stays silent")
	l.free()


func _counts(names: Array) -> Dictionary:
	var d := {}
	for n: String in names:
		d[n] = CwSfx.count(StringName(n))
	return d


# ------------------------------------------------------------------ Cometling voices
func _voices() -> void:
	print("Cometling voices")
	var sfx := CwSfx.get_instance()
	var happy := sfx.library.find(&"voice_happy")
	var keep_chance := happy.chance
	happy.chance = 1.0
	var world := Node3D.new()
	root.add_child(world)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 2, 8)
	cam.make_current()
	var cr := (load("res://scenes/npc/creature.tscn") as PackedScene).instantiate() as Cometling
	cr.listen_to_events = false
	world.add_child(cr)
	await _frames(2)
	var n := CwSfx.count(&"voice_happy")
	cr.show_emote("happy")
	_check(CwSfx.count(&"voice_happy") == n + 1, "an emote chirps")
	await _wait(0.5)
	cr.show_emote("heart")
	_check(CwSfx.count(&"voice_happy") == n + 1, "the same Cometling keeps quiet for its cooldown")
	var far := (load("res://scenes/npc/creature.tscn") as PackedScene).instantiate() as Cometling
	far.listen_to_events = false
	world.add_child(far)
	far.position = Vector3(0, 0, -400)
	await _frames(1)
	far.show_emote("happy")
	_check(CwSfx.count(&"voice_happy") == n + 1, "a Cometling far from the camera stays quiet")
	# a crowd emoting at once: the library's polyphony and cooldown keep it to a few voices
	var crowd: Array[Cometling] = []
	for i in 12:
		var c := (load("res://scenes/npc/creature.tscn") as PackedScene).instantiate() as Cometling
		c.listen_to_events = false
		world.add_child(c)
		c.position = Vector3(i - 6, 0, 0)
		crowd.append(c)
	await _frames(1)
	await _wait(0.4)
	var before := CwSfx.count(&"voice_happy")
	for c in crowd:
		c.show_emote("happy")
	var burst := CwSfx.count(&"voice_happy") - before
	_check(burst >= 1 and burst <= happy.max_voices, "twelve emotes at once make %d chirp(s) (max %d)" % [burst, happy.max_voices])
	happy.chance = keep_chance
	world.free()


# ------------------------------------------------------------------ music
func _music() -> void:
	print("music")
	var sfx := CwSfx.get_instance()
	CwSfx.music(&"music_menu", 0.2)
	await _frames(2)
	_check(sfx.current_music() == &"music_menu", "the menu theme plays")
	await _wait(0.4)
	CwSfx.music(&"music_campus", 0.2)
	await _frames(1)
	_check(sfx.current_music() == &"music_campus", "it crossfades to the campus loop")
	await _wait(0.5)
	# (headless runs never start the players: the decks' levels tell the crossfade)
	var decks: Array[AudioStreamPlayer] = [sfx.get_node("Music/DeckA") as AudioStreamPlayer, sfx.get_node("Music/DeckB") as AudioStreamPlayer]
	var up := 0
	for d: AudioStreamPlayer in decks:
		if d.volume_db > -40.0:
			up += 1
	var campus_deck: AudioStreamPlayer = decks[0] if decks[0].stream and decks[0].stream.resource_path.contains("campus") else decks[1]
	_check(up == 1 and campus_deck.volume_db > -40.0, "after the fade only the campus deck is up (%d up)" % up)
	var n := CwSfx.count(&"stinger_milestone")
	CwSfx.stinger(&"stinger_milestone")
	_check(CwSfx.count(&"stinger_milestone") == n + 1, "a stinger plays over the music")
	CwSfx.music(&"", 0.1)
	await _wait(0.3)


# ------------------------------------------------------------------ launch
func _launch() -> void:
	print("launch audio")
	var seq_scene := FileAccess.get_file_as_string("res://scenes/tycoon/launch/launch_sequence.tscn")
	_check(seq_scene.count("launch_audio.tscn") == 1 and seq_scene.count("[node name=\"LaunchAudio\"") == 1,
		"launch_sequence.tscn holds one LaunchAudio instance")
	# a stand-in sequence: an AnimationPlayer with the sequence's animation names
	var seq := Node.new()
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	var lib := AnimationLibrary.new()
	for a: Array in [["countdown", 7.0], ["flight_success", 7.5], ["result", 4.5]]:
		var an := Animation.new()
		an.length = a[1]
		lib.add_animation(a[0], an)
	ap.add_animation_library("", lib)
	seq.add_child(ap)
	var la := (load("res://scenes/tycoon/launch/launch_audio.tscn") as PackedScene).instantiate() as LaunchAudio
	seq.add_child(la)
	root.add_child(seq)
	await _frames(1)
	for a in ["countdown", "flight_success", "flight_partial", "flight_fail", "result", "outro"]:
		_check(la.cues.has_animation(a), "Cues has '%s'" % a)
	ap.play("countdown")
	await _wait(1.4)
	_check(int(la.cued.get(&"Tick", 0)) >= 2, "the countdown ticks with the sequence (%d)" % int(la.cued.get(&"Tick", 0)))
	ap.seek(6.9, true)   # the player skips
	await _frames(3)
	_check(not la.cued.has(&"Ignition") and not la.cued.has(&"Go"), "a skip does not fire the cues it jumped over")
	ap.play("flight_success")
	ap.seek(7.4, true)
	await _frames(3)
	_check(not la.cued.has(&"Cheer"), "skipping the flight stays quiet too")
	ap.play("result")
	await _wait(0.4)
	_check(int(la.cued.get(&"ResultSuccess", 0)) == 1, "the result card chimes for the outcome")
	seq.free()


# ------------------------------------------------------------------ campus
func _campus() -> void:
	print("campus soundscape")
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	root.add_child(main)
	await _frames(3)
	main.race_flow.autosave = false
	var audio := main.get_node_or_null("Audio") as CampusAudio
	_check(audio != null, "the campus has its Audio node")
	if audio == null:
		main.free()
		return
	_check(CwSfx.get_instance().current_music() == &"music_campus", "the campus loop plays")
	var cycle := main.get_node("DayCycle") as CampusDayCycle
	cycle.force_phase = 0.5
	await _wait(0.3)
	_check(audio.night_bed.mix > 0.9 and audio.day_bed.mix < 0.2, "at night the crickets take over (day %.2f, night %.2f)" % [audio.day_bed.mix, audio.night_bed.mix])
	cycle.force_phase = 0.05
	await _wait(0.3)
	_check(audio.day_bed.mix > 0.9 and audio.night_bed.mix < 0.3, "by day the birds are back (day %.2f, night %.2f)" % [audio.day_bed.mix, audio.night_bed.mix])
	await _wait(0.8)   # past the chime cooldown (the campaign may have opened with news)
	var news := CwSfx.count(&"news_chime")
	main.state.news.push_front({"key": "TY_NEWS_WELCOME", "args": []})
	main.state.changed.emit()
	_check(CwSfx.count(&"news_chime") == news + 1, "a news line chimes")
	main.state.changed.emit()
	_check(CwSfx.count(&"news_chime") == news + 1, "...once (a refresh without news is silent)")
	# milestones: the hook is wired; called directly so the race flow is not fed a fake one
	_check(main.state.milestone_claimed.is_connected(audio._on_milestone), "the campus listens to milestones")
	var st := CwSfx.count(&"stinger_milestone")
	await _wait(1.1)
	CwSfx.get_instance().stop_stinger()   # the one of the music check above
	audio._on_milestone("test", "player")
	_check(CwSfx.count(&"stinger_milestone") == st + 1, "the player's milestone plays the stinger")
	await _wait(1.1)
	CwSfx.get_instance().stop_stinger()
	audio._on_milestone("test2", "rival_a")
	_check(CwSfx.count(&"stinger_milestone") == st + 1, "a rival's does not")
	main.hud.open_screen("crew")
	await _wait(0.8)
	_check(audio.day_bed.mix < 0.8, "the beds dip under a full screen (%.2f)" % audio.day_bed.mix)
	main.hud.close_screen()
	await _frames(3)
	var clanks := audio.clanks.count
	audio.clanks.emit_once()
	_check(audio.clanks.count == clanks + 1 and audio.clanks.stream != null, "the workshop clanks")
	main.queue_free()
	await _frames(3)


# ------------------------------------------------------------------ scenes
func _scenes() -> void:
	print("scenes")
	var menu := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	var cue := menu.get_node_or_null("MusicCue") as CwMusicCue
	_check(cue != null and cue.track == &"music_menu", "the main menu cues its theme")
	menu.free()
	var item := (load("res://scenes/menu/menu_item.tscn") as PackedScene).instantiate()
	var bm := item.get_node("CwButton") as CwButtonMotion
	_check(bm.hover_sound == &"menu_hover" and bm.press_sound == &"menu_select", "menu items use the kalimba sounds")
	item.free()
	var probe := (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	var shots := (probe.get_node("Background") as MenuDirector).shots.duplicate()
	probe.free()
	for path: String in shots:
		var shot := (load(path) as PackedScene).instantiate()
		var amb := shot.get_node_or_null("Ambience") as CwAmbiencePlayer
		_check(amb != null and amb.stream != null and amb.bus == &"Ambience", "%s has its ambience" % path.get_file())
		shot.free()
