extends SceneTree
## Audio pass: the buses of default_bus_layout.tres exist; every entry of the sound library
## loads (streams present, buses known, loops looping); the volume options scale the buses;
## the sound player (CwSfx) plays and counts; the UI motion components make their sounds
## (hover, click, toggle, back, denied, screen open / close, number blips); a Cometling's
## emote chirps once and then keeps quiet for its cooldown; the music crossfades; the launch
## audio follows the sequence's AnimationPlayer and stays silent over a skip; the campus
## soundscape follows the day cycle and chimes on news and milestones; the menu shots carry
## their ambience; the newer features sound: the conference fair (bed, band, footsteps, talk
## chime, the award), the flight comic (page, pops, words, end sting), the launch watch (its
## hook, the skip's held loop), the CML / crew ticks (CwSfx.tally / run). Runs with the Dummy
## audio driver: nothing here needs a sound card.
## Run: godot --headless --path . --script res://tests/test_audio.gd

const LIB := "res://assets/audio/cw_sound_library.tres"
const BUSES := ["Music", "SFX", "UI", "Ambience"]
const LOOPS := ["music_menu", "music_campus", "amb_day", "amb_night", "amb_space", "launch_rumble", "amb_fair_day",
	"amb_fair_night", "music_fair", "sim_loop"]
## the sounds of the fair, the flight comic, the album, the launch watch and the checklists
const FEATURE_SOUNDS := ["amb_fair_day", "amb_fair_night", "music_fair", "fair_step", "fair_talk_chime", "fair_fanfare",
	"fair_applause", "comic_page", "comic_pop", "comic_vroom", "comic_clac", "comic_boom", "comic_whoosh", "comic_splash",
	"comic_end_good", "comic_end_meh", "comic_end_bad", "photo_shutter", "photo_develop", "photo_flip", "photo_pin",
	"warp_up", "warp_down", "sim_loop", "check_tick", "chip_tick"]

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
	await _helpers()
	await _fair()
	await _comic()
	await _watch()
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


# ------------------------------------------------------------------ newer features
func _helpers() -> void:
	print("held loops, runs, tallies")
	var lib := load(LIB) as CwSoundLibrary
	var missing: PackedStringArray = []
	for n: String in FEATURE_SOUNDS:
		if not lib.has(n):
			missing.append(n)
	_check(missing.is_empty(), "the library has the features' sounds %s" % ("" if missing.is_empty() else str(missing)))
	_check(lib.find(&"fair_fanfare").bus == &"Music" and lib.find(&"comic_end_good").bus == &"Music",
		"the jingles (fanfare, comic stings) are on the Music bus")
	_check(lib.find(&"fair_step").bus == &"SFX" and lib.find(&"amb_fair_day").bus == &"Ambience"
		and lib.find(&"check_tick").bus == &"UI", "steps on SFX, the fair's bed on Ambience, ticks on UI")
	var sfx := CwSfx.get_instance()
	var n := CwSfx.count(&"sim_loop")
	CwSfx.loop(&"sim_loop", &"t")
	CwSfx.loop(&"sim_loop", &"t")
	_check(CwSfx.looping(&"t") and CwSfx.count(&"sim_loop") == n + 1, "a held loop starts once under its key")
	CwSfx.end_loop(&"t")
	_check(not CwSfx.looping(&"t"), "end_loop lets it go")
	await _wait(sfx.loop_fade + 0.15)
	_check(not sfx._held.has(&"t"), "...and it is gone after its fade")
	var c := CwSfx.count(&"chip_tick")
	CwSfx.run(&"chip_tick", 3, 0.03, 0.05)
	await _wait(0.2)
	_check(CwSfx.count(&"chip_tick") == c + 3, "a run plays every step (%d)" % (CwSfx.count(&"chip_tick") - c))
	await _wait(0.1)
	_check(CwSfx.tally("test:cml", 2, &"check_tick") == 0, "a tally's first look is silent")
	_check(CwSfx.tally("test:cml", 2, &"check_tick") == 0, "the same count is silent")
	_check(CwSfx.tally("test:cml", 4, &"check_tick") == 2, "two items gained: two ticks")
	_check(CwSfx.tally("test:cml", 3, &"check_tick") == 0, "a lost item is silent")
	await _wait(0.3)


func _fair() -> void:
	print("the conference fair")
	var main := (load("res://scenes/tycoon/tycoon_main.tscn") as PackedScene).instantiate() as TycoonMain
	main.cutscenes = false
	root.add_child(main)
	await _frames(4)
	main.race_flow.autosave = false
	if main.tutorial:
		main.tutorial.set_process(false)
	if main.hud.current_screen() != "":
		main.hud.close_screen()
	main.state.tutorials = {"seen": {"campus": true}}
	main.state.race.pending_pages.clear()
	await _frames(2)
	_check(main.conference.dev_open(), "the fair opens")
	await _frames(3)
	var fair := main.conference.fair
	var snd := fair.get_node_or_null("ConferenceAudio") as ConferenceAudio if fair else null
	_check(snd != null, "the fair has its sound (ConferenceAudio)")
	if snd == null:
		main.conference.leave()
		main.queue_free()
		await _frames(2)
		return
	_check(CwSfx.get_instance().current_music() == &"music_fair", "the fair's band takes over the music")
	_check(snd.day_bed != null and snd.night_bed != null and snd.day_bed.bus == &"Ambience", "the fair's beds are up")
	_check(is_equal_approx(snd.day_bed.mix * snd.day_bed.mix + snd.night_bed.mix * snd.night_bed.mix, 1.0),
		"day and night beds share the mix (night %.2f)" % snd.night)
	# a stroll: the leader walks a few metres, the steps follow
	var steps := snd.steps
	for i in 14:
		fair.player.position += fair.player.forward() * 0.35
		await process_frame
	_check(snd.steps > steps, "walking makes footsteps (%d)" % (snd.steps - steps))
	var still := snd.steps
	await _frames(6)
	_check(snd.steps == still, "standing still is quiet")
	# someone to talk to comes into range
	var chime := CwSfx.count(&"fair_talk_chime")
	var e: Dictionary = fair.npcs[0]
	fair.player.position = (e["node"] as Node3D).position + Vector3(0, 0, 1.0)
	await _frames(3)
	_check(fair.focus.has("npc") and CwSfx.count(&"fair_talk_chime") == chime + 1, "a Lenda in reach chimes")
	await _frames(3)
	_check(CwSfx.count(&"fair_talk_chime") == chime + 1, "...once while it stays the one in reach")
	# the award
	var ap := fair.get_node("Ceremony/Approach") as Node3D
	fair.player.position = fair.to_local(ap.global_position)
	await _frames(3)
	CwSfx.get_instance().stop_stinger()
	await _wait(1.1)   # past the fanfare's cooldown
	var fan := CwSfx.count(&"fair_fanfare")
	_check(fair.interact(), "the ceremony starts")
	await _frames(2)
	_check(CwSfx.count(&"fair_fanfare") == fan + 1, "the fanfare plays as the host takes the stage")
	var winner := String(fair.ceremony["rec"]["winner"])
	var clap := CwSfx.count(&"fair_applause")
	var pops := CwSfx.count(&"confetti_pop")
	main.talk.choose(0)
	await _frames(3)
	await _wait(0.4)
	if winner != "":
		_check(CwSfx.count(&"fair_applause") == clap + 1 and CwSfx.count(&"confetti_pop") >= pops + 3,
			"the winner named: applause and confetti pops")
	else:
		print("    (no winner this time)")
	main.talk.close()
	await _frames(2)
	# a staged win for us (the campaign decides the real one once): the driver hears the moment
	await _wait(1.1)
	clap = CwSfx.count(&"fair_applause")
	pops = CwSfx.count(&"confetti_pop")
	var cheer := CwSfx.count(&"crowd_cheer")
	fair.ceremony = {"rec": {"winner": RaceDirector.PLAYER}, "confetti": false}
	await _frames(2)
	fair.ceremony["confetti"] = true
	await _frames(2)
	await _wait(0.4)
	_check(CwSfx.count(&"fair_applause") == clap + 1 and CwSfx.count(&"confetti_pop") >= pops + 3
		and CwSfx.count(&"crowd_cheer") == cheer + 1, "our award: applause, confetti pops and a cheer")
	fair.ceremony = {}
	await _frames(2)
	main.conference.leave()
	await _frames(3)
	_check(CwSfx.get_instance().current_music() == &"music_campus", "leaving brings the campus loop back")
	main.queue_free()
	await _frames(3)


func _comic() -> void:
	print("the flight comic")
	var c := (load("res://scenes/tycoon/ui/screens/flight_comic.tscn") as PackedScene).instantiate() as FlightComic
	root.add_child(c)
	await _frames(2)
	var snd := c.get_node_or_null("ComicAudio") as FlightComicAudio
	_check(snd != null, "the comic has its sound (FlightComicAudio)")
	if snd == null:
		c.free()
		return
	var events := [{"kind": "liftoff", "met": 0.0, "alt": 0.0}, {"kind": "stage_sep", "met": 140.0, "alt": 60000.0},
		{"kind": "orbit", "met": 560.0, "alt": 200000.0}]
	c.show_flight(null, {}, events, {}, {"embedded": true, "target": "leo", "code": "ORB-01", "outcome": "full"})
	await _frames(3)
	for i in 8:
		if bool(c.get("_on_report")):
			break   # one more would close it (an embedded comic frees itself)
		c.advance()
		await _frames(2)
		await _wait(0.12)
	var heard := snd.heard
	print("    ", heard)
	_check(heard.count("pop") >= 3, "each panel pops in (%d)" % heard.count("pop"))
	_check(heard.has("word:comic_vroom") and heard.has("word:comic_clac") and heard.has("word:comic_whoosh"),
		"each sound-effect word has its sound (VRUUUM, CLAC, the orbit)")
	_check(heard.has("end:good"), "a good flight ends on the good sting")
	_check(heard.count("page") >= 1, "the page turns to the report")
	c.queue_free()
	await _frames(2)
	# a lost flight ends softly
	var c2 := (load("res://scenes/tycoon/ui/screens/flight_comic.tscn") as PackedScene).instantiate() as FlightComic
	root.add_child(c2)
	await _frames(2)
	c2.show_flight(null, {}, [{"kind": "liftoff", "met": 0.0}, {"kind": "crash", "met": 40.0, "alt": 8000.0}],
		{"lost": true}, {"embedded": true, "target": "leo", "code": "ORB-03", "outcome": "fail"})
	await _frames(2)
	c2.show_report()
	await _frames(2)
	var s2 := c2.get_node("ComicAudio") as FlightComicAudio
	_check(s2.heard.has("end:bad"), "a lost flight ends on the gentle 'aww' (%s)" % str(s2.heard))
	c2.queue_free()
	await _frames(2)


func _watch() -> void:
	print("the launch watch")
	var w := (load("res://scenes/tycoon/tracking/launch_watch_overlay.tscn") as PackedScene).instantiate() as LaunchWatch
	root.add_child(w)
	await _frames(2)
	var snd := w.get_node_or_null("WatchAudio") as LaunchWatchAudio
	_check(snd != null, "the watch has its sound (LaunchWatchAudio)")
	_check(String(w.get_node("%Speed").get_meta("cw_sfx_press", "x")) == "", "the speed key's own click gives way to the whoosh")
	w.queue_free()
	await _frames(2)
	_check(not CwSfx.looping(LaunchWatchAudio.LOOP_KEY), "no simulate loop is left behind")


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
