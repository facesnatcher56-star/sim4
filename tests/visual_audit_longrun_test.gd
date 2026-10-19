extends RefCounted
## SLOW tier (task 27): the reviewer's visual audit (tests/visual_audit.gd) turned into a test. The real new-game path, every folk (household, guests,
## townies) with a real FolkView, 2 game hours at each speed (frame time 1/60 s), measuring what the player sees: Run frames while walking (non-urgent),
## sitting poses without a seat or with a standing clip, standing on a blocked tile outside its slot, folk on top of each other.
const VK = preload("res://tests/visual_kit.gd")

const GAME_MINUTES := 120
const RUN_MAX := 0.05
const OVERLAP_MAX := 0.01
const BLOCKED_WALK_MAX := 0.005      # a folk stepping out of a seat or stall is still inside the blocked tile for a few frames


func run() -> Array:
	var fails: Array = []
	for speed in [1, 2, 3]:
		var m: Dictionary = VK.run_audit(speed, GAME_MINUTES)
		var ff: float = maxf(float(m["folk_frames"]), 1.0)
		var mv: float = maxf(float(m["move"]), 1.0)
		print("VISUAL speed %d: %d frames, %d folk-frames, moving %d (run %d = %.1f%%, urgent run %d), sitting %d (no seat %d, standing clip %d), blocked still %d / walking %d (%.2f%%), overlap %d (%.2f%%)" % [
			speed, m["frames"], m["folk_frames"], m["move"], m["run"], 100.0 * float(m["run"]) / mv, m["run_urgent"], m["sit"], m["sit_no_seat"], m["sit_stand_clip"],
			m["blocked_still"], m["blocked_move"], 100.0 * float(int(m["blocked_still"]) + int(m["blocked_move"])) / ff, m["overlap"], 100.0 * float(m["overlap"]) / ff])
		var an: Dictionary = m["anoms"]
		var ks: Array = an.keys()
		ks.sort_custom(func(a, b): return an[a] > an[b])
		var top := ""
		for k in ks.slice(0, 4):
			top += "[%d x %s] " % [an[k], str(k).substr(0, 60)]
		var tag := "speed %d" % speed
		_check(fails, int(m["move"]) > 300, "%s: only %d moving folk-frames, the audit saw nothing walk" % [tag, int(m["move"])])
		_check(fails, int(m["folk_frames"]) > 5000, "%s: only %d folk-frames" % [tag, int(m["folk_frames"])])
		_check(fails, float(m["run"]) / mv < RUN_MAX, "%s: %.1f%% of moving frames play Run for a non-urgent walk (max %.0f%%) %s" % [tag, 100.0 * float(m["run"]) / mv, 100.0 * RUN_MAX, top])
		_check(fails, int(m["sit_no_seat"]) == 0, "%s: %d sitting frames without a seat %s" % [tag, int(m["sit_no_seat"]), top])
		_check(fails, int(m["sit_stand_clip"]) == 0, "%s: %d sitting frames with a standing clip %s" % [tag, int(m["sit_stand_clip"]), top])
		_check(fails, int(m["blocked_still"]) == 0, "%s: %d frames standing still on a blocked tile outside a slot %s" % [tag, int(m["blocked_still"]), top])
		_check(fails, float(m["blocked_move"]) / ff <= BLOCKED_WALK_MAX, "%s: %d frames walking over blocked tiles %s" % [tag, int(m["blocked_move"]), top])
		_check(fails, float(m["overlap"]) / ff < OVERLAP_MAX, "%s: %.2f%% of folk-frames overlap another folk (max %.0f%%) %s" % [tag, 100.0 * float(m["overlap"]) / ff, 100.0 * OVERLAP_MAX, top])
	return fails


func _check(fails: Array, cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
