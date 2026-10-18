class_name CrimePerson
extends RefCounted
## One view of "a person" for the crime and justice code: a real Folk (household member, or a townie standing on the map) or a Story townie
## record. Everything is addressed by person id (Folk ids and townie ids never collide). Full versus statistical is decided per action.

static func folk(pid: int):
	return SysUtil.folk(pid)

static func exists(pid: int) -> bool:
	return folk(pid) != null or Story.townies.has(pid)

static func alive(pid: int) -> bool:
	if folk(pid) != null:
		return true
	return Story.townies.has(pid) and bool(Story.townies[pid].get("alive", false))

static func rec(pid: int) -> Dictionary:
	return Story.townies.get(pid, {})

static func name_of(pid: int) -> String:
	var f = folk(pid)
	if f != null:
		return str(f.name)
	if Story.townies.has(pid):
		return str(Story.townies[pid].get("name", "Someone"))
	return "Someone"

## Household resident of the player (not a visiting townie).
static func is_player(pid: int) -> bool:
	return SysUtil.is_resident(folk(pid))

static func hid(pid: int) -> int:
	var f = folk(pid)
	return int(f.household_id) if SysUtil.is_resident(f) else 0

static func traits(pid: int) -> Array:
	var f = folk(pid)
	if f != null:
		return f.traits
	return rec(pid).get("traits", [])

static func has_trait(pid: int, t: String) -> bool:
	return traits(pid).has(t)

static func stage(pid: int) -> String:
	var f = folk(pid)
	if f != null:
		return str(f.age_stage)
	return Story.stage_of(rec(pid)) if Story.townies.has(pid) else "adult"

static func is_adult(pid: int) -> bool:
	return stage(pid) in ["adult", "elder"]

static func coins(pid: int) -> int:
	if is_player(pid):
		return WorldIface.get_coins(hid(pid))
	return int(rec(pid).get("coins", 0))

static func add_coins(pid: int, n: int, why: String = "") -> void:
	if is_player(pid):
		Economy.deposit(hid(pid), n, why)
	elif Story.townies.has(pid):
		Story.townies[pid]["coins"] = maxi(int(Story.townies[pid].get("coins", 0)) + n, 0)

## Spend what the person has (never below zero). Returns what was actually paid.
static func pay(pid: int, n: int, why: String = "") -> int:
	var have: int = coins(pid)
	var amt: int = mini(n, have)
	if amt > 0:
		add_coins(pid, -amt, why)
	return amt

static func career(pid: int) -> String:
	if is_player(pid) or folk(pid) != null:
		return Careers.career_of(pid)
	return str(rec(pid).get("career", ""))

static func has_job(pid: int) -> bool:
	return career(pid) != ""

static func lot_no(pid: int) -> int:
	return int(rec(pid).get("lot", 0))

## "home:1" for a household member, "town:3" for a townie's house.
static func home_key(pid: int) -> String:
	if is_player(pid):
		return "home:%d" % hid(pid)
	return "town:%d" % lot_no(pid)

static func reputation(pid: int) -> float:
	return RelationshipKnowledge.reputation(pid)

static func skill(pid: int, sk: String) -> int:
	var f = folk(pid)
	if f != null:
		return f.skill_level(sk)
	return IncidentSubject.of_townie(pid).skill_level(sk) if Story.townies.has(pid) else 0

static func charisma(pid: int) -> float:
	return clampf(float(skill(pid, "charisma")) / 5.0 + (0.2 if has_trait(pid, "charmer") else 0.0), 0.0, 1.0)

## Everyone alive: household residents, Story townies and visitor Folk (each once), sorted by id.
static func everyone() -> Array:
	var seen: Dictionary = {}
	for f in WorldIface.all_folk():
		seen[int(f.id)] = true
	for tid in Story.townies:
		if bool(Story.townies[tid].get("alive", false)):
			seen[int(tid)] = true
	var out: Array = seen.keys()
	out.sort()
	return out

static func townies_only() -> Array:
	var out: Array = []
	for tid in Story.townies:
		if bool(Story.townies[tid].get("alive", false)):
			out.append(int(tid))
	out.sort()
	return out

static func in_custody(pid: int) -> bool:
	return JusticeState.inmates.has(pid)

static func record_count(pid: int) -> int:
	return (JusticeState.records.get(pid, []) as Array).size()

static func has_record(pid: int) -> bool:
	return record_count(pid) > 0

## Persons who are family / partner / close friends of `pid`, nearest first by rank.
static func close_ones(pid: int) -> Array:
	var out: Array = []
	for rank in ["spouse", "partner", "family", "sweetheart", "best_friend"]:
		for o in RelationshipBits.others_with_bit(pid, rank):
			if not out.has(int(o)):
				out.append(int(o))
	return out

static func close_alive(pid: int) -> Array:
	return close_ones(pid).filter(func(x): return alive(int(x)))

static func friends(pid: int) -> Array:
	var out: Array = []
	for o in RelationshipBits.others_with_bit(pid, "friend"):
		if not out.has(int(o)):
			out.append(int(o))
	return out

static func is_kin_or_partner(a: int, b: int) -> bool:
	return RelationshipBits.bit_for(a, b) in ["family", "spouse", "partner", "sweetheart"]

## Mark the person gone from the world without grief or a grave yet (a hidden death): they stop acting but are still "owed" a discovery.
static func hide_death(pid: int, cause: String) -> void:
	var f = folk(pid)
	if f != null:
		Aging.kill(pid, cause)
		return
	if Story.townies.has(pid):
		var t: Dictionary = Story.townies[pid]
		t["alive"] = false
		t["hidden_death"] = cause
		t["missing_since"] = SysUtil.day()

## The death becomes known: grief, grave, chronicle (townie), exactly as an ordinary death.
static func reveal_death(pid: int) -> void:
	if not Story.townies.has(pid):
		return
	var t: Dictionary = Story.townies[pid]
	if not t.has("hidden_death"):
		return
	var cause: String = str(t["hidden_death"])
	t.erase("hidden_death")
	t.erase("missing_since")
	t["alive"] = true
	Aging.kill(pid, cause)

static func add_buff_safe(pid: int, buff: String) -> void:
	var f = folk(pid)
	if f != null:
		f.add_buff(buff)
