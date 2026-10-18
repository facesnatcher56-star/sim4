extends Node
## Loads every data/*.json into `tables` (file base name -> Dictionary). Tolerant of missing files.

const DATA_DIR := "res://data"

var tables: Dictionary = {}

func _ready() -> void:
	load_all()

func load_all(dir: String = DATA_DIR) -> void:
	tables.clear()
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".json"):
			var parsed: Variant = load_file(dir.path_join(f))
			if parsed is Dictionary:
				tables[f.get_basename()] = parsed

## Returns parsed JSON or null (never errors out).
func load_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return null
	var txt := fa.get_as_text()
	var json := JSON.new()
	if json.parse(txt) != OK:
		push_warning("Data: JSON parse error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data

func get_table(name: String) -> Dictionary:
	return tables.get(name, {})

func get_entry(table: String, id: String) -> Dictionary:
	var t: Dictionary = tables.get(table, {})
	return t.get(id, {})

# Convenience accessors
func needs() -> Dictionary: return get_table("needs")
func buffs() -> Dictionary: return get_table("buffs")
func traits() -> Dictionary: return get_table("traits")
func interactions() -> Dictionary: return get_table("interactions")
func objects() -> Dictionary: return get_table("objects")
func routines() -> Dictionary: return get_table("routines")
func buff_def(id: String) -> Dictionary: return get_entry("buffs", id)
func trait_def(id: String) -> Dictionary: return get_entry("traits", id)
func interaction_def(id: String) -> Dictionary: return get_entry("interactions", id)
func object_def(id: String) -> Dictionary: return get_entry("objects", id)
