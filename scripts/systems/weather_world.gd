class_name WeatherWorld
extends RefCounted
## Hourly/daily weather effects on objects, puddles, lightning and fishing.

# ------------------------------------------------------------------ hourly tick
static func _hour_rng(salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = Weather._mix(Weather.seed_value + salt, SimEnv.now_min())
	return r

static func on_hour(_hour: int) -> void:
	WeatherContent.install()
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
	_hourly_objects(cur, kind, e)
	_puddle_tick(kind, e)
	if cur == "thunderstorm":
		_lightning(e)
	_cozy(kind, e)

static func _objects() -> Array:
	return SysUtil.all_world_objects()

static func _def_of(o) -> Dictionary:
	return SimEnv.data().object_def(str(o.def_id))

static func _hourly_objects(cur: String, kind: String, e: Dictionary) -> void:
	if kind != "rain":
		return
	var g: Dictionary = e.get("garden", {})
	var w = WorldIface.world()
	var can_out: bool = w != null and w.has_method("is_outdoor")
	for o in _objects():
		var d: Dictionary = _def_of(o)
		var tags: Array = d.get("tags", [])
		var key: String = ""
		var amt: float = 0.0
		if str(o.def_id) == "garden_plot":
			key = "water"
			amt = float(g.get("rain_water_per_hour", 0.6))
		elif tags.has("plant") and can_out and bool(w.is_outdoor(o.tile, int(o.level))) and (d.get("state", {}) as Dictionary).has("water"):
			key = "water"
			amt = float(g.get("plant_rain_water_per_hour", 0.8))
		if key != "":
			WorldIface.state_add(o, key, amt)

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
	for o in _objects():
		var tags: Array = _def_of(o).get("tags", [])
		for t in l.get("break_tags", ["electronics"]):
			if tags.has(t) and not bool(WorldIface.state_get(o, "broken", false)):
				cands.append(o)
				break
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
static func on_day(day: int) -> void:
	var e: Dictionary = Weather.effects()
	var g: Dictionary = e.get("garden", {})
	var frost: bool = Weather._min_today < float(e.get("frost_temp", 0.0)) and bool(g.get("frost_kills", true))
	var mult: float = Weather.crop_growth_mult()
	var killed: int = 0
	for o in _objects():
		if str(o.def_id) != "garden_plot":
			continue
		var spec: Dictionary = ((_def_of(o).get("state", {}) as Dictionary).get("growth", {}) as Dictionary)
		var growth: float = float(WorldIface.state_get(o, "growth", 0.0))
		if Weather._heat_hours >= 4.0:
			WorldIface.state_add(o, "water", -float(g.get("heat_extra_dry", 1.0)))
		if frost:
			if growth > 0.0:
				WorldIface.state_set(o, "growth", 0.0)
				killed += 1
		elif mult > 1.0 and float(WorldIface.state_get(o, "water", 0.0)) >= 2.0:
			WorldIface.state_add(o, "growth", float(spec.get("daily_add", 2.0)) * (mult - 1.0))
	if killed > 0:
		SysUtil.notify("A hard frost killed the crops!", "warn")
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
