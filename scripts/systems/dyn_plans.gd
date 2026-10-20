class_name DynPlans
extends RefCounted
## Task 32c: small spontaneous plans (a stroll, ringing a friend, cooking something special, gardening, a creative itch, a tidy-up, a lazy spell ...).
## Once an hour each awake resident rolls stateless dice against data/dynamic_life.json `plans` (hours, weekend, stage, traits, mood, how empty a need
## is). A plan is a buff whose autonomy_mult steers Autonomy toward it (the folk still picks the nearest fix of any urgent need first) and may
## queue something at once (a stroll = real walks around the lot, a call to a friend = a phone interaction that rings someone for real).

static func _mood_factor(f, table: Dictionary) -> float:
	return float(table.get(str(f.mood_name), 1.0))

static func _need_factor(f, table: Dictionary) -> float:
	var m := 1.0
	for n in table:
		var st: Variant = f.needs.get(n, null)
		if st != null:
			var x: float = clampf((st.max - st.value) / maxf(st.max - st.min, 1.0), 0.0, 1.0)
			m *= 1.0 + float(table[n]) * x
	return m

## Chance of plan `p` for `f` this hour (0 = not now).
static func chance_of(f, p: Dictionary) -> float:
	var stage_f: float = float((p.get("stages", {}) as Dictionary).get(str(f.age_stage), 0.0))
	if stage_f <= 0.0 or not DynLife.in_hours(p.get("hours", []), SysUtil.hour_f()):
		return 0.0
	var c: float = float(p.get("chance", 0.0)) * stage_f
	if DynLife.is_weekend():
		c *= float(p.get("weekend_mult", 1.0))
	c *= DynLife.trait_factor(f, p.get("traits", {})) * _mood_factor(f, p.get("moods", {})) * _need_factor(f, p.get("needs", {}))
	return c

static func has_object(f, wanted: Array) -> bool:
	for o in WorldIface.objects_for(f, 30):
		var id := str(o.def_id)
		if wanted.has(id):
			return true
		for t in SimEnv.data().object_def(id).get("tags", []):
			if wanted.has(t):
				return true
	return false

static func bad_weather() -> bool:
	return Weather.is_precipitating() or Weather.severity() >= 5

## Roll the day's plans for one resident; at most one plan per hour and a pause of min_gap_hours between plans.
static func roll(f, abs_hour: int) -> void:
	var c: Dictionary = DynLife.cfg()
	var key := "dyn:plan"
	if SimEnv.now_min() < int(f.cooldowns.get(key, -1)):
		return
	for n in f.needs:
		if Autonomy.urgency(f, str(n)) > 5.0:
			return                      # a pressing need comes first: no plans for now
	var plans: Dictionary = c.get("plans", {})
	var i := 0
	var far: bool = Tiers.of(f) > Tiers.NEAR
	for pid in plans:
		i += 1
		var p: Dictionary = plans[pid]
		if p.has("buff") and f.has_buff(str(p["buff"])):
			continue
		var prob := chance_of(f, p)
		if prob <= 0.0 or DynLife.dice(int(f.id), abs_hour, i) >= prob:
			continue
		if far:
			_statistical(f, p, key, c)
			return
		if bool(p.get("outdoor", false)) and bad_weather():
			continue
		if p.has("needs_object") and not has_object(f, p["needs_object"]):
			continue
		if bool(p.get("needs_contact", false)) and contact_for(f) < 0:
			continue
		_start(f, str(pid), p, key, c)
		return

static func _start(f, pid: String, p: Dictionary, key: String, c: Dictionary) -> void:
	f.cooldowns[key] = SimEnv.now_min() + int(float(c.get("min_gap_hours", 3)) * 60.0)
	if p.has("buff"):
		f.add_buff(str(p["buff"]))
	for iid in p.get("queue", []):
		if str(iid) == "stroll":
			stroll(f)
		else:
			DynLife.queue(f, str(iid))
	SysUtil.game_event("dyn_plan", {"folk_id": int(f.id), "plan": pid})

## A resident who is not simulated minute by minute: the plan only nudges their needs.
static func _statistical(f, p: Dictionary, key: String, c: Dictionary) -> void:
	f.cooldowns[key] = SimEnv.now_min() + int(float(c.get("min_gap_hours", 3)) * 60.0)
	var so: Dictionary = p.get("stat_off", {})
	for n in so:
		f.add_to_stat(str(n), float(so[n]))

## A short walk: a couple of real stops on or around the lot, then a breath of air.
static func stroll(f) -> bool:
	var sc: Dictionary = DynLife.cfg().get("stroll", {})
	var w = WorldIface.world()
	var real: bool = WorldIface.stub == null and w != null and w.has_method("is_outdoor")
	var lot: String = Neighborhood.lot_of(f) if real else ""
	var rect := Rect2i(f.tile - Vector2i(12, 12), Vector2i(24, 24))
	if lot != "":
		rect = NeighborhoodLots.rect_of(lot)
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(Storyteller.master_seed), int(f.id), SimEnv.now_min()])
	var stops := 0
	var from: Vector2i = f.tile
	for _t in int(sc.get("tries", 14)):
		if stops >= int(sc.get("stops", 2)) or rect.size.x <= 0 or rect.size.y <= 0:
			break
		var t := Vector2i(rect.position.x + r.randi() % rect.size.x, rect.position.y + r.randi() % rect.size.y)
		if real and not w.is_outdoor(t, 0):
			continue
		var d: int = WorldIface.path_length(from, t)
		if d < int(sc.get("min_tiles", 4)) or d > int(sc.get("max_tiles", 22)):
			continue
		var ir := Interaction.create_goto(f, t, false)
		if ir != null:
			f.enqueue(ir)
			from = t
			stops += 1
	if stops == 0:
		return false
	DynLife.queue(f, "enjoy_the_air")
	return true

## A friend to ring: the best-liked known person who can be reached and was not rung today (-1 = nobody).
static func contact_for(f) -> int:
	for row in PhoneCmd.contacts(int(f.id), 14):
		if str(row["reason"]) == "" and float(row["friendship"]) >= 15.0 and PhoneState.today_count(int(f.id), int(row["id"]), "calls") < 1:
			return int(row["id"])
	return -1

## The call interaction ended: the phone call really happens (friendship, social, a short line for the player).
static func finish_call(folk_id: int) -> void:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return
	var other := contact_for(f)
	if other >= 0:
		PhoneCmd.call_person(folk_id, other)
