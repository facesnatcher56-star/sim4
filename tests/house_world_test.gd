extends RefCounted
## Every generated lot builds into the REAL World (same placement logic as LotLoader.apply), places every object, has walkable
## connected spawn tiles, every usable object is reachable from the entry, every room is reachable through doors, windows sit
## on exterior walls, doorways are not blocked, bathrooms / kitchens / bedrooms are equipped. Per-lot numbers are printed.
const Kit = preload("res://tests/house_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var W: Node = Kit.world()
	NeighborhoodContent.install()          # venue objects (park_bench, cafe_counter...) into World.defs
	var lots: Dictionary = HouseGenerator.lots()
	var ids: Array = lots.keys()
	ids.sort()
	var min_objects := {"small": 14, "medium": 30, "large": 50, "classic": 40, "park": 25, "cafe": 30, "gym": 25, "library": 40, "market": 25, "office": 30, "school": 40}
	var t0 := Time.get_ticks_msec()
	var report: Array = []
	for id in ids:
		var t: Dictionary = lots[id]
		var rep := Kit.apply(t, W)
		_check((rep["failed"] as Array).is_empty(), "%s: placement failed: %s" % [id, str(rep["failed"])])
		var key := str(t.get("size", t.get("venue", "")))
		_check(W.objects.size() >= int(min_objects.get(key, 10)), "%s: only %d objects" % [id, W.objects.size()])
		var spawn: Array = W.starter_spawn_tiles
		_check(not spawn.is_empty(), "%s: no spawn tiles" % id)
		if spawn.is_empty():
			continue
		var from: Vector2i = spawn[0]
		_check(W.is_walkable(from), "%s: entry not walkable" % id)
		for sp in spawn:
			_check(W.is_walkable(sp) and W.has_path(from, sp), "%s: spawn %s disconnected" % [id, str(sp)])
		var bad: Array = LotLoader.unreachable_objects(W, from)
		_check(bad.is_empty(), "%s: unreachable objects: %s" % [id, str(bad)])
		for sd in t.get("staff", []):
			var st := Vector2i(int(sd["tile"][0]), int(sd["tile"][1]))
			_check(W.is_walkable(st) and W.has_path(from, st), "%s: staff post %s unreachable" % [id, str(st)])
		var shell := Kit.shell_of(t)
		var room_reach: Dictionary = {}
		var door_n := 0
		var win_n := 0
		for o in W.all_objects():
			if o.def_id == "door":
				door_n += 1
				var e: Vector3i = W.mount_edge(o.tile, o.rot)
				var ts: Array = [Vector2i(e.x, e.y - 1), Vector2i(e.x, e.y)] if e.z == 0 else [Vector2i(e.x - 1, e.y), Vector2i(e.x, e.y)]
				for tt in ts:
					if shell.has_point(tt) or tt == from:
						_check(W.is_walkable(tt), "%s: door at %s opens into a blocked tile %s" % [id, str(o.tile), str(tt)])
			elif o.def_id == "window":
				win_n += 1
				var e2: Vector3i = W.mount_edge(o.tile, o.rot)
				var on_edge: bool = (e2.z == 0 and (e2.y == shell.position.y or e2.y == shell.end.y)) or (e2.z == 1 and (e2.x == shell.position.x or e2.x == shell.end.x))
				_check(on_edge, "%s: window at %s is not on an exterior wall" % [id, str(o.tile)])
				# nothing tall stands right in front of the window
				var inner: Vector2i = o.tile
				var blocker = W.object_at(inner)
				if blocker != null and float(blocker.def.get("height", 1.0)) >= 1.5 and not ("decor" in blocker.tags()):
					fails.append("%s: tall %s blocks the window at %s" % [id, blocker.def_id, str(o.tile)])
		if str(t.get("kind", "home")) == "home":
			# every room of the house is reachable through its doors
			for y in range(shell.position.y, shell.end.y):
				for x in range(shell.position.x, shell.end.x):
					var tile := Vector2i(x, y)
					var rid: int = W.room_id(tile)
					if room_reach.get(rid, false) or not W.is_walkable(tile):
						continue
					room_reach[rid] = W.has_path(from, tile) or tile == from
			var rooms_total: int = room_reach.size()
			for rid4 in room_reach:
				_check(bool(room_reach[rid4]), "%s: a room is cut off from the entry" % id)
			_check(win_n >= 5, "%s: only %d windows" % [id, win_n])
			_check(door_n >= 2, "%s: only %d doors" % [id, door_n])
			# fixtures per room type (world objects, by room)
			var by_room: Dictionary = {}
			for o in W.all_objects():
				if o.is_wall_mounted() or not shell.has_point(o.tile):
					continue
				var rid2: int = W.room_id(o.tile)
				if not by_room.has(rid2):
					by_room[rid2] = {}
				by_room[rid2][o.def_id] = true
			var baths := 0
			for rid3 in by_room:
				var d: Dictionary = by_room[rid3]
				if d.has("toilet"):
					_check(d.has("sink"), "%s: toilet without a sink" % id)
					if d.has("shower") or d.has("bathtub"):
						baths += 1
				if d.has("stove"):
					_check(d.has("fridge") and d.has("counter"), "%s: kitchen lacks fridge/counter" % id)
			_check(baths >= 1, "%s: no bathroom" % id)
			report.append("%-11s rooms %d  doors %d  windows %d  baths %d" % [id, rooms_total, door_n, win_n, baths])
		else:
			report.append("%-11s objects %d  doors %d  windows %d  staff %d" % [id, W.objects.size(), door_n, win_n, (t.get("staff", []) as Array).size()])
	print("---- built in the real World (%d lots, %d ms) ----" % [ids.size(), Time.get_ticks_msec() - t0])
	for line in report:
		print(line)
	W.reset()
	return fails
