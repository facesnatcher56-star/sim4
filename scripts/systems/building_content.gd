class_name BuildingContent
extends RefCounted
## Objects and interactions of the multi-floor buildings (data/building_rules.json "content": hospital beds, cell bunks, pews, ...).
## Installed into the shared Data tables and the live World defs like NeighborhoodContent (idempotent). LotLoader.place calls it first, so
## any template that uses these objects can be placed on any world.

const MARK := "_building_content"
const PATH := "res://data/building_rules.json"
static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = (p as Dictionary).get("content", {}) if p is Dictionary else {}
	return _cfg


static func install() -> void:
	ContentMerge.install(cfg(), MARK, {"_sys_gate": true})
