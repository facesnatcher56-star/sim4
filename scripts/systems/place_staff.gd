class_name PlaceStaff
extends RefCounted
## Who works where (task 14). Every place lists staff roles (`staff: [{role, career, n}]`); the roster is filled with townies whose career matches
## (they are the same people the commute system sends to that workplace) and, for the rest, LOCALS: a name and a role, no body on the map
## (statistical staff, never ACTIVE). A place with fewer staff than `min_staff` is "short of staff" and closed; a daily dice turns locals over
## (a new face, a line of news) and, rarely, shuts a place for the day (a sick day, a burst pipe) with a news line.
## Tier: TOWN-wide, DAILY, ~40 places x a handful of entries. Saved in the `life` block. Own seeded rng.

const SEED := 140041

static var rosters: Dictionary = {}       # place id -> [{"id": townie id or 0, "name", "role"}]
static var closures: Dictionary = {}      # place id -> {"day": last closed day, "why": text}
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	rosters.clear()
	closures.clear()
	rng = RandomNumberGenerator.new()
	rng.seed = SEED

static func cfg() -> Dictionary:
	return LifeDefs.cfg("staff")

static func roster(pid: String) -> Array:
	return rosters.get(pid, [])

static func min_staff(pid: String) -> int:
	var d: Dictionary = Places.def(pid)
	return int(d.get("min_staff", 1)) if d.has("staff") else 0

static func staffed(pid: String) -> bool:
	return roster(pid).size() >= min_staff(pid)

static func closed_today(pid: String) -> bool:
	return int((closures.get(pid, {}) as Dictionary).get("day", -1)) == SysUtil.day()

static func names(pid: String) -> Array:
	return roster(pid).map(func(e): return str(e["name"]))

## "Dr. Ana Reyes" style line for the first member with this role keyword ("" when nobody).
static func who(pid: String, role_part: String = "") -> String:
	for e in roster(pid):
		if role_part == "" or str(e["role"]).to_lower().find(role_part.to_lower()) >= 0:
			return str(e["name"])
	return ""

static func _needed(pid: String) -> Array:
	var out: Array = []
	for spec in Places.def(pid).get("staff", []):
		for _i in int(spec.get("n", 1)):
			out.append(spec)
	return out

static func _valid(e: Dictionary) -> bool:
	var tid: int = int(e.get("id", 0))
	if tid <= 0:
		return true
	var t: Dictionary = Story.townies.get(tid, {})
	return not t.is_empty() and bool(t.get("alive", false)) and not JusticeState.inmates.has(tid) and not Hospital.is_in(tid)

static func _employed_elsewhere(tid: int, pid: String) -> bool:
	for p2 in rosters:
		if p2 != pid:
			for e in rosters[p2]:
				if int(e["id"]) == tid:
					return true
	return false

static func _townie_for(spec: Dictionary, pid: String, taken: Array) -> Dictionary:
	var career: String = str(spec.get("career", ""))
	if career == "":
		return {}
	for t in Story.free_townies():
		var tid: int = int(t["id"])
		if str(t.get("career", "")) == career and Story.stage_of(t) == "adult" and not taken.has(tid) and not _employed_elsewhere(tid, pid):
			return t
	return {}

static func _local(spec: Dictionary) -> Dictionary:
	var sex: String = "female" if rng.randf() < 0.5 else "male"
	return {"id": 0, "name": "%s %s" % [Names.pick_first([], rng, sex), Names.pick_last(rng)], "role": str(spec.get("role", "Staff"))}

## Fill the rosters (a new game, a load without the block, or any time: idempotent). Returns the number of new hires.
static func fill_all(announce: bool = false) -> int:
	var hired := 0
	for pid in Places.all():
		var roster_now: Array = (rosters.get(pid, []) as Array).filter(func(e): return _valid(e))
		var taken: Array = roster_now.map(func(e): return int(e["id"]))
		var need: Array = _needed(pid)
		var have_roles: Dictionary = {}
		for e in roster_now:
			have_roles[e["role"]] = int(have_roles.get(e["role"], 0)) + 1
		for spec in need:
			var role: String = str(spec.get("role", "Staff"))
			if int(have_roles.get(role, 0)) > 0:
				have_roles[role] = int(have_roles[role]) - 1
				continue
			var t: Dictionary = _townie_for(spec, pid, taken)
			var e2: Dictionary
			if t.is_empty():
				e2 = _local(spec)
			else:
				e2 = {"id": int(t["id"]), "name": str(t["name"]), "role": role}
				taken.append(int(t["id"]))
			roster_now.append(e2)
			hired += 1
			if announce:
				LifeNote.news(pid, "%s joined %s as %s." % [e2["name"], Places.label(pid), _a(role)])
		rosters[pid] = roster_now
	return hired

static func _a(role: String) -> String:
	return ("an " if role.to_lower()[0] in ["a", "e", "i", "o", "u"] else "a ") + role.to_lower()

## Daily: leavers are replaced, locals turn over now and then, a place is rarely shut for the day.
static func on_day(day: int) -> void:
	var c: Dictionary = cfg()
	var turnover: float = float(c.get("turnover_per_day", 0.012))
	var shut: float = float(c.get("closure_per_day", 0.006))
	for pid in Places.all():          # dictionary order = data order: stable
		var r: Array = rosters.get(pid, [])
		for i in range(r.size() - 1, -1, -1):
			if int(r[i]["id"]) == 0 and rng.randf() < turnover:
				r.remove_at(i)
		if min_staff(pid) > 0 and rng.randf() < shut:
			var reasons: Array = c.get("closure_reasons", ["a burst pipe"])
			var why: String = str(reasons[rng.randi_range(0, reasons.size() - 1)])
			closures[pid] = {"day": day, "why": why}
			LifeNote.news(pid, "%s is closed today because of %s." % [Places.label(pid), why])
	fill_all(true)

static func to_dict() -> Dictionary:
	return {"rosters": rosters.duplicate(true), "closures": closures.duplicate(true), "rng_state": str(rng.state)}

static func from_dict(d: Dictionary) -> void:
	reset()
	rosters = (d.get("rosters", {}) as Dictionary).duplicate(true)
	for pid in rosters:
		for e in rosters[pid]:
			e["id"] = int(e["id"])
	closures = (d.get("closures", {}) as Dictionary).duplicate(true)
	for pid in closures:
		closures[pid]["day"] = int(closures[pid]["day"])
	if d.has("rng_state"):
		rng.state = int(str(d["rng_state"]))
