class_name CrimeRate
extends RefCounted
## Task 09c section 7: the town CRIME RATE (0..100), recomputed every day from recent crimes (weighted by seriousness, per head of population),
## poverty, unemployment and police presence. Lowered by police officers (career), street lamps, a neighbourhood watch (community event) and jobs.
##   crime_mult()   0.6 .. 1.8  scales desperate-crime odds (CrimePressure) and lets burglars give up more often when the town is safe
##   value_mult()   1.0 .. 0.8  property values drop when the rate is above 50 (Economy.lot_value uses it)
## Effects on people: above 55 folk feel "Uneasy at night". Every season (7 days) the Chronicle says whether crime rose or fell, with streaks
## ("Crime falls for the third season"), which the newspaper (task 08) prints.

static func cfg() -> Dictionary:
	return JusticeState.sect("rate")

static func weights() -> Dictionary:
	return cfg().get("weights", {})

## Recent crime points: the case log of the last `window` days.
static func recent_points() -> float:
	var k: Dictionary = cfg()
	var w: Dictionary = weights()
	var pts: float = 0.0
	var window: int = int(k.get("window_days", 28))
	for e in JusticeState.year_log:
		if SysUtil.day() - int(e.get("day", 0)) <= window:
			pts += float(w.get(str(e.get("kind", "")), 1.0))
	return pts

static func components() -> Dictionary:
	var k: Dictionary = cfg()
	var pop: Array = CrimePerson.townies_only()
	for f in SysUtil.residents():
		pop.append(int(f.id))
	var n: int = maxi(pop.size(), 6)
	var poor: int = 0
	var adults: int = 0
	var jobless: int = 0
	for p in pop:
		if CrimePerson.coins(int(p)) < 150:
			poor += 1
		if CrimePerson.is_adult(int(p)) and CrimePerson.stage(int(p)) != "elder":
			adults += 1
			if not CrimePerson.has_job(int(p)):
				jobless += 1
	var lamps: int = 0
	for o in SysUtil.all_world_objects():
		if str(o.def_id) in ["streetlamp", "street_lamp"]:
			lamps += 1
	var c: Dictionary = {
		"crimes": recent_points() / float(n) * float(k.get("crime_scale", 30.0)),
		"poverty": float(poor) / float(n) * float(k.get("poverty_scale", 20.0)),
		"jobless": float(jobless) / float(maxi(adults, 1)) * float(k.get("jobless_scale", 25.0)),
		"police": -minf(float(Police.officers()) * float(k.get("per_officer", 6.0)), float(k.get("police_cap", 20.0))),
		"lamps": -minf(float(lamps) * float(k.get("per_lamp", 1.5)), float(k.get("lamp_cap", 12.0))),
		"watch": -float(k.get("watch", 12.0)) if watch_active() else 0.0,
		"budget": -(CityBudget.funding("police") - 1.0) * 10.0 - (CityBudget.funding("parks") - 1.0) * 3.0,        # task 12: a funded police service and well kept parks lower crime
		"base": float(k.get("base", 8.0))}
	return c

static func compute() -> float:
	var total: float = 0.0
	var c: Dictionary = components()
	for key in c:
		total += float(c[key])
	return clampf(total, 0.0, 100.0)

static func value() -> float:
	return JusticeState.rate_now

static func crime_mult() -> float:
	return clampf(0.6 + JusticeState.rate_now / 60.0, 0.6, 1.8)

static func value_mult() -> float:
	if JusticeState.rate_now <= 50.0:
		return 1.0
	return clampf(1.0 - (JusticeState.rate_now - 50.0) / 250.0, 0.8, 1.0)

static func label() -> String:
	var r: float = JusticeState.rate_now
	if r < 20.0:
		return "Very safe"
	if r < 40.0:
		return "Safe"
	if r < 60.0:
		return "Uneasy"
	if r < 80.0:
		return "Dangerous"
	return "Lawless"

# ------------------------------------------------------------------ neighbourhood watch
static func watch_active() -> bool:
	return JusticeState.watch_until >= SysUtil.day()

static func start_watch(by: int = -1) -> void:
	JusticeState.watch_until = SysUtil.day() + int(cfg().get("watch_days", 28))
	var text: String = "A neighbourhood watch has started%s." % ((" - organised by %s" % CrimePerson.name_of(by)) if by >= 0 else "")
	ChronicleHook.note("watch", text, [by] if by >= 0 else [], "", 2, true)
	if by >= 0 and CrimePerson.is_player(by):
		SysUtil.notify(text, "story")

# ------------------------------------------------------------------ daily
static func on_day() -> void:
	JusticeState.rate_now = compute()
	var k: Dictionary = cfg()
	if JusticeState.rate_now >= float(k.get("uneasy_at", 55.0)):
		for r in SysUtil.residents():
			if JusticeState.chance((JusticeState.rate_now - 50.0) / 100.0):
				r.add_buff("uneasy_at_night")
	# sociable townies start a watch when things get bad
	if JusticeState.rate_now >= float(k.get("watch_trigger", 55.0)) and not watch_active():
		var social: Array = CrimePerson.townies_only().filter(func(p): return CrimePerson.has_trait(int(p), "social") or CrimePerson.has_trait(int(p), "generous") or CrimePerson.has_trait(int(p), "active"))
		if not social.is_empty() and JusticeState.chance(float(k.get("watch_daily", 0.05))):
			start_watch(int(social[0]))
	if SysUtil.day() % int(k.get("season_days", 7)) == 0:
		season_report()

## One line per season in the Chronicle, with streaks.
static func season_report() -> void:
	var now: float = JusticeState.rate_now
	var hist: Array = JusticeState.rate_hist
	var last: float = float(hist[hist.size() - 1]["rate"]) if not hist.is_empty() else now
	var streak: int = int(hist[hist.size() - 1].get("streak", 0)) if not hist.is_empty() else 0
	var dir: int = 0
	if now < last - 2.0:
		dir = -1
	elif now > last + 2.0:
		dir = 1
	var prev_dir: int = int(hist[hist.size() - 1].get("dir", 0)) if not hist.is_empty() else 0
	streak = streak + 1 if (dir != 0 and dir == prev_dir) else (1 if dir != 0 else 0)
	hist.append({"day": SysUtil.day(), "rate": now, "dir": dir, "streak": streak})
	while hist.size() > 40:
		hist.pop_front()
	JusticeState.rate_hist = hist
	if dir == 0:
		return
	var ord: String = ["", "", "second", "third", "fourth", "fifth"][mini(maxi(streak, 1), 5)]
	var text: String
	if dir < 0:
		text = "Crime falls%s." % ((" for the %s season" % ord) if streak >= 2 else " this season")
	else:
		text = "Crime rises%s." % ((" for the %s season in a row" % ord) if streak >= 2 else " this season")
	ChronicleHook.note("crime_rate", text, [], "", 2, true)
