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
##   (task 32c) "weekend": true|false               # Saturday + Sunday only | weekdays only
##              "moods": ["sad", ...]               # only while the folk's mood is one of these
##              "traits_any": ["night_owl"]         # only folk with at least one of these traits
##              "stages": ["child", "teen"]         # only these life stages
## }

## The routines that are active for `folk` right now ([[id, def], ...]); depends on the time of day and the job only, so one
## decision can compute it once and pass it to evaluate() for every candidate.
static func active_routines(folk) -> Array:
	var out: Array = []
	var routines: Dictionary = SimEnv.data().routines()
	var wk: bool = posmod(int(SimEnv.clock().day()) - 1, 7) >= 5
	var h: float = SimEnv.hour_f()
	for rid in routines:
		if _active(folk, routines[rid], wk, h):
			out.append([rid, routines[rid]])
	return out

## Returns {"mult": float, "bonus": float, "names": Array[String]} for an interaction. `active` = active_routines(folk) when
## the caller already has it.
static func evaluate(folk, def_id: String, tags: Array, active: Variant = null) -> Dictionary:
	var mult := 1.0
	var bonus := 0.0
	var names: Array = []
	if active == null:
		active = active_routines(folk)
	for pair in active:
		var rid = pair[0]
		var r: Dictionary = pair[1]
		if bool(r.get("once", false)) and not folk.routine_log.is_empty() and folk.routine_log.has(_log_key(str(rid), def_id)):
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
		if bool(r.get("once", false)) and _active(folk, r, posmod(int(SimEnv.clock().day()) - 1, 7) >= 5):
			folk.routine_log[_log_key(str(rid), def_id)] = true
	if folk.routine_log.size() > 200:
		folk.routine_log.clear()

static func _log_key(rid: String, def_id: String) -> String:
	return "%s:%d:%s" % [rid, int(SimEnv.clock().day()), def_id]

static func _active(folk, r: Dictionary, wk: bool = false, h: float = -1.0) -> bool:
	for req in r.get("requires", []):
		match str(req):
			"has_job":
				if not folk.has_job():
					return false
			"no_job":
				if folk.has_job():
					return false
	if r.has("weekend") and bool(r["weekend"]) != wk:
		return false
	if r.has("stages") and not (r["stages"] as Array).has(str(folk.age_stage)):
		return false
	if r.has("moods") and not (r["moods"] as Array).has(str(folk.mood_name)):
		return false
	if r.has("traits_any"):
		var any_t := false
		for t in r["traits_any"]:
			if folk.has_trait(str(t)):
				any_t = true
				break
		if not any_t:
			return false
	if r.has("circadian") and not Circadian.in_phase(folk, str(r["circadian"])):
		return false
	if h < 0.0:
		h = SimEnv.hour_f()
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
