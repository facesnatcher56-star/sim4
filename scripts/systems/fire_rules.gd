class_name FireRules
extends RefCounted
## Fire data and lookups shared by the Fire* classes: config.fire (data/incidents/03_fire.json), flammability of objects and floors,
## the safety objects of a lot (smoke alarm, extinguisher, sprinkler), who is asleep / helpless, rooms, exits and object tooltips.
## Works on the real World and on the StubWorld of the tests (every World call is guarded).

static var _tip_cache: Dictionary = {}

static func reset() -> void:
	_tip_cache.clear()

static func cfg() -> Dictionary:
	return IncidentDefs.cfg("fire", {})

static func num(key: String, default: float) -> float:
	return float(cfg().get(key, default))

static func at(key: String, i: int, default: float) -> float:
	var a: Array = cfg().get(key, [])
	return float(a[clampi(i, 0, a.size() - 1)]) if not a.is_empty() else default

# ------------------------------------------------------------------ places
static func lot_of(tile: Vector2i) -> String:
	var l: String = NeighborhoodLots.lot_at(tile)
	return l if l != "" else "street"

static func hid_of_lot(lot: String) -> int:
	return Economy.primary_household() if lot == Neighborhood.HOME else 0

static func is_home(lot: String) -> bool:
	return lot == Neighborhood.HOME

static func place_name(lot: String) -> String:
	if lot == Neighborhood.HOME:
		return "your home"
	return "a house nearby" if lot != "street" else "the street"

static func _world():
	return WorldIface.world()

static func room_of(tile: Vector2i) -> int:
	var w = _world()
	if w != null and w.has_method("room_id"):
		return int(w.room_id(tile))
	return 0

## Same room (real World) or close enough (stub: no rooms).
static func same_room(a: Vector2i, b: Vector2i, level: int = 0) -> bool:
	var w = _world()
	if w != null and w.has_method("room_id"):
		var ra: int = int(w.room_id(a, level))
		return ra != -1 and ra == int(w.room_id(b, level))
	return absi(a.x - b.x) + absi(a.y - b.y) <= 6

static func edge_open(a: Vector2i, b: Vector2i, level: int = 0) -> bool:
	var w = _world()
	if w == null or not w.has_method("edge_open"):
		return true
	if a.x == b.x or a.y == b.y:
		return bool(w.edge_open(a, b, level))
	return (bool(w.edge_open(a, Vector2i(b.x, a.y), level)) and bool(w.edge_open(Vector2i(b.x, a.y), b, level))) or (bool(w.edge_open(a, Vector2i(a.x, b.y), level)) and bool(w.edge_open(Vector2i(a.x, b.y), b, level)))

static func dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

## Tile folk run to: out in the street in front of the lot (stub worlds: a few tiles away).
static func exit_tile(lot: String, from: Vector2i) -> Vector2i:
	var rc: Rect2i = NeighborhoodLots.rect_of(lot)
	if rc.size != Vector2i.ZERO:
		return NeighborhoodLots.street_tile(lot)
	return Vector2i(maxi(from.x - 9, 1), from.y)

## The exit of a blaze is fixed when first needed (saved as [x, y] in the blaze record).
static func blaze_exit(b: Dictionary, from: Vector2i) -> Vector2i:
	if not b.has("exit"):
		var first: Vector2i = from
		for f in Fire.fires_in(str(b["lot"])):
			first = f["tile"]
			break
		var t: Vector2i = exit_tile(str(b["lot"]), first)
		b["exit"] = [t.x, t.y]
	return Vector2i(int(b["exit"][0]), int(b["exit"][1]))

# ------------------------------------------------------------------ objects
static func obj_def(o) -> Dictionary:
	return SimEnv.data().object_def(str(o.def_id))

static func footprint(o) -> Array:
	if o.has_method("footprint"):
		return o.footprint()
	return [o.tile]

static func object_at(t: Vector2i, level: int = 0):
	var w = _world()
	if w != null and w.has_method("object_at"):
		var o = w.object_at(t, level)
		if o != null and not o.is_wall_mounted():
			return o
		return null
	for o2 in SysUtil.all_world_objects():
		if o2.tile == t:
			return o2
	return null

static func objects_in_lot(lot: String, def_ids: Array) -> Array:
	var out: Array = []
	for o in SysUtil.all_world_objects():
		if def_ids.has(str(o.def_id)) and lot_of(o.tile) == lot:
			out.append(o)
	return out

static func is_floor(o) -> bool:
	if o.has_method("is_floor_layer"):
		return o.is_floor_layer()
	return str(obj_def(o).get("layer", "")) == "floor"

static func is_electrical(o) -> bool:
	for t in cfg().get("electrical_tags", []):
		if (obj_def(o).get("tags", []) as Array).has(t):
			return true
	return false

# ------------------------------------------------------------------ flammability
static func flammability(o, tile: Vector2i = Vector2i(-1, -1)) -> float:
	if o == null:
		return floor_flammability(tile)
	if o.has_method("is_wall_mounted") and o.is_wall_mounted():
		return 0.0
	var ids: Dictionary = cfg().get("flam_ids", {})
	var did: String = str(o.def_id)
	if ids.has(did):
		return float(ids[did])
	var tags: Dictionary = cfg().get("flam_tags", {})
	var m: float = 0.0
	for t in obj_def(o).get("tags", []):
		m = maxf(m, float(tags.get(str(t), 0.0)))
	return m

static func floor_flammability(t: Vector2i, level: int = 0) -> float:
	if t.x < 0:
		return 0.0
	if int((Fire.scorch.get(Fire.key(t), {}) as Dictionary).get("lv", 0)) >= 2:
		return 0.0
	var w = _world()
	if w == null or not w.has_method("get_floor"):
		return 0.0
	return float((cfg().get("flam_floors", {}) as Dictionary).get(str(w.get_floor(t, level)), 0.0))

# ------------------------------------------------------------------ safety objects
static func working_alarm(lot: String) -> bool:
	for o in objects_in_lot(lot, ["smoke_alarm"]):
		if float(WorldIface.state_get(o, "battery", 0.0)) > 0.0 and not bool(WorldIface.state_get(o, "broken", false)):
			return true
	return false

static func sprinkler_near(tile: Vector2i, lot: String) -> bool:
	var r: int = int(num("sprinkler_radius", 7))
	for o in objects_in_lot(lot, ["sprinkler"]):
		if dist(o.tile, tile) <= r:
			return true
	return false

static func best_extinguisher(lot: String, from: Vector2i):
	var best = null
	var bd: int = 1 << 20
	for o in objects_in_lot(lot, ["fire_extinguisher"]):
		if float(WorldIface.state_get(o, "charge", 0.0)) <= num("extinguisher_min_charge", 2.0):
			continue
		var d: int = dist(o.tile, from)
		if d < bd:
			bd = d
			best = o
	return best

# ------------------------------------------------------------------ people
static func asleep(f) -> bool:
	var c = f.current
	if c == null or str(c.state) != "running":
		return false
	return (c.def.get("tags", []) as Array).has("sleep") or str(c.def_id) == "pass_out"

static func helpless(f) -> bool:
	if (cfg().get("helpless_stages", []) as Array).has(str(f.age_stage)):
		return true
	if f.has_buff("collapsed"):          # task 02: collapsed from hunger / exhaustion / cold / heat
		return true
	return f.current != null and str(f.current.def_id) == "pass_out"

static func is_dependant(f) -> bool:
	return (cfg().get("dependant_stages", []) as Array).has(str(f.age_stage))

static func can_act(f) -> bool:
	return not helpless(f) and not SysUtil.is_away(f) and not Hospital.is_in(f)

static func folk_in_lot(lot: String) -> Array:
	var out: Array = []
	for f in WorldIface.all_folk():
		if f.has_meta("firefighter") or SysUtil.is_away(f) or Hospital.is_in(f):
			continue
		if lot_of(f.tile) == lot:
			out.append(f)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out

## Smoke dose thresholds scale with this (frail: elders, toddlers, kids, the sick and injured; fit adults slightly above 1).
static func dose_mult(f) -> float:
	var m: float = float((cfg().get("dose_stage", {}) as Dictionary).get(str(f.age_stage), 1.0))
	if f.has_buff("injured"):
		m *= num("dose_injured", 0.8)
	if f.has_buff("sick"):
		m *= num("dose_sick", 0.8)
	return m * (1.0 + num("dose_fitness", 0.02) * float(mini(f.skill_level("fitness"), 8))) * Creation.mult(int(f.id), "smoke_dose_mult")          # task 55: asthma

## How easily a sleeper wakes (1 = average). 0 = cannot wake (passed out, drunk).
static func wake_mult(f) -> float:
	if helpless(f) or f.has_buff("drunk"):
		return 0.0
	var m: float = 1.0
	var tr: Dictionary = cfg().get("wake_traits", {})
	for t in tr:
		if f.has_trait(str(t)):
			m *= float(tr[t])
	if f.has_buff("exhausted") or f.get_stat_value("energy") < -60.0:
		m *= num("wake_exhausted", 0.5)
	return m * Creation.mult(int(f.id), "wake_on_noise")          # task 55: light / heavy sleeper

static func trait_score(f) -> float:
	var s: float = 0.0
	for t in cfg().get("brave_traits", []):
		if f.has_trait(str(t)):
			s += 1.0
	for t2 in cfg().get("timid_traits", []):
		if f.has_trait(str(t2)):
			s -= 1.0
	return s

# ------------------------------------------------------------------ tooltips (shown when hovering an object)
## Extra hover line(s) for an object: the fire risk it carries or the protection it gives. "" when nothing to say.
static func hover_text(o) -> String:
	var now: int = SysUtil.now()
	var c: Array = _tip_cache.get(int(o.id), [])
	if not c.is_empty() and int(c[0]) == now:
		return str(c[1])
	var t: String = _tip(o)
	_tip_cache[int(o.id)] = [now, t]
	if _tip_cache.size() > 200:
		_tip_cache.clear()
	return t

static func _tip(o) -> String:
	var did: String = str(o.def_id)
	var lot: String = lot_of(o.tile)
	var hid: int = hid_of_lot(lot)
	var lines: Array = []
	match did:
		"stove", "grill":
			if hid > 0:
				var s := IncidentSubject.of_household(hid)
				var low: bool = not IncidentCond.check([{"all_members": [{"skill_at_least": ["cooking", 4]}]}], s)
				if low:
					lines.append("Low cooking skill: fire risk")
				else:
					lines.append("Skilled cooks: low fire risk")
			if bool(WorldIface.state_get(o, "broken", false)):
				lines.append("Broken: fire risk")
		"fireplace":
			lines.append("Fire risk if left burning alone")
		"smoke_alarm":
			var b: float = float(WorldIface.state_get(o, "battery", 0.0))
			lines.append("Wakes sleepers and warns everyone" if b > 0.0 else "Battery flat: replace it!")
			if b > 0.0 and b < 3.0:
				lines.append("Battery getting low")
		"fire_extinguisher":
			lines.append("Puts out small fires. Charge %d/10" % int(roundf(float(WorldIface.state_get(o, "charge", 0.0)))))
		"sprinkler":
			lines.append("Puts out small fires by itself")
		"ash_pile":
			lines.append("Sweep it up")
		_:
			if bool(WorldIface.state_get(o, "broken", false)) and is_electrical(o):
				lines.append("Broken: fire risk")
	if hid > 0 and (did == "stove" or did == "grill" or did == "fireplace") and not working_alarm(lot):
		lines.append("No working smoke alarm in the house")
	return "\n".join(PackedStringArray(lines))