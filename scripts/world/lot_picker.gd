class_name LotPicker
extends RefCounted
## Which template every lot of a new game gets: drawn WITHOUT replacement from the generated pools, seeded by the world seed,
## so no two lots share a layout and the same seed gives the same map. The result goes into the regions (saved), so a loaded
## game never re-rolls.
##   LotPicker.home_pool(start_id)            templates the player can get for that start ("classic" adds the hand-made house)
##   LotPicker.home_for(start_id, seed, avoid) one home template of the pool (not `avoid`)
##   LotPicker.pick(seed, start_id, home)     {lot_id: template_id} for all lots (home = `home` or a seeded pool pick)
##   LotPicker.signature(tid)                 HouseSignature layout signature (tests: pairwise distinct)

static func home_pool(start_id: String) -> Array:
	var kind := str(Neighborhood.start_def(start_id).get("pool", start_id))
	var out: Array = HouseGenerator.pool(kind)
	if kind == "classic":
		out.push_front(LotLoader.CLASSIC)
	return out

## Pool of a lot: its own pool kind (townie homes: same footprint class), its default template, and its venue alternates.
static func lot_pool(lot: Dictionary) -> Array:
	var out: Array = []
	var tpl := str(lot.get("template", ""))
	if tpl != "":
		out.append(tpl)
	if str(lot.get("pool", "")) != "":
		out.append_array(HouseGenerator.pool(str(lot["pool"])))
	if str(lot.get("type", "")) != "townie_home":
		for id in HouseGenerator.pool(str(lot.get("type", ""))):
			if not out.has(id):
				out.append(id)
	return out

static func _rng(seed_value: int, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, salt])
	return r

static func _draw(pool: Array, taken: Dictionary, r: RandomNumberGenerator) -> String:
	var free: Array = []
	for id in pool:
		if not taken.has(id):
			free.append(id)
	if free.is_empty():
		free = pool
	return "" if free.is_empty() else str(free[r.randi() % free.size()])

static func home_for(start_id: String, seed_value: int, avoid: String = "") -> String:
	return _draw(home_pool(start_id), {avoid: true}, _rng(seed_value, 1))

static func pick(seed_value: int, start_id: String, home: String = "") -> Dictionary:
	var out: Dictionary = {}
	var taken: Dictionary = {}
	if home == "":
		home = home_for(start_id, seed_value)
	out[Neighborhood.HOME] = home
	taken[home] = true
	var salt := 10
	for l in Neighborhood.lots():
		var lid := str(l["id"])
		if lid == Neighborhood.HOME:
			continue
		salt += 1
		var t := _draw(lot_pool(l), taken, _rng(seed_value, salt))
		if t == "":
			t = str(l.get("template", ""))
		out[lid] = t
		taken[t] = true
	return out

static func signature(tid: String) -> String:
	if tid == LotLoader.CLASSIC:
		return "classic"
	return str(HouseSignature.layout_sig(LotLoader.template(tid)))
