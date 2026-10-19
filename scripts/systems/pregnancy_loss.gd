class_name PregnancyLoss
extends RefCounted
## Pregnancy loss (task 18 part 4). SENSITIVE: handled with care, never a punchline, no gore, no moralising. A loss is a quiet notification
## (the player's folk also get a one-button "A quiet loss" note), then strong grief for both partners (the `Aging.kill` grief tiers, without a
## death record) and a lasting memory; friends and family who know comfort them (the grief is shorter), and a counsellor helps further.
## Rates (data/pregnancy.json "loss"): a miscarriage is rare and mostly in the first trimester, a stillbirth extremely rare and late; both
## scale with the pregnancy's risk factors (PregnancyRisk.multiplier) and fall with prenatal care.
## The content setting "Mature life events" (on by default): when OFF, neither losses nor terminations ever happen and the choice is not
## offered; pregnancy and birth work as usual. The world remembers the value (`mature_on` is saved), so a shared game stays consistent.
## Tier behaviour: a daily dice per pregnant resident (ACTIVE/NEAR residents, a handful); townies use townie_day() (STATISTICAL, no risk factors).

static var mature_on: int = -1            # -1 = follow the player setting, 0 / 1 = fixed for this world (tests, shared games)
static var pending: Array = []            # later memories [{id, day, value, text}] of people who lost or ended a pregnancy

static func reset() -> void:
	mature_on = -1
	pending.clear()

static func cfg() -> Dictionary:
	return Pregnancy.cfg("loss")

static func mature_enabled() -> bool:
	if mature_on >= 0:
		return mature_on == 1
	return GameSettings.get_bool("mature_events")

static func set_mature(on: bool) -> void:
	mature_on = 1 if on else 0

# ------------------------------------------------------------------ the dice
## Chance for today of `kind` (miscarriage | stillbirth) in trimester `tri` (1..3) at risk multiplier `mult`.
static func chance(kind: String, tri: int, mult: float) -> float:
	var arr: Array = cfg().get(kind + "_per_day", [])
	if tri < 1 or tri > arr.size():
		return 0.0
	return clampf(float(arr[tri - 1]) * mult, 0.0, 0.9)

static func on_day(id: int, r: Dictionary) -> void:
	if not mature_enabled() or not Aging.pregnancies.has(id):
		return
	var tri: int = Pregnancy.trimester(id)
	var mult: float = PregnancyRisk.multiplier(r)
	if Pregnancy.rng.randf() < chance("miscarriage", tri, mult):
		lose(id, "miscarriage")
	elif Pregnancy.rng.randf() < chance("stillbirth", tri, mult):
		lose(id, "stillbirth")

## Statistical townie version (no risk factors). Returns true when the pregnancy ended.
static func townie_day(_t: Dictionary, pr: Dictionary) -> bool:
	if not mature_enabled():
		return false
	var span: float = maxf(float(int(pr["due_day"]) - int(pr["started"])), 1.0)
	var p: float = clampf(float(SysUtil.day() - int(pr["started"])) / span, 0.0, 1.0)
	var tri: int = clampi(int(floor(p * 3.0)) + 1, 1, 3)
	return Pregnancy.rng.randf() < chance("miscarriage", tri, 1.0) + chance("stillbirth", tri, 1.0)

# ------------------------------------------------------------------ a loss
static func lose(id: int, kind: String) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	var m = SysUtil.folk(id)
	if r.is_empty() or m == null:
		return
	var father: int = int(r.get("father", -1))
	var c: Dictionary = cfg()
	var still: bool = kind == "stillbirth"
	var gs: Dictionary = c.get("grief_strength", {})
	var days: float = float((c.get("grief_days", {}) as Dictionary).get(kind, 4))
	var knowers: Array = _knowers(id, r)
	end_pregnancy(id)
	var supporters: int = 0
	for k in knowers:
		if int(k) != father and SysUtil.folk(int(k)) != null:
			supporters += 1
	_grieve(m, float(gs.get("stillbirth_mother" if still else "mother", 1.5)), days, supporters, id, still)
	var fa = SysUtil.folk(father) if father >= 0 else null
	if fa != null:
		_grieve(fa, float(gs.get("stillbirth_father" if still else "father", 1.3)), days, supporters, id, still)
	for k2 in knowers:
		if SysUtil.folk(int(k2)) != null and int(k2) != id and int(k2) != father:
			RelationshipService.add_value(int(k2), id, "friendship", 3.0)          # they stood by
	var text: String = ("%s lost the baby late in the pregnancy. It is a deep and quiet sorrow." if still else "%s lost the pregnancy. It is a quiet, sad time.") % m.name
	SysUtil.notify(text, "death")
	if CrimePerson.is_player(id):
		JusticePlayer.tell(id, "A quiet loss", Sexes.fill("%s lost the baby. Be gentle with {them}. Friends and a counsellor can help." % m.name, id))
	var line: String = "%s and %s lost a pregnancy." % [m.name, SysUtil.folk_name(father)] if fa != null else "%s lost a pregnancy." % m.name
	ChronicleHook.note("pregnancy_loss", line, [id, father], "home:%d" % int(m.household_id), 3, false)
	SysUtil.game_event("pregnancy_lost", {"folk_id": id, "target_id": father, "kind": kind})

## Take the pregnancy away: record, buffs, trimester bookkeeping, the rest period.
static func end_pregnancy(id: int) -> void:
	Aging.pregnancies.erase(id)
	Family.trimester.erase(id)
	var m = SysUtil.folk(id)
	if m != null:
		for b in ["pregnant", "pregnant_t1", "pregnant_t2", "pregnant_t3", "feeling_off", "bed_rest"]:
			m.remove_buff(b)
	Fertility.rest_for(id, int(cfg().get("rest_days", 5)))

static func _knowers(id: int, r: Dictionary) -> Array:
	var out: Array = (r.get("told", []) as Array).duplicate()
	if bool(r.get("public", false)):
		var friend_min: float = float(cfg().get("friend_min", 30))
		for o in SysUtil.residents():
			var oid: int = int(o.id)
			if oid != id and not out.has(oid) and (FamilyTree.is_kin(oid, id) or RelationshipService.value(oid, id, "friendship") >= friend_min):
				out.append(oid)
	return out

static func _grieve(person, strength: float, days: float, supporters: int, mother_id: int, still: bool) -> void:
	var buff: String = DeathCauses.grief_buff(strength)
	var cut: float = clampf(1.0 - float(cfg().get("support_cut", 0.25)) * float(mini(supporters, 2)), 0.3, 1.0)
	person.add_buff(buff)
	for b in person.buffs:
		if str(b["id"]) == buff:
			b["remaining"] = days * 1440.0 * cut
	Emotions.imprint(person, "loss:%d" % mother_id, -1.0 if still else -0.9, "loss", "sad", "the baby that was lost")
	person.add_to_stat("fun", -12.0 * strength)

## A counsellor: the grief of this person is cut by `counselling_cut` and they feel heard.
static func counsel(id: int) -> Dictionary:
	var f = SysUtil.folk(id)
	if f == null:
		return {"ok": false, "reason": "missing"}
	var cost: int = int(cfg().get("counselling_cost", 30))
	if WorldIface.get_coins(int(f.household_id)) < cost:
		SysUtil.notify("%s cannot afford a counsellor right now." % f.name, "warn")
		return {"ok": false, "reason": "no_money"}
	WorldIface.add_coins(int(f.household_id), -cost)
	var eased := false
	for b in f.buffs:
		if str(b["id"]).begins_with("grieving"):
			b["remaining"] = float(b["remaining"]) * (1.0 - float(cfg().get("counselling_cut", 0.5)))
			eased = true
	SysUtil.notify(Sexes.fill("%s talked it through with a counsellor and feels a little lighter." % f.name, id) if eased else "%s had a good talk with a counsellor." % f.name, "good")
	SysUtil.game_event("counselling", {"folk_id": id})
	return {"ok": true, "eased": eased}

# ------------------------------------------------------------------ later memories (mixed feelings over time)
static func add_memory(id: int, in_days: int, value: float, text: String) -> void:
	pending.append({"id": id, "day": SysUtil.day() + in_days, "value": value, "text": text})
	while pending.size() > 40:
		pending.pop_front()

static func daily_pending() -> void:
	var keep: Array = []
	for e in pending:
		if SysUtil.day() >= int(e["day"]):
			Emotions.imprint(SysUtil.folk(int(e["id"])), "choice:%d" % int(e["id"]), float(e["value"]), "life", "", str(e["text"]))
		else:
			keep.append(e)
	pending = keep

static func on_game_event(ev: String, payload: Dictionary) -> void:
	if ev == "counselling_session":
		counsel(int(payload.get("folk_id", -1)))
	elif ev == "secret_learned":
		PregnancyChoice.on_secret_learned(int(payload.get("folk_id", -1)), int(payload.get("target_id", -1)), int(payload.get("secret", -1)))

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"mature": mature_on, "pending": pending.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	mature_on = int(d.get("mature", -1))
	pending = (d.get("pending", []) as Array).duplicate(true)
	for e in pending:
		e["id"] = int(e["id"])
		e["day"] = int(e["day"])
