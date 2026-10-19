extends RefCounted
## Strangers near the household (venue crowd, visiting townies) do not end up in a bad way: a stranger who has been around for a few hours
## (venues serve their customers, hosts look after their guests: Crowd.recover) keeps hunger / energy / bladder / hygiene above FLOOR and
## social / fun above 0, over a multi-day run with the household at home. Fast tier: one day; full run (run_one / --slow): 3 days, 3 seeds.

const Kit = preload("res://tests/hood_kit.gd")
const FLOOR := 20.0
const BASIC := ["hunger", "energy", "bladder", "hygiene"]
const SETTLE_MIN := 180        # a newly arrived customer is tuned low on purpose (the venue is why they came): judged after this long

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var seeds: Array = [11] if TestFixture.fast else [11, 12, 13]
	for s in seeds:
		_days(int(s), TestFixture.pick(72, 24))
	Kit.teardown()
	return fails

func _days(seed_value: int, hours: int) -> void:
	SimSeed.apply(seed_value)
	var folk: Array = Kit.new_game("small", seed_value)
	Incidents.set_level("off")
	Kit.set_time(2, 8)
	StoryVisits.invite_over(int(Story.alive_townies()[0]["id"]), int(folk[1].id), 240)      # a household visit besides the venue crowds
	var first: Dictionary = {}                  # instance id -> game minute the stranger was first seen (for those without an arrival stamp)
	var worst: Dictionary = {}
	var samples := 0
	for h in hours:
		Kit.run(60)
		for f in WorldIface.all_folk():
			if not f.has_meta("visitor") or f.has_meta("staff") or int(f.household_id) > 0:
				continue
			var key: int = f.get_instance_id()
			if not first.has(key):
				first[key] = SimEnv.now_min()
			if SimEnv.now_min() - int(f.get_meta("arrived_min", first[key])) < SETTLE_MIN:
				continue
			samples += 1
			for n in f.needs:
				var v: float = f.get_stat_value(n)
				if not worst.has(n) or v < float(worst[n][0]):
					worst[n] = [v, "%s %s lot=%s tile=%s doing %s leaving=%s" % [f.name, str(f.traits), NeighborhoodLots.lot_at(f.tile), str(f.tile), f.current.def_id if f.current != null else "-", str(f.has_meta("leaving"))]]
	print("  [crowd_floor] seed %d: %d settled-stranger samples; worst %s" % [seed_value, samples, str(worst.keys().map(func(n): return "%s %d" % [n, int(worst[n][0])]))])
	_check(samples > 0, "seed %d: there were settled strangers to watch" % seed_value)
	for n in worst:
		var floor_v: float = FLOOR if BASIC.has(n) else (0.0 if n == "social" or n == "fun" else -100.0)
		_check(float(worst[n][0]) > floor_v, "seed %d: worst %s of a stranger is %d (> %d): %s" % [seed_value, n, int(worst[n][0]), int(floor_v), worst[n][1]])
