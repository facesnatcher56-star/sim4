class_name HealthExposure
extends RefCounted
## Hypothermia and heatstroke. Minutes OUTSIDE in freezing (hot) weather build `cold_min` (`heat_min`); being indoors drains them quickly.
## Stages (minutes scaled by the age-stage multiplier): shivering / overheating -> hypothermia / heat exhaustion (sick) -> collapsed ->
## a small chance per hour of dying. Counterplay: warm clothes (buff bundled_up: builds 60 percent slower), a drink of water (cooled_down),
## shelter, a rescue by a housemate or a doctor. Weather comes from Weather.feels_like(); "outside" from WeatherFolk.is_outside().

static func _tc(t: String) -> Dictionary:
	return Health.cfg("exposure").get(t, {})

static func stage_min(t: String, index: int) -> float:
	var st: Array = _tc(t).get("stages", [])
	return float((st[clampi(index - 1, 0, st.size() - 1)] as Dictionary).get("min", 0)) if not st.is_empty() else 0.0

## 0 none, 1 shivering, 2 sick, 3 collapsed.
static func stage_index(f, r: Dictionary, t: String) -> int:
	var mins: float = float(r.get(t + "_min", 0.0))
	var m: float = Health.stage_mult(f)
	var idx: int = 0
	var st: Array = _tc(t).get("stages", [])
	for i in st.size():
		if mins >= float((st[i] as Dictionary)["min"]) * m:
			idx = i + 1
	return idx

static func tick(f, r: Dictionary, now: int) -> void:
	if str(f.age_stage) == "baby":
		return
	var outside: bool = WeatherFolk.is_outside(f)
	var feels: float = Weather.feels_like()
	var m: float = Health.stage_mult(f)
	for t in ["cold", "heat"]:
		var tc: Dictionary = _tc(t)
		if tc.is_empty():
			continue
		var key: String = t + "_min"
		var cur: float = float(r.get(key, 0.0))
		var delta: float = 0.0
		if outside:
			delta = _build(f, t, tc, feels)
			if t == "cold" and delta > 0.0:
				HealthShelter.check(f, r, now)
		elif cur > 0.0:
			delta = -float(tc.get("indoor_recover", 3.0))
			if t == "cold" and cur + delta <= 0.0:
				HealthShelter.warm(r)
		if cur > 0.0 or delta > 0.0:
			cur = maxf(cur + delta, 0.0)
			r[key] = cur
			_apply_stages(f, r, t, tc, cur, m)

static func _build(f, t: String, tc: Dictionary, feels: float) -> float:
	if t == "cold":
		if feels >= float(tc["below"]):
			return -float(tc.get("outdoor_recover", 1.0))
		var d: float = 2.0 if feels < float(tc.get("hard_below", -9.0)) else 1.0
		return d * (float(tc.get("coat_mult", 0.4)) if f.has_buff("bundled_up") else 1.0)
	if feels <= float(tc["above"]):
		return -float(tc.get("outdoor_recover", 1.0))
	var d2: float = 2.0 if feels > float(tc.get("hard_above", 38.0)) else 1.0
	return d2 * (float(tc.get("water_mult", 0.5)) if f.has_buff("cooled_down") else 1.0)

static func _apply_stages(f, r: Dictionary, t: String, tc: Dictionary, cur: float, m: float) -> void:
	for st in tc.get("stages", []):
		var smin: float = float(st["min"]) * m
		var buff: String = str(st.get("buff", ""))
		if cur >= smin:
			if str(st.get("collapse", "")) != "":
				if not Health.is_collapsed(f):
					HealthCollapse.collapse(f, str(st["collapse"]))
			elif buff != "" and not f.has_buff(buff):
				f.add_buff(buff)
				Health.think(f, buff)
				Health.tell(f, buff, "bad" if bool(st.get("sick", false)) else "warn")
				Health.count("stage_" + buff)
				if bool(st.get("sick", false)):
					HealthIllness.mark_sick(f, float(tc.get("sick_hours", 6.0)))
		elif buff != "" and cur < smin * 0.5 and f.has_buff(buff):
			f.remove_buff(buff)

## Once per game hour: the small chance of dying after the long threshold.
static func hourly(f, r: Dictionary) -> void:
	if str(f.age_stage) == "baby":
		return
	var m: float = Health.stage_mult(f)
	for t in ["cold", "heat"]:
		var tc: Dictionary = _tc(t)
		if tc.is_empty():
			continue
		var cur: float = float(r.get(t + "_min", 0.0))
		if cur < stage_min(t, 1) * m * 0.5:
			_sweep(f, tc)
		if cur < float(tc["death_min"]) * m:
			continue
		if not (tc.get("death_stages", []) as Array).has(str(f.age_stage)):
			continue
		if Health.rng.randf() < float(tc["death_per_hour"]) * float(Health.cfg("elder_death_mult").get(str(f.age_stage), 1.0)):
			Health.count("death_" + t)
			Aging.kill(int(f.id), str(tc["cause"]))
			return

## Stage buffs have no timer: only the minute tick clears them, and only while the counter is above zero. A record that was pruned (the person
## was out of the world for a while) or reset leaves the buff on for ever otherwise: "shivering" at uncomfortable 3 colours every mood for
## months. Once an hour anyone wearing a stage buff with the counter back near zero loses it.
static func _sweep(f, tc: Dictionary) -> void:
	for st in tc.get("stages", []):
		var buff: String = str(st.get("buff", ""))
		if buff != "" and f.has_buff(buff):
			f.remove_buff(buff)

## A drink of water (interaction drink_water): takes the edge off the heat.
static func cool_down(f) -> void:
	var r: Dictionary = Health.rec_of(int(f.id))
	r["heat_min"] = maxf(float(r.get("heat_min", 0.0)) - float(_tc("heat").get("water_relief_min", 120.0)), 0.0)
	f.add_buff("cooled_down")
