class_name StaffPosts
extends RefCounted
## Task 53: the people who stand at the front of a place while it is open (data/staff_posts.json): the desk officer, the receptionist, the security guard
## at the entrance, the market guard at busy hours. Their tiles are worked out from the building's real front door, so they suit any layout.
## Crowd.update_staff spawns them like a template's own staff.   StaffPosts.defs(lot) -> [{role, tile (lot-local), hours, guard}]   StaffPosts.front(lot)

static var _cache: Dictionary = {}          # lot -> {door, inward}

static func reset() -> void:
	_cache = {}

static func cfg() -> Dictionary:
	return SysUtil.table("staff_posts")

## The lot's front door on the ground floor (nearest the lot's entry) and the direction into the building. {} if none.
static func front(lot: String) -> Dictionary:
	if _cache.has(lot):
		return _cache[lot]
	var w = WorldIface.world()
	if w == null:
		return {}
	var rc: Rect2i = NeighborhoodLots.rect_of(lot)
	var entry: Vector2i = NeighborhoodLots.gate_tile(lot)
	var best: Dictionary = {}
	var bd: int = 1 << 30
	for o in w.objects_of_def("door"):
		if ("level" in o and int(o.level) != 0) or not rc.has_point(o.tile):
			continue
		for dv in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var out: Vector2i = o.tile + dv
			var inn: Vector2i = o.tile - dv
			if w.is_outdoor(out) and not w.is_outdoor(inn):
				var d: int = (out - entry).length_squared()
				if d < bd:
					bd = d
					best = {"door": o.tile, "inward": -dv}
	_cache[lot] = best
	return best

static func defs(lot: String) -> Array:
	var vt: String = Venues.type_of_lot(lot)
	var posts: Array = (cfg().get("posts", {}) as Dictionary).get(vt, [])
	if posts.is_empty():
		return []
	var fr: Dictionary = front(lot)
	if fr.is_empty():
		return []
	var w = WorldIface.world()
	var origin: Vector2i = NeighborhoodLots.rect_of(lot).position
	var inward: Vector2i = fr["inward"]
	var side := Vector2i(-inward.y, inward.x)
	var out: Array = []
	for p in posts:
		var t: Vector2i = (fr["door"] as Vector2i) + inward * int(p.get("depth", 2)) + side * int(p.get("side", 0))
		if w != null and (not w.is_walkable(t) or w.is_outdoor(t)):
			t = WalkThen.near(t)
		var d: Dictionary = (p as Dictionary).duplicate()
		d["tile"] = [t.x - origin.x, t.y - origin.y]
		out.append(d)
	return out

static func is_guard(f) -> bool:
	return str(f.get_meta("staff", "")) in ["security", "counter_guard"]

## The guard on duty at a lot (a staff Folk at a post), or null.
static func guard_at(lot: String):
	for s in Crowd.staff_folk(lot):
		if is_guard(s):
			return s
	return null
