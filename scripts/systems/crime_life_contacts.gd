class_name CrimeLifeContacts
extends RefCounted
## Task 21: contacts. Townie criminals the player (or another member) can call on: met by asking around (the `ask_around` interaction), by chance in a
## bar, or through a record (people met inside, event `released`). A contact has a role (fence, driver, lookout, safecracker, muscle, hacker), trust
## that grows with shared jobs, and may refuse a snitch. Townie members get contacts too, with the same code, so the underworld is a web.

static func list(owner: int) -> Array:
	return CrimeLifeState.contacts.get(owner, [])

static func has(owner: int, pid: int) -> bool:
	for ct in list(owner):
		if int(ct["pid"]) == pid:
			return true
	return false

static func get_contact(owner: int, pid: int) -> Dictionary:
	for ct in list(owner):
		if int(ct["pid"]) == pid:
			return ct
	return {}

## The role a person is best at: fence when they have the standing, else the heist role their skills fit.
static func role_of(pid: int) -> String:
	if CrimeLifePath.rank_index(pid) >= CrimeLifePath.rank_index_of_id("fence"):
		return "fence"
	var best: String = "lookout"
	var bs: float = -1.0
	var roles: Dictionary = CrimeLifeState.sect("heists").get("roles", {})
	for rid in roles:
		var s: float = CrimeLifePath.skill_score(pid, (roles[rid] as Dictionary).get("skills", {}))
		if s > bs or (s == bs and str(rid) < best):
			bs = s
			best = str(rid)
	return best

static func add(owner: int, pid: int, role: String = "", trust: float = 0.3) -> Dictionary:
	if owner == pid or not CrimePerson.alive(pid):
		return {}
	var ex: Dictionary = get_contact(owner, pid)
	if not ex.is_empty():
		return ex
	var rows: Array = list(owner)
	var ct: Dictionary = {"pid": pid, "role": role if role != "" else role_of(pid), "trust": trust, "day": SysUtil.day()}
	rows.append(ct)
	var cap: int = int(CrimeLifeState.sect("general").get("contacts_cap", 12))
	while rows.size() > cap:
		rows.pop_front()
	CrimeLifeState.contacts[owner] = rows
	CrimeLifeState.count("contacts")
	if CrimePerson.is_player(owner):
		SysUtil.notify("%s is someone who knows people (%s)." % [CrimePerson.name_of(pid), str((CrimeLifeState.sect("heists").get("roles", {}) as Dictionary).get(str(ct["role"]), {}).get("label", ct["role"])).to_lower() if ct["role"] != "fence" else "a fence"], "story")
	return ct

static func drop(owner: int, pid: int) -> void:
	var rows: Array = list(owner)
	for i in rows.size():
		if int(rows[i]["pid"]) == pid:
			rows.remove_at(i)
			return

static func add_trust(owner: int, pid: int, amount: float) -> void:
	var ct: Dictionary = get_contact(owner, pid)
	if not ct.is_empty():
		ct["trust"] = clampf(float(ct["trust"]) + amount, 0.0, 1.0)

# ------------------------------------------------------------------ meeting people
## Game event crime_ask_around {folk_id, target_id}: one try per person a day. Returns {ok, msg, contact}.
static func ask_around(folk_id: int, target: int) -> Dictionary:
	var day: int = SysUtil.day()
	if int(CrimeLifeState.talk.get(folk_id, -1)) == day:
		return {"ok": false, "msg": "You have asked around enough for one day."}
	CrimeLifeState.talk[folk_id] = day
	if target < 0 or not CrimePerson.alive(target) or target == folk_id:
		return {"ok": false, "msg": ""}
	if not CrimeLifePath.is_member(folk_id):
		CrimeLifePath.join(folk_id, "chose")
	var tm: Dictionary = CrimeLifePath.member(target)
	var p: float = 0.2 + CrimePerson.charisma(folk_id) * 0.3 + CrimeLifePath.cred(folk_id) / 250.0 + (0.1 if CrimePerson.has_record(folk_id) else 0.0)
	if tm.is_empty():
		# an ordinary townie: dishonest or reckless folk know someone; the honest do not want to talk
		var shady: bool = CrimePerson.has_trait(target, "dishonest") or CrimePerson.has_trait(target, "reckless") or CrimePerson.has_trait(target, "kleptomaniac")
		if not shady or CrimePerson.has_trait(target, "honest"):
			return {"ok": false, "msg": "%s does not want to talk about that." % CrimePerson.name_of(target)}
		p *= 0.5
		if CrimeLifeState.chance(p):
			CrimeLifePath.join(target, "recruited")
			return {"ok": true, "msg": "%s has been on the edge of it for a while." % CrimePerson.name_of(target), "contact": add(folk_id, target)}
		return {"ok": false, "msg": "%s shrugs. Nothing doing." % CrimePerson.name_of(target)}
	if bool(tm.get("snitch", false)):
		return {"ok": false, "msg": "%s is known as a snitch. Nobody deals with them." % CrimePerson.name_of(target)}
	if bool(CrimeLifePath.member(folk_id).get("snitch", false)):
		return {"ok": false, "msg": "Word has got round that you talk to the police."}
	if CrimeLifeState.chance(p):
		return {"ok": true, "msg": "%s sizes you up and gives a nod." % CrimePerson.name_of(target), "contact": add(folk_id, target)}
	return {"ok": false, "msg": "%s says nothing. Maybe next time." % CrimePerson.name_of(target)}

## Daily: a member in a bar (the cafe) now and then meets a regular; released prisoners know people. Returns the number of new contacts.
static func on_day() -> int:
	var n: int = 0
	var chance: float = float(CrimeLifeState.sect("townie").get("contact_chance", 0.02))
	for pid in CrimeLifeState.members.keys():
		if not CrimePerson.is_player(int(pid)):
			continue
		if not CrimeLifeState.chance(chance):
			continue
		var pool: Array = []
		for q in CrimeLifeState.members.keys():
			if int(q) != int(pid) and not has(int(pid), int(q)) and CrimePerson.alive(int(q)) and not bool(CrimeLifeState.members[q].get("snitch", false)):
				pool.append(int(q))
		pool.sort()
		if not pool.is_empty():
			add(int(pid), int(pool[CrimeLifeState.rng.randi_range(0, pool.size() - 1)]))
			n += 1
	return n

## Game event released {folk_id}: time inside means you met people.
static func on_released(pid: int) -> void:
	if not CrimePerson.is_player(pid) and not CrimeLifePath.is_member(pid):
		return
	var pool: Array = []
	for q in CrimeLifeState.members.keys():
		if int(q) != pid and CrimePerson.alive(int(q)) and not has(pid, int(q)):
			pool.append(int(q))
	pool.sort()
	if pool.is_empty() or not CrimeLifeState.chance(0.7):
		return
	if CrimePerson.is_player(pid) and not CrimeLifePath.is_member(pid):
		return
	add(pid, int(pool[CrimeLifeState.rng.randi_range(0, pool.size() - 1)]), "", 0.4)
