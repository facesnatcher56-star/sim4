class_name CrimeLifeHeist
extends RefCounted
## Task 21: PLANNED HEISTS on a bank, a jewellery store or the museum. The leader PLANS (picks the target), CASES it (CrimeLifeCasing), recruits a CREW
## (contacts with a role, a cut and a loyalty), buys GEAR, steals a GETAWAY car, then GOES. The run is CrimeLifeHeistRun. All text is plain and
## abstract: skills, rolls, roles and a split of the takings, no methods.
##   heist = {id, leader, target ("bank"), scene ("biz:bank"), stage (planning | ready | done | failed), day, crew [{pid, role, cut, loyal}], getaway (bool)}

static func cfg() -> Dictionary:
	return CrimeLifeState.sect("heists")

static func target_def(t: String) -> Dictionary:
	return (cfg().get("targets", {}) as Dictionary).get(t, {})

static func target_ids() -> Array:
	var out: Array = (cfg().get("targets", {}) as Dictionary).keys()
	out.sort()
	return out

static func get_heist(hid: int) -> Dictionary:
	return CrimeLifeState.heists.get(hid, {})

## The leader's live plan, or {}.
static func plan_of(leader: int) -> Dictionary:
	for hid in CrimeLifeState.heists:
		var h: Dictionary = CrimeLifeState.heists[hid]
		if int(h["leader"]) == leader and str(h["stage"]) in ["planning", "ready"]:
			return h
	return {}

static func can_plan(pid: int) -> bool:
	return CrimeLifePath.rank_index(pid) >= CrimeLifePath.rank_index_of_id(str(CrimeLifeRoll.job("heist").get("rank", "burglar")))

# ------------------------------------------------------------------ planning
static func plan(leader: int, target: String, unproven_ok: bool = false) -> Dictionary:
	if target_def(target).is_empty():
		return {"ok": false, "msg": "No such target."}
	if not CrimePerson.alive(leader) or CrimePerson.in_custody(leader):
		return {"ok": false, "msg": "Not right now."}
	if not CrimeLifePath.is_member(leader):
		return {"ok": false, "msg": "Start with smaller jobs."}
	if not unproven_ok and not can_plan(leader):
		return {"ok": false, "msg": "Nobody will back a plan from someone unproven. Build a name as a burglar first."}
	if not plan_of(leader).is_empty():
		return {"ok": false, "msg": "You already have a plan going."}
	var live: int = 0
	for hid in CrimeLifeState.heists:
		if str(CrimeLifeState.heists[hid]["stage"]) in ["planning", "ready"]:
			live += 1
	if live >= int(CrimeLifeState.sect("general").get("heist_cap", 6)):
		return {"ok": false, "msg": "The underworld is busy: too many plans in the air."}
	var id: int = CrimeLifeState.next_heist
	CrimeLifeState.next_heist += 1
	var h: Dictionary = {"id": id, "leader": leader, "target": target, "scene": "biz:%s" % target, "stage": "planning", "day": SysUtil.day(), "crew": [], "getaway": false}
	CrimeLifeState.heists[id] = h
	CrimeLifeState.count("heists_planned")
	return {"ok": true, "msg": "You start planning a job on %s." % target_def(target).get("label", target), "heist": id}

static func abort(leader: int) -> bool:
	var h: Dictionary = plan_of(leader)
	if h.is_empty():
		return false
	h["stage"] = "aborted"
	return true

## Why the plan is not ready, in plain words ("" = ready to go).
static func missing(h: Dictionary) -> String:
	var leader: int = int(h["leader"])
	if SysUtil.day() - int(h["day"]) < int(cfg().get("planning_days", 2)):
		return "A good plan needs a couple of days to come together."
	if CrimeLifeCasing.amount(leader, str(h["scene"])) < 0.3:
		return "You barely know the place yet. Watch it first."
	return ""

# ------------------------------------------------------------------ crew
static func recruit(leader: int, hid: int, member_pid: int, role: String, cut: float = -1.0) -> Dictionary:
	var h: Dictionary = get_heist(hid)
	if h.is_empty() or int(h["leader"]) != leader or str(h["stage"]) not in ["planning", "ready"]:
		return {"ok": false, "msg": "There is no plan to join."}
	var roles: Dictionary = cfg().get("roles", {})
	if not roles.has(role):
		return {"ok": false, "msg": "Unknown role."}
	if (h["crew"] as Array).size() >= int(cfg().get("crew_max", 4)):
		return {"ok": false, "msg": "The crew is full."}
	if crew_entry(h, member_pid) != null or member_pid == leader:
		return {"ok": false, "msg": "Already in."}
	if not CrimePerson.alive(member_pid) or CrimePerson.in_custody(member_pid) or not CrimePerson.is_adult(member_pid):
		return {"ok": false, "msg": "They are not available."}
	var range_: Array = cfg().get("cut_range", [0.05, 0.35])
	var c: float = clampf(cut if cut >= 0.0 else float(cfg().get("cut_default", 0.15)), float(range_[0]), float(range_[1]))
	var ct: Dictionary = CrimeLifeContacts.get_contact(leader, member_pid)
	var p: float = float(cfg().get("recruit_base", 0.35)) + c * 1.5 + float(ct.get("trust", 0.0)) * 0.5 + CrimeLifePath.cred(leader) / 250.0 + CrimePerson.charisma(leader) * 0.15 \
		+ float(RelationshipService.value(member_pid, leader, "friendship")) / 300.0
	if CrimePerson.has_trait(member_pid, "honest"):
		p *= 0.15
	if CrimeLifePath.member(member_pid).is_empty():
		p *= 0.4 if (CrimePerson.has_trait(member_pid, "dishonest") or CrimePerson.has_trait(member_pid, "reckless")) else 0.05
	if bool(CrimeLifePath.member(member_pid).get("snitch", false)):
		p = 0.0
	if not CrimeLifeState.chance(clampf(p, 0.0, 0.95)):
		return {"ok": false, "msg": "%s turns the job down." % CrimePerson.name_of(member_pid)}
	if CrimeLifePath.member(member_pid).is_empty():
		CrimeLifePath.join(member_pid, "recruited")
	var loyal: float = clampf(float(cfg().get("loyalty_base", 0.45)) + c * float(cfg().get("loyalty_cut", 1.2)) + float(ct.get("trust", 0.0)) * 0.3 \
		+ float(RelationshipService.value(member_pid, leader, "friendship")) * float(cfg().get("loyalty_friend", 0.003)) - (0.15 if CrimePerson.has_trait(member_pid, "dishonest") else 0.0), 0.05, 0.98)
	(h["crew"] as Array).append({"pid": member_pid, "role": role, "cut": c, "loyal": loyal})
	CrimeLifeContacts.add(leader, member_pid, role, 0.3)
	return {"ok": true, "msg": "%s is in as the %s, for %d%%." % [CrimePerson.name_of(member_pid), str((roles[role] as Dictionary).get("label", role)).to_lower(), int(c * 100.0)]}

static func crew_entry(h: Dictionary, pid: int):
	for e in h["crew"]:
		if int(e["pid"]) == pid:
			return e
	return null

static func drop_crew(leader: int, hid: int, member_pid: int) -> bool:
	var h: Dictionary = get_heist(hid)
	if h.is_empty() or int(h["leader"]) != leader:
		return false
	var crew: Array = h["crew"]
	for i in crew.size():
		if int(crew[i]["pid"]) == member_pid:
			crew.remove_at(i)
			return true
	return false

## Hand over a stolen car from the stash as the getaway car.
static func use_getaway(leader: int, hid: int) -> bool:
	var h: Dictionary = get_heist(hid)
	if h.is_empty() or int(h["leader"]) != leader or bool(h["getaway"]):
		return false
	for it in CrimeLifeFence.items_of(leader):
		if bool(it.get("car", false)):
			CrimeLifeFence.take_item(leader, int(it["id"]))
			h["getaway"] = true
			h["getaway_case"] = int(it.get("case", -1))
			return true
	return false

# ------------------------------------------------------------------ gear
static func buy_gear(pid: int, gid: String) -> Dictionary:
	var g: Dictionary = CrimeLifeRoll.gear_cfg().get(gid, {})
	if g.is_empty():
		return {"ok": false, "msg": "Unknown kit."}
	if CrimeLifeRoll.has_gear(pid, gid):
		return {"ok": false, "msg": "You already have that."}
	var price: int = int(g.get("price", 50))
	if CrimePerson.coins(pid) < price:
		return {"ok": false, "msg": "That costs %d coins." % price}
	CrimePerson.pay(pid, price, "kit")
	var rec: Dictionary = CrimeLifeState.gear.get(pid, {})
	rec[gid] = true
	CrimeLifeState.gear[pid] = rec
	if not CrimeLifePath.is_member(pid):
		CrimeLifePath.join(pid, "chose")
	return {"ok": true, "msg": "Bought: %s." % str(g.get("label", gid))}

# ------------------------------------------------------------------ going
## The leader sets off. The run is rolled when the time is up. Returns {ok, msg}.
static func go(leader: int, hid: int) -> Dictionary:
	var h: Dictionary = get_heist(hid)
	if h.is_empty() or int(h["leader"]) != leader or str(h["stage"]) not in ["planning", "ready"]:
		return {"ok": false, "msg": "There is no plan to carry out."}
	var why: String = missing(h)
	if why != "":
		return {"ok": false, "msg": why}
	var f = CrimePerson.folk(leader)
	if f != null:
		if SysUtil.is_away(f) or CrimePerson.in_custody(leader):
			return {"ok": false, "msg": "Not right now."}
		Away.send(f, float(CrimeLifeRoll.job("heist").get("minutes", 180)), "errand", {"label": "On the job"})
	h["stage"] = "ready"
	var mins: int = int(CrimeLifeRoll.job("heist").get("minutes", 180)) if f != null else 1
	CrimeLifeState.queue({"kind": "heist", "heist": hid, "due_min": SysUtil.now() + mins})
	return {"ok": true, "msg": "It is on. Everyone is in position."}

static func on_due(p: Dictionary) -> void:
	var h: Dictionary = get_heist(int(p.get("heist", -1)))
	if h.is_empty() or str(h["stage"]) != "ready":
		return
	if not CrimePerson.alive(int(h["leader"])) or CrimePerson.in_custody(int(h["leader"])):
		h["stage"] = "failed"
		return
	CrimeLifeHeistRun.run(h)

## A plain summary of the odds for the planning screen (no hidden numbers, words only).
static func outlook(h: Dictionary) -> Dictionary:
	var leader: int = int(h["leader"])
	var o: Dictionary = CrimeLifeRoll.odds(leader, "heist", str(h["scene"]), {"night": true})
	return {"entry": float(o["pull_off"]), "noticed": float(o["detect"]), "cased": float(o["cased"]), "crew": (h["crew"] as Array).size(), "getaway": bool(h["getaway"])}
