class_name UIPrefs
extends RefCounted
## Tiny per-machine UI flags (user://ui_prefs.cfg): first-run tips seen, etc. Never part of a save game.
static var PATH := "user://ui_prefs.cfg"      # static var so the test runners can point it at a private folder (TestFixture.isolate_user_files)

static func get_flag(key: String, default: bool = false) -> bool:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return default
	return bool(cf.get_value("ui", key, default))

static func set_flag(key: String, value: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)
	cf.set_value("ui", key, value)
	cf.save(PATH)
