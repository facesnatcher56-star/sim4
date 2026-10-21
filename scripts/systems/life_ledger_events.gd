class_name LifeLedgerEvents
extends RefCounted
## Task 44: the milestones of a life that are game events, not chronicle notes: jobs, promotions, a layoff, retiring, friends and enemies, romance,
## engagement, marriage, a break-up, someone moving in, the death of someone close. Each becomes one LifeLedger entry for the residents involved, linked
## only to the event that really caused it (a layoff before a new job, an engagement before a wedding, a hospital stay before a death).
##   LifeLedgerEvents.on_event(name, payload)   (from SystemsManager._on_game_event)

const CLOSE := ["spouse", "partner", "sweetheart", "fiance", "best_friend"]

static func _res(id: int) -> bool:
	var f = SysUtil.folk(id)
	return f != null and SysUtil.is_resident(f)

static func _nm(id: int) -> String:
	return CrimePerson.name_of(id)

## "Amateur (Athlete)": the title with the line of work, so a title alone is never a puzzle.
static func _job(p: Dictionary) -> String:
	var cid: String = str(p.get("career", Careers.career_of(int(p.get("folk_id", -1)))))
	var t: String = str(p.get("title", ""))
	if t == "":
		t = str(Careers.level_def(cid, int(p.get("level", 1))).get("title", cid))
	var lbl: String = str(Careers.career_def(cid).get("label", ""))
	return t if lbl == "" or lbl == t else "%s (%s)" % [t, lbl]

static func on_event(ev: String, p: Dictionary) -> void:
	var a: int = int(p.get("folk_id", -1))
	var b: int = int(p.get("target_id", -1))
	match ev:
		"hired":
			if _res(a):
				LifeLedger.add_linked("job", "Started work as %s." % _job(p), [a], 2, ["layoff", "fired", "left_job", "choice"], "")
		"promoted":
			if _res(a):
				LifeLedger.add_linked("promotion", "Promoted to %s." % _job(p), [a], 2, [], "")
		"left_job":
			if _res(a):
				var why: String = str(p.get("reason", ""))
				if why.contains("laid") or why.contains("cut"):
					LifeLedger.add_linked("layoff", "Laid off.", [a], 3, [], "")
				elif why == "fired":
					LifeLedger.add_linked("fired", "Fired from the job.", [a], 3, ["missed_shift", "crime", "jailed"], "")
				elif why == "retired":
					LifeLedger.add_linked("retired", "Retired.", [a], 2, [], "")
		"relationship_bit_changed":
			var bit: String = str(p.get("bit", ""))
			var old: String = str(p.get("old", ""))
			var tg: String = "best friend" if bit == "best_friend" else "enemy"
			if _res(a) and ((bit == "best_friend" and old != "best_friend") or (bit == "enemy" and old != "enemy")) and not LifeLedger.has_tag(a, b, tg):          # once per person: the bit goes up and down
				var txt: String = "%s became a close friend." % _nm(b) if bit == "best_friend" else "Fell out badly with %s." % _nm(b)
				LifeLedger.add_linked("relationship", txt, [a, b], 2, ["fight", "crime", "revenge", "secret_out"] if bit == "enemy" else [], "best friend" if bit == "best_friend" else "enemy")
		"relationship_status":
			var st: String = str(p.get("status", ""))
			if (_res(a) or _res(b)) and st in ["sweetheart", "partner", "dating"]:
				LifeLedger.add_linked("romance", "Got together with %s." % _nm(b if _res(a) else a), [a, b], 2, [], {"sweetheart": "sweetheart", "partner": "partner", "dating": "dating"}[st])
		"engaged":
			if _res(a) or _res(b):
				LifeLedger.add_linked("engaged", "Engaged to %s." % _nm(b if _res(a) else a), [a, b], 2, ["romance"], "engaged")
		"married":
			if _res(a) or _res(b):
				LifeLedger.add_linked("wedding", "Married %s." % _nm(b if _res(a) else a), [a, b], 3, ["engaged"], "married")
		"breakup", "divorced":
			if _res(a) or _res(b):
				LifeLedger.add_linked("breakup", ("Divorced %s." if ev == "divorced" else "Broke up with %s.") % _nm(b if _res(a) else a), [a, b], 3, ["secret_out", "jealousy", "separation"], "ex")
		"moved_in":
			if _res(a):
				LifeLedger.add_linked("moved_in", "%s moved in." % _nm(a), [a] + _housemates(a), 2, ["romance", "engaged", "wedding", "eviction", "fire"], "lived together")
		"died":
			for r in SysUtil.residents():
				var rid: int = int(r.id)
				if rid == a:
					continue
				var flag: String = ""
				for fl in CLOSE:
					if RelationshipBits.has_flag(rid, a, fl):
						flag = fl
						break
				if flag == "" and not (FamilyTree.parents_of(rid).has(a) or FamilyTree.children_of(rid).has(a) or FamilyTree.siblings_of(rid).has(a)):
					continue
				var txt2: String = "%s died. You were widowed." % _nm(a) if flag == "spouse" else "%s died." % _nm(a)
				LifeLedger.add_linked("bereaved", txt2, [rid, a], 3, ["hospital", "collapse", "fire", "fight", "car_crash", "crime"], "widowed" if flag == "spouse" else "died")

static func _housemates(id: int) -> Array:
	var f = SysUtil.folk(id)
	var out: Array = []
	for r in SysUtil.residents():
		if f != null and int(r.household_id) == int(f.household_id) and int(r.id) != id:
			out.append(int(r.id))
	return out
