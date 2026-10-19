extends RefCounted
## Task 14b on the REAL map (SLOW tier): one household nobody plays, the same five game days with the outings switched off and on. Outings must really
## walk (go, use, home), and home life must not be swamped: the share of waking time spent at home, the worst need and the missed shifts stay close.

const Kit = preload("res://tests/hood_kit.gd")
const DAYS := 5
const SEED := 4343

func _play(auto_on: bool) -> Dictionary:
	var folk: Array = Kit.new_game("classic", SEED, SEED)
	var mira = folk[0]
	var wren = folk[2]
	Aging.set_age_days(mira, 90.0)
	Aging.set_age_days(folk[1], 90.0)
	Aging.set_age_days(wren, 62.0)
	Careers.hire(mira, "coder", 1)
	Careers.enroll_school()
	WorldIface.coins[1] = 3000
	PlaceAuto.off = not auto_on
	Kit.set_time(1, 6)
	var home_n := 0
	var seen_n := 0
	var worst := 1000.0
	for i in DAYS * 96:
		Kit.run(15)
		var h: float = SysUtil.hour_f()
		for f in folk:
			for n in ["hunger", "energy", "bladder", "hygiene"]:
				worst = minf(worst, f.get_stat_value(n))
			if h >= 7.0 and h < 22.0 and not SysUtil.is_away(f):
				seen_n += 1
				if Neighborhood.lot_of(f) == PlayerLots.home_of(f):
					home_n += 1
	var missed := 0
	var shifts := 0
	var school_missed := 0
	for e in Kit.events:
		if e[0] == "returned_from_work":
			shifts += 1
			if bool(e[1].get("skipped", false)):
				missed += 1
		if e[0] == "late_for_work" or e[0] == "missed_shift":
			missed += 1
		if e[0] == "returned_from_school" and bool(e[1].get("skipped", false)):
			school_missed += 1
	var out := {"home": float(home_n) / maxf(float(seen_n), 1.0), "worst": worst, "missed": missed, "shifts": shifts, "school_missed": school_missed,
		"stats": PlaceAuto.stats.duplicate(true), "used": PlaceAuto.kinds_used(1), "places": Kit.count_events("place_used")}
	Kit.teardown()
	return out

func run() -> Array:
	var f: Array = []
	var off: Dictionary = _play(false)
	var on: Dictionary = _play(true)
	print("life_auto_home: OFF home %.2f worst need %.0f missed %d of %d shifts, school missed %d" % [off["home"], off["worst"], off["missed"], off["shifts"], off["school_missed"]])
	print("life_auto_home: ON  home %.2f worst need %.0f missed %d of %d shifts, school missed %d, stats %s, used %s" % [on["home"], on["worst"], on["missed"], on["shifts"], on["school_missed"], str(on["stats"]), str(on["used"])])
	var s: Dictionary = on["stats"]
	if int(s.get("started", 0)) < 1:
		f.append("nobody went out in %d days" % DAYS)
	if int(s.get("done", 0)) < 1:
		f.append("no outing was finished")
	if float(on["home"]) < float(off["home"]) - 0.25 or float(on["home"]) < 0.5:
		f.append("home life swamped: %.2f of waking time at home, %.2f without outings" % [on["home"], off["home"]])
	if float(on["worst"]) < float(off["worst"]) - 30.0 or float(on["worst"]) < -90.0:
		f.append("needs suffered: worst %.0f against %.0f without outings" % [on["worst"], off["worst"]])
	if int(on["missed"]) > int(off["missed"]) + 1:
		f.append("work was hurt: %d missed against %d" % [on["missed"], off["missed"]])
	if int(on["school_missed"]) > int(off["school_missed"]) + 1:
		f.append("school was hurt: %d missed against %d" % [on["school_missed"], off["school_missed"]])
	return f
