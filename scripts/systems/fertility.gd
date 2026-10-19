class_name Fertility
extends RefCounted
## How likely a person is to conceive (task 18 part 2). A number 0..1 per person: the age curve of their sex (high for young adults, falling
## through adult life, NONE for elders and anyone below adult), times small trait / buff modifiers (health, stress, grief, hunger, the clinic's
## "treated" boost). Some people are infertile: decided once (a dice from the pregnancy stream the first time it matters, then saved), shown
## only after trying for a while ("revealed"), and treated at the fertility clinic. Data: data/pregnancy.json "fertility".
## Tier behaviour: only asked for when a couple tries or is intimate (event driven), never polled. No loops over people.

static func cfg() -> Dictionary:
	return SysUtil.table("pregnancy").get("fertility", {})

## Linear value of a [[age_days, value], ...] curve.
static func curve_value(curve: Array, age: float) -> float:
	if curve.is_empty():
		return 1.0
	if age <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(1, curve.size()):
		var x1: float = float(curve[i][0])
		if age <= x1:
			var x0: float = float(curve[i - 1][0])
			var t: float = (age - x0) / maxf(x1 - x0, 0.0001)
			return lerpf(float(curve[i - 1][1]), float(curve[i][1]), t)
	return float(curve[curve.size() - 1][1])

## Age part only (no traits / health): 0 for babies to teens and for elders.
static func by_age(id: int) -> float:
	var stage: String = RomanceRules.stage_of(id)
	if stage != "adult":
		return 0.0 if stage != "elder" else float(cfg().get("elder", 0.0))
	var c: Dictionary = cfg()
	var curve: Array = c.get("female_curve", []) if Sexes.is_female(id) else c.get("male_curve", [])
	return curve_value(curve, Family.age_days_of(id))

## Full fertility 0..1: age x traits x buffs, 0 when infertile.
static func of(id: int) -> float:
	var base: float = by_age(id)
	if base <= 0.0 or is_infertile(id):
		return 0.0
	var c: Dictionary = cfg()
	var m: float = 1.0
	var f = SysUtil.folk(id)
	if f != null:
		var tm: Dictionary = c.get("trait_mult", {})
		for t in f.traits:
			m *= float(tm.get(str(t), 1.0))
		var bm: Dictionary = c.get("buff_mult", {})
		for b in f.buffs:
			m *= float(bm.get(str(b["id"]), 1.0))
	if treated(id):
		m *= float((c.get("buff_mult", {}) as Dictionary).get("treated", 1.5))
	return clampf(base * m, 0.0, 1.0)

# ------------------------------------------------------------------ infertility
static func state(id: int) -> Dictionary:
	if not Pregnancy.extra.has(id):
		Pregnancy.extra[id] = {"infertile": Pregnancy.rng.randf() < float(cfg().get("infertile_rate", 0.06)), "tries": 0, "revealed": false, "boost_until": 0}
	return Pregnancy.extra[id]

static func is_infertile(id: int) -> bool:
	return bool(state(id)["infertile"])

## The pause after a birth or a loss: no new pregnancy until this day.
static func resting(id: int) -> bool:
	return Pregnancy.extra.has(id) and SysUtil.day() < int((Pregnancy.extra[id] as Dictionary).get("rest_until", 0))

static func rest_for(id: int, days: int) -> void:
	state(id)["rest_until"] = SysUtil.day() + days

static func treated(id: int) -> bool:
	return Pregnancy.extra.has(id) and SysUtil.day() <= int((Pregnancy.extra[id] as Dictionary).get("boost_until", 0))

## One planned try that did not work: after enough of them an infertile person finds out (revealed).
static func note_failed_try(id: int) -> void:
	var s: Dictionary = state(id)
	s["tries"] = int(s["tries"]) + 1
	if bool(s["infertile"]) and not bool(s["revealed"]) and int(s["tries"]) >= int(cfg().get("reveal_after_tries", 3)):
		s["revealed"] = true
		SysUtil.notify(Sexes.fill("%s has been trying for a baby for a while without luck. {They} could ask the fertility clinic for help." % SysUtil.folk_name(id), id), "info")
		SysUtil.game_event("infertility_found", {"folk_id": id})

static func revealed(id: int) -> bool:
	return Pregnancy.extra.has(id) and bool((Pregnancy.extra[id] as Dictionary).get("revealed", false))

## The fertility clinic (expensive): may cure infertility and boosts the odds (and the chance of twins) for a while.
static func treat(id: int) -> Dictionary:
	var f = SysUtil.folk(id)
	var c: Dictionary = cfg().get("clinic", {})
	if f == null or by_age(id) <= 0.0:
		return {"ok": false, "reason": "not_possible"}
	var cost: int = int(c.get("cost", 400))
	var hid: int = int(f.household_id)
	if WorldIface.get_coins(hid) < cost:
		return {"ok": false, "reason": "no_money"}
	WorldIface.add_coins(hid, -cost)
	var s: Dictionary = state(id)
	var cured: bool = false
	if bool(s["infertile"]) and Pregnancy.rng.randf() < float(c.get("cure_chance", 0.6)):
		s["infertile"] = false
		cured = true
	s["boost_until"] = SysUtil.day() + int(c.get("boost_days", 12))
	s["revealed"] = bool(s["infertile"]) and bool(s["revealed"])
	SysUtil.notify(Sexes.fill("%s had treatment at the fertility clinic.%s" % [f.name, " The news is good." if cured else ""], id), "info")
	SysUtil.game_event("fertility_treated", {"folk_id": id, "cured": cured})
	return {"ok": true, "reason": "treated", "cured": cured}
