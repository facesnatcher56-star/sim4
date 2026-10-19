extends RefCounted
## Guard for the cost of one autonomous decision for a household folk on the full 160x120 map (fixed-seed new game).
## Two checks, because wall-clock time alone is noisy when other processes load the machine:
##  - structure (load independent): at most MAX_PATHS real path_length queries per Autonomy.choose (it was one per candidate,
##    ~100, each a full A* before the cache fix);
##  - time: Autonomy.choose is timed in ROUNDS rounds of CALLS calls and the BEST round's average must stay under BUDGET_MS.
## Wall-clock is noisy on a shared machine, so the time check only fails at BUDGET_MS x SLACK_MS (24 ms; the old code took 26-40 ms
## quiet, 9-10 ms was the round-1 figure under load, about 6 ms now under load). The load-independent check is the number of real path
## queries per choose (MAX_PATHS). The measured numbers are always printed.

const Kit = preload("res://tests/hood_kit.gd")
const BUDGET_MS := 8.0
const SLACK_MS := 3.0                         # the wall-clock check fails at BUDGET_MS x SLACK_MS (24 ms), far below the old 26-40 ms but safe on a busy machine
const MAX_PATHS := 12                         # about 7 now (it was ~19 with the DETAIL_N stopping rule and ~100 before the bound ranking)
const ROUNDS := 5
const CALLS := 12

var fails: Array = []

func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("classic", 777)
	Kit.set_time(2, 12)
	Autonomy.full_debug = false                   # as in the game
	var n_cands := 0
	for f in folk:
		n_cands += Autonomy.gather(f).size()
		Autonomy.choose(f)                        # warm: caches, graph, distance fields
	var rounds: Array = []
	var q0 := Autonomy.path_queries
	for r in ROUNDS:
		var t0 := Time.get_ticks_usec()
		for i in CALLS:
			Autonomy.choose(folk[i % folk.size()])
		rounds.append(float(Time.get_ticks_usec() - t0) / 1000.0 / float(CALLS))
	var paths := float(Autonomy.path_queries - q0) / float(ROUNDS * CALLS)
	var best: float = rounds.min()
	print("  [perf] Autonomy.choose best round %.2f ms (rounds: %s; ~%d candidates/folk, %.1f path queries per choose), budget %.1f ms / %d paths" % [best, ", ".join(rounds.map(func(x): return "%.1f" % x)), n_cands / folk.size(), paths, BUDGET_MS, MAX_PATHS])
	if best >= BUDGET_MS * SLACK_MS:
		fails.append("Autonomy.choose averages %.2f ms in its best round (budget %.1f ms x %.0f)" % [best, BUDGET_MS, SLACK_MS])
	if paths > MAX_PATHS:
		fails.append("Autonomy.choose makes %.1f path queries per call (max %d): is the distance-free ranking still pruning?" % [paths, MAX_PATHS])
	Kit.teardown()
	return fails