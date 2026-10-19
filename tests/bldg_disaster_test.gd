extends RefCounted
## Disasters in a house with floors (home = medium_f02: two floors and a cellar with a storm-shelter room): a tornado is waited out in the
## basement (or beside a ground-floor fixture, never upstairs), floods hit the basement first and never the upper floor, earthquakes shake the
## upper floors harder than the basement.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _cfg(kind: String, key: String, v: Variant) -> void:
	((IncidentDefs.config["disasters"]["damage"] as Dictionary)[kind] as Dictionary)[key] = v


func run() -> Array:
	fails = []
	_multipliers()
	_tornado()
	_flood()
	_quake()
	Kit.teardown()
	return fails


func _game() -> Array:
	var folk: Array = Kit.new_game("medium", 777, 1, "medium_f02")
	IncidentDefs.reset()
	IncidentDefs.ensure()
	DisasterContent.ensure()
	WorldIface.coins[1] = 3000
	Economy.refresh_objects()
	return folk


func _multipliers() -> void:
	_check(LevelInfo.height_mult("quake", 3) > LevelInfo.height_mult("quake", 1) and LevelInfo.height_mult("quake", 1) > 1.0, "quakes: higher is worse")
	_check(LevelInfo.height_mult("quake", -1) < 1.0, "quakes: the basement is steadier")
	_check(LevelInfo.height_mult("flood", -1) > 1.0 and LevelInfo.height_mult("flood", 1) == 0.0, "floods: basement first, upper floors dry")
	_check(LevelInfo.height_mult("tornado", 2) > 1.0 and LevelInfo.height_mult("tornado", -1) < 1.0, "tornado: roof side first, cellar safest")


func _fixture_level(o) -> int:
	return int(o.level)


func _tornado() -> void:
	var folk: Array = _game()
	var W: Node = Kit.world()
	_check(LevelInfo.has_basement(NeighborhoodLots.entry_tile(Neighborhood.HOME)), "the home has a basement")
	var objs: Array = DisasterDamage.objects(1)
	var levels: Dictionary = {}
	for o in objs:
		if LevelDisasters.FIXTURES.has(str(o.def_id)):
			levels[o.level] = int(levels.get(o.level, 0)) + 1
	_check(levels.has(0) and levels.has(1), "fixtures on the ground floor and upstairs: %s" % str(levels))
	var spots: Array = LevelDisasters.cover_spots(objs)
	var all_ground := not spots.is_empty()
	for s in spots:
		all_ground = all_ground and s.level == 0
	_check(all_ground, "cover = ground-floor fixtures only (%d spots)" % spots.size())
	for f in folk:
		f.level = 0
	var sent: int = DisasterAftermath.send_to_cover(1)
	_check(sent == 3, "everyone is sent to cover (%d)" % sent)
	for f in folk:
		var target = null
		for q in f.queue:
			if (q as Interaction).def_id == "take_cover":
				target = (q as Interaction).obj
		_check(target != null and target.level == 0 and LevelDisasters.FIXTURES.has(str(target.def_id)), "%s takes cover at a ground-floor fixture" % f.name)
		f.clear_queue()
	# without ground fixtures the cellar is the place to be
	for o in objs:
		if LevelDisasters.FIXTURES.has(str(o.def_id)) and o.level == 0:
			W.remove_object(o.id)
	Economy.refresh_objects()
	for f in folk:
		f.level = 0
		f.remove_buff("siren_alert")
	sent = DisasterAftermath.send_to_cover(1)
	var cellar_goto := 0
	for f in folk:
		for q in f.queue:
			if (q as Interaction).def_id == "go_here" and (q as Interaction).goto_level < 0:
				cellar_goto += 1
		f.clear_queue()
	_check(cellar_goto == 3, "with no fixture downstairs everyone goes down to the cellar (%d)" % cellar_goto)
	# exposure: in the cellar = cover; beside an upstairs bath fixture = NOT cover
	var m: Folk = folk[0]
	m.level = -1
	_check(DisasterDamage.exposure(m, 1) == "cover", "in the cellar: covered")
	var bath = null
	for o in objs:
		if str(o.def_id) in ["shower", "toilet", "bathtub"] and o.level == 1:
			bath = o
	_check(bath != null, "an upstairs bathroom fixture exists")
	if bath != null:
		m.tile = bath.tile + Vector2i(0, 1)
		m.level = 1
		_check(DisasterDamage.exposure(m, 1) == "in", "beside an upstairs bath: not covered")


func _flood() -> void:
	_game()
	var W: Node = Kit.world()
	_cfg("flood", "object_hit", [0.34, 0.34, 0.34])
	_cfg("flood", "scope", "floor")
	_cfg("flood", "destroy_share", 1.0)
	var by_level: Dictionary = {}
	for o in DisasterDamage.objects(1):
		if not DisasterDamage._in_scope(o, "floor"):
			continue
		if not by_level.has(o.level):
			by_level[o.level] = []
		(by_level[o.level] as Array).append(int(o.id))
	_check(by_level.has(-1) and by_level.has(0) and by_level.has(1), "furniture on every floor: %s" % str(by_level.keys()))
	Incidents.rng.seed = 5
	DisasterDamage.strike(1, "flood", 2)
	var lost: Dictionary = {}
	for lv in by_level:
		lost[lv] = 0
		for id in by_level[lv]:
			var o = W.get_object(int(id))
			if o == null or bool(o.state.get("broken", false)):
				lost[lv] += 1
	var n: Dictionary = {}
	for lv in by_level:
		n[lv] = (by_level[lv] as Array).size()
	_check(int(lost[-1]) == int(n[-1]), "the flood takes the whole basement (%d of %d)" % [lost[-1], n[-1]])
	_check(int(lost[1]) == 0, "and none of the upper floor (%d of %d)" % [lost[1], n[1]])
	_check(int(lost[0]) < int(n[0]), "the ground floor only in part (%d of %d)" % [lost[0], n[0]])


func _quake() -> void:
	var rate_up := 0.0
	var rate_down := 0.0
	for seed_i in 4:
		_game()
		var W: Node = Kit.world()
		_cfg("quake", "object_hit", [0.5, 0.5, 0.5])
		_cfg("quake", "destroy_share", 1.0)
		var ids_up: Array = []
		var ids_down: Array = []
		for o in DisasterDamage.objects(1):
			if not DisasterDamage._in_scope(o, "furniture"):
				continue
			if o.level >= 1:
				ids_up.append(int(o.id))
			elif o.level < 0:
				ids_down.append(int(o.id))
		Incidents.rng.seed = 20 + seed_i
		DisasterDamage.strike(1, "quake", 2)
		var lost_up := 0
		for id in ids_up:
			var o = W.get_object(id)
			if o == null or bool(o.state.get("broken", false)):
				lost_up += 1
		var lost_down := 0
		for id in ids_down:
			var o2 = W.get_object(id)
			if o2 == null or bool(o2.state.get("broken", false)):
				lost_down += 1
		rate_up += float(lost_up) / maxf(1.0, float(ids_up.size())) / 4.0
		rate_down += float(lost_down) / maxf(1.0, float(ids_down.size())) / 4.0
	_check(rate_up > rate_down, "earthquakes shake the upper floor harder than the cellar (%.2f vs %.2f)" % [rate_up, rate_down])
	var m: Folk = null
	for f in SysUtil.residents():
		m = f
	if m != null:
		m.level = 0
		var base := LevelDisasters.folk_mult("quake", m)
		m.level = 1
		_check(LevelDisasters.folk_mult("quake", m) > base, "and folk upstairs are hurt more often")
