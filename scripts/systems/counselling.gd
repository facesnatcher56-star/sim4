class_name Counselling
extends RefCounted
## Counselling and therapy (task 14). A session with a counsellor helps with the heavy things in a life:
##   * GRIEF (grieving buffs, the low mood after a birth): the rest of the grief is cut by `grief_cut` (half)
##   * BURNOUT, SHOCK AND TRAUMA from crime, fire, accidents, disasters and money trouble (`counselling.other`): the rest is cut by `other_cut`
##   * WORK STRAIN: drops by `strain_cut`
## and the person gets the `in_therapy` buff for a while. The place "therapy" (Willow Mind and Mood Centre) sells sessions; the old home action
## "Talk to a Counsellor" (task 18) calls the same code through PregnancyLoss.counsel, which keeps its own price.
## Data: data/life/20_health.json config.counselling.

static func cfg() -> Dictionary:
	return LifeDefs.cfg("counselling")

## Which buffs of this person a counsellor can help with: [{id, kind: grief|other}].
static func helpable(f) -> Array:
	var out: Array = []
	var c: Dictionary = cfg()
	for b in f.buffs:
		var id: String = str(b["id"])
		if (c.get("grief", []) as Array).has(id):
			out.append({"id": id, "kind": "grief"})
		elif (c.get("other", []) as Array).has(id):
			out.append({"id": id, "kind": "other"})
	return out

static func needs_help(f) -> bool:
	return not helpable(f).is_empty() or float(HealthLife.peek(int(f.id)).get("strain", 0.0)) >= 50.0

## The session itself (payment is the caller's business). Returns {eased: n, text}.
static func session(f, grief_too: bool = true) -> Dictionary:
	var c: Dictionary = cfg()
	var eased := 0
	for h in helpable(f):
		if str(h["kind"]) == "grief" and not grief_too:
			continue
		var cut: float = float(c.get("grief_cut", 0.5)) if str(h["kind"]) == "grief" else float(c.get("other_cut", 0.6))
		for b in f.buffs:
			if str(b["id"]) != str(h["id"]):
				continue
			if float(b["remaining"]) < 0.0 or float(b["remaining"]) * (1.0 - cut) < 30.0:
				f.remove_buff(str(h["id"]))
			else:
				b["remaining"] = float(b["remaining"]) * (1.0 - cut)
			eased += 1
			break
	var r: Dictionary = HealthLife.rec(int(f.id))
	var before: float = float(r["strain"])
	r["strain"] = maxf(before - float(HealthLife.cfg().get("strain", {}).get("counsel_cut", 35)), 0.0)
	r["sessions"] = int(r["sessions"]) + 1
	HealthIllness.timed(f, str(c.get("therapy_buff", "in_therapy")), 3.0 * 1440.0)
	f.add_to_stat("social", 6.0)
	HealthLife.count("counselling")
	SysUtil.game_event("counselling_done", {"folk_id": int(f.id), "eased": eased})
	return {"eased": eased, "relief": before - float(r["strain"]), "text": ""}
