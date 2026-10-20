extends RefCounted
## Task 32f: a home with little in it sends folk out and furnishes itself when nobody plays.
##  - HomeBare: an empty home is bare (1.0), a furnished one is not (0); bare homes raise the 14b outing chance, the 32c stroll / call chance and the
##    friends-over chance, and make daydreaming less attractive; a furnished home changes nothing.
##  - AutoFurnish: a household nobody gives orders to buys the basics after two days (bed per person, toilet, fridge, shower, stove, a seat per
##    person) from its own coins with a plain toast, everything reachable; a household whose player gives orders is not furnished by default;
##    the setting 'on' furnishes a played household that went away, 'off' never does.

const Kit := preload("res://tests/start_kit.gd")
var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _idle(f) -> bool:
	if f.current == null:
		return true
	var d := str(f.current.def_id)
	return d.begins_with("idle") or d == "daydream"


func _asleep(f) -> bool:
	return f.current != null and (str(f.current.def_id).begins_with("sleep") or str(f.current.def_id).contains("nap"))


## Run `hours` game hours in 10-minute steps; returns [idle minutes, awake minutes] of the household's folk.
func _run_sampling(folk: Array, hours: int) -> Array:
	var idle := 0
	var awake := 0
	for _i in hours * 6:
		Kit.run(10)
		var hr: int = int(Kit.clock().hour())
		if hr < 7 or hr >= 22:
			continue                                   # the waking day (nights are Circadian's business, not what a home offers)
		for f in folk:
			if f.has_meta("away") or _asleep(f):
				continue
			awake += 10
			if _idle(f):
				idle += 10
	return [idle, awake]


func run() -> Array:
	fails = []
	AutoFurnish.reset()
	var toasts: Array = []
	var cb := func(text, _kind): toasts.append(str(text))
	Events.notification.connect(cb)

	# ---- 1. bare vs furnished: the factors the dice and autonomy read
	var fur: Array = Kit.new_game("family", "normal", {}, -1, {"home_state": "furnished", "world_seed": 5})
	var f_fur: Folk = fur[0]
	var bare_fur: float = HomeBare.factor(f_fur)
	var chance_fur: float = PlaceAutoPlan.chance(f_fur, "cinema", PlaceAutoPlan.kind_def("cinema"), 0)
	var stroll: Dictionary = DynLife.cfg()["plans"]["stroll"]
	var plan_fur: float = _stroll_chance(f_fur, stroll)
	var dd_def: Dictionary = SimEnv.data().interactions()["daydream"]
	var dd_fur: float = HomeBare.autonomy_mult(f_fur, "daydream", dd_def)
	_check(bare_fur < 0.05, "a furnished home is not bare (%.2f)" % bare_fur)
	_check(dd_fur == 1.0, "furnished: daydreaming is unchanged")
	Kit.teardown()

	var folk: Array = Kit.new_game("family", "normal", {}, -1, {"home_state": "empty", "world_seed": 5})
	var f0: Folk = folk[0]
	var bare: float = HomeBare.factor(f0)
	_check(bare > 0.9, "an empty home is bare (%.2f)" % bare)
	var chance_bare: float = PlaceAutoPlan.chance(f0, "cinema", PlaceAutoPlan.kind_def("cinema"), 0)
	_check(chance_bare > chance_fur * 3.0, "bare: the outing chance rises (%.3f vs %.3f)" % [chance_bare, chance_fur])
	_check(PlaceAutoPlan.trips_cap(f0, 2) > 2, "bare: more outings a day are allowed (%d)" % PlaceAutoPlan.trips_cap(f0, 2))
	_check(_stroll_chance(f0, stroll) > plan_fur * 3.0, "bare: a stroll is likelier (%.3f vs %.3f)" % [_stroll_chance(f0, stroll), plan_fur])
	_check(HomeBare.autonomy_mult(f0, "daydream", dd_def) < 0.6, "bare: daydreaming loses appeal (%.2f)" % HomeBare.autonomy_mult(f0, "daydream", dd_def))
	_check(PlaceAutoGate.eval("bare", f0, "park_trail", {}, 2).get("mult", 0.0) > 0.5, "bare: the free park outings are on")

	# ---- 2. unplayed, empty household: nothing for two days, then the basics, with one plain toast
	_check(not StartHome.next_basic(1).is_empty(), "start: the basics are missing")
	var funds0: int = Economy.balance(1)
	var objs0: int = Economy.objects_of(1).size()
	var s1: Array = _run_sampling(folk, 24)
	_check(StartHome.next_basic(1).is_empty() == false, "day 1: nothing bought yet")
	_check(not toasts.any(func(t): return "bought some furniture" in t), "day 1: no furniture toast")
	var s2: Array = _run_sampling(folk, 40)          # into day 3
	_check(StartHome.next_basic(1).is_empty(), "day 3: the household bought the basics (missing: %s)" % str(StartHome.next_basic(1)))
	var toast: String = ""
	for t in toasts:
		if "bought some furniture" in t:
			toast = t
	_check(toast.begins_with("The ") and toast.ends_with("bought some furniture."), "one plain toast (%s)" % toast)
	_check(Economy.balance(1) >= 0 and Economy.balance(1) < funds0, "paid from the household's coins (%d -> %d)" % [funds0, Economy.balance(1)])
	_check(Economy.objects_of(1).size() >= objs0 + 6, "the new things belong to the household (%d -> %d)" % [objs0, Economy.objects_of(1).size()])
	_check(_reachable(folk), "everything bought can be walked up to")
	_check(HomeBare.factor(f0) < bare, "the home is less bare after buying (%.2f -> %.2f)" % [bare, HomeBare.factor(f0)])
	var s3: Array = _run_sampling(folk, 24)          # day 4: furnished, still nobody playing
	var idle_before: float = 100.0 * float(s1[0] + s2[0]) / maxf(1.0, float(s1[1] + s2[1]))
	var idle_after: float = 100.0 * float(s3[0]) / maxf(1.0, float(s3[1]))
	print("auto_furnish: idle %.0f%% in the bare days 1-3, %.0f%% on day 4 once furnished" % [idle_before, idle_after])
	var idle_all: float = 100.0 * float(s1[0] + s2[0] + s3[0]) / maxf(1.0, float(s1[1] + s2[1] + s3[1]))
	_check(idle_all < 15.0, "an unplayed empty household over 4 days: idle under 15%% of awake time (%.1f%%)" % idle_all)
	_check(idle_after < 15.0, "and on day 4, furnished by itself (%.1f%%)" % idle_after)
	Events.notification.disconnect(cb)
	Kit.teardown()

	# ---- 3. a played household is not furnished by default; 'on' does it once the player is away; 'off' never
	fails.append_array(_played_cases())
	AutoFurnish.reset()
	return fails


func _played_cases() -> Array:
	var out: Array = []
	var folk: Array = Kit.new_game("solo", "normal", {}, -1, {"home_state": "empty", "world_seed": 5})
	AutoFurnish.reset()
	var day := SysUtil.day()
	AutoFurnish.note_order(1)                          # the player gave an order on day 1
	AutoFurnish.on_day(day + 3)
	if StartHome.next_basic(1).is_empty():
		out.append("a played household was furnished by default")
	AutoFurnish.mode = "off"
	AutoFurnish.on_day(day + 5)
	if StartHome.next_basic(1).is_empty():
		out.append("'off' still furnished the household")
	AutoFurnish.mode = "on"
	WorldIface.coins[1] = 6000
	AutoFurnish.on_day(day + 1)
	if not StartHome.next_basic(1).is_empty() and AutoFurnish.wanted(1, day + 1):
		out.append("'on' wanted to furnish after only one idle day")
	AutoFurnish.on_day(day + 6)
	if not StartHome.next_basic(1).is_empty():
		out.append("'on': an away played household was not furnished (missing %s)" % str(StartHome.next_basic(1)))
	Kit.teardown()
	return out


## The stroll plan's chance for a folk now (the hour is set to a stroll hour).
func _stroll_chance(f, plan: Dictionary) -> float:
	return DynPlans.chance_of(f, plan)


## Every household object has a free walkable tile beside it that the folk can reach.
func _reachable(folk: Array) -> bool:
	var W = Kit.world()
	var from: Vector2i = folk[0].tile
	for o in Economy.objects_of(1):
		if o.is_wall_mounted() or not (o.def.get("interactions", []) as Array).size() > 0:
			continue
		var fp: Array = o.footprint()
		var ok := false
		for q in fp:
			for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = q + dd
				if not fp.has(nb) and W.is_walkable(nb) and WorldIface.path_length(from, nb) >= 0:
					ok = true
		if not ok:
			return false
	return true
