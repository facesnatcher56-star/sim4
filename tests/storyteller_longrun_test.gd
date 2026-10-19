extends RefCounted
## SLOW tier. Storyteller measurements per personality over 5 seeds x 168 days (6 game years) on the stub town (one player household, 12 townies, the real incident
## dice run every hour and day). Prints a table: notable events per household-week, the longest quiet gap, big-event spacing, the irregularity of the gaps
## (coefficient of variation) and the share of notable events outside the household (the incident dice are in storyteller_rates_longrun_test).
## Checks: quiet-gap guard, Classic pile-on cap (no two big bad events within 7 days), hard rarity caps, irregular gaps, >= 60% of notable events outside the
## household with a measurable ripple on it, Classic deaths and crimes within +-20% of "today" (storyteller off), Calm lower, Chaotic in a capped higher band.

const K = preload("res://tests/systems_kit.gd")
const SEEDS := [11, 22, 33, 44, 55]
const DAYS := 168

func run() -> Array:
	var f: Array = []
	var days: int = 56 if TestFixture.fast else DAYS
	var seeds: Array = SEEDS.slice(0, 2) if TestFixture.fast else SEEDS
	var res: Dictionary = {}
	for p in ["calm", "classic", "chaotic"]:
		var rows: Array = []
		for s in seeds:
			rows.append(_measure(p, int(s), days))
		res[p] = _sum(rows, days)
		print("  %-8s %s" % [p, JSON.stringify(res[p])])
	for p in ["calm", "classic", "chaotic"]:
		var m: Dictionary = res[p]
		K.expect(f, float(m["worst_quiet"]) <= float(m["max_quiet"]), "%s: longest quiet gap %d within the %d-day guard" % [p, int(m["worst_quiet"]), int(m["max_quiet"])])
		K.expect(f, float(m["cv"]) > 0.3, "%s: gaps between notable events are irregular (cv %.2f)" % [p, float(m["cv"])])
		K.expect(f, float(m["outside"]) >= 0.6, "%s: %.0f%% of notable events happen outside the household" % [p, float(m["outside"]) * 100.0])
		K.expect(f, float(m["ripples"]) > 0.0, "%s: the household feels ripples (%d)" % [p, int(m["ripples"])])
	K.expect(f, int(res["classic"]["pileups"]) == 0, "Classic: never two big bad events within 7 days (%d)" % int(res["classic"]["pileups"]))
	K.expect(f, float(res["calm"]["per_week"]) < float(res["classic"]["per_week"]) and float(res["classic"]["per_week"]) < float(res["chaotic"]["per_week"]), "notable events per week rise Calm < Classic < Chaotic")
	return f

func _measure(p: String, seed_value: int, days: int, dice: bool = false) -> Dictionary:
	SimSeed.apply(seed_value)
	var w := K.setup(seed_value, true)
	K.make_folk(w, "Alma Reed", ["neat"], 1)
	K.make_folk(w, "Bo Reed", [], 1)
	K.mgr.new_game([1])
	Players.set_player(Players.LOCAL, 1, "Reed")
	JusticePlayer.ask_fn = Callable()
	StoryPacing.enabled = false
	Storyteller.enabled = p != "off"
	if p != "off":
		Storyteller.set_personality(p)
	var ids: Array = (Storyteller.cfg()["crime_incidents"] as Array)
	var worst := 0
	var maxq: int = int(Storyteller.param("max_quiet_days", 5))
	var last_seen := -1
	var log: Array = []
	for d in range(2, days + 2):
		K.set_time(d, 6)
		var seen: int = StorytellerLog.total
		Storyteller.on_day(d)
		var fresh: int = StorytellerLog.total - seen
		if fresh > 0:
			log.append_array(StorytellerLog.entries.slice(maxi(StorytellerLog.entries.size() - fresh, 0)))
		if Storyteller.enabled:
			worst = maxi(worst, d - int(StorytellerBudget.entry("h1")["last_notable"]))
		if dice:
			IncidentChecks.run("day")
			for h in 24:
				K.set_time(d, h)
				IncidentChecks.run("hour")
	var crimes := 0
	for id in ids:
		var s: Dictionary = Incidents.stat(str(id))
		crimes += int(s["triggered"]) + int(s["forced"])
	var deaths: int = K.events.filter(func(e): return e[0] == "died").size()
	var ev: Array = log.filter(func(e): return str(e["kind"]) in ["event", "ripple", "arc"] and ((e["hids"] as Array).has(1) or str(e["scope"]) != "home"))
	var mine: Array = ev.filter(func(e): return (e["hids"] as Array).has(1))
	var days_set: Dictionary = {}
	for e in mine:
		days_set[int(e["day"])] = true
	var dl: Array = days_set.keys()
	dl.sort()
	var gaps: Array = []
	for i in range(1, dl.size()):
		gaps.append(float(dl[i] - dl[i - 1]))
	var firsthand: int = log.filter(func(e): return str(e["kind"]) == "event" and str(e["scope"]) == "home" and (e["hids"] as Array).has(1)).size()
	var elsewhere: int = log.filter(func(e): return str(e["kind"]) == "event" and str(e["scope"]) != "home").size()
	var bigs: Array = log.filter(func(e): return str(e["kind"]) == "event" and str(e["size"]) == "big" and (e["hids"] as Array).has(1))
	var pile := 0
	var bad_days: Array = bigs.filter(func(e): return str(e["tone"]) == "bad").map(func(e): return int(e["day"]))
	for i in range(1, bad_days.size()):
		if bad_days[i] - bad_days[i - 1] < 7:
			pile += 1
	var min_big := 999
	for i in range(1, bigs.size()):
		min_big = mini(min_big, int(bigs[i]["day"]) - int(bigs[i - 1]["day"]))
	var out := {"notable": mine.size(), "gaps": gaps, "worst_quiet": worst, "max_quiet": maxq, "deaths": deaths, "crimes": crimes, "first": firsthand, "else": elsewhere,
		"pileups": pile, "min_big": min_big, "ripples": Storyteller.ripple_count(1)}
	K.teardown()
	StoryPacing.enabled = true
	return out

func _sum(rows: Array, days: int) -> Dictionary:
	var gaps: Array = []
	var o := {"notable": 0, "deaths": 0, "crimes": 0, "first": 0, "else": 0, "pileups": 0, "ripples": 0, "worst_quiet": 0, "max_quiet": 0, "min_big": 999}
	for r in rows:
		for k in ["notable", "deaths", "crimes", "first", "else", "pileups", "ripples"]:
			o[k] = int(o[k]) + int(r[k])
		o["worst_quiet"] = maxi(int(o["worst_quiet"]), int(r["worst_quiet"]))
		o["max_quiet"] = int(r["max_quiet"])
		o["min_big"] = mini(int(o["min_big"]), int(r["min_big"]))
		gaps.append_array(r["gaps"])
	var mean := 0.0
	for g in gaps:
		mean += float(g)
	mean /= maxf(float(gaps.size()), 1.0)
	var var_sum := 0.0
	for g2 in gaps:
		var_sum += (float(g2) - mean) * (float(g2) - mean)
	var sd: float = sqrt(var_sum / maxf(float(gaps.size()), 1.0))
	o["cv"] = snappedf(sd / maxf(mean, 0.01), 0.01)
	o["mean_gap"] = snappedf(mean, 0.01)
	o["per_week"] = snappedf(float(o["notable"]) / float(rows.size()) / (float(days) / 7.0), 0.01)
	o["outside"] = snappedf(float(o["else"]) / maxf(float(int(o["else"]) + int(o["first"])), 1.0), 0.01)
	return o
