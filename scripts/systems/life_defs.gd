class_name LifeDefs
extends RefCounted
## Loads the data of the life areas (task 14): every data/life/*.json in file-name order (10_education, 20_health, 30_food, 40_culture ...).
## Each file has named SECTIONS (places, majors, courses, conditions, ...). A section is a dictionary merged by id (later files win per key),
## `config` is merged key by key. Nothing here knows any content: a new place or course is a new entry in a data file.
##   LifeDefs.section("places") -> Dictionary    LifeDefs.cfg("education") -> Dictionary    LifeDefs.get_in("places", "clinic") -> Dictionary

const DIR := "res://data/life"

static var _loaded: bool = false
static var sections: Dictionary = {}
static var config: Dictionary = {}

static func reset() -> void:
	_loaded = false
	sections = {}
	config = {}

static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var data = SimEnv.data()
	var d := DirAccess.open(DIR)
	if d == null:
		return
	var names: Array = []
	for f in d.get_files():
		if f.ends_with(".json") and not f.begins_with("_"):
			names.append(f)
	names.sort()
	for n in names:
		var parsed: Variant = data.load_file(DIR.path_join(n))
		if parsed is Dictionary:
			_merge(parsed)

static func _merge(d: Dictionary) -> void:
	for k in d:
		var v: Variant = d[k]
		if k == "config" and v is Dictionary:
			for ck in v:
				if v[ck] is Dictionary and config.get(ck) is Dictionary:
					(config[ck] as Dictionary).merge(v[ck], true)
				else:
					config[ck] = v[ck]
		elif v is Dictionary and not str(k).begins_with("_"):
			if not sections.has(k):
				sections[k] = {}
			for id in v:
				if (sections[k] as Dictionary).has(id) and v[id] is Dictionary:
					(sections[k][id] as Dictionary).merge(v[id], true)
				else:
					sections[k][id] = v[id]

static func section(name: String) -> Dictionary:
	ensure()
	return sections.get(name, {})

static func cfg(name: String) -> Dictionary:
	ensure()
	return config.get(name, {})

static func get_in(name: String, id: String) -> Dictionary:
	return section(name).get(id, {})
