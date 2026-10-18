class_name DestDefs
extends RefCounted
## The holiday MAPS (task 22): data/destinations/<id>.json = {id, template} where template is the lot template format of LotLoader
## (floors, walls, objects, spawn, entry, optional `levels` for the ship, plus `cabins` / `posts` / `lobby` for the ship).
## Loaded lazily; the templates are NOT added to data/lot_templates.json, DestLoader injects them into LotLoader only while it places one.
##
##   DestDefs.ids() / map(id) / has_map(id)
##   DestDefs.config() / zone_config()      data/vacation.json "config" and its "zones" block

const DIR := "res://data/destinations"

static var _maps: Dictionary = {}
static var _loaded: bool = false

static func reset() -> void:
	_maps.clear()
	_loaded = false

static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(f)))
		if parsed is Dictionary and (parsed as Dictionary).has("template"):
			_maps[str(parsed.get("id", f.get_basename()))] = parsed["template"]

static func ids() -> Array:
	_ensure()
	var out: Array = _maps.keys()
	out.sort()
	return out

static func has_map(id: String) -> bool:
	_ensure()
	return _maps.has(id)

static func map(id: String) -> Dictionary:
	_ensure()
	return _maps.get(id, {})

static func config() -> Dictionary:
	return (SysUtil.table("vacation").get("config", {}) as Dictionary)

static func zone_config() -> Dictionary:
	return (config().get("zones", {}) as Dictionary)
