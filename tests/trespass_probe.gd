extends SceneTree
## Reviewer tool (not a test; the runner skips it): does the world react when the player walks into someone else's house or stands in the road?
## Starts a solo game, orders the pawn (as a player order) to a tile inside another household's home, waits, then to the middle of a road at
## rush hour and waits; prints every toast and notable game event, where the pawn ended up, and the road-accident marker.
var _main: Node = null
var _frames := 0
var _f = null
var _log: Array = []
var _phase := 0
var _t := 0

func _W():
	return root.get_node("World")

func _clock():
	return root.get_node("Clock")

func _stamp() -> String:
	var c = _clock()
	return "d%d %02d:%02d" % [c.day(), c.hour(), c.minute()]

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
		_main.start_new_game(h, str(Scenario.def("solo").get("start_id", "small")), {"scenario": "solo", "difficulty": "normal", "world_seed": 77, "funds": Scenario.funds_for("solo", "normal")})
		return false
	if _frames == 15:
		_f = SysUtil.residents()[0]
		var ev = root.get_node("Events")
		ev.notification.connect(func(text, kind): _log.append("%s TOAST [%s] %s" % [_stamp(), kind, text]))
		ev.game_event.connect(func(n, p):
			if n in ["need_low", "mood_changed", "buff_added", "buff_removed", "skill_xp", "systems_day", "weather_changed", "autonomy_choice", "interaction_started", "interaction_finished", "walk_started", "walk_arrived", "mood_journal", "emotional_memory"]:
				return
			_log.append("%s EVENT %s %s" % [_stamp(), n, str(p).left(160)]))
		# a tile inside another household's house: carpet or tile floor far from the pawn's home
		var W = _W()
		var best := Vector2i(-1, -1)
		var bd := 1e9
		for y in W.height:
			for x in W.width:
				var t := Vector2i(x, y)
				var fl: String = W.get_floor(t)
				if fl in ["carpet", "tile", "wood"] and W.is_walkable(t) and Neighborhood.lot_at(t) != Neighborhood.HOME and Neighborhood.lot_at(t).begins_with("townie"):
					var d: float = t.distance_to(_f.tile)
					if d > 12 and d < bd:
						bd = d
						best = t
		print("TRESPASS pawn %s, target inside another home %s (%.0f tiles away, lot %s)" % [str(_f.tile), str(best), bd, str(Neighborhood.lot_at(best)) if best.x >= 0 else "-"])
		_clock().reset(8 * 60)
		if best.x >= 0:
			_f.enqueue(Interaction.create_goto(_f, best, true, 0))
		_phase = 1
		return false
	if _phase == 1 or _phase == 2:
		for m in 10:
			_clock().advance_minutes(1)
		_t += 10
		if _phase == 1 and _t >= 240:
			print("TRESPASS after 4 h: pawn at %s floor %s lot %s doing %s" % [str(_f.tile), _W().get_floor(_f.tile), str(Neighborhood.lot_at(_f.tile)), str(_f.current.def_id) if _f.current != null else "-"])
			# now the middle of the road at rush hour
			var W = _W()
			var road := Vector2i(-1, -1)
			var bd2 := 1e9
			for y in W.height:
				for x in W.width:
					var t2 := Vector2i(x, y)
					if W.get_floor(t2) == "asphalt" and W.is_walkable(t2):
						var d2: float = t2.distance_to(_f.tile)
						if d2 < bd2:
							bd2 = d2
							road = t2
			print("TRESPASS road target %s" % str(road))
			_f.cancel_current("new order"); _f.enqueue(Interaction.create_goto(_f, road, true, 0))
			_phase = 2
			_t = 0
		elif _phase == 2 and _t >= 240:
			print("TRESPASS after road: pawn at %s floor %s; buffs %s; Traffic.provider set %s" % [str(_f.tile), _W().get_floor(_f.tile), str(_f.buffs.keys() if _f.get("buffs") is Dictionary else "?"), str(Traffic.provider.is_valid())])
			for l in _log:
				print("TRESPASS " + str(l))
			quit(0)
	return false
