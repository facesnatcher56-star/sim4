extends RefCounted
## Fast-tier twin of tests/perf_scale.gd: builds the generated "mini" town (4x3 slots, 11 lots, ~24 townies, one level_kit tower)
## and runs 2-4 game hours. Checks only load-independent things: the generator still works through the real game paths,
## the work counts stay bounded (path queries per choose / per fill, candidates per choose, folk in the world vs the active-set cap)
## and the report code runs. No wall-clock assert, no results file (the big benchmark does that).

const Scale = preload("res://tests/perf_scale.gd")
const MINI_ACTIVE_CAP := 45

func run() -> Array:
	var fails: Array = []
	var s := Scale.new()
	var res := s.measure("mini", TestFixture.pick(240, 120))
	var info: Dictionary = res["info"]
	if int(info["lots"]) != 11:
		fails.append("mini town has %d lots, expected 11" % int(info["lots"]))
	if (info["map"] as Vector2i) != Vector2i(160, 106):
		fails.append("mini map is %s" % str(info["map"]))
	if int(info["townies"]) < 20:
		fails.append("only %d townies" % int(info["townies"]))
	if int(res["folk_max"]) > MINI_ACTIVE_CAP:
		fails.append("%d folk in the world (cap %d)" % [int(res["folk_max"]), MINI_ACTIVE_CAP])
	s.check(res, false, false)
	fails.append_array(s.fails)
	print("  [perf_scale mini] %.2f ms/game-min, folk avg %.1f max %d, %d townies, %.1f s build" % [res["total_ms"] / float(res["minutes"]), res["folk_avg"], res["folk_max"], int(info["townies"]), info["build_s"]])
	return fails
