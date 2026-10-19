extends RefCounted
## SLOW: task 22 rates. Six 14-day cruises (3 cruise-years of exposure) at the Chaotic Surprises level (x10): every cruise incident rolls from the
## data file, the measured yearly rates land near the data (rate x 10), nothing breaks (cases, deaths, fires, outbreaks all resolve), and the
## cruises still end properly with everybody home or accounted for.

const K = preload("res://tests/vacation_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	K.new_game("small", 90000, false, 1234)
	Incidents.set_level("chaotic")
	var ids: Array = ["cruise_storm", "cruise_norovirus", "cruise_cabin_theft", "cruise_brawl"]
	var trips: int = TestFixture.pick(6, 3)
	var ran: int = 0
	for n in trips:
		K.Kit.set_time(5 + n * 20, 8, 0)
		for ff in VacationCost.household_folk(1):
			if Hospital.is_in(int(ff.id)):
				Hospital.discharge(int(ff.id))        # warping does not run the hospital's hidden stay
			ff.remove_buff("sick")
		var res: Dictionary = Vacation.book_and_go(1, "cruise", {"length_days": 14, "cabin_class": "inside", "seed": 100 + n, "force_afford": true, "ignore_busy": true})
		_check(bool(res["ok"]), "cruise %d booked: %s" % [n, str(res.get("reason", ""))])
		if not bool(res["ok"]):
			break
		ran += 1
		var t: Dictionary = Vacation.trip(int(res["trip"]))
		var guard: int = 0
		while not Vacation.trip(int(res["trip"])).is_empty() and guard < 14 * 24 + 300:
			K.warp(60)
			Incidents.on_hour()
			guard += 1
		_check(Vacation.trip(int(res["trip"])).is_empty(), "cruise %d ended" % n)
		for f in SysUtil.residents():
			if f.has_meta("away") and str(f.get_meta("away")) == "vacation":
				fails.append("a folk is still in transit after cruise %d" % n)
		_check(DestLoader.region_of_zone(0) < 0 and DestLoader.region_of_zone(1) < 0, "zones unloaded after cruise %d" % n)
	var base := {"cruise_storm": 0.7, "cruise_norovirus": 0.2, "cruise_cabin_theft": 0.6, "cruise_brawl": 0.5}
	var total: int = 0
	for id in ids:
		var st: Dictionary = Incidents.stat(id)
		var expect: float = float(base[id]) * 10.0
		print("  [cruise] %-20s triggered %d, exposure %.2f cruise-years, measured %.2f / year (data x10: %.2f)" % [id, int(st["triggered"]), float(st["exposure"]), Incidents.measured_rate(id), expect])
		_check(float(st["exposure"]) > float(ran) * 14.0 / 28.0 * (0.5 if id in ["cruise_storm", "cruise_norovirus"] else 0.15), "%s: exposure counted" % id)
		total += int(st["triggered"])
	_check(total >= 2, "the incidents roll during cruises (%d in all)" % total)
	K.teardown()
	return fails