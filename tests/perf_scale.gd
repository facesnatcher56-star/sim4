extends RefCounted
## SCALE BENCHMARK (slow tier / its own runner; the fast-tier twin is perf_scale_small_test.gd). Builds a generated town
## (tests/perf_town.gd), runs it for N game days through the real clock, and reports ms per game minute by system, allocations,
## node count and work counts. It FAILS when a budget is exceeded:
##   - load-independent counts (path queries per choose / per fill, folk in the world vs the active-set cap, nodes, memory growth), and
##   - wall clock at SLACK x the budget (the numbers are printed, a busy machine must not flake; the budget itself is only a WARN).
## Run:   powershell -File tools/run_scale.ps1 [-Profile big|today|mini] [-Days 3]      (or run_one.gd -- perf_scale --profile=big --days=3)
## Writes a dated section to docs/PERF_SCALE_RESULTS.md (not with --no-write). See docs/PERFORMANCE.md "Rules every system must follow".

const Town = preload("res://tests/perf_town.gd")
const Kit = preload("res://tests/hood_kit.gd")
const RESULTS := "res://docs/PERF_SCALE_RESULTS.md"

# ---- budgets (docs/PERFORMANCE.md): speed 3 = 12 game minutes per second = 0.2 game minutes per 60 fps frame
const FRAME_PER_MIN := 0.2
const BUDGET_FRAME_AVG_MS := 4.0         # simulation per frame, average
const BUDGET_FRAME_WORST_MS := 12.0      # simulation in the worst frame (a frame that runs a game minute pays for the whole minute)
const BUDGET_CHOOSE_MS := 3.0            # one household Autonomy.choose
const BUDGET_TOWN_FRAME_MS := 1.0        # everything that is not SimDirector's folk ticking, per frame, average
const SLOW_MIN_MS := 30                 # a game minute over this is listed with what it spent the time on
const SLACK := 4.0                       # wall-clock FAIL at SLACK x budget (WARN above the budget)
# ---- wall-clock CEILINGS per profile = about 3x the baseline measured 2026-10-18 (docs/PERFORMANCE.md "Baseline"). The budget above is the goal (a WARN
# "OVER BUDGET" line and a red row in docs/PERF_SCALE_RESULTS.md); the ceiling only catches a regression. Tighten them as steps 17.2+ land, never loosen.
# A profile's FAIL limit is max(SLACK x budget, its ceiling).
const CEIL := {
	"today": {"frame_avg": 6.0, "worst": 300.0, "town": 2.5, "choose": 12.0},       # tightened with the tiers (17.3)
	"big": {"frame_avg": 12.0, "worst": 2500.0, "town": 8.0, "choose": 18.0},
	"mini": {"frame_avg": 6.0, "worst": 300.0, "town": 2.5, "choose": 12.0},
}
# ---- load-independent limits
const MAX_PATHS_PER_CHOOSE := 25
const TARGET_CAND_PER_CHOOSE := 450      # Autonomy.gather rows for one folk: WARN above (target of step 17.4: spatial index), ...
const MAX_CAND_PER_CHOOSE := 3000        # ... FAIL above (the big town: ~2000 for a folk inside a crowded multi-floor lot)
const MAX_PATHS_PER_FILL := 3.0          # avg real path queries per SimDirector._fill call over the run
const MAX_NODE_GROWTH := 1.25            # node count at the end vs after the first measured day (+ 300 slack)
const MAX_MEM_GROWTH := 1.5              # static memory at the end vs after the first measured day

var fails: Array = []
var _sched: SimScheduler = null          # the Clock's scheduler: every clock job is timed there (profile = true)
var _profile: String = ""


func run() -> Array:
	var args := OS.get_cmdline_user_args()
	var profile := "big"
	var days := 3
	var write := true
	for a in args:
		if a.begins_with("--profile="):
			profile = a.substr(10)
		elif a.begins_with("--days="):
			days = int(a.substr(7))
		elif a == "--no-write":
			write = false
	var res := measure(profile, days * 1440)
	print_report(res)
	check(res, true)
	if write:
		append_results(res)
	return fails


# ------------------------------------------------------------------ measure
func measure(profile: String, minutes: int) -> Dictionary:
	var wall0 := Time.get_ticks_msec()
	var info := Town.build(profile)
	info["incident_defs"] = Incidents.list().size()
	var root: Window = Engine.get_main_loop().root
	var clock = root.get_node("Clock")
	var dir = root.get_node("SimDirector")
	var W: WorldGrid = Kit.world()
	Autonomy.full_debug = false                      # as in the game
	var res: Dictionary = {"profile": profile, "info": info, "minutes": minutes, "date": Time.get_datetime_string_from_system(false, true)}
	print("== built '%s': %s tiles, %d lots, %d townies, %d objects, %d buildings, %d towers, %d incident defs in %.1f s" % [profile, str(info["map"]), info["lots"], info["townies"], info["objects"], info["buildings"], info["towers"], info["incident_defs"], info["build_s"]])
	clock.advance_minutes(60)                        # warm-up: caches, the first crowd fill (not measured)
	_sched = SimScheduler.of(clock)
	_sched.reset_stats()
	_sched.profile = true
	dir.prof.clear()
	dir.prof_on = true
	PerfProf.totals.clear()
	PerfProf.on = true
	var pq0: int = Autonomy.path_queries
	var times: PackedInt32Array = PackedInt32Array()
	times.resize(minutes)
	var folk_sum := 0
	var folk_max := 0
	var crowd_max := 0
	var crowd_sum := 0
	var crowd_n := 0
	var tier_sum: Array = [0, 0, 0, 0]
	var tier_n := 0
	var active_max := 0
	var node_max := 0
	var mem_day1 := 0
	var nodes_day1 := 0
	var day_ms: Array = []
	var day_t := 0
	var t_all := 0
	var slow: Array = []                             # minutes over SLOW_MIN_MS: what they spent it on (the worst-frame spikes)
	var before: Dictionary = _snap(dir)
	for m in minutes:
		var t0 := Time.get_ticks_usec()
		clock.advance_minutes(1)
		var dt := Time.get_ticks_usec() - t0
		var after: Dictionary = _snap(dir)
		if dt > SLOW_MIN_MS * 1000 and slow.size() < 6000:
			slow.append([dt, _slow_row(clock.time_string(), dt, before, after)])
		before = after
		times[m] = dt
		t_all += dt
		day_t += dt
		var nf: int = W.folk.size()
		active_max = maxi(active_max, Tiers.set_of(Tiers.ACTIVE).size())
		folk_sum += nf
		folk_max = maxi(folk_max, nf)
		if m % 10 == 0:
			var tc: Array = Tiers.counts()
			for ti in 4:
				tier_sum[ti] += int(tc[ti])
			tier_n += 1
			var nc: int = Crowd.count() + Crowd.staff_folk().size()
			crowd_max = maxi(crowd_max, nc)
			crowd_sum += nc
			crowd_n += 1
		if m % 60 == 0:
			node_max = maxi(node_max, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		if (m + 1) % 1440 == 0:
			day_ms.append(float(day_t) / 1000.0 / 1440.0)
			day_t = 0
			print("   day %d done: %.2f ms/game-min (%d folk, %d nodes)" % [day_ms.size(), day_ms[-1], nf, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
			if day_ms.size() == 1:
				mem_day1 = int(Performance.get_monitor(Performance.MEMORY_STATIC))
				nodes_day1 = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	dir.prof_on = false
	_sched.profile = false
	PerfProf.on = false
	slow.sort_custom(func(a, b): return a[0] > b[0])
	res["slow"] = slow.slice(0, 12).map(func(r): return r[1])
	res["slow_count"] = slow.size()
	res["total_ms"] = float(t_all) / 1000.0
	res["day_ms_per_min"] = day_ms
	var sorted := Array(times)
	sorted.sort()
	res["worst_min_ms"] = float(sorted[sorted.size() - 1]) / 1000.0
	res["p99_min_ms"] = float(sorted[int(sorted.size() * 0.99)]) / 1000.0
	res["median_min_ms"] = float(sorted[sorted.size() / 2]) / 1000.0
	res["folk_avg"] = float(folk_sum) / float(minutes)
	res["folk_max"] = folk_max
	res["active_max"] = active_max
	res["active_cap"] = int(Tiers.cfg().get("active_cap", 60))
	var ticked := 0
	for pk in dir.prof:
		if str(pk).ends_with("needs/buffs/mood"):
			ticked += int((dir.prof[pk] as Array)[1])
	res["folk_ticked_per_min"] = float(ticked) / float(minutes)
	res["tiers_avg"] = tier_sum.map(func(x): return float(x) / float(maxi(tier_n, 1)))
	res["tiers_end"] = Tiers.counts()
	res["crowd_avg"] = float(crowd_sum) / float(maxi(crowd_n, 1))
	res["crowd_max"] = crowd_max
	res["paths_run"] = Autonomy.path_queries - pq0
	res["nodes_max"] = node_max
	res["nodes_end"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	res["nodes_day1"] = nodes_day1
	res["orphans_end"] = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	res["objects_end"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	res["resources_end"] = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	res["mem_end"] = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	res["mem_day1"] = mem_day1
	res["townies_end"] = Story.alive_townies().size()
	res["rows"] = _rows(dir)
	res["sched"] = _sched.stats()
	var fills := 0
	for k in dir.prof:
		if str(k).ends_with("fill (autonomy)"):
			fills += int((dir.prof[k] as Array)[1])
	res["fills"] = fills
	res["choose"] = _sample_choose(W)
	res["wall_s"] = float(Time.get_ticks_msec() - wall0) / 1000.0
	Town.teardown()
	return res


## usec per label of every profiler (scheduler jobs, director phases, PerfProf leaves), cumulative.
func _snap(dir) -> Dictionary:
	var out: Dictionary = {}
	for r in _sched.stats()["rows"]:
		out[_job_key(r)] = int(r["usec"])
	for k in dir.prof:
		out["director/" + k] = dir.prof[k][0]
	for k in PerfProf.totals:
		out[k] = PerfProf.totals[k][0]
	return out


## Row label of a scheduler job: hour / day jobs keep their own "hour/..." "day/..." names, minute jobs are "systems/<name>".
func _job_key(r: Dictionary) -> String:
	var n: String = r["name"]
	return n if (n.begins_with("hour/") or n.begins_with("day/") or int(r["cadence"]) >= 60) else "systems/" + n


func _slow_row(when: String, dt: int, before: Dictionary, after: Dictionary) -> String:
	var d: Array = []
	for k in after:
		var x: int = int(after[k]) - int(before.get(k, 0))
		if x > 4000:
			d.append([k, x])
	d.sort_custom(func(a, b): return a[1] > b[1])
	var parts: Array = []
	for r in d.slice(0, 5):
		parts.append("%s %.0f" % [r[0], r[1] / 1000.0])
	return "%s  %.0f ms: %s" % [when, dt / 1000.0, "; ".join(parts)]


## Rows [label, total ms, calls, ms per game minute, group] sorted by cost. Groups: "listener" (the three scheduler layers: minute without the
## director, the director itself, hour jobs, day jobs; they contain the rows below them), "systems" (minute-layer jobs), "director" (SimDirector phases),
## "leaf" (PerfProf labels inside the systems and the hour / day jobs).
func _rows(dir) -> Array:
	var rows: Array = []
	var st: Dictionary = _sched.stats()
	var dir_us := 0
	var hour_us := 0
	var day_us := 0
	for r in st["rows"]:
		var key := _job_key(r)
		if r["name"] == "SimDirector":
			dir_us += int(r["usec"])
			continue
		if key.begins_with("systems/"):
			rows.append([key, float(r["usec"]) / 1000.0, r["calls"], "systems"])
		else:
			rows.append([key, float(r["usec"]) / 1000.0, r["calls"], "leaf"])
	var lu: Array = st["layer_usec"]
	rows.append(["min  SimDirector", dir_us / 1000.0, _sched.layer_calls[0], "listener"])
	rows.append(["min  scheduler minute jobs (all but the director)", (int(lu[0]) - dir_us) / 1000.0, _sched.layer_calls[0], "listener"])
	rows.append(["hour scheduler hour jobs", int(lu[1]) / 1000.0, _sched.layer_calls[1], "listener"])
	rows.append(["day  scheduler day jobs", int(lu[2]) / 1000.0, _sched.layer_calls[2], "listener"])
	for k in dir.prof:
		rows.append(["director/" + k, dir.prof[k][0] / 1000.0, dir.prof[k][1], "director"])
	for k in PerfProf.totals:
		rows.append([k, PerfProf.totals[k][0] / 1000.0, PerfProf.totals[k][1], "leaf"])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	return rows


## Autonomy.choose for the household and a few crowd NPCs at the end of the run: candidates, real path queries, best-round ms.
func _sample_choose(W: WorldGrid) -> Dictionary:
	var hh: Array = []
	var others: Array = []
	for f in W.all_folk():
		if f.household_id > 0 and not f.has_meta("visitor"):
			hh.append(f)
		elif others.size() < 10:
			others.append(f)
	var out: Dictionary = {}
	for pair in [["household", hh], ["npc", others]]:
		var group: Array = pair[1]
		if group.is_empty():
			continue
		var cands := 0
		for f in group:
			cands = maxi(cands, Autonomy.gather(f).size())
			Autonomy.choose(f)
		var rounds: Array = []
		var q0: int = Autonomy.path_queries
		var calls := 0
		for r in 4:
			var t0 := Time.get_ticks_usec()
			for i in 6:
				Autonomy.choose(group[(r * 6 + i) % group.size()])
				calls += 1
			rounds.append(float(Time.get_ticks_usec() - t0) / 1000.0 / 6.0)
		out[pair[0]] = {"ms": rounds.min(), "paths": float(Autonomy.path_queries - q0) / float(calls), "cands": cands, "n": group.size()}
	return out


# ------------------------------------------------------------------ derived numbers and checks
static func frame_avg_ms(res: Dictionary) -> float:
	return float(res["total_ms"]) / float(res["minutes"]) * FRAME_PER_MIN


## Town-level work per frame: every Clock listener except SimDirector's folk ticking (SystemsManager steps, hourly / daily jobs, social, ...).
static func town_frame_ms(res: Dictionary) -> float:
	var ms := 0.0
	for r in res["rows"]:
		if r[3] == "listener" and not str(r[0]).contains("SimDirector"):
			ms += float(r[1])
	return ms / float(res["minutes"]) * FRAME_PER_MIN


## strict = also the run-length asserts (active-set cap, node / memory growth); wall = FAIL on the wall-clock hard limits (the fast tier only prints them).
func check(res: Dictionary, strict: bool, wall: bool = true) -> void:
	fails = []
	_profile = str(res["profile"])
	var fa := frame_avg_ms(res)
	var tf := town_frame_ms(res)
	var worst: float = res["worst_min_ms"]
	print("-- budgets (OVER BUDGET above the budget, FAIL above max(%.0fx, ceiling)): frame avg %.2f ms / %.1f, worst frame %.1f ms / %.1f, town-level %.2f ms / %.1f" % [SLACK, fa, BUDGET_FRAME_AVG_MS, worst, BUDGET_FRAME_WORST_MS, tf, BUDGET_TOWN_FRAME_MS])
	_budget("simulation per frame (avg)", fa, BUDGET_FRAME_AVG_MS, wall, "frame_avg")
	_budget("simulation worst frame", worst, BUDGET_FRAME_WORST_MS, wall, "worst")
	_budget("town-level work per frame (avg)", tf, BUDGET_TOWN_FRAME_MS, wall, "town")
	var ch: Dictionary = res["choose"]
	if ch.has("household"):
		_budget("household Autonomy.choose", ch["household"]["ms"], BUDGET_CHOOSE_MS, wall, "choose")
	for k in ch:
		var c: Dictionary = ch[k]
		if float(c["paths"]) > MAX_PATHS_PER_CHOOSE:
			fails.append("%s choose makes %.1f path queries per call (max %d)" % [k, c["paths"], MAX_PATHS_PER_CHOOSE])
		if int(c["cands"]) > TARGET_CAND_PER_CHOOSE and int(c["cands"]) <= MAX_CAND_PER_CHOOSE:
			print("   WARN: %s choose gathers %d candidates (target %d)" % [k, c["cands"], TARGET_CAND_PER_CHOOSE])
		if int(c["cands"]) > MAX_CAND_PER_CHOOSE:
			fails.append("%s choose gathers %d candidates (max %d): is the candidate search still bounded to the folk's surroundings?" % [k, c["cands"], MAX_CAND_PER_CHOOSE])
	if int(res["fills"]) > 0:
		var pf: float = float(res["paths_run"]) / float(res["fills"])
		print("-- %.2f path queries per SimDirector fill (max %.1f), %d fills" % [pf, MAX_PATHS_PER_FILL, res["fills"]])
		if pf > MAX_PATHS_PER_FILL:
			fails.append("%.2f path queries per fill (max %.1f)" % [pf, MAX_PATHS_PER_FILL])
	if strict:
		if int(res["active_max"]) > int(res["active_cap"]):
			fails.append("%d ACTIVE people at once (tier cap %d)" % [res["active_max"], res["active_cap"]])
		var cap: int = int(Town.PROFILES.get(res["profile"], {}).get("active_cap", 0))
		if cap > 0 and int(res["folk_max"]) > cap:
			fails.append("%d folk in the world at once (active-set cap %d): crowd / visitors are no longer bounded" % [res["folk_max"], cap])
		if int(res["nodes_day1"]) > 0 and int(res["nodes_end"]) > int(res["nodes_day1"]) * MAX_NODE_GROWTH + 300:
			fails.append("node count grew from %d (day 1) to %d" % [res["nodes_day1"], res["nodes_end"]])
		if int(res["mem_day1"]) > 0 and float(res["mem_end"]) > float(res["mem_day1"]) * MAX_MEM_GROWTH:
			fails.append("static memory grew from %.0f MB (day 1) to %.0f MB: an unbounded history?" % [float(res["mem_day1"]) / 1048576.0, float(res["mem_end"]) / 1048576.0])
	for f in fails:
		print("   FAIL: " + f)


func _budget(what: String, value: float, budget: float, wall: bool = true, ceil_key: String = "") -> void:
	var limit: float = budget * SLACK
	if ceil_key != "" and CEIL.has(_profile):
		limit = maxf(limit, float(CEIL[_profile][ceil_key]))
	if value > limit and wall:
		fails.append("%s %.2f ms (budget %.1f, hard limit %.1f)" % [what, value, budget, limit])
	elif value > budget:
		print("   OVER BUDGET: %s %.2f ms is over its %.1f ms budget (hard limit %.1f)" % [what, value, budget, limit])


# ------------------------------------------------------------------ output
func print_report(res: Dictionary) -> void:
	var minutes: int = res["minutes"]
	var m := float(minutes)
	print("== SCALE '%s': %d game minutes (%.1f days) in %.0f ms (%.2f ms/game-min; per frame at speed 3: avg %.2f ms, worst minute %.1f ms, p99 %.1f, median %.2f)" % [res["profile"], minutes, m / 1440.0, res["total_ms"], res["total_ms"] / m, frame_avg_ms(res), res["worst_min_ms"], res["p99_min_ms"], res["median_min_ms"]])
	print("   ms/game-min by day: %s" % ", ".join((res["day_ms_per_min"] as Array).map(func(x): return "%.2f" % x)))
	print("   folk in world avg %.1f max %d, crowd+staff avg %.1f max %d, townies alive %d, path queries %d (%.2f per game-min)" % [res["folk_avg"], res["folk_max"], res["crowd_avg"], res["crowd_max"], res["townies_end"], res["paths_run"], float(res["paths_run"]) / m])
	print("   tiers (avg active/near/town/statistical): %s; at the end %s; ACTIVE max %d (cap %d); folk ticked per game minute %.1f" % [str((res["tiers_avg"] as Array).map(func(x): return snappedf(x, 0.1))), str(res["tiers_end"]), res["active_max"], res["active_cap"], res["folk_ticked_per_min"]])
	print("   nodes max %d end %d (day 1: %d), orphans %d, objects %d, resources %d, static mem %.0f MB (day 1: %.0f MB)" % [res["nodes_max"], res["nodes_end"], res["nodes_day1"], res["orphans_end"], res["objects_end"], res["resources_end"], float(res["mem_end"]) / 1048576.0, float(res["mem_day1"]) / 1048576.0])
	for k in res["choose"]:
		var c: Dictionary = res["choose"][k]
		print("   choose(%s): %.2f ms best round, %.1f path queries/call, %d candidates, %d folk sampled" % [k, c["ms"], c["paths"], c["cands"], c["n"]])
	print("   %d game minutes over %d ms; the 12 worst:" % [res["slow_count"], SLOW_MIN_MS])
	for r in res["slow"]:
		print("   slow minute " + r)
	print("   ---- by system (ms per game minute; listener rows contain the rows below them) ----")
	var shown := 0
	for r in res["rows"]:
		if float(r[1]) / m < 0.02:
			continue
		print("   %-8s %-52s %8.3f ms/min %9.0f ms %9d calls" % [r[3], r[0], float(r[1]) / m, r[1], r[2]])
		shown += 1
	print("   (%d rows >= 0.02 ms/min of %d)" % [shown, res["rows"].size()])
	var st: Dictionary = res["sched"]
	print("   scheduler: %d jobs, %d ticks, deferred %d (pending %d), timed fired %d" % [st["jobs"], st["ticks"], st["deferred_total"], st["deferred_pending"], st["timed_fired"]])


## Append a dated section to docs/PERF_SCALE_RESULTS.md (header added when the file is new).
func append_results(res: Dictionary) -> void:
	var path := ProjectSettings.globalize_path(RESULTS)
	var header := "# Scale benchmark results\n\nAppended by `tests/perf_scale.gd` (tools/run_scale.ps1). One section per run; compare the `ms/game-min` and `frame avg` lines between runs (a regression over 10% needs a written reason in the done message). Machine load is not controlled: compare the load-independent counts first.\n"
	var existing := ""
	if FileAccess.file_exists(path):
		existing = FileAccess.get_file_as_string(path)
	if existing == "":
		existing = header
	var m := float(res["minutes"])
	var info: Dictionary = res["info"]
	var s := "\n## %s  %s  (%d lots, %d townies, map %s, %.1f days)\n\n" % [res["date"], res["profile"], info["lots"], res["townies_end"], str(info["map"]), m / 1440.0]
	s += "- **ms/game-min %.2f** | frame avg %.2f ms (budget %.0f) | worst minute %.1f ms (budget %.0f) | p99 %.1f | median %.2f | town-level %.2f ms/frame (budget %.0f) | by day: %s\n" % [res["total_ms"] / m, frame_avg_ms(res), BUDGET_FRAME_AVG_MS, res["worst_min_ms"], BUDGET_FRAME_WORST_MS, res["p99_min_ms"], res["median_min_ms"], town_frame_ms(res), BUDGET_TOWN_FRAME_MS, ", ".join((res["day_ms_per_min"] as Array).map(func(x): return "%.2f" % x))]
	s += "- tiers (avg active / near / town / statistical): %s; ACTIVE max %d (cap %d); folk ticked per game minute %.1f; at the end %s
" % [str((res["tiers_avg"] as Array).map(func(x): return snappedf(x, 0.1))), res["active_max"], res["active_cap"], res["folk_ticked_per_min"], str(res["tiers_end"])]
	s += "- folk in world avg %.1f / max %d; crowd+staff avg %.1f / max %d; path queries %d (%.2f/game-min, %d fills); " % [res["folk_avg"], res["folk_max"], res["crowd_avg"], res["crowd_max"], res["paths_run"], float(res["paths_run"]) / m, res["fills"]]
	for k in res["choose"]:
		var c: Dictionary = res["choose"][k]
		s += "choose(%s) %.2f ms, %.1f paths, %d cands; " % [k, c["ms"], c["paths"], c["cands"]]
	s += "\n- nodes max %d / end %d (day 1: %d), orphans %d, objects %d, resources %d, static mem %.0f MB (day 1 %.0f MB); build %.1f s, run %.0f s wall\n\n" % [res["nodes_max"], res["nodes_end"], res["nodes_day1"], res["orphans_end"], res["objects_end"], res["resources_end"], float(res["mem_end"]) / 1048576.0, float(res["mem_day1"]) / 1048576.0, info["build_s"], res["wall_s"]]
	if not (res["slow"] as Array).is_empty():
		s += "- slow minutes (> %d ms): %s\n\n" % [SLOW_MIN_MS, " / ".join((res["slow"] as Array).slice(0, 8))]
	var sst: Dictionary = res["sched"]
	s += "- scheduler: %d jobs, deferred %d (pending at end %d), timed fired %d; ms per game minute by system: %s" % [sst["jobs"], sst["deferred_total"], sst["deferred_pending"], sst["timed_fired"], _by_owner_text(sst, m)] + "\n\n"
	s += "| group | row | ms/game-min | total ms | calls |\n|---|---|---|---|---|\n"
	var n := 0
	for r in res["rows"]:
		if n >= 30 or float(r[1]) / m < 0.02:
			break
		s += "| %s | %s | %.3f | %.0f | %d |\n" % [r[3], r[0], float(r[1]) / m, r[1], r[2]]
		n += 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("   (could not write %s)" % path)
		return
	f.store_string(existing + s)
	f.close()
	print("   results appended to docs/PERF_SCALE_RESULTS.md")


func _by_owner_text(st: Dictionary, minutes: float) -> String:
	var rows: Array = []
	for o in st["by_owner"]:
		rows.append([o, float(st["by_owner"][o]["usec"]) / 1000.0 / minutes, int(st["by_owner"][o]["deferred"])])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	var parts: Array = []
	for r in rows.slice(0, 14):
		parts.append("%s %.2f%s" % [r[0], r[1], (" (%d deferred)" % r[2]) if r[2] > 0 else ""])
	return ", ".join(parts)
