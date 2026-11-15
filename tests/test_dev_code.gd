extends SceneTree
## The dev code in Options › Acesso: a release build has no dev menu until the right code is
## typed; a wrong code does nothing; the unlock is saved in user://settings.cfg [dev].

var failures := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var cfg := ConfigFile.new()
	var had := cfg.load(CwDevMenu.UNLOCK_CFG) == OK
	var before: Variant = cfg.get_value("dev", "unlocked", null) if had else null
	if had and cfg.has_section_key("dev", "unlocked"):
		cfg.erase_section_key("dev", "unlocked")
		cfg.save(CwDevMenu.UNLOCK_CFG)
	CwDevMenu.simulate_release = true
	_check(not CwDevMenu.enabled(), "a release build starts with no dev menu")
	_check(not CwDevMenu.try_code("senha errada"), "a wrong code is refused")
	_check(not CwDevMenu.enabled(), "still locked after a wrong code")
	_check(CwDevMenu.try_code("  CometLings2026 "), "the right code works (case and spaces ignored)")
	_check(CwDevMenu.enabled(), "the dev menu is available after the code")
	_check(CwDevMenu.unlocked(), "the unlock is saved")
	var dev := root.get_node_or_null("CwDev")
	_check(dev != null and dev.get_meta("set_up", false), "the dev menu node is set up after unlocking")
	# put the settings back as they were
	cfg = ConfigFile.new()
	cfg.load(CwDevMenu.UNLOCK_CFG)
	if before == null:
		if cfg.has_section_key("dev", "unlocked"):
			cfg.erase_section_key("dev", "unlocked")
	else:
		cfg.set_value("dev", "unlocked", before)
	cfg.save(CwDevMenu.UNLOCK_CFG)
	CwDevMenu.simulate_release = false
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(1 if failures else 0)
