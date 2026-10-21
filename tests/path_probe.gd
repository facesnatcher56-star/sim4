extends SceneTree
## Reviewer tool (not a test; the runner skips it): map walkability and walls around the player's home, then path from a sidewalk tile to yard tiles.
var _main: Node = null
var _frames := 0

func _W():
	return root.get_node("World")

func _process(_d: float) -> bool:
	if _main == null:
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5:
		var r := RandomNumberGenerator.new()
		r.seed = 77
		var h := HouseholdSetup.make_household("solo", r)
		_main.start_new_game(h, str(Scenario.def("solo").get("start_id", "small")), {"scenario": "solo", "difficulty": "normal", "world_seed": 77})
		return false
	if _frames == 20:
		var W = _W()
		var f = W.all_folk()[0]
		var c: Vector2i = f.tile
		print("PAWN at ", c, " floor ", W.get_floor(c))
		var x0 := c.x - 22
		var y0 := c.y - 16
		var lines: Array = []
		var sw: Array = []
		var yard: Array = []
		for y in range(y0, y0 + 34):
			var s := ""
			for x in range(x0, x0 + 46):
				var t := Vector2i(x, y)
				var fl: String = W.get_floor(t)
				var ch := "?"
				if not W.in_bounds(t):
					ch = " "
				elif not W.is_walkable(t):
					var o = W.object_at(t, 0)
					ch = "#" if o == null else "o"
				else:
					ch = fl.substr(0, 1) if fl != "" else "."
					if fl.contains("side") or fl.contains("pave") or fl.contains("walk"):
						sw.append(t)
					if fl.contains("grass") or fl.contains("lawn") or fl.contains("yard"):
						yard.append(t)
				# wall edge to the east / south
				var we: String = W.wall_at(W.edge_between(t, t + Vector2i(1, 0)))
				var ws: String = W.wall_at(W.edge_between(t, t + Vector2i(0, 1)))
				if we != "" and ws != "":
					ch = "+"
				elif we != "":
					ch = "|"
				elif ws != "":
					ch = "_"
				s += ch
			lines.append(s)
		print("MAP x0=%d y0=%d (# blocked, o object, | east wall edge, _ south wall edge, + both, letters = floor initial)" % [x0, y0])
		for l in lines:
			print("MAP ", l)
		var floors := {}
		for y in range(y0, y0 + 34):
			for x in range(x0, x0 + 46):
				var fl2: String = W.get_floor(Vector2i(x, y))
				floors[fl2] = int(floors.get(fl2, 0)) + 1
		print("FLOORS ", floors)
		# paths: from the nearest sidewalk tile to several yard tiles
		if not sw.is_empty() and not yard.is_empty():
			sw.sort_custom(func(a, b): return a.distance_to(c) < b.distance_to(c))
			var a: Vector2i = sw[0]
			yard.sort_custom(func(p, q): return p.distance_to(a) < q.distance_to(a))
			for i in [0, 3, 8, 15, 30]:
				if i >= yard.size():
					break
				var b: Vector2i = yard[i]
				var p: Array = W.find_path(a, b)
				var manh: int = absi(a.x - b.x) + absi(a.y - b.y)
				print("PATH %s -> %s  steps %d  manhattan %d  ratio %.1f  %s" % [str(a), str(b), p.size(), manh, float(p.size()) / maxf(manh, 1), str(p.slice(0, 40))])
		quit(0)
	return false
