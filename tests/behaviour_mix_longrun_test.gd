extends RefCounted
## Task 32c on the REAL map (SLOW tier): one household nobody plays, the same days with DynLife (plans, reactions, household initiative, idle life) off and on.
## With it on, per folk per day the mix has at least 8 different interactions, no interaction more than 4 times outside the needs, and under 10% of the
## awake time is spent with nothing to do; home life is not swamped (share of waking time at home) and work / school attendance and needs are not hurt.

const Kit = preload("res://tests/hood_kit.gd")
const Mix = preload("res://tests/behaviour_mix_kit.gd")
const DAYS := 4
const SEED := 4343

func _play(on: bool) -> Dictionary:
	Kit.teardown()
	SimSeed.apply(SEED)
	var folk: Array = Kit.new_game("classic", SEED, SEED)
	var mira = folk[0]
	var wren = folk[2]
	Aging.set_age_days(mira, 90.0)
	Aging.set_age_days(folk[1], 90.0)
	Aging.set_age_days(wren, 62.0)
	Careers.hire(mira, "coder", 1)
	Careers.enroll_school()
	WorldIface.coins[1] = 3000
	DynLife.off = not on
	var cap_before: Variant = AutonomyVariety.cfg().get("daily_cap", 0)
	var kept_routines: Dictionary = {}
	if not on:                              # the old game: no dynamic content, no daily cap
		AutonomyVariety.cfg()["daily_cap"] = 0
		for iid in SimEnv.data().get_table("content_dynamic").get("interactions", {}):
			SimEnv.data().interactions().erase(iid)
		for rid in SimEnv.data().routines().keys():
			for pre in ["weekend_", "weekday_", "after_school", "school_holiday", "mood_", "night_owl_evening", "early_bird_morning"]:
				if str(rid).begins_with(pre):
					kept_routines[rid] = SimEnv.data().routines()[rid]
					SimEnv.data().routines().erase(rid)
	var mix = Mix.new()
	mix.watch(folk)
	Kit.set_time(1, 6)
	var home_n := 0
	var seen_n := 0
	var worst := 1000.0
	var low_n := 0
	var all_n := 0
	var worst_who := ""
	var worst_trace := ""
	for i in DAYS * 1440:
		Kit.run(1)
		mix.sample()
		if i % 15 == 0:
			var h: float = SysUtil.hour_f()
			for f in folk:
				all_n += 1
				var low := false
				for n in ["hunger", "energy", "bladder", "hygiene"]:
					var v: float = f.get_stat_value(n)
					low = low or v < -60.0
					if v < worst:
						worst = v
						worst_trace = str(mix.recent.get(f.id, []))
						worst_who = "%s %s day %d %02d:%02d at %s doing %s" % [f.name, n, SysUtil.day(), int(h), int(fposmod(h, 1.0) * 60.0), Neighborhood.lot_of(f), str(f.current.def_id) if f.current != null else "-"]
				if low:
					low_n += 1
				if h >= 7.0 and h < 22.0 and not SysUtil.is_away(f):
					seen_n += 1
					if Neighborhood.lot_of(f) == PlayerLots.home_of(f):
						home_n += 1
	mix.unwatch()
	var missed := 0
	var school_missed := 0
	for e in Kit.events:
		if e[0] == "returned_from_work" and bool(e[1].get("skipped", false)):
			missed += 1
		if e[0] == "late_for_work" or e[0] == "missed_shift":
			missed += 1
		if e[0] == "returned_from_school" and bool(e[1].get("skipped", false)):
			school_missed += 1
	var out := {"low": float(low_n) / maxf(float(all_n), 1.0), "home": float(home_n) / maxf(float(seen_n), 1.0), "worst": worst, "worst_who": worst_who, "trace": worst_trace, "missed": missed, "school_missed": school_missed, "rows": [], "plans": Kit.count_events("dyn_plan"), "house": Kit.count_events("dyn_household")}
	for p in folk:
		for d in range(1, DAYS + 1):
			var s: Dictionary = mix.day_summary(p.id, d)
			out["rows"].append("%s d%d: %d kinds, most %s x%d" % [p.name, d, s["distinct"], s["worst_iid"], s["worst_repeat"]])
			out["min_kinds"] = mini(int(out.get("min_kinds", 999)), int(s["distinct"]))
			out["max_repeat"] = maxi(int(out.get("max_repeat", 0)), int(s["worst_repeat"]))
		out["idle_" + str(p.name)] = mix.idle_share(p.id)
		out["idle_max"] = maxf(float(out.get("idle_max", 0.0)), mix.idle_share(p.id))
	Kit.teardown()
	DynLife.off = false
	AutonomyVariety.cfg()["daily_cap"] = cap_before
	for rid in kept_routines:
		SimEnv.data().routines()[rid] = kept_routines[rid]
	return out

func run() -> Array:
	var f: Array = []
	var off: Dictionary = _play(false)
	var on: Dictionary = _play(true)
	print("behaviour_mix_long: OFF kinds>=%d repeat<=%d idle max %.1f%% home %.2f low-need share %.3f worst need %.0f missed %d school missed %d" % [off["min_kinds"], off["max_repeat"], float(off["idle_max"]) * 100.0, off["home"], off["low"], off["worst"], off["missed"], off["school_missed"]])
	print("behaviour_mix_long: ON  kinds>=%d repeat<=%d idle max %.1f%% home %.2f low-need share %.3f worst need %.0f missed %d school missed %d, plans %d household things %d" % [on["min_kinds"], on["max_repeat"], float(on["idle_max"]) * 100.0, on["home"], on["low"], on["worst"], on["missed"], on["school_missed"], on["plans"], on["house"]])
	print("behaviour_mix_long: worst need OFF: %s; ON: %s" % [off["worst_who"], on["worst_who"]])
	print("behaviour_mix_long: ON trace before the worst need: ", on["trace"])
	for r in on["rows"]:
		print("  ", r)
	if int(on["min_kinds"]) < 8:
		f.append("a folk-day had only %d different interactions" % on["min_kinds"])
	if int(on["max_repeat"]) > 4:
		f.append("one interaction was repeated %d times in a day" % on["max_repeat"])
	if float(on["idle_max"]) >= 0.10:
		f.append("somebody stood idle %.0f%% of the awake time" % (float(on["idle_max"]) * 100.0))
	if float(on["home"]) < float(off["home"]) - 0.2 or float(on["home"]) < 0.5:
		f.append("home life swamped: %.2f at home against %.2f" % [on["home"], off["home"]])
	if float(on["low"]) > float(off["low"]) + 0.05:
		f.append("needs suffered: a need below -60 %.3f of the time against %.3f" % [on["low"], off["low"]])
	if int(on["missed"]) > int(off["missed"]) + 1:
		f.append("work was hurt: %d missed against %d" % [on["missed"], off["missed"]])
	if int(on["school_missed"]) > int(off["school_missed"]) + 1:
		f.append("school was hurt: %d missed against %d" % [on["school_missed"], off["school_missed"]])
	if int(on["plans"]) + int(on["house"]) < 1:
		f.append("no plan and no household activity in %d days" % DAYS)
	return f
