extends RefCounted
## CaseEvidence.suspects counts company at a place and gossip once per case (task 17.4) instead of once per suspect; the scores must be exactly the
## direct per-person ones (CaseEvidence.suspicion called outside a scan).

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	C.town(14)
	K.set_time(10, 12)
	var ids: Array = C.adults()
	_check(f, ids.size() >= 6, "enough adult townies")
	var locs := ["town:1", "town:2", "park", "street", "work", "town:1"]
	for i in ids.size():
		CrimePlace.record_now(int(ids[i]), locs[i % locs.size()])
	var c: Dictionary = CaseStore.create("burglary", int(ids[0]), int(ids[1]), "town:1", {"witnessed": false, "witnesses": [], "trace": 0.3})
	RelationshipService.gossip_items[int(ids[2])] = [{"about": int(ids[3]), "kind": "grudge", "sid": -1, "other": -1, "told": []},
		{"about": int(ids[4]), "kind": "crime_suspect", "sid": int(c["id"]), "other": -1, "told": []},
		{"about": int(ids[4]), "kind": "crime_suspect", "sid": 9999, "other": -1, "told": []}]
	var rows: Array = CaseEvidence.suspects(c, 100)
	_check(f, not rows.is_empty(), "the scan finds suspects")
	var by := {}
	for r in rows:
		by[int(r["pid"])] = float(r["score"])
	for p in CrimePerson.everyone():
		if p == int(c.get("victim", -2)) or not CrimePerson.is_adult(p) or CrimePerson.in_custody(p):
			continue
		var direct: float = CaseEvidence.suspicion(p, c)
		if direct > 0.05:
			_check(f, by.has(p) and absf(float(by[p]) - direct) < 0.00001, "person %d: scan score %s equals direct %s" % [p, str(by.get(p, -1)), str(direct)])
		else:
			_check(f, not by.has(p), "person %d below the cut is not listed" % p)
	_check(f, not CaseEvidence._scanning, "the scan is closed afterwards")
	K.teardown()
	return f

func _check(f: Array, cond: bool, msg: String) -> void:
	if not cond:
		f.append(msg)
