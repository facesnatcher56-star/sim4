class_name Paternity
extends RefCounted
## Paternity (task 18 part 6). When a baby is conceived inside an undiscovered affair of the MOTHER (RelationshipService.affairs: she is the
## cheater, the baby's father is `other`), her partner (the victim) is the "assumed father". After the birth he may begin to doubt
## (buff doubting_father); the clinic's paternity test ("Take a Paternity Test", a fee) settles it. If the baby is not his, the affair
## comes out: the couple's romance collapses, the relationship ends, a game event `paternity_revealed` is raised for the justice system
## (custody questions, task 09) to pick up. If the doubt was wrong the test calms him. Nothing here is graphic; the text stays factual.
## Data: data/pregnancy.json "paternity". Tier behaviour: event driven, residents only.

static func cfg() -> Dictionary:
	return Pregnancy.cfg("paternity")

## At conception: remember who believes he is the father, if the mother is cheating with the real father.
static func at_conception(carrier: int, other: int, r: Dictionary) -> void:
	for af in RelationshipService.affairs:
		if int(af.get("cheater", -1)) == carrier and int(af.get("other", -1)) == other:
			r["assumed_father"] = int(af.get("victim", -1))
			return

## After the birth: the assumed father may doubt.
static func after_birth(mother_id: int, r: Dictionary, babies: Array) -> void:
	var assumed: int = int(r.get("assumed_father", -1))
	var v = SysUtil.folk(assumed) if assumed >= 0 else null
	if v == null or babies.is_empty() or Pregnancy.rng.randf() >= float(cfg().get("doubt_chance", 0.5)):
		return
	v.add_buff("doubting_father")
	for b in v.buffs:
		if str(b["id"]) == "doubting_father":
			b["remaining"] = float(cfg().get("doubt_days", 6)) * 1440.0
	Fertility.state(assumed)["doubt"] = {"mother": mother_id, "father": int(r.get("father", -1)), "baby": int(babies[0].id)}
	SysUtil.notify(Sexes.fill("%s has begun to wonder whether the baby is really {their}." % v.name, assumed), "relationship")

## The clinic test. Costs a fee; the answer is the truth.
static func test(v_id: int) -> Dictionary:
	var v = SysUtil.folk(v_id)
	var st: Dictionary = Pregnancy.extra.get(v_id, {})
	if v == null or not st.has("doubt"):
		return {"ok": false, "reason": "no_doubt"}
	var cost: int = int(cfg().get("test_cost", 80))
	if WorldIface.get_coins(int(v.household_id)) < cost:
		SysUtil.notify("%s cannot afford the test right now." % v.name, "warn")
		return {"ok": false, "reason": "no_money"}
	WorldIface.add_coins(int(v.household_id), -cost)
	var d: Dictionary = st["doubt"]
	st.erase("doubt")
	v.remove_buff("doubting_father")
	var mother: int = int(d["mother"])
	var real: int = int(d["father"])
	var is_his: bool = real == v_id
	if is_his or real < 0:
		v.add_buff("reassured")
		SysUtil.notify(Sexes.fill("The test is clear: it is {their} baby, after all. %s is relieved." % v.name, v_id), "good")
		SysUtil.game_event("paternity_checked", {"folk_id": v_id, "target_id": mother, "his": true})
		return {"ok": true, "his": true}
	_reveal(v_id, mother, real, int(d["baby"]))
	return {"ok": true, "his": false}

static func _reveal(v_id: int, mother: int, real: int, baby: int) -> void:
	var v = SysUtil.folk(v_id)
	RelationshipService.affairs = RelationshipService.affairs.filter(func(a): return not (int(a.get("cheater", -1)) == mother and int(a.get("victim", -1)) == v_id))
	RelationshipService.add_both(v_id, mother, "romance", -float(cfg().get("reveal_romance_loss", 40.0)))
	if v != null:
		v.add_buff("cheated_on")
	RelationshipRomance.breakup(v_id, mother, "breakup", 1.0)
	SysUtil.notify("The test shows the baby is not %s's. The truth about the affair is out, and the relationship is over." % SysUtil.folk_name(v_id), "relationship")
	SysUtil.game_event("paternity_revealed", {"folk_id": v_id, "target_id": mother, "father": real, "baby_id": baby})
	ChronicleHook.note("paternity", "A paternity test ended a relationship.", [v_id, mother, real], "", 3, false)

static func on_game_event(ev: String, payload: Dictionary) -> void:
	if ev == "paternity_test":
		test(int(payload.get("folk_id", -1)))
