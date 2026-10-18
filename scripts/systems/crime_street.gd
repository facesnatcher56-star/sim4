class_name CrimeStreet
extends RefCounted
## Street robbery (mugging): out on the open map at night, alone, carrying coins. Handler of incident `street_robbery` (about 0.1 times a year
## for someone who walks at night). A player Folk gets a clear choice: Hand over / Run / Fight (JusticePlayer.ask; no UI = the default, Hand over).
## Far townies use the statistical version with the same record.

static func cfg() -> Dictionary:
	return JusticeState.sect("robbery")

static func on_incident(ctx: Dictionary, _args: Dictionary) -> Dictionary:
	if not JusticeState.enabled:
		return {"text": ""}
	var subj = ctx["subject"]
	var forced: bool = bool(ctx.get("forced", false))
	var victim: int = int(subj.id)
	var k: Dictionary = cfg()
	if bool(ctx["statistical"]):
		if not forced and not JusticeState.chance(float(k.get("townie_out_share", 0.2))):
			return {"text": ""}
	else:
		var f = ctx["folk"]
		if f == null or SysUtil.is_away(f):
			return {"text": ""}
		if not forced and (Neighborhood.lot_of(f) != "" or not _alone(f)):
			return {"text": ""}
	if not forced and not JusticeState.chance(Police.patrol_factor()):
		return {"text": ""}                            # officers on patrol
	var robber: int = CrimeBurglary.pick_burglar("street", [victim])
	if robber < 0 or CrimePerson.coins(victim) < int(k.get("min_coins", 20)):
		return {"text": ""}
	if bool(ctx["statistical"]):
		_resolve(victim, robber, "hand", true)
		return {"text": ""}
	var f2 = ctx["folk"]
	JusticePlayer.ask(int(f2.id), "Robbery!", "A stranger steps out of the dark and demands your coins. What does %s do?" % f2.name,
		[{"id": "hand", "label": "Hand it over"}, {"id": "run", "label": "Run"}, {"id": "fight", "label": "Fight back"}],
		func(choice): _resolve(victim, robber, str(choice), false), "hand")
	return {"text": ""}

## Nobody else of the player's household within sight.
static func _alone(f) -> bool:
	for o in WorldIface.all_folk():
		if int(o.id) != int(f.id) and CrimePlace.can_witness(int(o.id), int(f.id)):
			return false
	return true

## Play out the robbery with the chosen reaction. Returns the case.
static func _resolve(victim: int, robber: int, choice: String, statistical: bool) -> Dictionary:
	var k: Dictionary = cfg()
	if not CrimePerson.alive(victim):
		return {}
	var f = CrimePerson.folk(victim)
	var fit: float = float(CrimePerson.skill(victim, "fitness"))
	var lose: bool = true
	var hurt: int = 0
	var died: bool = false
	match choice:
		"run":
			lose = not JusticeState.chance(clampf(0.35 + fit * 0.07 + (0.1 if CrimePerson.has_trait(victim, "active") else 0.0), 0.1, 0.9))
			if lose and JusticeState.chance(0.4):
				hurt = 1
		"fight":
			var win: bool = JusticeState.chance(clampf(0.25 + fit * 0.08 + (0.1 if CrimePerson.has_trait(victim, "hot_headed") else 0.0), 0.1, 0.8))
			lose = not win
			hurt = 0 if win else JusticeState.rng.randi_range(1, 2)
			if not win and JusticeState.chance(float(k.get("death", 0.004))):
				died = true
	var amt: int = 0
	if lose:
		amt = mini(CrimePerson.coins(victim), maxi(int(float(CrimePerson.coins(victim)) * float(k.get("share", 0.5))), int(k.get("min_coins", 20))))
		CrimePerson.pay(victim, amt, "robbed")
		CrimePerson.add_coins(robber, amt)
	var c: Dictionary = CaseStore.create("robbery", robber, victim, "street", {"witnessed": true, "witness_clarity": JusticeState.rng.randf_range(0.25, 0.6),
		"witnesses": [victim], "trace": 0.12, "stolen_coins": amt, "loot_value": amt})
	CrimePlace.place_at_scene(robber, "street")
	if died:
		var cause_kill: Dictionary = CrimeMurder.kill(robber, victim, "street", "manslaughter", {"case": int(c["id"])})
		return cause_kill
	if hurt > 0:
		if f != null:
			Hospital.injure(f, hurt, "a mugging")
		elif hurt >= 2:
			Hospital.admit(victim, 2, "a mugging")
	# victims report most of the time; a few keep quiet out of fear
	if JusticeState.chance(float(k.get("report", 0.85))):
		var txt: String = ""
		if choice == "fight" and not lose:
			txt = "%s fought off a mugger!" % CrimePerson.name_of(victim)
		elif lose:
			txt = "%s was mugged and lost %d coins." % [CrimePerson.name_of(victim), amt]
		else:
			txt = "%s got away from a mugger." % CrimePerson.name_of(victim)
		CaseStore.toast(c, txt, "bad" if lose else "good")
		CaseDiscovery.report(c, victim, "victim")
		c["notes"].append({"day": SysUtil.day(), "text": txt})
	else:
		c["hush"] = true
		c["state"] = "closed"
	return c
