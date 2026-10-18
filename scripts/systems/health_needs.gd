class_name HealthNeeds
extends RefCounted
## Starvation and exhaustion. Per minute a person whose hunger (energy) sits at the very bottom adds a minute to `hunger_min` (`energy_min`);
## eating (sleeping) above the reset line clears it. Stages (all minutes scaled by the age-stage multiplier, so kids and elders suffer sooner):
##   warn_min     "faint with hunger": thought + toast, buff weak_hunger
##   collapse_min "Collapsed": cannot act; housemates help on their own, a doctor or the hospital also works
##   death_min    a small chance per hour; only the stages listed in death_stages can die (kids are taken to hospital instead)
## Also the neglect meter for toddlers, kids and elders (hook for task 07, see Health.register_neglect_hook).
## None of this uses Incidents dice or the Surprises setting.

static func tick(f, r: Dictionary, now: int) -> void:
	if str(f.age_stage) == "baby":
		return          # BabyCare owns babies
	var needs: Dictionary = Health.cfg("needs")
	var m: float = Health.stage_mult(f)
	for t in needs:
		_track(f, r, str(t), needs[t], m)
	_neglect(f, r, now)

static func _track(f, r: Dictionary, t: String, tc: Dictionary, m: float) -> void:
	var key: String = t + "_min"
	var v: float = f.get_stat_value(str(tc["stat"]))
	if v <= float(tc["floor"]):
		r[key] = float(r.get(key, 0.0)) + 1.0
	elif v > float(tc["reset"]):
		if float(r.get(key, 0.0)) > 0.0 or bool(r.get("w_" + t, false)):
			r[key] = 0.0
			r.erase("w_" + t)
			_clear_warn(f, tc)
	var mins: float = float(r.get(key, 0.0))
	if mins >= float(tc["warn_min"]) * m and not bool(r.get("w_" + t, false)):
		r["w_" + t] = true
		if str(tc.get("warn_buff", "")) != "":
			f.add_buff(str(tc["warn_buff"]))
		Health.think(f, str(tc.get("warn_key", t)))
		Health.tell(f, str(tc.get("warn_key", t)))
		Health.count("warn_" + t)
	if mins >= float(tc["collapse_min"]) * m and not Health.is_collapsed(f):
		HealthCollapse.collapse(f, str(tc.get("collapse_kind", t)))

static func _clear_warn(f, tc: Dictionary) -> void:
	if str(tc.get("warn_buff", "")) != "":
		f.remove_buff(str(tc["warn_buff"]))

## Once per game hour: the small chance of dying after the long threshold.
static func hourly(f, r: Dictionary) -> void:
	if str(f.age_stage) == "baby":
		return
	var needs: Dictionary = Health.cfg("needs")
	var m: float = Health.stage_mult(f)
	for t in needs:
		var tc: Dictionary = needs[t]
		var mins: float = float(r.get(str(t) + "_min", 0.0))
		if mins < float(tc["death_min"]) * m or not (tc.get("death_stages", []) as Array).has(str(f.age_stage)):
			continue
		var p: float = float(tc["death_per_hour"]) * float(Health.cfg("elder_death_mult").get(str(f.age_stage), 1.0))
		if Health.rng.randf() < p:
			Health.count("death_" + str(t))
			Aging.kill(int(f.id), str(tc["cause"]))
			return

## 0 fine .. 3 collapsed for each track (tests / UI).
static func stages(f, r: Dictionary) -> Dictionary:
	var out: Dictionary = {"hunger": 0, "energy": 0, "cold": 0, "heat": 0}
	var needs: Dictionary = Health.cfg("needs")
	var m: float = Health.stage_mult(f)
	for t in needs:
		var mins: float = float(r.get(str(t) + "_min", 0.0))
		var tc: Dictionary = needs[t]
		out[str(t)] = 3 if mins >= float(tc["collapse_min"]) * m else (2 if mins >= float(tc["warn_min"]) * m else (1 if mins > 0.0 else 0))
	for t2 in ["cold", "heat"]:
		out[t2] = HealthExposure.stage_index(f, r, t2)
	return out

# ------------------------------------------------------------------ neglect (toddlers, kids, elders)
static func _neglect(f, r: Dictionary, now: int) -> void:
	var nc: Dictionary = Health.cfg("neglect")
	if not (nc.get("stages", []) as Array).has(str(f.age_stage)):
		return
	var low: Array = []
	for n in nc.get("needs", []):
		if f.get_stat_value(str(n)) < float(nc.get("below", -60)):
			low.append(str(n))
	if not low.is_empty():
		r["neglect_min"] = float(r.get("neglect_min", 0.0)) + 1.0
	elif float(r.get("neglect_min", 0.0)) > 0.0:
		r["neglect_min"] = maxf(float(r["neglect_min"]) - float(nc.get("recover_per_min", 2.0)), 0.0)
	var mins: float = float(r.get("neglect_min", 0.0))
	if mins >= float(nc.get("warn_min", 480)) and not f.has_buff("neglected"):
		f.add_buff("neglected")
		Health.count("neglect")
		var info: Dictionary = {"kind": str(f.age_stage), "minutes": mins, "needs": low, "day": SysUtil.day(), "time": now}
		Health.tell(f, "neglected_" + ("elder" if str(f.age_stage) == "elder" else "child"))
		SysUtil.game_event("neglect_noticed", {"folk_id": int(f.id), "stage": str(f.age_stage), "needs": low, "minutes": mins})
		for cb in Health.neglect_hooks:
			if (cb as Callable).is_valid():
				(cb as Callable).call(f, info)
	elif mins < float(nc.get("warn_min", 480)) * 0.5 and f.has_buff("neglected"):
		f.remove_buff("neglected")
