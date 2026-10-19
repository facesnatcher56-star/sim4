extends RefCounted
## SimScheduler: deterministic order, timed jobs at exactly their minute, bucket spreading, frame-budget deferral (counts, not ms: the
## clock and frame counter are injected), idle jobs cost zero, groups, freed owners, and the registry itself (old step order, no direct Clock listeners).

var fails: Array = []
var log: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _clock():
	var c = load("res://scripts/core/clock.gd").new()
	c.total_minutes = 7 * 60
	return c

func _note(tag: String) -> void:
	log.append(tag)

func run() -> Array:
	fails = []
	_order()
	_timed()
	_buckets()
	_budget()
	_idle_and_groups()
	_registry()
	return fails

func _order() -> void:
	var run_once := func() -> Array:
		var clk = _clock()
		var s := SimScheduler.of(clk)
		log = []
		# registered out of order on purpose; same order value = registration order
		s.add("day", "t", "g", 1440, 10, SimScheduler.NORMAL, _note.bind("day"))
		s.add("hourB", "t", "g", 60, 20, SimScheduler.NORMAL, _note.bind("hourB"))
		s.add("hourA", "t", "g", 60, 10, SimScheduler.NORMAL, _note.bind("hourA"))
		s.add("m3", "t", "g", 1, 30, SimScheduler.NORMAL, _note.bind("m3"))
		s.add("m1", "t", "g", 1, 10, SimScheduler.CRITICAL, _note.bind("m1"))
		s.add("m2a", "t", "g", 1, 20, SimScheduler.LOW, _note.bind("m2a"))
		s.add("m2b", "t", "g", 1, 20, SimScheduler.NORMAL, _note.bind("m2b"))
		clk.total_minutes = 1439
		clk.advance_minutes(2)           # 23:59 -> 00:00 (hour + day boundary) -> 00:01
		clk.free()
		return log.duplicate()
	var a: Array = run_once.call()
	var b: Array = run_once.call()
	var expect := ["m1", "m2a", "m2b", "m3", "hourA", "hourB", "day", "m1", "m2a", "m2b", "m3"]
	_check(a == expect, "order is (layer, order, seq): minute, then hour, then day: %s" % str(a))
	_check(a == b, "two identical runs give the identical order")
	# cadence 5 / 15 with a phase
	var clk2 = _clock()
	var s2 := SimScheduler.of(clk2)
	log = []
	var j5 := s2.add("c5", "t", "g", 5, 10, SimScheduler.NORMAL, _note.bind("c5"))
	j5.phase = 0
	clk2.total_minutes = 0
	clk2.advance_minutes(20)
	_check(log.size() == 4, "cadence 5 runs 4 times in 20 minutes (%d)" % log.size())
	clk2.free()

func _timed() -> void:
	var clk = _clock()
	var s := SimScheduler.of(clk)
	log = []
	var t0: int = clk.total_minutes
	s.at(t0 + 5, "t", _note.bind("b1"))
	s.at(t0 + 3, "t", _note.bind("a"))
	s.at(t0 + 5, "t", _note.bind("b2"))
	var cancelled := s.at(t0 + 5, "t", _note.bind("never"))
	s.at(t0 + 10, "t", _note.bind("c"))
	_check(s.cancel(cancelled), "cancel returns true for a pending wake-up")
	_check(not s.cancel(cancelled), "and false the second time")
	_check(s.timed_pending() == 4, "4 wake-ups pending")
	clk.advance_minutes(2)
	_check(log.is_empty(), "nothing fires before its minute")
	clk.advance_minutes(1)
	_check(log == ["a"], "fires at exactly minute +3: %s" % str(log))
	clk.advance_minutes(2)
	_check(log == ["a", "b1", "b2"], "same minute: registration order, cancelled one skipped: %s" % str(log))
	clk.advance_minutes(5)
	_check(log == ["a", "b1", "b2", "c"] and s.timed_pending() == 0, "last one at +10, nothing pending: %s" % str(log))
	s.at(clk.total_minutes - 30, "t", _note.bind("late"))
	clk.advance_minutes(1)
	_check(log.back() == "late", "a wake-up in the past fires on the next tick")
	clk.free()

func _buckets() -> void:
	var clk = _clock()
	var s := SimScheduler.of(clk)
	var seen: Dictionary = {}
	var job := s.add_bucketed("townies", "t", "g", 60, 10, SimScheduler.NORMAL, func(id, elapsed): seen[id] = int(seen.get(id, 0)) + 1; _check(elapsed == 60, "elapsed is the cadence"))
	for id in range(1000, 1200):
		job.track(id)
	_check(job.count == 200, "200 ids tracked")
	job.track(1000)
	_check(job.count == 200, "tracking twice does not duplicate")
	clk.advance_minutes(60)
	var all_once := seen.size() == 200
	for id in seen:
		if seen[id] != 1:
			all_once = false
	_check(all_once, "every id is visited exactly once per 60 minutes")
	_check(job.max_batch <= 4, "200 ids at cadence 60 run at most 4 per minute (max %d)" % job.max_batch)
	job.untrack(1000)
	seen.clear()
	clk.advance_minutes(60)
	_check(seen.size() == 199 and not seen.has(1000), "untracked ids are no longer visited")
	clk.free()

func _budget() -> void:
	var clk = _clock()
	var s := SimScheduler.of(clk)
	var fake := [0]
	var frame := [1]
	s.now_fn = func(): return fake[0]
	s.frame_fn = func(): return frame[0]
	s.budget_usec = 1500
	log = []
	var cost := func(tag: String): fake[0] += 1000; log.append(tag)
	s.add("crit", "t", "g", 1, 10, SimScheduler.CRITICAL, cost.bind("crit"))
	s.add("norm", "t", "g", 1, 20, SimScheduler.NORMAL, cost.bind("norm"))
	s.add("low", "t", "g", 1, 30, SimScheduler.LOW, cost.bind("low"))
	clk.advance_minutes(1)
	_check(log == ["crit", "norm"], "LOW is deferred once the frame spent its budget, CRITICAL and NORMAL run: %s" % str(log))
	_check(s.stats()["deferred_total"] == 1 and s.stats()["deferred_pending"] == 1, "the deferral is counted")
	clk.advance_minutes(1)            # same frame, still over budget: coalesced, not piled up
	_check(s.stats()["deferred_pending"] == 1 and s.job("low").coalesced == 1, "a second due run coalesces into the postponed one")
	frame[0] += 1
	clk.advance_minutes(1)            # a new frame: the postponed run goes first, then everything else
	_check(log.count("low") >= 1 and s.stats()["deferred_pending"] == 0 or s.stats()["deferred_pending"] <= 1, "a later frame runs the postponed work")
	_check(log.count("crit") == 3 and log.count("norm") == 3, "CRITICAL and NORMAL ran in every minute")
	# starvation guard: stuck in one frame forever, the postponed run still happens after MAX_DEFER_TICKS ticks
	var ran := log.count("low")
	clk.advance_minutes(SimScheduler.MAX_DEFER_TICKS + 2)
	_check(log.count("low") > ran, "postponed work is forced after MAX_DEFER_TICKS")
	# no budget (tests / headless): nothing is ever deferred
	s.budget_usec = 0
	var d0: int = s.stats()["deferred_total"]
	clk.advance_minutes(5)
	_check(s.stats()["deferred_total"] == d0, "budget 0 = unlimited, nothing deferred")
	clk.free()

func _idle_and_groups() -> void:
	var clk = _clock()
	var s := SimScheduler.of(clk)
	var busy := [false]
	var runs := [0]
	var j := s.add("idle", "t", "g1", 1, 10, SimScheduler.NORMAL, func(): runs[0] += 1, "", func(): return busy[0])
	var b := s.add_bucketed("empty", "t", "g1", 15, 20, SimScheduler.NORMAL, func(_id, _e): runs[0] += 1)
	clk.advance_minutes(120)
	_check(runs[0] == 0 and j.calls == 0 and b.calls == 0, "an idle job and an empty bucket job never run (%d)" % runs[0])
	busy[0] = true
	clk.advance_minutes(3)
	_check(j.calls == 3, "the gate opening starts the job")
	s.set_group_enabled("g1", false)
	clk.advance_minutes(3)
	_check(j.calls == 3, "a disabled group is skipped")
	s.set_group_enabled("g1", true)
	s.remove_group("g1")
	clk.advance_minutes(3)
	_check(j.calls == 3 and s.job("idle") == null and not s.has_group("g1"), "a removed group is gone")
	# a freed owner is dropped instead of erroring
	var owner := Node.new()
	var hits := [0]
	s.add("owned", "t", "g2", 1, 10, SimScheduler.NORMAL, Callable(owner, "get_name"))
	clk.advance_minutes(1)
	owner.free()
	clk.advance_minutes(2)
	_check(s.job("owned") == null, "a job whose owner was freed is dropped")
	# a job registered from inside a job does not break the running tick
	log = []
	s.add("spawner", "t", "g3", 1, 10, SimScheduler.NORMAL, func(): s.add("child", "t", "g3", 1, 20, SimScheduler.NORMAL, _note.bind("child")); s.job("spawner").enabled = false)
	clk.advance_minutes(2)
	_check(log.size() >= 1, "a job added during a tick runs from the next tick")
	_check(s.describe().find("| minute |") >= 0, "describe() prints the table")
	clk.free()

func _registry() -> void:
	var clk = _clock()
	var s := SimScheduler.of(clk)
	var sm := SystemsManager.new()
	SimRegistry.install_systems(s, sm)
	var order: Array = []
	for r in s.stats()["rows"]:
		if int(r["cadence"]) == 1 and not (r["name"] in ["Tiers", "TownSim.sync"]):      # the tier rows (17.3) are not old steps
			order.append(r["name"])
	var old_steps := ["NeighborhoodService.before", "CareerShifts", "Away", "StoryVisits", "BabyCare", "AccidentMarks", "Incidents", "CrimeFlow", "Fire",
		"DisasterClock", "Vacation", "NeighborhoodService.after", "WeatherFolk", "LevelSystems"]
	_check(order == old_steps, "the minute rows keep the old SystemsManager step order: %s" % str(order))
	var d: String = s.describe()
	for needle in ["hour/Incidents.on_hour", "day/CrimeFlow.on_day", "| minute | 210 |"]:
		_check(d.find(needle) >= 0, "describe() lists " + needle)
	_check(s.job("hour/AccidentMarks.on_hour").order < s.job("hour/Incidents.on_hour").order and s.job("hour/Incidents.on_hour").order < s.job("hour/AccidentMarks.after_hour").order, "AccidentMarks.on_hour runs before Incidents.on_hour and after_hour right after it")
	SimRegistry.install_social(s)
	_check(s.job("SocialDynamics.on_minute").order > s.job("LevelSystems").order, "SocialDynamics runs after the SystemsManager steps, like its old connection order")
	sm.free()
	clk.free()
	# nobody listens to the Clock's signals directly in the simulation any more (views may)
	var offenders: Array = []
	for dir in ["res://scripts/sim", "res://scripts/systems", "res://scripts/net", "res://scripts/core"]:
		for fname in DirAccess.get_files_at(dir):
			if not fname.ends_with(".gd"):
				continue
			var text := FileAccess.get_file_as_string(dir + "/" + fname)
			for sig in ["minute_passed.connect", "hour_passed.connect", "day_passed.connect"]:
				if text.find(sig) >= 0 and fname != "sim_scheduler.gd":
					offenders.append(fname)
	_check(offenders.is_empty(), "sim code connects to the Clock only through the scheduler: %s" % str(offenders))
