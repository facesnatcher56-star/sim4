class_name HealthCond
extends RefCounted
## Long-term conditions (task 14): asthma, diabetes, high blood pressure, arthritis. RARE, and managed with medicine rather than cured.
##   onset      a daily dice from `onset_per_year` x risk (poor fitness and diet raise it for the conditions that list it), by life stage
##   symptoms   a few days later the household is told the person keeps feeling run down; only a check-up at the clinic (or the first flare) DIAGNOSES it
##   medicine   the pharmacy counter sells 14 days of medicine (prescription); every day with medicine left counts as MANAGED: flares are a tenth as likely
##   flare      an unmanaged flare is a bout of illness (Health.fall_ill, in hospital when serious); townies' flares are statistical (the hospital's townie stay)
##   effects    unmanaged conditions shorten life a little (HealthLife.death_mult) and high blood pressure raises heart trouble (HealthRisk)
## Townies buy their own medicine when they can afford it and are diagnosed after `townie_diagnosis_days`.
## Data: data/life/20_health.json "conditions". Tier: residents ACTIVE daily, townies STATISTICAL daily.

static func defs() -> Dictionary:
	return LifeDefs.section("conditions")

static func def(cid: String) -> Dictionary:
	return defs().get(cid, {})

static func has(id: int, cid: String) -> bool:
	return (HealthLife.peek(id).get("conds", {}) as Dictionary).has(cid)

static func diagnosed(id: int, cid: String) -> bool:
	return bool(((HealthLife.peek(id).get("conds", {}) as Dictionary).get(cid, {}) as Dictionary).get("diag", false))

static func doses(id: int, cid: String) -> int:
	return int(((HealthLife.peek(id).get("conds", {}) as Dictionary).get(cid, {}) as Dictionary).get("doses", 0))

static func managed(id: int, cid: String) -> bool:
	return diagnosed(id, cid) and doses(id, cid) > 0

## [{id, label, diagnosed, managed, doses}] of the conditions a person has (undiagnosed ones only when `all`).
static func list(id: int, all: bool = false) -> Array:
	var out: Array = []
	for cid in (HealthLife.peek(id).get("conds", {}) as Dictionary):
		if all or diagnosed(id, str(cid)):
			out.append({"id": str(cid), "label": str(def(str(cid)).get("label", cid)), "diagnosed": diagnosed(id, str(cid)), "managed": managed(id, str(cid)), "doses": doses(id, str(cid))})
	return out

static func _risk_factor(id: int, d: Dictionary) -> float:
	var r: Dictionary = HealthLife.rec(id)
	var f := 1.0
	var risk: Dictionary = d.get("risk", {})
	if risk.has("fitness_low"):
		f *= clampf(1.0 + float(risk["fitness_low"]) * (1.0 - float(r["fitness"]) / 50.0), 0.4, 4.0)
	if risk.has("diet_low"):
		f *= clampf(1.0 + float(risk["diet_low"]) * (1.0 - float(r["diet"]) / 50.0), 0.4, 4.0)
	return f

## Chance of getting `cid` today.
static func onset_chance(id: int, cid: String, stage: String) -> float:
	var d: Dictionary = def(cid)
	if d.is_empty() or has(id, cid) or not (d.get("stages", []) as Array).has(stage):
		return 0.0
	return float(d.get("onset_per_year", 0.0)) / IncidentRisk.year_days() * _risk_factor(id, d)

static func give(id: int, cid: String, diag: bool = false) -> void:
	var r: Dictionary = HealthLife.rec(id)
	if (r["conds"] as Dictionary).has(cid):
		return
	r["conds"][cid] = {"since": SysUtil.day(), "diag": diag, "doses": 0, "flares": 0, "told": false}
	HealthLife.count("onset_" + cid)

static func diagnose(id: int, cid: String, announce: bool = true) -> bool:
	if not has(id, cid) or diagnosed(id, cid):
		return false
	HealthLife.rec(id)["conds"][cid]["diag"] = true
	var f = SysUtil.folk(id)
	if f != null and announce:
		var d: Dictionary = def(cid)
		SysUtil.notify("%s has %s. With %s from the pharmacy counter it stays under control." % [f.name, str(d.get("label", cid)).to_lower(), str(d.get("medicine", "medicine"))], "info")
	LifeNote.say("health", "%s was diagnosed with %s." % [LifeNote.nm(id), str(def(cid).get("label", cid)).to_lower()], [id], 1, false)
	return true

static func prescribe(id: int, cid: String) -> void:
	var c: Dictionary = HealthLife.rec(id)["conds"][cid]
	c["doses"] = mini(int(c["doses"]) + int(def(cid).get("dose_days", 14)), 2 * int(def(cid).get("dose_days", 14)))

## Heart trouble multiplier from conditions (hypertension).
static func cardiac_mult(id: int) -> float:
	var m := 1.0
	for cid in (HealthLife.peek(id).get("conds", {}) as Dictionary):
		var d: Dictionary = def(str(cid))
		if d.has("cardiac_mult"):
			m *= float(d.get("managed_cardiac_mult", 1.2)) if managed(id, str(cid)) else float(d["cardiac_mult"])
	return m

# ------------------------------------------------------------------ the daily pass for one person
static func day(id: int, stage: String, resident: bool) -> void:
	if stage == "baby":
		return
	for cid in defs():
		if HealthLife.rng.randf() < onset_chance(id, str(cid), stage):
			give(id, str(cid))
	var conds: Dictionary = HealthLife.rec(id)["conds"]
	for cid2 in conds.keys():
		_condition_day(id, str(cid2), conds[cid2], resident)

static func _condition_day(id: int, cid: String, c: Dictionary, resident: bool) -> void:
	var d: Dictionary = def(cid)
	var cfg: Dictionary = HealthLife.cfg()
	var age: int = SysUtil.day() - int(c["since"])
	if not bool(c["diag"]):
		if resident and age >= int(cfg.get("conditions_symptom_days", 4)) and not bool(c["told"]):
			c["told"] = true
			var f = SysUtil.folk(id)
			if f != null:
				SysUtil.notify("%s %s. A check-up at the clinic would say why." % [f.name, str(d.get("symptom", "feels run down"))], "info")
		elif not resident and age >= int(cfg.get("townie_diagnosis_days", 6)):
			diagnose(id, cid, false)
	if not resident and bool(c["diag"]) and int(c["doses"]) <= 0:
		var t: Dictionary = Story.townies.get(id, {})
		var price: int = int(d.get("refill_price", 15))
		if not t.is_empty() and int(t.get("coins", 0)) >= price:
			t["coins"] = int(t["coins"]) - price
			prescribe(id, cid)
	var was: int = int(c["doses"])
	if was > 0:
		c["doses"] = was - 1
		if was == 1 and resident:
			var f2 = SysUtil.folk(id)
			if f2 != null:
				SysUtil.notify("%s has run out of %s." % [f2.name, str(d.get("medicine", "medicine"))], "warn")
	var p: float = float(d.get("flare_per_day", 0.05))
	if bool(c["diag"]) and was > 0:
		p *= float(d.get("managed_mult", 0.1))
	if HealthLife.rng.randf() < p:
		flare(id, cid, resident)

static func flare(id: int, cid: String, resident: bool) -> void:
	var d: Dictionary = def(cid)
	var sevs: Array = d.get("severities", [1])
	var sev: int = int(sevs[HealthLife.rng.randi_range(0, sevs.size() - 1)])
	var c: Dictionary = HealthLife.rec(id)["conds"][cid]
	c["flares"] = int(c["flares"]) + 1
	HealthLife.count("flare_" + cid)
	var reason: String = "%s: %s" % [str(d.get("label", cid)), str(d.get("flare", "a flare-up"))]
	var f = SysUtil.folk(id)
	if resident and f != null:
		if not bool(c["diag"]):
			diagnose(id, cid, true)
		Health.fall_ill(f, "generic", sev, reason)
		SysUtil.notify("%s %s%s." % [f.name, str(d.get("flare", "had a flare-up")), "" if sev < 2 else " and needs a hospital"], "warn")
		return
	if sev >= 2 and Story.townies.has(id):
		Hospital.admit(id, sev, reason)
		LifeNote.say("health", "%s %s and was taken to hospital." % [LifeNote.nm(id), str(d.get("flare", "had a flare-up"))], [id], 2, false)
