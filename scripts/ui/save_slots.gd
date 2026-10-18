class_name SaveSlots
extends RefCounted
## Thin, replaceable save/load layer: user://saves/slot<N>.json
const DIR := "user://saves"
const SLOTS := 3

static func path(slot: int) -> String:
	return "%s/slot%d.json" % [DIR, slot]

static func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(path(slot))

static func has_any() -> bool:
	for i in range(1, SLOTS + 1):
		if has_slot(i):
			return true
	return false

static func slot_summary(slot: int) -> String:
	if not has_slot(slot):
		return "Empty"
	var d = read(slot)
	if d.is_empty():
		return "Corrupt"
	return SaveLoad.summary(slot)

static func read(slot: int) -> Dictionary:
	var f := FileAccess.open(path(slot), FileAccess.READ)
	if f == null:
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

static func capture(household_name: String = "Household") -> Dictionary:
	var folk: Array = []
	for f in World.all_folk():
		folk.append(f.to_dict())
	var d := {"version": 1, "household_name": household_name, "world": World.save_dict(true), "folk": folk, "day": UIU.day_number(),
		"colors": UIU.folk_colors.duplicate()}
	d["colors"] = {}
	for k in UIU.folk_colors:
		d["colors"][str(k)] = (UIU.folk_colors[k] as Color).to_html(false)
	d["clock_total"] = Clock.get("total_minutes")
	return d

## Delegates to the systems SaveLoad (v2 format) and keeps the HUD-only folk colours as an extra key.
static func save(slot: int, household_name: String = "Household") -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	if not SaveLoad.save(slot, household_name):
		return false
	var d := read(slot)
	d["colors"] = capture(household_name)["colors"]
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	return true

static func load_slot(slot: int) -> bool:
	if not SaveLoad.load(slot):
		return false
	var d := read(slot)
	UIU.folk_colors.clear()
	for k in d.get("colors", {}):
		UIU.folk_colors[int(k)] = Color(str(d["colors"][k]))
	return true

static func apply(d: Dictionary) -> void:
	World.load_dict(d.get("world", {}))
	if World.all_folk().is_empty():
		var fc = UIU.cls("Folk")
		for fd in d.get("folk", []):
			var f = fc.call("from_dict", fd)
			World.add_folk(f, f.tile)
	UIU.folk_colors.clear()
	for k in d.get("colors", {}):
		UIU.folk_colors[int(k)] = Color(str(d["colors"][k]))
	if Clock.has_method("reset") and d.has("clock_total"):
		Clock.call("reset", int(d["clock_total"]))
