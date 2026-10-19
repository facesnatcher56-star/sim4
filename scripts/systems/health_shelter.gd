class_name HealthShelter
extends RefCounted
## Getting in out of the cold: a resident who has been outside long enough in freezing weather (exposure.cold.shelter_min, before the
## shivering stage) drops what they are doing and walks indoors (own home: the nearest roofed tile; elsewhere: walk home). A walk that does
## not work (no path, still outside after a few tries) ends in an instant trip home, so nobody freezes standing in a queue or a corner.

const RADIUS := 14

static var seek_hook: Callable = Callable()      # tests: called with the folk instead of the real walk indoors

static func _cold() -> Dictionary:
	return Health.cfg("exposure").get("cold", {})

## Called every minute from HealthExposure.tick for a person who is outside with cold exposure building.
static func check(f, r: Dictionary, now: int) -> void:
	var tc: Dictionary = _cold()
	if Health.is_collapsed(f) or SysUtil.is_away(f) or int(r.get("shelter_next", 0)) > now:
		return
	if float(r.get("cold_min", 0.0)) < float(tc.get("shelter_min", 60)) * Health.stage_mult(f):
		return
	if not seek_hook.is_valid():
		var w = WorldIface.world()
		if w == null or not w.has_method("is_outdoor"):
			return                       # stub test worlds without roofs / lots: "outside" is a flag, there is nowhere to walk to
	r["shelter_next"] = now + int(tc.get("shelter_retry_min", 10))
	var tries: int = int(r.get("shelter_tries", 0)) + 1
	r["shelter_tries"] = tries
	Health.count("shelter")
	if seek_hook.is_valid():
		seek_hook.call(f)
		return
	if tries > int(tc.get("shelter_walk_tries", 3)) or not _walk_in(f):
		Neighborhood.go_home([int(f.id)], {"instant": true, "quiet": true})
		r["shelter_tries"] = 0

## Indoors again: the counter starts over.
static func warm(r: Dictionary) -> void:
	r.erase("shelter_tries")
	r.erase("shelter_next")

static func _walk_in(f) -> bool:
	var lot: String = Neighborhood.lot_of_folk(f)
	if lot != Neighborhood.HOME:
		return bool(Neighborhood.go_home([int(f.id)], {}).get("ok", false))
	var spot: Vector2i = _nearest_roofed(f)
	if spot.x < 0:
		return false
	var ir := Interaction.create_goto(f, spot, false)
	if ir == null:
		return false
	f.cancel_current("cold")
	f.clear_queue()
	f.enqueue(ir)
	return true

static func _nearest_roofed(f) -> Vector2i:
	var w = WorldIface.world()
	if w == null or not w.has_method("is_outdoor"):
		return Vector2i(-1, -1)
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for dx in range(-RADIUS, RADIUS + 1):
		for dy in range(-RADIUS, RADIUS + 1):
			var d: int = absi(dx) + absi(dy)
			if d >= best_d:
				continue
			var t: Vector2i = f.tile + Vector2i(dx, dy)
			if w.is_walkable(t) and not w.is_outdoor(t, 0) and WorldIface.path_length(f.tile, t) >= 0:
				best = t
				best_d = d
	return best
