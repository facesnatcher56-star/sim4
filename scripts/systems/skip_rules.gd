class_name SkipRules
extends RefCounted
## When somebody "chooses to skip" school or work (task 19j). Something else of the player's queued on a folk at shift time used to be a skip every time: 14 skips in
## 168 days in one household, both children on the same morning. Now it is a decision, once per person per day and kind: a small base chance that lazy, hot-headed or
## stubborn folk and folk in a bad mood raise and diligent or cheerful folk lower; a housemate who already skipped today makes a second skip very unlikely unless this
## person has a strong reason (a skipping trait AND a bad mood). Skipping on purpose with the "skip work today" command is not touched (Careers.skip_flags).
## Data: data/careers.json "skip". Randomness: the shared seeded stream, asked once per person per day and kind (the answer is remembered).

static var decided: Dictionary = {}        # folk id -> {day, kind, skip}
static var household_log: Dictionary = {}  # household id -> {day, ids: [folk ids who skipped today]}

static func cfg() -> Dictionary:
	return Careers.cfg().get("skip", {})

static func reset() -> void:
	decided.clear()
	household_log.clear()

## Has this person a skipping trait and a bad mood: the only way two housemates skip on the same morning.
static func strong_reason(f) -> bool:
	var c: Dictionary = cfg()
	var tm: Dictionary = c.get("trait_mult", {})
	var traity := false
	for t in f.traits:
		if float(tm.get(str(t), 1.0)) > 1.0:
			traity = true
	return traity and float((c.get("mood_mult", {}) as Dictionary).get(str(f.mood_name), 1.0)) > 1.0

## The chance (0..1) this person skips `kind` ("work" | "school") today, before the housemate rule.
static func chance(f, kind: String) -> float:
	var c: Dictionary = cfg()
	var p: float = float(c.get("base_" + kind, c.get("base", 0.1)))
	var tm: Dictionary = c.get("trait_mult", {})
	for t in f.traits:
		p *= float(tm.get(str(t), 1.0))
	p *= float((c.get("mood_mult", {}) as Dictionary).get(str(f.mood_name), 1.0))
	return clampf(p, 0.0, float(c.get("max", 0.6)))

## True when this person really does skip. Asked by the shift / school start and again by the commute: the first answer of the day stands.
static func chooses_to_skip(f, kind: String) -> bool:
	if Pawn.is_pawn(f):          # the player's character never skips on their own
		return false
	var fid: int = int(f.id)
	var day: int = SysUtil.day()
	var d: Dictionary = decided.get(fid, {})
	if not d.is_empty() and int(d["day"]) == day and str(d["kind"]) == kind:
		return bool(d["skip"])
	var p: float = chance(f, kind)
	var hid: int = int(f.household_id)
	var log: Dictionary = household_log.get(hid, {})
	var others: Array = (log.get("ids", []) as Array) if int(log.get("day", -1)) == day else []
	if not others.is_empty():
		p = p * float(cfg().get("housemate_mult", 0.15)) if strong_reason(f) else 0.0
	var skip: bool = SysUtil.chance(p) if p > 0.0 else false
	decided[fid] = {"day": day, "kind": kind, "skip": skip}
	if skip:
		if int(log.get("day", -1)) != day:
			log = {"day": day, "ids": []}
		(log["ids"] as Array).append(fid)
		household_log[hid] = log
	return skip

static func to_dict() -> Dictionary:
	return {"decided": SysUtil.str_keys(decided).duplicate(true), "log": SysUtil.str_keys(household_log).duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	reset()
	decided = SysUtil.int_keys((d.get("decided", {}) as Dictionary).duplicate(true))
	household_log = SysUtil.int_keys((d.get("log", {}) as Dictionary).duplicate(true))
