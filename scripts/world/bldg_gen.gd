class_name BuildingGen
extends RefCounted
## Multi-floor buildings (task 10 part B): houses of 1-3 floors with an optional basement, apartment blocks, office towers, a hospital,
## school, courthouse, police station and a parking garage. Same template schema as data/lot_templates.json plus a `levels` block
## (LotLevels) and objects with "level". Deterministic per spec seed; written to data/generated_buildings.json by tools/gen_buildings.gd.
##   BuildingGen.template("hospital_01") -> Dictionary      BuildingGen.ids() / pool("tower") -> ["tower_01", ...]
##   BuildingGen.make(spec, taken) -> {template, report}    BuildingGen.make_all(bump) -> {lots, reports, failed}
## Method per building: BldgFrame (axis, corridor, stair core) -> per level BldgLevel (cells -> rooms -> walls, doors, furniture, windows)
## -> BldgExport (floors / walls / objects per level, stairs + lift from the core) -> uniqueness gate (HouseSignature incl. upper floors).

const SPECS_PATH := "res://data/building_specs.json"
const RULES_PATH := "res://data/building_rules.json"
const GENERATED_PATH := "res://data/generated_buildings.json"
const MAX_TRIES := 300

static var _specs: Dictionary = {}
static var _rules: Dictionary = {}
static var _generated: Dictionary = {}
static var _loaded: bool = false


static func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return p if p is Dictionary else {}


static func specs() -> Dictionary:
	if _specs.is_empty():
		_specs = _load(SPECS_PATH)
	return _specs


## House rules + venue rooms + the building rooms (data/building_rules.json).
static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = HouseGenerator.rules().duplicate(true)
		(_rules["rooms"] as Dictionary).merge(HouseGenerator.specs().get("venue_rooms", {}), true)
		(_rules["rooms"] as Dictionary).merge(_load(RULES_PATH).get("rooms", {}), true)
	return _rules


static func reload() -> void:
	_specs = {}
	_rules = {}
	_generated = {}
	_loaded = false


static func lots() -> Dictionary:
	if not _loaded:
		_generated = _load(GENERATED_PATH).get("lots", {})
		_loaded = true
	return _generated


static func template(id: String) -> Dictionary:
	return lots().get(id, {})


static func ids() -> Array:
	var out: Array = lots().keys()
	out.sort()
	return out


## Ids of one kind, sorted: pool("tower") -> [tower_01, tower_02].
static func pool(kind: String) -> Array:
	var out: Array = []
	for id in lots():
		if str(id).begins_with(kind + "_"):
			out.append(str(id))
	out.sort()
	return out


## Ids of the buildings of one venue type ("office" -> the towers), sorted.
static func venue_pool(venue: String) -> Array:
	var out: Array = []
	for id in lots():
		if str(lots()[id].get("venue", "")) == venue:
			out.append(str(id))
	out.sort()
	return out


## Level keys of a spec ("0", "1-5", "-1") -> {level: level spec}.
static func level_specs(spec: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var lv: Dictionary = spec["levels"]
	for key in lv:
		var k := str(key)
		var cut := k.find("-", 1)
		if cut > 0:
			for l in range(int(k.substr(0, cut)), int(k.substr(cut + 1)) + 1):
				out[l] = lv[key]
		else:
			out[int(k)] = lv[key]
	return out


## Try sub-seeds until every level builds and the signatures are not in `taken`.
static func make(spec: Dictionary, taken: Dictionary = {}) -> Dictionary:
	var rl := rules()
	var why: Dictionary = {}
	var lvs := level_specs(spec)
	var bottom := 0
	var top := 0
	for l in lvs:
		bottom = mini(bottom, int(l))
		top = maxi(top, int(l))
	var sh: Array = spec.get("shell", [5, 4, 22, 14])
	var shell := Rect2i(int(sh[0]), int(sh[1]), int(sh[2]), int(sh[3]))
	var flip := str(spec.get("flip", ""))
	var fr := BldgFrame.new(shell, str(spec.get("axis", "ew")), flip.contains("u"), flip.contains("v"), int(spec.get("da", 5)), bool(spec.get("lift", true)))
	for attempt in MAX_TRIES:
		var plans: Dictionary = {}
		var units: Array = []
		var bad := ""
		for l in range(bottom, top + 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = int(spec["seed"]) * 7919 + attempt * 104729 + (l + 50) * 31
			var r := BldgLevel.build(spec, l, lvs.get(l, {}), fr, rl, rng)
			if r.has("fail"):
				bad = str(r["fail"])
				break
			plans[l] = r
			for u in r["units"]:
				var ud: Dictionary = (u as Dictionary).duplicate()
				ud["level"] = l
				units.append(ud)
		if bad != "":
			var k := bad.substr(0, 40)
			why[k] = int(why.get(k, 0)) + 1
			continue
		var t := BldgExport.template(spec, fr, plans, units, lvs, bottom, top, rl)
		var ls := HouseSignature.layout_sig(t)
		if taken.has(ls):
			why["duplicate"] = int(why.get("duplicate", 0)) + 1
			continue
		return {"template": t, "report": {"tries": attempt + 1, "layout_sig": ls, "levels": top - bottom + 1, "objects": (t["objects"] as Array).size(), "units": units.size()}}
	return {"report": {"failed": true, "rejected": why}}


## Signatures of every home / venue that already exists (hand-made + generated), the starting point of the uniqueness registry.
static func taken_registry() -> Dictionary:
	var taken: Dictionary = {}
	var legacy := HouseSignature.legacy_templates()
	for id in legacy:
		taken[HouseSignature.layout_sig(legacy[id])] = id
	for id in HouseGenerator.lots():
		taken[HouseSignature.layout_sig(HouseGenerator.lots()[id])] = id
	return taken


## Every spec of data/building_specs.json. Returns {lots, reports, failed}; `taken` is shared with the house generator's registry.
static func make_all(bump: int = 0, taken: Dictionary = {}, only: PackedStringArray = PackedStringArray()) -> Dictionary:
	var lots_out: Dictionary = {}
	var reports: Dictionary = {}
	var failed: Array = []
	for sp in specs().get("buildings", []):
		var s: Dictionary = (sp as Dictionary).duplicate(true)
		if not only.is_empty() and str(s["id"]) not in only:
			continue
		s["seed"] = int(s["seed"]) + bump
		var r := make(s, taken)
		if not r.has("template"):
			failed.append(str(s["id"]))
			reports[str(s["id"])] = r["report"]
			continue
		lots_out[str(s["id"])] = r["template"]
		reports[str(s["id"])] = r["report"]
		taken[HouseSignature.layout_sig(r["template"])] = str(s["id"])
	return {"lots": lots_out, "reports": reports, "failed": failed}


static func write(lots_out: Dictionary, bump: int = 0) -> void:
	var ids_sorted: Array = lots_out.keys()
	ids_sorted.sort()
	var txt := '{\n"version": 1,\n"seed_bump": %d,\n"notes": "Generated by tools/gen_buildings.gd (BuildingGen). Multi-floor lot templates (a `levels` block); see docs/HOUSE_LAYOUTS.md.",\n"lots": {\n' % bump
	var rows: Array = []
	for id in ids_sorted:
		rows.append('"%s": %s' % [id, JSON.stringify(lots_out[id])])
	txt += ",\n".join(rows) + "\n}\n}\n"
	var f := FileAccess.open(GENERATED_PATH, FileAccess.WRITE)
	f.store_string(txt)
	f.close()
