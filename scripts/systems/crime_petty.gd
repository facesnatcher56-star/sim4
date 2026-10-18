class_name CrimePetty
extends RefCounted
## Task 09c section 5: small offences - vandalism, trespassing, public disturbance, shoplifting (reckless driving later, once vehicles exist).
## Handled with a fine, community service and a dent in the town reputation, WITHOUT a full trial (JusticeProcess.file_charges settles petty
## charges on the spot). Data: justice.json "petty" {caught, fine, service, reputation, cost}. Incidents in data/incidents/09c_motives.json
## feed vandalism / trespassing / disturbance; shoplifting comes from need (CrimePressure) and from kleptomaniacs.

static func cfg() -> Dictionary:
	return JusticeState.sect("petty")

static func def(kind: String) -> Dictionary:
	return (cfg().get(kind, {}) as Dictionary)

## Someone commits a petty offence. scene: lot key or "street". Returns the case when the offender was identified, else {}.
static func commit(kind: String, pid: int, scene: String, opts: Dictionary = {}) -> Dictionary:
	var d: Dictionary = def(kind)
	if d.is_empty() or not CrimePerson.alive(pid):
		return {}
	JusticeState.count(kind)
	var cost: int = 0
	var vhid: int = int(scene.get_slice(":", 1)) if scene.begins_with("home:") else 0
	if kind == "vandalism" and vhid > 0:
		var cr: Array = d.get("cost", [20, 60])
		cost = JusticeState.rng.randi_range(int(cr[0]), int(cr[1]))
		Economy.deposit(vhid, -mini(cost, WorldIface.get_coins(vhid)), "cleanup after vandals")
		SysUtil.notify("Vandals defaced %s. The cleanup cost %d coins." % [CaseStore.house_label(scene), cost], "bad")
	elif kind == "disturbance" and vhid > 0:
		SysUtil.notify("A noisy drunk kept the street awake last night.", "warn")
	elif kind == "trespassing" and vhid > 0:
		SysUtil.notify("Someone was seen wandering around %s." % CaseStore.house_label(scene), "warn")
	var caught: float = float(d.get("caught", 0.35)) * Police.strength() * (1.5 if bool(opts.get("seen", false)) else 1.0)
	CrimePlace.place_at_scene(pid, scene)
	if not JusticeState.chance(caught):
		return {}
	var c: Dictionary = CaseStore.create(kind, pid, -1, scene, {"witnessed": true, "witness_clarity": 0.9, "witnesses": [], "trace": 0.5, "vhid": vhid, "loot_value": cost})
	c["state"] = "open"
	c["disc_day"] = SysUtil.day()
	c["charge"] = kind
	c["accused"] = pid
	settle(c)
	return c

## No trial: a fine or community service on the spot, a small reputation hit, a note in the record (which never closes jobs).
static func settle(c: Dictionary) -> void:
	var pid: int = int(c["accused"])
	var kind: String = str(c["kind"])
	var d: Dictionary = def(kind)
	var fr: Array = d.get("fine", [15, 50])
	var service_days: int = JusticeState.rng.randi_range(int(d.get("service", [1, 2])[0]), int(d.get("service", [1, 2])[1]))
	var use_service: bool = JusticeState.chance(float(d.get("service_share", 0.35)))
	var text: String
	if use_service:
		JusticeState.service[pid] = {"days_left": service_days, "last_day": -1}
		text = "%s was caught (%s) and got %d days of community service." % [CrimePerson.name_of(pid), str(d.get("label", kind)).to_lower(), service_days]
		c["sentence"] = {"type": "service", "days": service_days}
	else:
		var fine: int = JusticeState.rng.randi_range(int(fr[0]), int(fr[1]))
		JusticeSentence._fine(pid, fine)
		text = "%s was caught (%s) and fined %d coins." % [CrimePerson.name_of(pid), str(d.get("label", kind)).to_lower(), fine]
		c["sentence"] = {"type": "fine", "fine": fine}
	c["verdict"] = "petty"
	c["state"] = "closed"
	c["closed_day"] = SysUtil.day()
	CaseStore.mark_solved(c)
	RelationshipKnowledge.add_reputation(pid, -float(d.get("reputation", 2)))
	var recs: Array = JusticeState.records.get(pid, [])
	recs.append({"day": SysUtil.day(), "charge": kind, "case": int(c["id"]), "result": "petty"})
	JusticeState.records[pid] = recs
	CaseStore.note(c, text, "petty_crime", 1, false)
	if CrimePerson.is_player(pid) or int(c.get("vhid", 0)) > 0:
		SysUtil.notify(text, "story")
	SysUtil.game_event("petty_settled", {"folk_id": pid, "case": int(c["id"]), "kind": kind})

# ------------------------------------------------------------------ incident handler
## Handler of vandalism / trespassing / disturbance incidents (lot or folk scope, FULL or statistical).
static func on_incident(ctx: Dictionary, args: Dictionary) -> Dictionary:
	if not JusticeState.enabled:
		return {"text": ""}
	var kind: String = str(args.get("kind", "vandalism"))
	var subj = ctx["subject"]
	var offender: int = -1
	if subj.kind == "lot":
		offender = _offender(subj.lot_key, kind)
		if offender >= 0:
			commit(kind, offender, subj.lot_key)
	else:
		offender = int(subj.id)
		if CrimePerson.is_player(offender):
			return {"text": ""}
		commit(kind, offender, "street")
	return {"text": ""}

## Offenders are young-ish, reckless, vengeful or under pressure.
static func _offender(lot_key: String, kind: String) -> int:
	var ids: Array = []
	var w: Array = []
	for pid in CrimePerson.townies_only():
		if lot_key == CrimePerson.home_key(int(pid)) or CrimePerson.in_custody(int(pid)):
			continue
		var weight: float = 0.3 + CrimePressure.risk(int(pid)) * 2.0
		for t in ["reckless", "vengeful", "hot_headed", "dishonest"]:
			if CrimePerson.has_trait(int(pid), t):
				weight *= 2.0
		if CrimePerson.stage(int(pid)) == "teen":
			weight *= 2.0
		ids.append(int(pid))
		w.append(weight)
	var i: int = JusticeState.pick_index(w)
	return int(ids[i]) if i >= 0 else -1
