class_name PregnancyTownie
extends RefCounted
## The STATISTICAL version of conception and pregnancy for townies (no Folk on the lot, task 18). Once a day, for each townie couple that is
## together (StoryGrowth walks the pairs): one female and one male adult (RomanceRules.allowed, same rules as the full version), the
## chance is the data's baby_chance x the couple's fertility (age curve, elders none, infertility). A pregnancy is a small dict on the
## female's townie record (`preg`: father, due_day, kids, sexes); on the due day StoryGrowth._born makes each baby with its sex (twins and
## triplets by the same data). Loss of a pregnancy (PregnancyLoss.townie_day) uses the same base rates, without risk factors.
## Tier behaviour: STATISTICAL daily dice; cost O(townie pairs) once a day + O(pregnant townies). Caps: one `preg` dict per pregnant townie.

static func cfg() -> Dictionary:
	return Pregnancy.cfg("townie")

## A couple's day: maybe a conception. ta / tb are townie records.
static func consider(ta: Dictionary, tb: Dictionary, base_chance: float) -> bool:
	var a: int = int(ta["id"])
	var b: int = int(tb["id"])
	var sa: String = Sexes.of_townie(ta)
	if sa == Sexes.of_townie(tb):
		return false                               # a same-sex couple cannot conceive (they can adopt)
	var carrier: Dictionary = ta if sa == Sexes.FEMALE else tb
	var other: Dictionary = tb if carrier == ta else ta
	if carrier.has("preg") or not RomanceRules.allowed(a, b):
		return false
	var cid: int = int(carrier["id"])
	var p: float = base_chance * Conception.couple_fertility(cid, int(other["id"]))
	if Fertility.resting(cid) or Pregnancy.rng.randf() >= p:
		return false
	var kids: int = Pregnancy.roll_kids(cid)
	var sexes: Array = []
	for _i in kids:
		sexes.append(Sexes.roll())
	carrier["preg"] = {"father": int(other["id"]), "due_day": SysUtil.day() + Pregnancy.length_days(), "kids": kids, "sexes": sexes, "started": SysUtil.day()}
	return true

## Daily: births (and losses) of pregnant townies.
static func on_day() -> void:
	for id in Story.townies.keys():
		var t: Dictionary = Story.townies[id]
		if not t.has("preg"):
			continue
		if not bool(t.get("alive", true)):
			t.erase("preg")
			continue
		var pr: Dictionary = t["preg"]
		if PregnancyLoss.townie_day(t, pr):
			t.erase("preg")
			continue
		if SysUtil.day() >= int(pr["due_day"]):
			var other: Dictionary = Story.townies.get(int(pr["father"]), {})
			if not other.is_empty():
				for s in pr["sexes"]:
					StoryGrowth._born(t, other, str(s))
			t.erase("preg")
			Fertility.rest_for(int(id), int(Pregnancy.cfg("conception").get("after_birth_days", 4)))
