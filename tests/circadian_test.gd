extends RefCounted
## Circadian rhythm: per-folk bed/wake times by stage and traits, phases, and a multi-day sim where adults sleep through the night
## (asleep at 03:00 on >= 90% of nights, main sleep starts 21:00-01:00 and lasts 6.5-9.5 h). Fast tier: 5 days, slow: 14.

const Kit = preload("res://tests/sim_testkit.gd")

func run() -> Array:
	var f: Array = []
	_schedules(f)
	_sleep_nights(f)
	return f

func _hours_between(bed: float, wake: float) -> float:
	return fposmod(wake - bed, 24.0)

func _schedules(f: Array) -> void:
	var w := Kit.setup(31)
	var names := ["Ann", "Bo", "Cy", "Di", "Ed", "Flo"]
	var seen_beds: Dictionary = {}
	for n in names:
		var a := Folk.create(n, [])
		a.age_stage = "adult"
		var sc: Array = Circadian.schedule(a)
		seen_beds[snappedf(sc[0], 0.01)] = true
		var len_h: float = _hours_between(sc[0], sc[1])
		Kit.expect(f, sc[0] >= 22.0 or sc[0] < 0.01, "%s adult bed time %.2f" % [n, sc[0]])
		Kit.expect(f, len_h >= 7.0 and len_h <= 8.6, "%s sleep length %.2f h" % [n, len_h])
	Kit.expect(f, seen_beds.size() >= 4, "adults do not share one bedtime (%d distinct)" % seen_beds.size())
	var kid := Folk.create("Kid", [])
	kid.age_stage = "child"
	var ad := Folk.create("Ann", [])
	ad.age_stage = "adult"
	Kit.expect(f, Circadian.schedule(kid)[0] < 21.5 and Circadian.schedule(kid)[0] >= 20.0, "kids go to bed early")
	var elder := Folk.create("Ann", [])
	elder.age_stage = "elder"
	Kit.expect(f, Circadian.schedule(elder)[0] < 22.6, "elders go to bed earlier than adults")
	var owl := Folk.create("Ann", ["night_owl"])
	owl.age_stage = "adult"
	var bird := Folk.create("Ann", ["early_bird"])
	bird.age_stage = "adult"
	Kit.expect(f, fposmod(Circadian.schedule(owl)[0] - 12.0, 24.0) > fposmod(Circadian.schedule(bird)[0] - 12.0, 24.0), "night owls go to bed later than early birds")
	var worker := Folk.create("Ann", [])
	worker.age_stage = "adult"
	worker.work_start = 7.0
	worker.work_end = 15.0
	Kit.expect(f, Circadian.schedule(worker)[1] <= 5.5, "an early shift pulls the wake time earlier (%.2f)" % Circadian.schedule(worker)[1])
	# phases follow the clock
	var sc2: Array = Circadian.schedule(ad)
	Kit.set_time(2, int(sc2[0]) , 0)
	Kit.expect(f, Circadian.in_phase(ad, "wind_down") or Circadian.in_phase(ad, "bedtime"), "at bedtime it is bedtime")
	(ad.needs["energy"] as Stat).set_value(70)
	Kit.expect(f, Circadian.in_phase(ad, "sleep_ok"), "even with 70 energy they may go to bed at bedtime")
	Kit.set_time(2, 14)
	Kit.expect(f, not Circadian.in_phase(ad, "sleep_ok"), "no big sleep in the afternoon at 70 energy")
	(ad.needs["energy"] as Stat).set_value(10)
	Kit.expect(f, Circadian.in_phase(ad, "sleep_ok"), "utterly worn out folk may sleep any time")
	Kit.teardown()

func _sleep_nights(f: Array) -> void:
	var days: int = 5 if TestFixture.fast else 9
	var w := Kit.setup(99)
	Kit.set_time(1, 8)
	var objs := Kit.furnish(w)
	w.add_object("bed", Vector2i(12, 14))
	w.add_object("bed", Vector2i(14, 14))
	w.add_object("bed", Vector2i(16, 16))
	w.add_object("toilet", Vector2i(16, 14))
	var folks: Array = []
	for n in ["Alice", "Bob", "Cara", "Dora"]:
		var p := Folk.create(n, ["night_owl"] if n == "Dora" else [])
		p.age_stage = "adult"
		w.add_folk(p, Vector2i(12 + folks.size(), 12))
		folks.append(p)
	var dir = Kit.director()
	var asleep3: Dictionary = {}      # folk id -> nights asleep at 03:00
	var starts: Dictionary = {}       # folk id -> current sleep start minute
	var sessions: Array = []          # [folk id, start hour, length h] of sleeps longer than 3 h
	SimEnv.events().interaction_started.connect(func(i, d, _t):
		if d == "sleep_bed":
			starts[i] = SimEnv.now_min())
	SimEnv.events().interaction_finished.connect(func(i, d, _s):
		if d == "sleep_bed" and starts.has(i):
			var len_h: float = float(SimEnv.now_min() - int(starts[i])) / 60.0
			if len_h >= 3.0:
				sessions.append([i, fposmod(float(int(starts[i]) % 1440) / 60.0, 24.0), len_h])
			starts.erase(i))
	var nights := 0
	for minute in days * 1440:
		SimEnv.clock().advance_minutes(1)
		if minute % 1440 == 1439:
			(objs["fridge"] as StubWorld.StubObject).state["stock"] = 10
		dir.tick_minute(1)
		if SimEnv.now_min() % 1440 == 180 and minute > 1440:        # 03:00 of day 2 onwards
			nights += 1
			for p in folks:
				if p.current != null and p.current.def_id in ["sleep_bed", "nap_bed", "nap_sofa"]:
					asleep3[p.id] = int(asleep3.get(p.id, 0)) + 1
	var owl_share: float = float(asleep3.get(folks[3].id, 0)) / float(maxi(nights, 1))
	Kit.expect(f, owl_share >= 0.9, "even the night owl is asleep at 03:00 on >= 90%% of nights (%.2f; before: night owls up on 80 of 112 nights)" % owl_share)
	var total_asleep := 0
	for p in folks:
		total_asleep += int(asleep3.get(p.id, 0))
	var share: float = float(total_asleep) / float(maxi(nights * folks.size(), 1))
	print("  circadian: %d nights, asleep at 03:00 share %.2f, %d long sleeps" % [nights, share, sessions.size()])
	# before (reviewer, 56 nights): Tess awake at 03:00 on 32 nights (57%), Tobin on 37 (66%): parties to 03:30, homework and showers at 3 am.
	# after: required <= 10% of nights awake at 03:00
	Kit.expect(f, share >= 0.9, "adults are asleep at 03:00 on >= 90%% of nights (%.2f)" % share)
	var bad_start := 0
	var bad_len := 0
	for s in sessions.slice(folks.size() * 2):       # the first day starts mid-afternoon with the energy of a test fixture
		var h: float = s[1]
		if not (h >= 21.0 or h <= 1.0):
			bad_start += 1
		if s[2] < 6.5 or s[2] > 9.5:
			bad_len += 1
			print("   odd sleep: start %.1f h, %.1f h long" % [s[1], s[2]])
	Kit.expect(f, sessions.size() >= folks.size() * (days - 2), "main sleeps happened (%d)" % sessions.size())
	Kit.expect(f, bad_start <= maxi(1, sessions.size() / 8), "main sleep starts between 21:00 and 01:00 (%d outside of %d)" % [bad_start, sessions.size()])
	Kit.expect(f, bad_len <= maxi(1, sessions.size() / 8), "main sleep lasts 6.5-9.5 h (%d outside of %d)" % [bad_len, sessions.size()])
	for p in folks:
		Kit.expect(f, (p.needs["energy"] as Stat).value > -60.0 and (p.needs["hunger"] as Stat).value > -95.0, "%s did not collapse" % p.name)
	Kit.teardown()
