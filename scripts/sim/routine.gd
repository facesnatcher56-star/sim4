class_name Routine
extends RefCounted
## Data-driven daily routines (data/routines.json). A routine is active in a time window and boosts
## interactions carrying certain tags, e.g. "prepare" (shower, eat, brush teeth) before work.
##
## "routine_id": {
##   "label": "getting ready for work",
##   "requires": ["has_job"] | ["no_job"],          # optional
##   "before_work_hours": [2.5, 0.0],               # window = [work_start-2.5h, work_start-0h)   (needs a job)
##   "time_between": [22, 24],                      # absolute window (hours, may wrap midnight)
##   "tag_mult": {"prepare": 2.0},                  # score multiplier for interactions with the tag
##   "tag_bonus": {"prepare": 4.0},                 # flat score bonus (added after multipliers)
##   "once": true                                   # each interaction only boosted once per day per routine
## }

## Returns {"mult": float, "bonus": float, "names": Array[String]} for an interaction.
static func evaluate(folk, def_id: String, tags: Array) -> Dictionary:
	var mult := 1.0
	var bonus := 0.0
	var names: Array = []
	var routines: Dictionary = SimEnv.data().routines()
	for rid in routines:
		var r: Dictionary = routines[rid]
		if not _active(folk, r):
			continue
		if bool(r.get("once", false)) and folk.routine_log.has(_log_key(str(rid), def_id)):
			continue
		var hit := false
		var tm: Dictionary = r.get("tag_mult", {})
		for t in tm:
			if tags.has(t):
				mult *= float(tm[t])
				hit = true
		var tb: Dictionary = r.get("tag_bonus", {})
		for t in tb:
			if tags.has(t):
				bonus = maxf(bonus, float(tb[t]))
				hit = true
		if hit:
			names.append(str(r.get("label", rid)))
	return {"mult": mult, "bonus": bonus, "names": names}

## Called when an interaction finishes so "once" routines stop boosting it.
static func mark_done(folk, def_id: String) -> void:
	var routines: Dictionary = SimEnv.data().routines()
	for rid in routines:
		var r: Dictionary = routines[rid]
		if bool(r.get("once", false)) and _active(folk, r):
			folk.routine_log[_log_key(str(rid), def_id)] = true
	if folk.routine_log.size() > 200:
		folk.routine_log.clear()

static func _log_key(rid: String, def_id: String) -> String:
	return "%s:%d:%s" % [rid, int(SimEnv.clock().day()), def_id]

static func _active(folk, r: Dictionary) -> bool:
	for req in r.get("requires", []):
		match str(req):
			"has_job":
				if not folk.has_job():
					return false
			"no_job":
				if folk.has_job():
					return false
	var h: float = SimEnv.hour_f()
	if r.has("before_work_hours"):
		if not folk.has_job():
			return false
		var bw: Array = r["before_work_hours"]
		var lo: float = fposmod(folk.work_start - float(bw[0]), 24.0)
		var hi: float = fposmod(folk.work_start - float(bw[1]), 24.0)
		if not _in_window(h, lo, hi):
			return false
	if r.has("time_between"):
		var tb: Array = r["time_between"]
		if not _in_window(h, float(tb[0]), float(tb[1])):
			return false
	return true

static func _in_window(h: float, lo: float, hi: float) -> bool:
	if is_equal_approx(lo, hi):
		return false
	if lo < hi:
		return h >= lo and h < hi
	return h >= lo or h < hi
