class_name CityPolicy
extends RefCounted
## Local laws and policies (task 12.4): the mayor proposes, the council votes. A policy is data (data/city.json gov.policies): its `axes` say what kind of people
## like it (safety, freedom, thrift, services, peace, green) and its numbers say what it does:
##   curfew       under-18s may not enter venues late at night (Venues.check_entry), fewer street crimes (crime_mult), a fine for the household
##   park_hours   the parks close at night
##   noise_rules  loud interactions at night can bring a complaint and a fine (SystemsManager interaction hook)
##   free_buses   no bus fares (TransportBus), a little more tax
##   green_grants solar panels and wells cut bills further (UtilityBills)
##   permits      building walls and starting a business cost a permit fee (CommandActions._build_wall, business start)
## A council member leans on each axis; a member votes yes when the policy's axes match their leaning (plus a little noise). Townie mayors propose a policy that
## fits their platform about once a month; a player mayor proposes with the mailbox interactions. Nothing here is required: a player never has to touch it.

const AXES := ["safety", "freedom", "thrift", "services", "peace", "green"]

static func cfg() -> Dictionary:
	return CityGov.cfg().get("policies", {})

static func ids() -> Array:
	var k: Array = cfg().keys()
	k.sort()
	return k

static func active(id: String) -> bool:
	return CityGov.policies.has(id)

static func value(id: String, key: String, default: Variant = 0.0) -> Variant:
	return (cfg().get(id, {}) as Dictionary).get(key, default) if active(id) else default

# ------------------------------------------------------------------ the council
static func _lean() -> Dictionary:
	var l: Dictionary = {}
	for a in AXES:
		l[a] = snappedf(CityState.rng.randf_range(-1.0, 1.0), 0.01)
	return l

static func pick_council(pool: Array, mayor_id: int) -> Array:
	var size: int = int(CityGov.cfg().get("council_size", 4))
	var ids_: Array = pool.filter(func(p): return int(p) != mayor_id)
	var out: Array = []
	while out.size() < size and not ids_.is_empty():
		var i: int = CityState.rng.randi_range(0, ids_.size() - 1)
		out.append({"id": int(ids_[i]), "name": CrimePerson.name_of(int(ids_[i])), "lean": _lean()})
		ids_.remove_at(i)
	return out

## After an election: one or two seats change hands.
static func refresh_council(old: Array, mayor_id: int) -> Array:
	var keep: Array = old.filter(func(m): return int(m["id"]) != mayor_id)
	var pool: Array = CityElection.eligible().filter(func(p): return int(p) != mayor_id and not keep.any(func(m): return int(m["id"]) == int(p)))
	var drop: int = mini(CityState.rng.randi_range(1, 2), keep.size())
	for i in drop:
		keep.remove_at(CityState.rng.randi_range(0, keep.size() - 1))
	while keep.size() < int(CityGov.cfg().get("council_size", 4)) and not pool.is_empty():
		var j: int = CityState.rng.randi_range(0, pool.size() - 1)
		keep.append({"id": int(pool[j]), "name": CrimePerson.name_of(int(pool[j])), "lean": _lean()})
		pool.remove_at(j)
	return keep

static func fit(member: Dictionary, policy: Dictionary) -> float:
	var s: float = 0.0
	for a in (policy.get("axes", {}) as Dictionary):
		s += float(policy["axes"][a]) * float((member["lean"] as Dictionary).get(a, 0.0))
	return s

# ------------------------------------------------------------------ propose and vote
## Adopt (or, when it is already in force, end) a policy by council vote. Returns the result words.
static func propose(id: String, by_player: bool = false) -> Dictionary:
	var p: Dictionary = cfg().get(id, {})
	if p.is_empty() or CityGov.council.is_empty():
		return {"ok": false, "text": "There is no such policy."}
	var repeal: bool = active(id)
	if repeal and SysUtil.day() - int((CityGov.policies[id] as Dictionary).get("since", 0)) < int(CityGov.cfg().get("repeal_after_days", 28)):
		var why: String = "%s has only just come in. The council will not reopen it yet." % str(p.get("label", id))
		if by_player:
			SysUtil.notify(why, "info")
		return {"ok": false, "text": why}
	var yes: int = 0
	for m in CityGov.council:
		var v: float = fit(m, p) * (-1.0 if repeal else 1.0) + CityState.rng.randfn(0.0, 0.25)
		if v > -0.05:
			yes += 1
	var passed: bool = yes * 2 > CityGov.council.size() or (yes * 2 == CityGov.council.size() and CityState.chance(0.5))
	var texts: Dictionary = CityGov.cfg().get("texts", {})
	var line: String
	if not passed:
		line = str(texts.get("rejected", "")).replace("{label}", str(p.get("label", id)))
	elif repeal:
		CityGov.policies.erase(id)
		line = str(texts.get("repealed", "")).replace("{label}", str(p.get("label", id)))
	else:
		CityGov.policies[id] = {"since": SysUtil.day(), "by": int(CityGov.mayor.get("id", -1))}
		line = str(texts.get("passed", "")).replace("{label}", str(p.get("label", id)))
		if p.has("tax"):
			CityGov.set_tax(CityGov.tax + float(p["tax"]))
	line += " %s" % str(p.get("text", "")) if passed and not repeal else ""
	CityGov.note("policy", line)
	SysUtil.notify(line, "info" if passed else "warn")
	ChronicleHook.note("policy", line, [], "", 2, true)
	SysUtil.game_event("policy_voted", {"policy": id, "passed": passed, "repeal": repeal, "folk_id": -1})
	return {"ok": passed, "text": line, "yes": yes}

## A townie mayor tries a policy that matches the platform about once a month.
static func on_day(day: int) -> void:
	if CityGov.mayor.is_empty() or bool(CityGov.mayor.get("player", false)):
		return
	var every: int = int(CityGov.cfg().get("policy_every_days", 28))
	if every <= 0 or day % every != 0 or CityState.chance(0.4):
		return
	var plat: Dictionary = (CityGov.cfg().get("platforms", {}) as Dictionary).get(str(CityGov.mayor.get("platform", "")), {})
	var want: String = str(plat.get("complaint", ""))
	var axis: String = {"crime": "safety", "services": "services", "tax": "thrift", "roads": "services", "schools": "services"}.get(want, "services")
	var best: String = ""
	var top: float = -9.0
	for id in ids():
		if active(id) and SysUtil.day() - int((CityGov.policies[id] as Dictionary).get("since", 0)) < int(CityGov.cfg().get("repeal_after_days", 28)):
			continue
		var s: float = float(((cfg()[id] as Dictionary).get("axes", {}) as Dictionary).get(axis, 0.0)) * (-1.0 if active(id) else 1.0) + CityState.rng.randf() * 0.5
		if s > top:
			top = s
			best = id
	if best != "" and top > 0.2:
		propose(best, false)

# ------------------------------------------------------------------ what the policies do (hooks)
static func _night(from_h: float, to_h: float) -> bool:
	var h: float = SysUtil.hour_f()
	return h >= from_h or h < to_h

## Venues.check_entry hook: "" or the reason a lot is closed to these folk right now.
static func blocks_entry(lot_id: String, folk_ids: Array) -> String:
	if CityGov.policies.is_empty():
		return ""
	var t: String = str(Neighborhood.lot(lot_id).get("type", ""))
	if active("park_hours") and t == "park" and _night(float(value("park_hours", "from", 22)), float(value("park_hours", "to", 6))):
		return "The park is closed at night."
	if active("curfew") and _night(float(value("curfew", "from", 22)), float(value("curfew", "to", 5))) and not (t in ["home", "hospital", "school", "townie_home"]) and lot_id != Neighborhood.HOME:
		for id in folk_ids:
			var f = SysUtil.folk(int(id))
			if f != null and str(f.age_stage) in ["child", "teen"]:
				return "There is a curfew: nobody under 18 may be out at night."
	return ""

## Street crimes are rarer under a curfew.
static func crime_mult() -> float:
	return float(value("curfew", "crime_mult", 1.0))

static func fare_mult() -> float:
	return float(value("free_buses", "fare_mult", 1.0))

static func solar_bonus() -> float:
	return float(value("green_grants", "solar_bonus", 0.0))

## Interaction hook (SystemsManager): loud things at night can bring a complaint from the neighbours.
static func on_interaction(f, iid: String) -> void:
	if not active("noise_rules") or CityGov.mayor.is_empty():
		return
	var p: Dictionary = cfg().get("noise_rules", {})
	if not (p.get("noisy", []) as Array).has(iid) or not _night(float(p.get("from", 22)), float(p.get("to", 7))):
		return
	if CityState.chance(float(p.get("chance", 0.4))):
		var fee: int = int(p.get("fine", 20))
		Economy.record(int(f.household_id), -fee, "noise fine")
		SysUtil.notify("A neighbour complained about the noise. Fine: %d coins." % fee, "warn")
		SysUtil.game_event("noise_fine", {"folk_id": int(f.id), "fine": fee})

## Build / business permits: "" when fine, else the reason (and the fee is charged by pay_permit).
static func permit_fee(kind: String) -> int:
	if not active("permits"):
		return 0
	return int(value("permits", "build_fee" if kind == "build" else "business_fee", 0))

static func pay_permit(hid: int, kind: String) -> Dictionary:
	var fee: int = permit_fee(kind)
	if fee <= 0:
		return {"ok": true, "fee": 0}
	if kind == "build" and int(CityGov.permit_day.get(str(hid), -1)) == SysUtil.day():
		return {"ok": true, "fee": 0}
	if not Economy.spend(hid, fee, "%s permit" % kind):
		return {"ok": false, "fee": fee, "reason": "A %s permit costs %d coins." % [kind, fee]}
	if kind == "build":
		CityGov.permit_day[str(hid)] = SysUtil.day()
	return {"ok": true, "fee": fee}

# ------------------------------------------------------------------ content (mayor and election interactions, generated from the data)
static func _def(label: String, ev: String, tests: Array, thought: String, objects: Array = ["mailbox"], extra: Dictionary = {}) -> Dictionary:
	var d := {"kind": "super", "target": "object", "objects": objects, "tags": ["paperwork"], "duration_min": 4, "posture": "stand", "per_min": {}, "autonomous": false,
		"priority": "normal", "advertises": {}, "label": label, "tests": tests, "on_finish": [{"fire_event": ev}], "thought": thought}
	d.merge(extra, true)
	return d

static func install_content() -> void:
	var g: Dictionary = CityGov.cfg()
	if g.is_empty():
		return
	var inter: Dictionary = {}
	var mayor_test: Array = [{"has_buff": "mayor"}]
	inter["town_notice"] = _def("Read the Town Notice", "town_notice", [], "What is the town up to?")
	inter["vote_mayor"] = _def("Vote for Mayor", "vote_mayor", [], "Time to have my say.")
	inter["run_for_mayor"] = _def("Run for Mayor", "run_for_mayor", [], "Maybe I should stand for mayor.")
	inter["tax_up"] = _def("Raise Taxes", "tax_up", mayor_test, "The town needs the money.")
	inter["tax_down"] = _def("Lower Taxes", "tax_down", mayor_test, "People could do with a break.")
	for d in (g.get("dept_labels", {}) as Dictionary):
		if d != "reserve":
			inter["focus_" + str(d)] = _def("Budget: more for %s" % str((g["dept_labels"] as Dictionary)[d]), "focus_" + str(d), mayor_test, "Where should the money go?")
	for zk in ["residential", "commercial", "civic"]:
		inter["rezone_" + zk] = _def("Rezone: more %s land" % zk, "rezone_" + zk, mayor_test, "How should the town grow?")
	for pid in ids():
		inter["propose_" + pid] = _def("Council: %s" % str((cfg()[pid] as Dictionary).get("label", pid)), "propose_" + pid, mayor_test, "Let me put it to the council.")
	var on_mailbox: Array = inter.keys()
	inter["give_campaign_speech"] = _def("Give a Campaign Speech", "campaign_speech", [], "Let me tell them what I stand for.", ["podium"],
		{"duration_min": 30, "per_min": {"energy": -0.1}, "skill_xp_per_min": {"charisma": 0.5}, "tags": ["skill", "speech"]})
	var content := {
		"buffs": {"mayor": {"label": "Mayor", "mood": {"focused": 1}, "duration_min": 0, "thought": "I am the mayor of this town."}},
		"objects": {"podium": {"def": {"label": "Speaker's Podium", "size": [1, 1], "price": 250, "tags": ["outdoor", "civic"], "model": "res://assets/models/podium.glb",
			"color": "#8a6a3e", "height": 1.1, "slots": [{"offset": [0, 1], "pose": "stand"}], "state": {}, "advertises": {}, "decor": 0.3, "interactions": ["give_campaign_speech"]}}},
		"interactions": inter,
		"object_interactions": {"mailbox": on_mailbox}}
	ContentMerge.install(content)
