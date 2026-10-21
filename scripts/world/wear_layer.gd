class_name WearLayer
extends RefCounted
## Task 41a (view only; reads sim state, never writes it, no rng): how worn / poor each lot looks right now.
##   poverty_at(tile)   0..1 wealth score of the lot at a tile (1 = broke): the player's lot from its household's funds, any lot from its district's wear level
##   lot_wear(lot_id)   0..1 exterior wear of a lot: its district's declared level (data/district_dressing.json), the poverty of its household, an override
## Hooks for later (a rough block that gentrifies or declines): `set_district_wear(id, level)` changes a district at run time; `set_lot_override` forces a lot
## (look-test shots, tests). Every change emits `bus.changed(lot_id)` and LotView / WearView refresh what depends on it. Reset with `reset()`.

class Bus extends RefCounted:
	signal changed(lot_id: String)

static var bus := Bus.new()
static var _lot_over: Dictionary = {}          # lot id -> {poverty, wear} forced values
static var _district_over: Dictionary = {}     # district id -> wear level set at run time
static var _cache: Dictionary = {}             # lot id -> {poverty, wear}


static func reset() -> void:
	_lot_over.clear()
	_district_over.clear()
	_cache.clear()


static func set_lot_override(lot_id: String, poverty: float, wear: float = -1.0) -> void:
	_lot_over[lot_id] = {"poverty": poverty, "wear": poverty if wear < 0.0 else wear}
	invalidate(lot_id)


static func clear_lot_override(lot_id: String) -> void:
	_lot_over.erase(lot_id)
	invalidate(lot_id)


## The hook: a district's wear level 0..1 (a run-time value wins over the data).
static func set_district_wear(district_id: String, level: float) -> void:
	_district_over[district_id] = clampf(level, 0.0, 1.0)
	for d in WearRules.dressing_cfg().get("districts", []):
		if str(d.get("id", "")) == district_id:
			for l in (d.get("lots", []) as Array):
				invalidate(str(l))


static func district_wear(district_id: String) -> float:
	if _district_over.has(district_id):
		return float(_district_over[district_id])
	for d in WearRules.dressing_cfg().get("districts", []):
		if str(d.get("id", "")) == district_id:
			return float(d["wear"]) if d.has("wear") else float(WearRules.preset(str(d.get("preset", ""))).get("wear", 0.0))
	return 0.0


static func invalidate(lot_id: String = "") -> void:
	if lot_id == "":
		_cache.clear()
	else:
		_cache.erase(lot_id)
	bus.changed.emit(lot_id)


## Drops a lot's cached score without telling listeners (the caller compares and decides).
static func invalidate_quiet(lot_id: String) -> void:
	_cache.erase(lot_id)


## Districts that declare a wear level: [{id, lots, wear, preset}].
static func districts() -> Array:
	var out: Array = []
	for d in WearRules.dressing_cfg().get("districts", []):
		var e: Dictionary = (d as Dictionary).duplicate()
		e["wear"] = district_wear(str(d.get("id", "")))
		out.append(e)
	return out


static func _district_of_lot(lot_id: String) -> float:
	for d in WearRules.dressing_cfg().get("districts", []):
		if lot_id in (d.get("lots", []) as Array):
			return district_wear(str(d.get("id", "")))
	return -1.0


static func _funds_poverty(lot_id: String) -> float:
	if lot_id != Neighborhood.HOME:
		return 0.0
	return WearRules.poverty_score(Economy.balance(World.current_household_id))


static func _entry(lot_id: String) -> Dictionary:
	if _lot_over.has(lot_id):
		return _lot_over[lot_id]
	if _cache.has(lot_id):
		return _cache[lot_id]
	var dw := _district_of_lot(lot_id)
	var floor_p := float((WearRules.cfg().get("poverty", {}) as Dictionary).get("district_floor", 0.9))
	var pov := maxf(_funds_poverty(lot_id), maxf(dw, 0.0) * floor_p)
	var e := {"poverty": pov, "wear": maxf(dw, pov * float((WearRules.cfg().get("wall", {}) as Dictionary).get("poverty_weight", 0.8)))}
	_cache[lot_id] = e
	return e


static func lot_poverty(lot_id: String) -> float:
	return float(_entry(lot_id)["poverty"])


static func lot_wear(lot_id: String) -> float:
	return float(_entry(lot_id)["wear"])


static func poverty_at(tile: Vector2i) -> float:
	var lot := NeighborhoodLots.lot_at(tile)
	return lot_poverty(lot) if lot != "" else 0.0


static func wear_at(tile: Vector2i) -> float:
	var lot := NeighborhoodLots.lot_at(tile)
	return lot_wear(lot) if lot != "" else 0.0
