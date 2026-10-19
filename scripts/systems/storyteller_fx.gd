class_name StorytellerFx
extends RefCounted
## The small effect vocabulary the deck and the arcs are written in (data lists of one-key dictionaries), applied to a ctx
## {key, hid, folk_id, other, lot, zone, who, stat}. Everything goes through existing systems (Economy, RelationshipService, buffs, Careers, StoryVisits,
## CityGov mood, Utilities, TransportTraffic) so the rest of the game sees ordinary consequences.
##   coins n | [lo,hi]      the household (or the townie lot) gains / loses coins (a loss never goes below zero)
##   other_coins n | [a,b]  the other person (or the victim) gains / loses coins
##   buff id                a buff on the person the card is about          friend n | other_friend n   friendship with the other person
##   rep n                  reputation (RelationshipKnowledge)              conscience true   a troubled conscience buff
##   roll p, then, else     a seeded coin flip with two effect lists        visit minutes | visit_days n   the other person calls round
##   job_offer true         a job offer for the person                      jealous_if_partnered true   the partner is a little jealous
##   mood_city x            the town's mood about the council (decays)      heat [tag, n]   makes related events likelier in the zone
##   lay_off n              n townies of the zone lose their job             power_cut [lo,hi] hours   road_works days   vanish days (a townie is away)

static func fill(text: String, ctx: Dictionary) -> String:
	var zone: String = str(ctx.get("zone", ""))
	var who: int = int(ctx.get("who", -1))
	return text.replace("{name}", SysUtil.folk_name(int(ctx.get("folk_id", -1))) if int(ctx.get("folk_id", -1)) >= 0 else "someone") \
		.replace("{other}", SysUtil.folk_name(int(ctx.get("other", -1))) if int(ctx.get("other", -1)) >= 0 else "someone") \
		.replace("{who}", SysUtil.folk_name(who) if who >= 0 else "someone") \
		.replace("{zone}", CityState.zone_label(zone) if zone != "" else "town")

static func _num(v) -> float:
	if v is Array:
		return float(Storyteller.rng.randi_range(int(v[0]), int(v[1])))
	return float(v)

# ------------------------------------------------------------------ the other person
static func make_other(kind: String, ctx: Dictionary) -> int:
	if kind == "":
		return -1
	if kind == "gossip" or Story.alive_townies().size() >= int(Story.cfg().get("max_population", 24)) + CityPlan.extra_capacity():
		return _existing_townie(ctx)
	var adult: float = StoryGrowth._adult_age()
	var t: Dictionary = Story.add_townie(adult)
	t["career"] = StoryGrowth._job() if kind != "rival" or Storyteller.rng.randf() < 0.5 else ""
	t["arrived_day"] = SysUtil.day()
	if kind == "headhunter":
		t["career"] = ""
	Story._log("%s moved to town." % t["name"])
	SysUtil.game_event("townie_arrived", {"townie_id": int(t["id"]), "folk_id": -1})
	return int(t["id"])

static func _existing_townie(ctx: Dictionary) -> int:
	var pool: Array = []
	var hid: int = int(ctx.get("hid", 0))
	for t in Story.alive_townies():
		if Story.stage_of(t) in ["adult", "elder"] and int(t.get("lot", 0)) != int(ctx.get("lot", -1)):
			pool.append(int(t["id"]))
	pool.sort()
	if pool.is_empty():
		return -1
	return int(pool[Storyteller.rng.randi_range(0, pool.size() - 1)])

# ------------------------------------------------------------------ apply
static func apply(fx: Array, ctx: Dictionary) -> void:
	for e in fx:
		_one(e as Dictionary, ctx)

static func _one(e: Dictionary, ctx: Dictionary) -> void:
	var fid: int = int(ctx.get("folk_id", -1))
	var other: int = int(ctx.get("other", -1))
	var hid: int = int(ctx.get("hid", 0))
	for k in e.keys():
		match str(k):
			"coins":
				_coins(ctx, int(_num(e[k])))
			"other_coins":
				var oid: int = other if other >= 0 else int(ctx.get("who", -1))
				if Story.townies.has(oid):
					Story.townies[oid]["coins"] = maxi(int(Story.townies[oid].get("coins", 0)) + int(_num(e[k])), 0)
			"buff":
				_buff(ctx, str(e[k]))
			"friend", "other_friend":
				var oid2: int = other if other >= 0 else int(ctx.get("who", -1))
				if fid >= 0 and oid2 >= 0 and fid != oid2:
					RelationshipService.add_both(fid, oid2, "friendship", float(e[k]))
			"rep":
				if fid >= 0:
					RelationshipKnowledge.add_reputation(fid, float(e[k]))
			"conscience":
				_buff(ctx, "troubled_conscience" if not SimEnv.data().buff_def("troubled_conscience").is_empty() else "guilty_pang")
			"roll":
				apply(e.get("then", []) if Storyteller.rng.randf() < float(e[k]) else e.get("else", []), ctx)
			"visit":
				_visit(ctx, int(e[k]), 600)
			"visit_days":
				_visit(ctx, 60, mini(int(e[k]) * 480, 1500))
			"job_offer":
				var f = SysUtil.folk(fid)
				if f != null and not Careers.offers.has(fid):
					Careers.make_offer(f)
			"tempt":
				Straying.tempt(fid)
			"jealous_if_partnered":
				_jealous(hid, fid)
			"mood_city":
				StorytellerCycles.add_mood(float(e[k]))
			"heat":
				StorytellerChaos.add_heat(str(ctx.get("zone", "")), str((e[k] as Array)[0]), float((e[k] as Array)[1]))
			"lay_off":
				_lay_off(ctx, int(e[k]))
			"power_cut":
				Utilities.begin("power", str(ctx.get("zone", "")), _num(e[k]), "fault")
			"road_works":
				TransportTraffic.add_works(str(ctx.get("zone", "")), "roadworks", float(e[k]))
			"vanish":
				if Story.townies.has(other if other >= 0 else int(ctx.get("who", -1))):
					Story.townies[other if other >= 0 else int(ctx.get("who", -1))]["missing_until"] = SysUtil.day() + int(e[k])

static func _coins(ctx: Dictionary, n: int) -> void:
	var hid: int = int(ctx.get("hid", 0))
	if hid > 0:
		if n >= 0:
			Economy.deposit(hid, n, "luck")
		else:
			Economy.spend(hid, mini(-n, Economy.balance(hid)), "bad luck")
		return
	var mem: Array = StorytellerPlay.lot_members(int(ctx.get("lot", 0)))
	if not mem.is_empty():
		Story.townies[mem[0]]["coins"] = maxi(int(Story.townies[mem[0]].get("coins", 0)) + n, 0)

static func _buff(ctx: Dictionary, bid: String) -> void:
	if SimEnv.data().buff_def(bid).is_empty():
		return
	var f = SysUtil.folk(int(ctx.get("folk_id", -1)))
	if f != null:
		f.add_buff(bid)

static func _visit(ctx: Dictionary, delay: int, duration: int) -> void:
	var other: int = int(ctx.get("other", -1))
	var host: int = int(ctx.get("folk_id", -1))
	if other >= 0 and Story.townies.has(other) and SysUtil.folk(host) != null:
		StoryVisits.schedule_visit([other], host, SysUtil.now() + delay, duration, "visit")

static func _jealous(hid: int, fid: int) -> void:
	if not SimEnv.data().buff_def("jealous_pang").is_empty():
		for r in StorytellerPlay.residents_of(hid):
			if int(r.id) != fid and (RelationshipBits.has_flag(fid, int(r.id), "partner") or RelationshipBits.has_flag(fid, int(r.id), "spouse")):
				r.add_buff("jealous_pang")

static func _lay_off(ctx: Dictionary, n: int) -> void:
	var pool: Array = []
	for tid in StorytellerPlay.townies_in_zone(str(ctx.get("zone", ""))):
		if str(Story.townies[tid].get("career", "")) != "":
			pool.append(int(tid))
	var done := 0
	while done < n and not pool.is_empty():
		var i: int = Storyteller.rng.randi_range(0, pool.size() - 1)
		var tid2: int = int(pool[i])
		pool.remove_at(i)
		Story.townies[tid2]["career"] = ""
		Story._log("%s lost their job." % Story.name_of(tid2))
		if done == 0:
			ctx["who"] = tid2
		done += 1
