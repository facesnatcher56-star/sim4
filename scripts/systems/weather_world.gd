class_name WeatherWorld
extends RefCounted
## Hourly/daily weather effects on objects, puddles, lightning and fishing.

# ------------------------------------------------------------------ hourly tick
static func _hour_rng(salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = Weather._mix(Weather.seed_value + salt, SimEnv.now_min())
	return r

static func on_hour(_hour: int) -> void:
	var t0 := PerfProf.start()
	WeatherContent.install()
	PerfProf.stop("weather/content", t0)
	var e: Dictionary = Weather.effects()
	var cur: String = Weather.current()
	var temp: float = Weather.temperature()
	# bills
	var b: Dictionary = e.get("bills", {})
	Weather._heat_dh += maxf(0.0, float(b.get("heat_below", 16.0)) - temp)
	Weather._cool_dh += maxf(0.0, temp - float(b.get("cool_above", 22.0)))
	Weather._bill_hours += 1.0
	Weather._min_today = minf(Weather._min_today, temp)
	var kind: String = Weather.precip_kind(cur)
	# snow cover / wetness
	if kind == "snow" and temp < 2.0:
		Weather._snow = clampf(Weather._snow + float(e.get("snow_per_hour", 0.12)) * Weather.precip_intensity(cur) / 0.6, 0.0, 1.0)
	elif temp > float(e.get("snow_melt_temp", 1.0)):
		Weather._snow = clampf(Weather._snow - float(e.get("snow_melt_per_hour", 0.04)) * (1.0 + maxf(temp - 5.0, 0.0) * 0.15), 0.0, 1.0)
	if kind == "rain":
		Weather._wet = clampf(Weather._wet + float(e.get("wet_per_hour", 0.35)), 0.0, 1.0)
		Weather._rain_hours += 1.0
	else:
		Weather._wet = clampf(Weather._wet - float(e.get("dry_per_hour", 0.15)), 0.0, 1.0)
	if kind == "snow":
		Weather._rain_hours += 0.5
	if cur == "heatwave":
		Weather._heat_hours += 1.0
	var t := PerfProf.start()
	_hourly_objects(cur, kind, e)
	PerfProf.stop("weather/objects", t)
	t = PerfProf.start()
	_puddle_tick(kind, e)
	PerfProf.stop("weather/puddles", t)
	if cur == "thunderstorm":
		_lightning(e)
	t = PerfProf.start()
	_cozy(kind, e)
	PerfProf.stop("weather/cozy", t)

static func _objects() -> Array:
	return SysUtil.all_world_objects()

## Object index (task 17.3 "places"): the few objects the weather touches are kept in per-kind sets that are updated only for NEW objects (ids from the
## last indexed next id upwards); removed objects are pruned when the set is read. Nothing walks every object of the town each rainy hour.
## kind: "rain" (garden plots + plants with water), "plot", or a comma list of tags.
static var _ix_world = null
static var _ix_next: int = 0
static var _ix: Dictionary = {}           # kind -> {object id: object}

static func reset_index() -> void:
	_def_match = {}
	_ix_world = null
	_ix_next = 0
	_ix = {}
	_catch = {}
	_rain_groups = {}          # holds the OLD game's WorldObject instances; its key (count, id sum, world node) matches a new game that reuses the node
	_rain_groups_key = []

static var _def_match: Dictionary = {}     # kind -> {def id: bool}: the object definitions decide, so the answer is memoised per definition

static func _matches(kind: String, o) -> bool:
	var dm: Dictionary = _def_match.get(kind, {})
	if not _def_match.has(kind):
		_def_match[kind] = dm
	var did: String = str(o.def_id)
	if dm.has(did):
		return bool(dm[did])
	var d: Dictionary = _def_of(o)
	var tags: Array = d.get("tags", [])
	var yes := false
	match kind:
		"rain":
			yes = did == "garden_plot" or (tags.has("plant") and (d.get("state", {}) as Dictionary).has("water"))
		"plot":
			yes = did == "garden_plot"
		_:
			for t in kind.split(","):
				if tags.has(t):
					yes = true
					break
	dm[did] = yes
	return yes

static func _indexed(kind: String) -> Array:
	var w = WorldIface.world()
	if w == null or not ("objects" in w) or not ("_next_id" in w):
		var out: Array = []
		for o in _objects():
			if _matches(kind, o):
				out.append(o)
		return out
	if not is_same(_ix_world, w) or int(w._next_id) < _ix_next:
		_ix_world = w
		_ix = {}
		_ix_next = 0
	var objs: Dictionary = w.objects
	if _ix_next < int(w._next_id):                       # new objects since the last call: test them against every known kind
		for id in range(_ix_next, int(w._next_id)):
			var o = objs.get(id, null)
			if o == null:
				continue
			for k in _ix:
				if _matches(k, o):
					(_ix[k] as Dictionary)[id] = o
		_ix_next = int(w._next_id)
	if not _ix.has(kind):                                # first use of a kind: one scan of the objects that exist now
		var found: Dictionary = {}
		for o2 in _objects():
			if _matches(kind, o2):
				found[int(o2.id)] = o2
		_ix[kind] = found
	var set: Dictionary = _ix[kind]
	var res: Array = []
	for id2 in set.keys():
		if objs.has(id2):
			res.append(set[id2])
		else:
			set.erase(id2)
	return res

static func _def_of(o) -> Dictionary:
	return SimEnv.data().object_def(str(o.def_id))

## The rain index grouped by lot: lot id -> {"plots": garden plots, "plants": plants with a water state}; "" = not inside a lot. Rebuilt when
## objects were added or removed. A rainy hour then visits the plants of the lots near an anchor only; a far lot is one counter (caught up daily).
static var _rain_groups: Dictionary = {}
static var _rain_groups_key: Array = []

static func _rain_by_lot() -> Dictionary:
	var lst: Array = _indexed("rain")
	var ids: int = 0                       # the key is the index itself (count + id sum), not the world's next object id: a shop restocking
	for o0 in lst:                         # or a bought chair must not rebuild the groups (that rebuild was the 190 ms rainy hour)
		ids += int(o0.id)
	var key: Array = [lst.size(), ids, WorldIface.world()]
	if key == _rain_groups_key and not _rain_groups.is_empty():
		return _rain_groups
	_rain_groups_key = key
	_rain_groups = {}
	for o in lst:
		var d: Dictionary = _def_of(o)
		var which: String = ""
		if str(o.def_id) == "garden_plot":
			which = "plots"
		elif (d.get("tags", []) as Array).has("plant") and (d.get("state", {}) as Dictionary).has("water"):
			which = "plants"
		if which == "":
			continue
		var lot: String = NeighborhoodLots.lot_at(o.tile)
		if not _rain_groups.has(lot):
			_rain_groups[lot] = {"plots": [], "plants": []}
		((_rain_groups[lot] as Dictionary)[which] as Array).append(o)
	return _rain_groups

static func _hourly_objects(cur: String, kind: String, e: Dictionary) -> void:
	if kind != "rain":
		return
	var g: Dictionary = e.get("garden", {})
	var plot_amt: float = float(g.get("rain_water_per_hour", 0.6))
	var groups: Dictionary = _rain_by_lot()
	var sliced: bool = RainSlices.enabled()
	for lot in groups:
		var grp: Dictionary = groups[lot]
		for o in grp["plots"]:                       # garden plots catch the rain wherever they are (cheap: a few per lot)
			WorldIface.state_add(o, "water", plot_amt)
		if (grp["plants"] as Array).is_empty():
			continue
		# plants: with the scheduler every lot only counts the owed rain hour; RainSlices waters the lots near an anchor a few per minute (a rainy hour used
		# to water them all in one frame, 100-400 ms), and the daily catch-up (on_day) takes what is still owed for far lots. Without it (tests) water now.
		if sliced or lot_is_far(lot, grp):
			Weather._rain_deferred[lot] = int(Weather._rain_deferred.get(lot, 0)) + 1
		else:
			water_lot(lot, 1)

## A lot whose plants are not worth visiting now: no anchor is within the near radius (no anchor at all = nothing is far).
static func lot_is_far(lot: String, grp: Dictionary) -> bool:
	if Tiers.anchors.is_empty() or (grp.get("plants", []) as Array).is_empty():
		return false
	if lot != "":
		return not Tiers.lot_distances(int(Tiers.cfg().get("near_radius", 64))).has(lot)
	return not Tiers.tile_near((grp["plants"][0] as Object).tile)

## Water the outdoor plants of one lot for `hours` rainy hours. The outdoor tests come first, then the writes: a state write drops the lot's room partition
## (decor depends on state), so interleaving them rebuilt the lot's rooms once per plant (a park with 30 plants: 90 ms).
static func water_lot(lot: String, hours: int) -> void:
	var w = WorldIface.world()
	var grp: Dictionary = _rain_by_lot().get(lot, {})
	if w == null or not w.has_method("is_outdoor") or grp.is_empty() or hours <= 0:
		return
	var amt: float = float(Weather.effects().get("garden", {}).get("plant_rain_water_per_hour", 0.8)) * float(hours)
	var wet: Array = []
	for o in grp["plants"]:
		if bool(w.is_outdoor(o.tile, int(o.level))):
			wet.append(o)
	for o2 in wet:
		WorldIface.state_add(o2, "water", amt)

static func _puddle_tick(kind: String, e: Dictionary) -> void:
	var w = WorldIface.world()
	if w == null or not w.has_method("add_mess") or not w.has_method("is_outdoor"):
		return
	var p: Dictionary = e.get("puddle", {})
	var r: RandomNumberGenerator = _hour_rng(7)
	if kind == "rain":
		var n: int = int(p.get("per_hour", 2))
		for i in n:
			if Weather._puddles.size() >= int(p.get("max", 10)):
				break
			var t := Vector2i(r.randi_range(0, int(w.width) - 1), r.randi_range(0, int(w.height) - 1))
			if bool(w.is_outdoor(t)) and w.is_walkable(t) and float(w.mess.get(t, 0.0)) <= 0.0:
				var a: float = float(p.get("amount", 0.9))
				w.add_mess(t, a)
				Weather._puddles[t] = a
	elif not Weather._puddles.is_empty():
		for t2 in Weather._puddles.keys():
			if r.randf() < float(p.get("dry_chance", 0.5)):
				w.add_mess(t2, -float(Weather._puddles[t2]))
				Weather._puddles.erase(t2)

static func _lightning(e: Dictionary) -> void:
	var l: Dictionary = e.get("lightning", {})
	var r: RandomNumberGenerator = _hour_rng(13)
	if r.randf() > float(l.get("per_hour_chance", 0.1)):
		return
	var cands: Array = []
	for o in _indexed(",".join(l.get("break_tags", ["electronics"]))):
		if not bool(WorldIface.state_get(o, "broken", false)):
			cands.append(o)
	var broke: bool = false
	var oid: int = -1
	if not cands.is_empty():
		var o2 = cands[r.randi_range(0, cands.size() - 1)]
		oid = int(o2.id)
		if r.randf() < float(l.get("break_chance", 0.45)):
			WorldIface.state_set(o2, "broken", true)
			broke = true
			SysUtil.notify("Lightning struck: the %s is broken!" % str(_def_of(o2).get("label", o2.def_id)).to_lower(), "warn")
	SysUtil.game_event("lightning", {"object_id": oid, "broke": broke, "folk_id": -1})

static func _cozy(kind: String, e: Dictionary) -> void:
	if kind == "":
		return
	var r: RandomNumberGenerator = _hour_rng(29)
	if not WeatherFolk._has_def("cozy"):
		return
	for f in WorldIface.all_folk():
		if SysUtil.is_away(f) or WeatherFolk.is_outside(f) or not SysUtil.is_resident(f):
			continue
		if r.randf() < float(e.get("cozy_chance_per_hour", 0.3)):
			f.add_buff("cozy")

# ------------------------------------------------------------------ daily tick
## The daily catch-up of the plants in lots that were far away while it rained (or are still owed their rain): the owed rain hours of their lot x the hourly amount.
static func catch_up_lot(lot: String) -> void:
	water_lot(lot, int(_catch.get(lot, 0)))

static var _catch: Dictionary = {}

static func on_day_sched(day: int) -> void:
	on_day(day, DaySlices.enabled())

static func on_day(day: int, sliced: bool = false) -> void:
	if not Weather._rain_deferred.is_empty():
		_catch = Weather._rain_deferred.duplicate()
		Weather._rain_deferred.clear()
		var lots: Array = _catch.keys()
		lots.sort()
		if sliced:
			DaySlices.begin("rain_catchup", lots, Callable(WeatherWorld, "catch_up_lot"))
		else:
			for lot in lots:
				catch_up_lot(str(lot))
	var e: Dictionary = Weather.effects()
	var g: Dictionary = e.get("garden", {})
	var frost: bool = Weather._min_today < float(e.get("frost_temp", 0.0)) and bool(g.get("frost_kills", true))
	var mult: float = Weather.crop_growth_mult()
	var killed: int = 0
	for o in _indexed("plot"):
		var spec: Dictionary = ((_def_of(o).get("state", {}) as Dictionary).get("growth", {}) as Dictionary)
		var growth: float = float(WorldIface.state_get(o, "growth", 0.0))
		if Weather._heat_hours >= 4.0:
			WorldIface.state_add(o, "water", -float(g.get("heat_extra_dry", 1.0)))
		if frost:
			if growth > 0.0:
				WorldIface.state_set(o, "growth", 0.0)
				if NeighborhoodLots.lot_at(o.tile) == Neighborhood.HOME:
					killed += 1          # only your own crops are news to you (the park's plots die quietly)
		elif mult > 1.0 and float(WorldIface.state_get(o, "water", 0.0)) >= 2.0:
			WorldIface.state_add(o, "growth", float(spec.get("daily_add", 2.0)) * (mult - 1.0))
	if killed > 0:
		SysUtil.notify("A hard frost killed your crops.", "warn")
		SysUtil.game_event("crops_frozen", {"count": killed, "folk_id": -1})
	Weather._min_today = 99.0
	Weather._rain_hours = 0.0
	Weather._heat_hours = 0.0
	var s: String = Seasons.current()
	if Weather._last_season == "":
		Weather._last_season = s
	elif s != Weather._last_season:
		Weather._last_season = s
		SysUtil.notify("%s has arrived." % Seasons.label(s), "weather")
		SysUtil.game_event("season_changed", {"season": s, "year": Seasons.year(), "day": day, "folk_id": -1})

# ------------------------------------------------------------------ fishing: better in the rain
static func on_game_event(ev_name: String, payload: Dictionary) -> void:
	if ev_name == "caught_fish":
		Weather._caught[int(payload.get("folk_id", -1))] = true

static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	var fe: Dictionary = Weather.effects().get("fishing", {})
	if not (fe.get("interactions", []) as Array).has(iid):
		return
	var caught: bool = Weather._caught.has(folk_id)
	Weather._caught.erase(folk_id)
	if not success or Weather.precip_kind() != "rain":
		return
	var f = SysUtil.folk(folk_id)
	if f == null:
		return
	if caught:
		WorldIface.add_coins(int(f.household_id), int(fe.get("rain_bonus_coins", 8)))
	elif SysUtil.chance(float(fe.get("rain_extra_catch_chance", 0.3))):
		WorldIface.add_coins(int(f.household_id), int(fe.get("extra_coins", 14)))
		f.add_buff("fresh_catch")
		SysUtil.game_event("caught_fish", {"folk_id": folk_id, "object_id": -1, "target_id": -1})
		Weather._caught.erase(folk_id)
