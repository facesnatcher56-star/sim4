class_name StorytellerTilt
extends RefCounted
## Owner rule 43 (no magic events): the storyteller never creates an outcome. A card that names a real incident (a burglary, a cold, a burst pipe ...)
## only RAISES THE ODDS of that incident's own roll for one subject for a few days; the roll then runs the incident's own conditions, risk and prevention
## (locks, alarms, wealth, skills, the police, insurance ...) like any other roll. Nothing is announced: no warning, no toast.
## State: [{id, key, mult, until}] saved with the storyteller. Strength per card size: data/storyteller.json "tilt" {small|medium|big: [mult, days]}.

static var tilts: Array = []

static func reset() -> void:
	tilts = []

static func cfg() -> Dictionary:
	return (Storyteller.cfg().get("tilt", {}) as Dictionary)

## Subject key as the tilt table knows it: "home:<hid>" / "town:<n>" for lots, "folk:<id>", "townie:<id>".
static func key_of(s) -> String:
	match str(s.kind):
		"folk":
			return "folk:%d" % int(s.id)
		"townie":
			return "townie:%d" % int(s.id)
	return str(s.lot_key)

static func add(incident_id: String, key: String, size: String) -> void:
	var spec: Array = cfg().get(size, [6.0, 2])
	tilts.append({"id": incident_id, "key": key, "mult": float(spec[0]), "until": SysUtil.day() + int(spec[1])})

## Product of the active tilts of this incident on this subject (1.0 when none).
static func mult(incident_id: String, s) -> float:
	if tilts.is_empty():
		return 1.0
	var key: String = key_of(s)
	var m: float = 1.0
	for t in tilts:
		if str(t["id"]) == incident_id and str(t["key"]) == key:
			m *= float(t["mult"])
	return m

static func on_day(day: int) -> void:
	if tilts.is_empty():
		return
	tilts = tilts.filter(func(t): return int(t["until"]) >= day)

static func to_dict() -> Array:
	return tilts.duplicate(true)

static func from_dict(a) -> void:
	tilts = []
	if a is Array:
		for t in a:
			tilts.append({"id": str((t as Dictionary).get("id", "")), "key": str(t.get("key", "")), "mult": float(t.get("mult", 1.0)), "until": int(t.get("until", 0))})
