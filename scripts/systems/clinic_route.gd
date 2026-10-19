class_name ClinicRoute
extends RefCounted
## Other routes to a family (task 18 part 7) besides adoption (existing: any couple or single adult can adopt, see FamilyHousehold.adopt):
##   * the FERTILITY CLINIC "Have a Baby with the Clinic's Help" for a committed couple of any sexes (expensive, a good chance, can bring
##     twins): a couple with a woman in it (also a same-sex female couple, with a donor) starts a normal pregnancy for her; the partner is
##     the second parent (record flag `donor`);
##   * SURROGACY for two men: a surrogate carries the baby; after the usual length the baby joins their household, both men are the parents.
## RomanceRules.allowed still guards the pair; elders and non-adults are refused. Data: data/pregnancy.json "clinic_route".
## Tier behaviour: event driven; surrogate births live in Pregnancy.extra[a]["surrogate"] and are checked daily (a handful of entries).

static func cfg() -> Dictionary:
	return Pregnancy.cfg("clinic_route")

static func why_not(a: int, b: int) -> String:
	if SysUtil.folk(a) == null or SysUtil.folk(b) == null:
		return "Needs a partner who is here."
	if not RomanceRules.allowed(a, b):
		return "They are family." if RomanceRules.is_adult(a) and RomanceRules.is_adult(b) else "Too young for that."
	if not (RelationshipBits.bit_for(a, b) in ["sweetheart", "partner", "spouse"]):
		return "The clinic needs a couple."
	if Fertility.by_age(a) <= 0.0 and Fertility.by_age(b) <= 0.0:
		return "Too old for the clinic."
	if Aging.pregnancies.has(a) or Aging.pregnancies.has(b):
		return "A baby is already on the way."
	return ""

static func start(a: int, b: int) -> Dictionary:
	var why: String = why_not(a, b)
	if why != "":
		return {"ok": false, "reason": "not_possible", "msg": why}
	var fa = SysUtil.folk(a)
	var cost: int = int(cfg().get("cost", 900))
	if WorldIface.get_coins(int(fa.household_id)) < cost:
		SysUtil.notify("%s and %s cannot afford the clinic right now." % [fa.name, SysUtil.folk_name(b)], "warn")
		return {"ok": false, "reason": "no_money"}
	WorldIface.add_coins(int(fa.household_id), -cost)
	var females: Array = [a, b].filter(func(x): return Sexes.is_female(int(x)) and Fertility.by_age(int(x)) > 0.0)
	Fertility.state(a)["boost_until"] = SysUtil.day() + 2             # the clinic's treatment boosts the odds of twins for this try
	Fertility.state(b)["boost_until"] = SysUtil.day() + 2
	if Pregnancy.rng.randf() >= float(cfg().get("success", 0.8)):
		SysUtil.notify("The clinic could not help this time. They can try again.", "info")
		return {"ok": false, "reason": "no_luck"}
	if not females.is_empty():
		var carrier: int = a if females.has(a) else b
		var other: int = b if carrier == a else a
		var r: Dictionary = Pregnancy.start(carrier, other, true)
		r["donor"] = not Sexes.is_male(other)
		return {"ok": true, "reason": "pregnant", "carrier": carrier}
	var kids: int = Pregnancy.roll_kids(a)
	Fertility.state(a)["surrogate"] = {"partner": b, "due_day": SysUtil.day() + Pregnancy.length_days(), "kids": kids}
	SysUtil.notify("The clinic found a surrogate for %s and %s. Their baby is on the way." % [fa.name, SysUtil.folk_name(b)], "birthday")
	return {"ok": true, "reason": "surrogate"}

## Daily: surrogate babies that are due join their parents' household.
static func on_day() -> void:
	for id in Pregnancy.extra.keys():
		var st: Dictionary = Pregnancy.extra[id]
		if not st.has("surrogate") or SysUtil.day() < int(st["surrogate"]["due_day"]):
			continue
		var sg: Dictionary = st["surrogate"]
		st.erase("surrogate")
		var a = SysUtil.folk(int(id))
		var b = SysUtil.folk(int(sg["partner"]))
		if a == null or b == null:
			continue
		var made: Array = []
		for i in int(sg["kids"]):
			var baby = PregnancyBirth._make_baby(a, int(id), int(b.id), Sexes.roll(), Aging.cfg().get("pregnancy", {}))
			Family.on_birth(baby, int(id), int(b.id))
			made.append(baby)
		var names: Array = made.map(func(x): return str(x.name))
		SysUtil.notify("%s %s born to %s and %s, with the help of their surrogate!" % [" and ".join(names), "was" if names.size() == 1 else "were", a.name, b.name], "birthday")
		for baby2 in made:
			SysUtil.game_event("baby_born", {"folk_id": int(id), "baby_id": baby2.id, "target_id": int(b.id), "hospital": false, "multiple": made.size(), "surrogate": true})

static func on_game_event(ev: String, payload: Dictionary) -> void:
	if ev == "clinic_baby":
		start(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1)))
