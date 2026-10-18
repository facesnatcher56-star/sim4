class_name AccidentMarks
extends RefCounted
## Exposure markers for accidents (task 05). The incident dice only know conditions on buffs, so what a person is DOING is turned into
## short hidden marker buffs (acc_water, acc_eating, acc_repair_electric, acc_exercise, acc_on_road, acc_crosswalk, acc_slippery, acc_icy,
## acc_job_risky, acc_job_very_risky, acc_near_water, acc_near_road, acc_unsupervised, acc_alone) that the hourly incident check reads.
## Folk on the map: scanned every game minute from their current interaction, tile and company. Far townies: one hourly dice roll per
## marker (AccidentTownies) using the same marker names, so the SAME incident data drives both versions.
## Hooks (SystemsManager): on_minute(), on_hour(hour) BEFORE Incidents.on_hour(), after_hour() right AFTER it, on_interaction_finished(folk_id, iid, success).

const PREFIX := "acc_"

static func cfg() -> Dictionary:
	return IncidentDefs.cfg("accidents", {})

static func mark(f, buff: String) -> void:
	if f != null and not SimEnv.data().buff_def(buff).is_empty():
		f.add_buff(buff)          # re-adding refreshes the timer

static func unmark(f, buff: String) -> void:
	if f != null and f.has_buff(buff):
		f.remove_buff(buff)

static func _apply(f, buff: String, on: bool) -> void:
	if on:
		mark(f, buff)
	else:
		unmark(f, buff)

# ------------------------------------------------------------------ company
static func is_awake_here(f) -> bool:
	return f != null and not SysUtil.is_away(f) and not Hospital.is_in(f) and str(f.posture) != "lie" and str(f.age_stage) != "baby"

## Other people who could help right now (awake, same lot or the same street).
static func company(f, stages: Array = []) -> Array:
	var out: Array = []
	for o in WorldIface.folk_near(f):
		if int(o.id) == int(f.id) or not is_awake_here(o):
			continue
		if not stages.is_empty() and not stages.has(str(o.age_stage)):
			continue
		out.append(o)
	return out

static func helper_stages() -> Array:
	return cfg().get("helper_stages", ["teen", "adult", "elder"])

# ------------------------------------------------------------------ minute scan (Folk on the map)
static func on_minute() -> void:
	var c: Dictionary = cfg()
	if c.is_empty():
		return
	for f in WorldIface.all_folk():
		if Hospital.is_in(f) or str(f.age_stage) == "baby":
			continue
		_scan(f, c)
	AccidentRescue.on_minute()

static func _scan(f, c: Dictionary) -> void:
	if SysUtil.is_away(f):
		return                       # job markers are set only around the hourly dice (on_hour / after_hour), never while a save can see them
	var hour: float = SimEnv.hour_f()
	var ir = f.current
	if ir != null and str(ir.state) == "running":
		var iid: String = str(ir.def_id)
		if (c.get("water_interactions", []) as Array).has(iid):
			mark(f, "acc_water")
		elif iid.begins_with(str(c.get("eat_prefix", "eat_meal"))) or (c.get("eat_interactions", []) as Array).has(iid):
			mark(f, "acc_eating")
		elif (c.get("exercise_interactions", []) as Array).has(iid):
			mark(f, "acc_exercise")
			if ir.obj != null:
				f.set_meta("acc_exercise_obj", int(ir.obj.id))    # the interaction is already gone when it finishes
		elif (c.get("repair_interactions", []) as Array).has(iid) and ir.obj != null and _is_electric(ir.obj, c):
			mark(f, "acc_repair_electric")
	# the road
	var kind: String = Traffic.road_kind(f.tile)
	if kind != "":
		var risk: float = Traffic.risk_at(f.tile, hour)
		if risk > 0.0 and _u(f, 1) < risk:
			mark(f, "acc_on_road")
			if kind == "crosswalk":
				mark(f, "acc_crosswalk")
	if kind != "" or _on_floor(f.tile, "sidewalk"):
		mark(f, "acc_near_road")
	# slippery ground
	var outside: bool = WeatherFolk.is_outside(f)
	var icy: bool = outside and Weather.snow_cover() >= float(c.get("icy_snow_cover", 0.25))
	if icy or (outside and Weather.wetness() >= float(c.get("slippery_wetness", 0.5))) or _on_puddle(f.tile, c):
		mark(f, "acc_slippery")
	if icy:
		mark(f, "acc_icy")
	# next to water
	if _near_water(f, c):
		mark(f, "acc_near_water")
	# company: states, kept fresh (they are short-lived buffs)
	var adults: int = company(f, ["adult", "elder"]).size()
	_apply(f, "acc_unsupervised", adults == 0 and (str(f.age_stage) == "child" or str(f.age_stage) == "toddler"))
	_apply(f, "acc_alone", company(f).is_empty())

static func _is_electric(obj, c: Dictionary) -> bool:
	var tags: Array = SimEnv.data().object_def(str(obj.def_id)).get("tags", [])
	for t in (c.get("electric_tags", ["electronics", "appliance"]) as Array):
		if tags.has(t):
			return true
	return false

static func _floor_at(tile: Vector2i) -> String:
	if Traffic.test_floors.has(tile):
		return str(Traffic.test_floors[tile])
	var w = WorldIface.world()
	return str(w.get_floor(tile)) if w != null and w.has_method("get_floor") else ""

static func _on_floor(tile: Vector2i, floor_name: String) -> bool:
	return _floor_at(tile) == floor_name

static func _on_puddle(tile: Vector2i, c: Dictionary) -> bool:
	var w = WorldIface.world()
	if w != null and "mess" in w and (w.mess as Dictionary).has(tile):
		return float(w.mess[tile]) >= float(c.get("puddle_mess", 0.3))
	return false

static func _near_water(f, c: Dictionary) -> bool:
	var r: int = int(c.get("near_water_tiles", 4))
	for o in WorldIface.objects_near(f.tile, r):
		if (c.get("water_objects", []) as Array).has(str(o.def_id)) and Vector2(o.tile - f.tile).length() <= float(r):
			return true
	return false

## Deterministic 0..1 value for (folk, salt, this minute): no extra rng state to save.
static func _u(f, salt: int) -> float:
	return float(hash([int(f.id), salt, SysUtil.now()]) & 0xFFFFF) / 1048576.0

# ------------------------------------------------------------------ hourly
## Before the hourly dice: people away at a physical job are exposed, far townies get their markers.
static func on_hour(hour: int) -> void:
	var c: Dictionary = cfg()
	if c.is_empty():
		return
	for f in WorldIface.all_folk():
		if SysUtil.is_away(f) and str(Away.info(int(f.id)).get("reason", "")) == "work":
			var tier: int = int((c.get("physical_careers", {}) as Dictionary).get(Careers.career_of(int(f.id)), 0))
			if tier >= 1:
				mark(f, "acc_job_risky")
			if tier >= 2:
				mark(f, "acc_job_very_risky")
	AccidentTownies.on_hour(hour)

## Right after the hourly dice: the job markers go again (an away person's buff order must not change under a save).
static func after_hour() -> void:
	for f in WorldIface.all_folk():
		unmark(f, "acc_job_risky")
		unmark(f, "acc_job_very_risky")

# ------------------------------------------------------------------ interaction finished: a treadmill that gives way
static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	var c: Dictionary = cfg()
	if c.is_empty() or not success or not (c.get("exercise_interactions", []) as Array).has(iid):
		return
	var f = SysUtil.folk(folk_id)
	if f == null or not f.has_meta("acc_exercise_obj"):
		return
	var obj = WorldIface.get_object(int(f.get_meta("acc_exercise_obj")))
	f.remove_meta("acc_exercise_obj")
	if obj != null and str(obj.def_id) == "treadmill" and bool(WorldIface.state_get(obj, "broken", false)):
		Incidents.force("treadmill_gives_way", {"folk_id": folk_id})
