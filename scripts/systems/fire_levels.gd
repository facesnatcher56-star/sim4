class_name FireLevels
extends RefCounted
## Fire in a building with several floors (task 10 part B). The fire system stays tile based; a fire record carries its `level`.
##   - spreading UPWARD is faster than sideways: every spread tick a growing fire (stage 2+) tries the floor above it: much more likely
##     through a stairwell (the hole above a staircase) or a lift shaft than through the ceiling;
##   - smoke RISES: the room above a burning room (through the stairwell) fills with smoke too;
##   - stairs and the fire escape are the exits; the LIFT is switched off for the whole blaze (a lift in a fire is a trap): folk route around it;
##   - folk who jump from a window on a high floor get hurt.
## Config (data/incidents/03_fire.json config.fire, all optional): up_chance, up_stairwell_mult, up_min_stage, smoke_rise, jump_hurt_level.

static func num(key: String, default: float) -> float:
	return FireRules.num(key, default)


# ------------------------------------------------------------------ spreading upward
## Called after the sideways spread of a fire. Returns true when a fire was lit on the floor above.
static func climb(f: Dictionary) -> bool:
	var w = WorldIface.world()
	if w == null or not ("levels" in w) or w.levels == null:
		return false
	var lvl := int(f.get("level", 0))
	var tile: Vector2i = f["tile"]
	var top: int = LevelInfo.top_level(tile)
	if lvl >= top or int(f["stage"]) < int(num("up_min_stage", 2.0)):
		return false
	var above := lvl + 1
	var lay = w.levels.layer(above, false)
	if lay == null:
		return false
	var stage_mult: float = FireRules.at("stage_mult", int(f["stage"]) - 1, 1.0)
	var best: Dictionary = {}
	for t in f["tiles"]:
		for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + d
			if not lay.floors.has(n) or not Fire.fire_at(n, above).is_empty():
				continue
			var o = FireRules.object_at(n, above)
			var flam: float = FireRules.flammability(o, n) if o != null else FireRules.floor_flammability(n, above)
			if flam <= 0.0:
				continue
			var shaft: bool = lay.holes.has(n) or _lift_shaft(w, n, above)
			var p: float = clampf(num("up_chance", 0.45) * stage_mult * (0.4 + flam) * (num("up_stairwell_mult", 2.2) if shaft else 1.0), 0.0, 0.95)
			if best.is_empty() or p > float(best["p"]):
				best = {"p": p, "tile": n if o == null else o.tile, "obj": o}
	if best.is_empty() or Fire.rng.randf() >= float(best["p"]):
		return false
	var target = best["obj"] if best["obj"] != null else best["tile"]
	if Fire.ignite(target, str(f["source"]), {"culprit": int(f["culprit"]), "quiet": true, "level": above}):
		Fire._stat("climbed")
		return true
	return false


static func _lift_shaft(w, tile: Vector2i, level: int) -> bool:
	for rec in w.portals.portals.values():
		if str(rec["kind"]) == "elevator" and rec["tile"] == tile and level >= int(rec["base"]) and level <= int(rec["top"]):
			return true
	return false


# ------------------------------------------------------------------ smoke rises
## Smoke of the rooms ABOVE burning rooms (called at the end of FireSmoke.step): `rs` = blaze["rs"] {room id -> 0..1}.
static func smoke_up(rs: Dictionary, fires: Array) -> void:
	var w = FireSmoke._w()
	if w == null:
		return
	var rise: float = num("smoke_rise", 0.8)
	for f in fires:
		var lvl := int(f.get("level", 0))
		if lvl >= LevelInfo.top_level(f["tile"]) or int(f["stage"]) < 2:
			continue
		var below: float = float(rs.get(FireSmoke.room_of(f["tile"], lvl), 0.0))
		for t in (f["tiles"] as Array):
			var rid: int = FireSmoke.room_of(t, lvl + 1)
			if rid < 0:
				continue
			var up_pct: float = rise if (w.levels.layer(lvl + 1, false) != null and w.levels.layer(lvl + 1, false).holes.has(t)) else rise * 0.45
			rs[rid] = maxf(float(rs.get(rid, 0.0)), minf(below * up_pct, 1.0))


# ------------------------------------------------------------------ lifts
## The first fire of a blaze switches the lifts of the building off (remembered in the blaze so only those are restored).
static func on_blaze_start(b: Dictionary, tile: Vector2i) -> void:
	var off: Array = []
	for o in LevelInfo.lifts_at(tile):
		if not bool(o.state.get("out_of_order", false)):
			WorldIface.state_set(o, "out_of_order", true)
			off.append(int(o.id))
	if not off.is_empty():
		b["lifts_off"] = off
		if FireRules.is_home(str(b["lot"])):
			SysUtil.notify("The lift is out of service while there is a fire. Use the stairs!", "warn")


static func on_blaze_end(b: Dictionary) -> void:
	for id in b.get("lifts_off", []):
		var o = WorldIface.get_object(int(id))
		if o != null:
			WorldIface.state_set(o, "out_of_order", false)
	b.erase("lifts_off")


# ------------------------------------------------------------------ escaping
## Route of a folk to the blaze exit (level aware: stairs, never a disabled lift). [] = no way out. Returns Vector3i points.
static func escape_route(f, exit: Vector2i) -> Array:
	var w = WorldIface.world()
	if w == null or not w.has_method("find_route") or (int(f.level) == 0 and not LevelInfo.is_multi(f.tile)):
		var out: Array = []
		for t in WorldIface.find_path(f.tile, exit):
			out.append(Vector3i(t.x, t.y, 0))
		return out
	return w.find_route(Vector3i(f.tile.x, f.tile.y, int(f.level)), Vector3i(exit.x, exit.y, 0), LevelPortals.stair_mult(f))


## Somebody is put at the exit (rescue, jumped from a window): ground level; a jump from a high floor hurts.
static func land(f, jumped: bool = false) -> void:
	var from_level := int(f.level)
	f.level = 0
	if jumped and from_level >= int(num("jump_hurt_level", 2.0)):
		Hospital.injure(f, 1 if from_level < 4 else 2, "a jump from a window")
