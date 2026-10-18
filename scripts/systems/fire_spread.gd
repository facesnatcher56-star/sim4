class_name FireSpread
extends RefCounted
## How fires live: grow with age (stage 1 small .. 3 raging), may be stopped by a sprinkler, spread to flammable neighbours every few minutes
## (walls stop it, open doors do not) and finally burn their object away (value lost, burnt remains left behind). Smoke builds up per lot.

static func step_all(now: int) -> void:
	for f in Fire.active():
		if Fire.fires.has(int(f["id"])):
			_step_one(Fire.fires[int(f["id"])], now)
	_smoke()

static func _step_one(f: Dictionary, now: int) -> void:
	f["age"] = float(f["age"]) + 1.0
	var sa: Array = FireRules.cfg().get("stage_age", [4, 10])
	var st: int = 1 if float(f["age"]) < float(sa[0]) else (2 if float(f["age"]) < float(sa[1]) else 3)
	f["stage"] = maxi(int(f["stage"]), st)
	var id: int = int(f["id"])
	if int(f["obj"]) >= 0 and WorldIface.get_object(int(f["obj"])) == null:
		Fire.end_fire(id, "out", "self")
		return
	if FireRules.sprinkler_near(f["tile"], str(f["lot"])):
		var p: float = FireRules.num("sprinkler_stop", 0.28) if int(f["stage"]) < 3 else FireRules.num("sprinkler_stop_stage3", 0.1)
		if Fire.rng.randf() < p:
			Fire.end_fire(id, "out", "sprinkler")
			return
	if float(f["age"]) >= float(f["burn"]):
		_consume(f)
		return
	if now >= int(f["next_spread"]):
		f["next_spread"] = now + int(round(FireRules.num("spread_min", 4.0) * Fire.rng.randf_range(0.75, 1.25)))
		_spread(f)

# ------------------------------------------------------------------ spread
static func _neighbors(f: Dictionary) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var r: int = 2 if int(f["stage"]) >= 3 else 1
	var own: Array = f["tiles"]
	for t in own:
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var n: Vector2i = t + Vector2i(dx, dy)
				if n == t or own.has(n) or seen.has(n):
					continue
				if maxi(absi(dx), absi(dy)) == 1:
					if not FireRules.edge_open(t, n):
						continue
				else:
					var mid: Vector2i = t + Vector2i(signi(dx), signi(dy))
					if not FireRules.edge_open(t, mid) or not FireRules.edge_open(mid, n):
						continue
				seen[n] = true
				if not Fire.fire_at(n).is_empty():
					continue
				var o = FireRules.object_at(n)
				var flam: float = FireRules.flammability(o, n)
				if flam <= 0.0:
					continue
				if o != null:
					if seen.has(-int(o.id) - 10):
						continue
					seen[-int(o.id) - 10] = true
				out.append({"tile": n if o == null else o.tile, "obj": o, "flam": flam})
	return out

static func _spread(f: Dictionary) -> void:
	var cands: Array = _neighbors(f)
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return float(a["flam"]) > float(b["flam"]) or (float(a["flam"]) == float(b["flam"]) and a["tile"].x + a["tile"].y * 1000 < b["tile"].x + b["tile"].y * 1000))
	var mult: float = FireRules.at("stage_mult", int(f["stage"]) - 1, 1.0)
	if FireRules.sprinkler_near(f["tile"], str(f["lot"])):
		mult *= FireRules.num("sprinkler_spread_mult", 0.3)
	var budget: int = 2 if int(f["stage"]) >= 3 else 1
	for c in cands:
		if budget <= 0:
			break
		var p: float = clampf(FireRules.num("spread_chance", 0.55) * mult * (0.4 + float(c["flam"])), 0.0, 0.95)
		if Fire.rng.randf() >= p:
			continue
		var target = c["obj"] if c["obj"] != null else c["tile"]
		if Fire.ignite(target, str(f["source"]), {"culprit": int(f["culprit"]), "quiet": true}):
			budget -= 1
			var b: Dictionary = Fire.blazes.get(str(f["lot"]), {})
			if not b.is_empty():
				if not bool(b["spread"]):
					b["spread"] = true
					Fire._stat("spread_blazes")
				Fire._stat("spread_events")
				b["peak"] = maxi(int(b["peak"]), Fire.fires_in(str(f["lot"])).size())

# ------------------------------------------------------------------ burning down / survivors
## The object burns away: gone, its price counted as lost, burnt remains (and a scorch mark) in its place.
static func _consume(f: Dictionary) -> void:
	var o = WorldIface.get_object(int(f["obj"])) if int(f["obj"]) >= 0 else null
	var b: Dictionary = Fire.blazes.get(str(f["lot"]), {})
	if o != null:
		var label: String = str(FireRules.obj_def(o).get("label", o.def_id))
		var price: int = Economy.price_of_def(str(o.def_id))
		var tile: Vector2i = o.tile
		var w = WorldIface.world()
		var oid: int = int(o.id)
		if w != null and w.has_method("remove_object"):
			w.remove_object(oid)
		Economy.on_object_removed(oid)
		if not b.is_empty():
			b["loss"] = int(b["loss"]) + price
			(b["lost"] as Array).append(label)
		Fire._stat("destroyed")
		Fire._stat("loss", price)
		_ash(tile)
	Fire.end_fire(int(f["id"]), "burnt")

static func _ash(tile: Vector2i) -> void:
	var w = WorldIface.world()
	if w == null or not w.has_method("place_object"):
		return
	if w.has_method("can_place") and not w.can_place("ash_pile", tile, 0):
		return
	w.place_object("ash_pile", tile, 0)

## A fire put out in time: the object lives but is scorched; if it had burned a while it is broken (repair it).
static func damage_survivor(f: Dictionary) -> void:
	if int(f["obj"]) < 0 or float(f["age"]) < 0.5 * float(f["burn"]):
		return
	var o = WorldIface.get_object(int(f["obj"]))
	if o != null and (FireRules.obj_def(o).get("state", {}) as Dictionary).has("broken"):
		WorldIface.state_set(o, "broken", true)

# ------------------------------------------------------------------ smoke
static func _smoke() -> void:
	for lot in Fire.blazes:
		FireSmoke.step(Fire.blazes[lot], Fire.fires_in(str(lot)))
