extends RefCounted
## Every bed on the map is under a roof: a room that holds a bed must not count as outdoors (weather, cold exposure, rain).
## Checks the real map for every start (the player home differs per start) and every townie home and venue.

const Kit = preload("res://tests/hood_kit.gd")

func run() -> Array:
	var f: Array = []
	for s in Neighborhood.starts():
		var sid: String = str(s["id"])
		Kit.new_game(sid)
		var W = Kit.world()
		var beds: int = 0
		var bad: Array = []
		for o in W.objects.values():
			var d: Dictionary = SimEnv.data().object_def(str(o.def_id))
			var tags: Array = d.get("tags", [])
			if not (tags.has("bed") or tags.has("sleep") or str(o.def_id).find("bed") >= 0):
				continue
			beds += 1
			if W.is_outdoor(o.tile, int(o.level)):
				var info: Dictionary = W.rooms.room_info(o.tile, int(o.level))
				bad.append("%s %s@%s L%d lot=%s room=%s" % [sid, o.def_id, str(o.tile), int(o.level), str(Neighborhood.lot_at(o.tile)), str(info.get("id", "?"))])
		if beds == 0:
			f.append("start %s: no beds found on the map (test setup)" % sid)
		if not bad.is_empty():
			f.append("beds under the open sky: " + str(bad))
	Kit.teardown()
	return f
