extends RefCounted
## Task 32c on the stub world (fast tier): three household folk with a furnished home live DAYS full game days on autonomy. Per folk per day the mix must
## have at least 8 different interactions, no interaction more than 4 times outside the needs (bathroom, meals, sleep, hygiene, work), and the awake
## time with nothing to do stays under 10%. Printed: the numbers behind it, for before / after comparisons.

const Kit = preload("res://tests/sim_testkit.gd")
const Mix = preload("res://tests/behaviour_mix_kit.gd")
const DAYS := 2

func run() -> Array:
	var f: Array = []
	var w := Kit.setup(777)
	DynLife.install()
	SysContent.gate_late_content()
	Kit.furnish(w)
	w.add_object("bed", Vector2i(12, 14))
	w.add_object("bed", Vector2i(14, 12))
	w.add_object("toilet", Vector2i(16, 14))
	var folks := [Folk.create("Alice", ["neat", "social"]), Folk.create("Bob", ["lazy", "gamer"]), Folk.create("Cara", ["creative", "active"])]
	for i in 3:
		folks[i].household_id = 1                    # residents: DynLife shapes their day too
		w.add_folk(folks[i], Vector2i(12 + i, 12))
	var dir = Kit.director()
	var mix = Mix.new()
	mix.watch(folks)
	Kit.set_time(1, 0)
	for minute in DAYS * 1440:
		SimEnv.clock().advance_minutes(1)
		dir.tick_minute(1)
		if minute % 60 == 59:
			DynLife.on_hour(int(SysUtil.hour_f()))         # the SimRegistry row, driven by hand
		mix.sample()
	mix.unwatch()
	var worst_idle := 0.0
	for p in folks:
		var idle: float = mix.idle_share(p.id)
		worst_idle = maxf(worst_idle, idle)
		for d in range(1, DAYS + 1):
			var s: Dictionary = mix.day_summary(p.id, d)
			print("  behaviour_mix %s day %d: %d different interactions, most repeated %s x%d" % [p.name, d, s["distinct"], s["worst_iid"], s["worst_repeat"]])
			Kit.expect(f, int(s["distinct"]) >= 8, "%s day %d did only %d different interactions" % [p.name, d, s["distinct"]])
			Kit.expect(f, int(s["worst_repeat"]) <= 4, "%s day %d did %s %d times" % [p.name, d, s["worst_iid"], s["worst_repeat"]])
		print("  behaviour_mix %s idle %.1f%% of awake time" % [p.name, idle * 100.0])
		Kit.expect(f, idle < 0.10, "%s stood idle %.0f%% of the time" % [p.name, idle * 100.0])
	Kit.teardown()
	return f
