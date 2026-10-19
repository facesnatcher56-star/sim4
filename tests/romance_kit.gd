extends RefCounted
## Helpers for the romance long runs (no run(), so the runner skips it): watches a running game for anything romantic, intimate or
## cheating that involves a minor or a relative.

const EVENTS := ["relationship_status", "date_accepted", "date_completed", "first_kiss", "married", "engaged", "pregnant", "baby_born",
	"cheating_discovered", "feelings_shared", "breakup"]

var violations: Array = []
var events_seen: int = 0
var romantic_runs: int = 0
var _dir_events: Array = []

func start() -> void:
	SimEnv.events().game_event.connect(func(n, p): _dir_events.append([n, p, SysUtil.day()]))

func _bad_pair(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and a != b and not RomanceRules.allowed(a, b)

## Call about once per game hour: the stored state, the new events and the running interactions.
func scan(folk: Array) -> void:
	for e in _dir_events:
		if EVENTS.has(str(e[0])):
			events_seen += 1
			var p: Dictionary = e[1]
			var x: int = int(p.get("folk_id", -1))
			var y: int = int(p.get("target_id", -1))
			var bad: bool = _bad_pair(x, y)
			if str(e[0]) == "cheating_discovered":     # victim, cheater, other: the cheater's fling is the pair that matters
				bad = _bad_pair(y, int(p.get("other_id", -1)))
			if bad:
				violations.append("day %d event %s %s" % [e[2], e[0], str(p)])
	_dir_events.clear()
	for key in RelationshipService.pairs:
		var p2: Dictionary = RelationshipService.pairs[key]
		var a: int = int(p2["lo"])
		var b: int = int(p2["hi"])
		if RomanceRules.allowed(a, b):
			continue
		for fl in RomanceRules.ROMANTIC_FLAGS:
			if fl != "ex" and bool((p2["flags"] as Dictionary).get(fl, false)):
				violations.append("day %d pair %d/%d has bit %s" % [SysUtil.day(), a, b, fl])
		if RelationshipService.value(a, b, "romance") > 0.0 or RelationshipService.value(b, a, "romance") > 0.0:
			violations.append("day %d pair %d/%d has romance %.0f" % [SysUtil.day(), a, b, RelationshipService.value(a, b, "romance")])
		if FamilyTree.spouse_of(a) == b or FamilyMarriage.is_engaged(a, b):
			violations.append("day %d pair %d/%d married or engaged" % [SysUtil.day(), a, b])
	for af in RelationshipService.affairs:
		if _bad_pair(int(af["cheater"]), int(af["other"])) or _bad_pair(int(af["cheater"]), int(af["victim"])):
			violations.append("day %d affair %s" % [SysUtil.day(), str(af)])
	for fk in folk:
		var cur = fk.current
		if cur != null and cur.target_kind == "folk" and RomanceRules.is_romantic_def(cur.def):
			romantic_runs += 1
			if _bad_pair(int(cur.actor_id), int(cur.target_id)):
				violations.append("day %d %d runs %s with %d" % [SysUtil.day(), cur.actor_id, cur.def_id, cur.target_id])
	for pid in Aging.pregnancies:
		if _bad_pair(int(pid), int(Aging.pregnancies[pid]["father"])):
			violations.append("day %d pregnancy %d/%d" % [SysUtil.day(), pid, Aging.pregnancies[pid]["father"]])
