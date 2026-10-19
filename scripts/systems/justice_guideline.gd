class_name JusticeGuideline
extends RefCounted
## Sentencing from GUIDELINES, not dice (task 20). Every charge in data/justice.json has a `guideline` (low/high ranges per sentence type and the
## score where custody starts). The sentence SCORE (0..1) is `base` + aggravating factors - mitigating factors + a small judge spread
## (`sentencing.spread`); the score picks the sentence inside the guideline ranges. Factors only count when the charge lists them.
## `compute(c, pid, plea)` returns the whole sentence for the case (one part per charge, combined: concurrent unless the charge is `consecutive`).

static func cfg() -> Dictionary:
	return JusticeState.sect("sentencing")

static func charge(id: String) -> Dictionary:
	return JusticeProcess.charge_def(id)

static func family_of(id: String) -> String:
	return str(charge(id).get("family", id))

## Earlier convictions of the charge's family (assault, domestic violence and aggravated assault are one family).
static func prior_same(pid: int, charge_id: String) -> int:
	var fam: String = family_of(charge_id)
	var n: int = 0
	for r in JusticeRecords.convictions(pid):
		if family_of(str(r.get("charge", ""))) == fam:
			n += 1
	return n

static func prior_against(pid: int, victim: int) -> int:
	var n: int = 0
	if victim < 0:
		return 0
	for r in JusticeRecords.convictions(pid):
		if int(r.get("victim", -1)) == victim:
			n += 1
	return n

## {"agg": {key: amount}, "mit": {key: amount}} for one charge of the case.
static func factors(c: Dictionary, pid: int, charge_id: String, plea: bool) -> Dictionary:
	var K: Dictionary = cfg()
	var cd: Dictionary = charge(charge_id)
	var aggk: Dictionary = K.get("aggravating", {})
	var mitk: Dictionary = K.get("mitigating", {})
	var victim: int = int(c.get("victim", -1))
	var agg: Dictionary = {}
	var mit: Dictionary = {}
	var priors: int = JusticeRecords.convictions(pid).size()
	for key in (cd.get("aggravating", []) as Array):
		var w: float = float((aggk.get(key, {}) as Dictionary).get("weight", 0.0))
		var cap: int = int((aggk.get(key, {}) as Dictionary).get("cap", 1))
		var n: float = 0.0
		match str(key):
			"prior_record": n = float(mini(priors, cap))
			"same_charge_prior": n = float(mini(prior_same(pid, charge_id), cap))
			"injury": n = 1.0 if int(c.get("severity", 1)) >= 2 or bool(c.get("injury", false)) else 0.0
			"child_victim": n = 1.0 if victim >= 0 and CrimePerson.stage(victim) in ["baby", "toddler", "child"] else 0.0
			"elder_victim": n = 1.0 if victim >= 0 and CrimePerson.stage(victim) == "elder" else 0.0
			"domestic": n = 1.0 if bool(c.get("domestic", false)) else 0.0
			"repeat_victim": n = float(mini(prior_against(pid, victim), cap))
			"order_breach": n = 1.0 if charge_id == "order_violation" or bool(c.get("order_breach", false)) else 0.0
			"cruelty": n = 1.0 if bool(c.get("cruelty", false)) else 0.0
			"on_probation": n = 1.0 if JusticeState.probation.has(pid) and int(JusticeState.probation[pid]) >= SysUtil.day() else 0.0
			"multiple_victims": n = 1.0 if int(c.get("counts", 1)) >= 2 or int(c.get("serial", -1)) >= 0 else 0.0
		if n > 0.0:
			agg[str(key)] = w * n
	for key2 in (cd.get("mitigating", []) as Array):
		var w2: float = float((mitk.get(key2, {}) as Dictionary).get("weight", 0.0))
		var m: float = 0.0
		match str(key2):
			"first_offence": m = 1.0 if priors == 0 else 0.0
			"plea": m = 1.0 if plea else 0.0
			"provocation": m = 1.0 if bool(c.get("provoked", false)) or (victim >= 0 and CrimeMurder.anger(victim, pid) >= 0.5) else 0.0
			"remorse": m = 1.0 if CrimePressure.conscience(pid) >= 0.6 else 0.0
			"reputation": m = 1.0 if CrimePerson.reputation(pid) >= 20.0 else 0.0
			"lawyer": m = clampf(float(c.get("lawyer_skill", 0.3)), 0.0, 1.0)
		if m > 0.0:
			mit[str(key2)] = w2 * m
	return {"agg": agg, "mit": mit}

static func labels(f: Dictionary) -> Dictionary:
	var K: Dictionary = cfg()
	return {"agg": (f["agg"] as Dictionary).keys().map(func(k): return str((K["aggravating"][k] as Dictionary)["label"])),
		"mit": (f["mit"] as Dictionary).keys().map(func(k): return str((K["mitigating"][k] as Dictionary)["label"]))}

## The 0..1 score. `spread` false gives the exact (deterministic) score.
static func score(c: Dictionary, pid: int, charge_id: String, plea: bool, spread: bool = true) -> float:
	var f: Dictionary = factors(c, pid, charge_id, plea)
	var s: float = float(cfg().get("base", 0.3))
	for k in f["agg"]:
		s += float(f["agg"][k])
	for k2 in f["mit"]:
		s -= float(f["mit"][k2])
	if spread:
		var sp: float = float(cfg().get("spread", 0.04))
		s += JusticeState.rng.randf_range(-sp, sp)
	return clampf(s, 0.0, 1.0)

static func _lerp_range(r: Array, t: float) -> int:
	return int(round(lerpf(float(r[0]), float(r[1]), clampf(t, 0.0, 1.0))))

## The sentence for ONE charge: {charge, custody: "" | jail | prison, days, fine, service, probation, courses: [{kind, days}], restitution, order, life, custody_loss, score}.
static func one(c: Dictionary, pid: int, charge_id: String, plea: bool, spread: bool = true) -> Dictionary:
	var cd: Dictionary = charge(charge_id)
	var g: Dictionary = cd.get("guideline", {})
	var s: float = score(c, pid, charge_id, plea, spread)
	var out: Dictionary = {"charge": charge_id, "custody": "", "days": 0, "fine": 0, "service": 0, "probation": 0, "courses": [], "restitution": 0, "order": false,
		"life": false, "custody_loss": false, "score": snappedf(s, 0.001), "consecutive": bool(cd.get("consecutive", false))}
	var cust_at: float = float(g.get("custody_at", 1.1))
	var prison_at: float = float(g.get("prison_at", 1.1))
	var has_jail: bool = g.has("jail")
	var has_prison: bool = g.has("prison")
	if s >= cust_at and (has_jail or has_prison):
		if has_prison and (s >= prison_at or not has_jail):
			var t: float = (s - prison_at) / maxf(1.0 - prison_at, 0.001) if has_jail else (s - cust_at) / maxf(1.0 - cust_at, 0.001)
			out["custody"] = "prison"
			out["days"] = _lerp_range(g["prison"], t)
			if g.has("life_at") and s >= float(g["life_at"]):
				out["life"] = true
		else:
			var top: float = prison_at if has_prison else 1.0
			out["custody"] = "jail"
			out["days"] = _lerp_range(g["jail"], (s - cust_at) / maxf(top - cust_at, 0.001))
		if g.has("fine"):
			out["fine"] = _lerp_range(g["fine"], s)
		if g.has("probation"):
			out["probation"] = _lerp_range(g["probation"], s)
	else:
		var t2: float = clampf(s / cust_at, 0.0, 1.0) if cust_at <= 1.0 else clampf(s, 0.0, 1.0)
		if g.has("fine"):
			out["fine"] = _lerp_range(g["fine"], t2)
		if g.has("service") and t2 >= 0.4:
			out["service"] = _lerp_range(g["service"], t2)
		if g.has("probation") and t2 >= 0.6:
			out["probation"] = _lerp_range(g["probation"], t2)
	var courses: Array = cd.get("courses", [])
	if not courses.is_empty() and s >= float(cd.get("course_at", 0.3)):
		for kind in courses:
			var dr: Array = (cfg().get("course_days", {}) as Dictionary).get(kind, [3, 5])
			(out["courses"] as Array).append({"kind": str(kind), "days": _lerp_range(dr, s)})
	if bool(cd.get("restitution", false)):
		out["restitution"] = int(c.get("loot_value", 0)) + int(c.get("stolen_coins", 0))
	out["order"] = bool(cd.get("order", false)) and int(c.get("victim", -1)) >= 0
	out["custody_loss"] = bool(cd.get("custody_loss", false)) and (out["custody"] != "" or s >= 0.3)
	return out

## Charges of the case (primary first).
static func charges_of(c: Dictionary) -> Array:
	var list: Array = c.get("charges", [])
	if list.is_empty():
		list = [str(c.get("charge", "theft"))]
	return list

## The whole sentence of the case: every charge, combined. The result keeps the old keys (type, days, fine, life) and adds the parts.
static func compute(c: Dictionary, pid: int, plea: bool, spread: bool = true) -> Dictionary:
	var parts: Array = []
	for id in charges_of(c):
		if not charge(str(id)).is_empty():
			parts.append(one(c, pid, str(id), plea, spread))
	if parts.is_empty():
		return {"type": "fine", "days": 0, "fine": 50, "life": false, "courses": [], "parts": []}
	var s: Dictionary = {"type": "fine", "days": 0, "fine": 0, "life": false, "service_days": 0, "probation_days": 0, "courses": [], "restitution": 0, "order": false,
		"custody_loss": false, "parts": parts, "charges": parts.map(func(p): return p["charge"]), "score": parts[0]["score"]}
	var concurrent: int = 0
	var added: int = 0
	var prison: bool = false
	for p in parts:
		if str(p["custody"]) == "prison":
			prison = true
		if bool(p["consecutive"]):
			added += int(p["days"])
		else:
			concurrent = maxi(concurrent, int(p["days"]))
		s["fine"] = int(s["fine"]) + int(p["fine"])
		s["service_days"] = maxi(int(s["service_days"]), int(p["service"]))
		s["probation_days"] = maxi(int(s["probation_days"]), int(p["probation"]))
		s["restitution"] = int(s["restitution"]) + int(p["restitution"])
		s["order"] = bool(s["order"]) or bool(p["order"])
		s["life"] = bool(s["life"]) or bool(p["life"])
		s["custody_loss"] = bool(s["custody_loss"]) or bool(p["custody_loss"])
		for co in (p["courses"] as Array):
			var have: bool = false
			for e in (s["courses"] as Array):
				if str(e["kind"]) == str(co["kind"]):
					e["days"] = maxi(int(e["days"]), int(co["days"]))
					have = true
			if not have:
				(s["courses"] as Array).append(co.duplicate())
	var days: int = concurrent + added
	if days > 0:
		var jail_max: int = int(JusticeState.sect("sentences").get("jail_max_days", 10))
		s["type"] = "prison" if (prison or days > jail_max) else "jail"
		s["days"] = days
	elif int(s["probation_days"]) > 0:
		s["type"] = "probation"
		s["days"] = int(s["probation_days"])
	elif int(s["service_days"]) > 0:
		s["type"] = "service"
		s["days"] = int(s["service_days"])
	if bool(s["life"]):
		s["type"] = "prison"
		s["days"] = 99999
	return s

## The factors of the primary charge as words, for the notice and the case board ("a repeat offence, a child victim").
static func explain(c: Dictionary, pid: int, plea: bool) -> String:
	var l: Dictionary = labels(factors(c, pid, str(c.get("charge", "")), plea))
	var bits: Array = []
	if not (l["agg"] as Array).is_empty():
		bits.append("taken into account: " + ", ".join(l["agg"]))
	if not (l["mit"] as Array).is_empty():
		bits.append("in their favour: " + ", ".join(l["mit"]))
	return "; ".join(bits)
