class_name EduState
extends RefCounted
## Education records (task 14): one small record per person who has ever studied (residents AND townies), plus the town's job board state.
## Saved in the `life` block (`edu`). Record keys: degrees [ids], diploma "" | letter, certs [ids], courses {id: lessons}, college {major, credits,
## lectures, scores[]}, reports [{day, avg, letter, comment}], hw {due, set_day, missed}, preschool bool, early float, grade_seen float.

static var recs: Dictionary = {}          # person id -> record
static var fired: Dictionary = {}         # school event id -> calendar year it last ran
static var board: Dictionary = {}         # job board: {week, openings {career: n}, demand {career: factor}}
static var last_term: int = -1            # the term number of the last report cards
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

const SEED := 140051

static func reset() -> void:
	recs.clear()
	fired.clear()
	board = {}
	last_term = -1
	rng = RandomNumberGenerator.new()
	rng.seed = SEED

static func cfg() -> Dictionary:
	return LifeDefs.cfg("education")

static func rec(id: int) -> Dictionary:
	if not recs.has(id):
		recs[id] = {"degrees": [], "diploma": "", "certs": [], "courses": {}, "college": {}, "reports": [], "hw": {"due": false, "set_day": -1, "missed": 0},
			"preschool": false, "early": 0.0, "grade_seen": 0.0}
	return recs[id]

static func peek(id: int) -> Dictionary:
	return recs.get(id, {})

static func has_degree(id: int, degree: String = "") -> bool:
	var d: Array = (peek(id).get("degrees", []) as Array)
	return not d.is_empty() if degree == "" else d.has(degree)

static func degrees(id: int) -> Array:
	return (peek(id).get("degrees", []) as Array).duplicate()

static func has_cert(id: int, course: String) -> bool:
	return (peek(id).get("certs", []) as Array).has(course)

static func forget(id: int) -> void:
	recs.erase(id)

static func stage_of(id: int) -> String:
	var f = SysUtil.folk(id)
	if f != null:
		return str(f.age_stage)
	var t: Dictionary = Story.townies.get(id, {})
	return Story.stage_of(t) if not t.is_empty() else ""

static func to_dict() -> Dictionary:
	return {"recs": SysUtil.str_keys(recs).duplicate(true), "fired": fired.duplicate(), "board": board.duplicate(true), "last_term": last_term, "rng_state": str(rng.state)}

static func from_dict(d: Dictionary) -> void:
	reset()
	recs = SysUtil.int_keys((d.get("recs", {}) as Dictionary).duplicate(true))
	for id in recs:
		var r: Dictionary = recs[id]
		var cs: Dictionary = {}
		for k in (r.get("courses", {}) as Dictionary):
			cs[str(k)] = int(r["courses"][k])
		r["courses"] = cs
		var c: Dictionary = r.get("college", {})
		if not c.is_empty():
			c["credits"] = int(c.get("credits", 0))
			c["lectures"] = int(c.get("lectures", 0))
		r["early"] = float(r.get("early", 0.0))
		var hw: Dictionary = r.get("hw", {})
		hw["set_day"] = int(hw.get("set_day", -1))
		hw["missed"] = int(hw.get("missed", 0))
	for k in (d.get("fired", {}) as Dictionary):
		fired[str(k)] = int(d["fired"][k])
	board = (d.get("board", {}) as Dictionary).duplicate(true)
	if board.has("week"):
		board["week"] = int(board["week"])
		var op: Dictionary = {}
		for k in (board.get("openings", {}) as Dictionary):
			op[str(k)] = int(board["openings"][k])
		board["openings"] = op
	last_term = int(d.get("last_term", -1))
	if d.has("rng_state"):
		rng.state = int(str(d["rng_state"]))
