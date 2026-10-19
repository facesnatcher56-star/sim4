class_name CrimeLifeFence
extends RefCounted
## Task 21: selling the goods. Stolen things are not coins until they are FENCED: a fence contact pays a lower price and each item may be TRACED
## (a tip reaches the case: "some of it turned up at a fence"); the alternative is to keep it HIDDEN in the stash, where police searches can find it
## once the thief is a suspect. Rates and trace chances are data (crimelife.json "fence"). A fence-ranked player earns a commission from the town's thieves.

static func cfg() -> Dictionary:
	return CrimeLifeState.sect("fence")

# ------------------------------------------------------------------ the stash
static func add_stash(pid: int, jid: String, value: int, case_id: int, car: bool) -> Dictionary:
	var list: Array = CrimeLifeState.stash.get(pid, [])
	var names: Dictionary = {"shoplift": "shop goods", "burglary": "household valuables", "car_theft": "a stolen car", "store_robbery": "takings", "heist": "heist loot", "pickpocket": "a wallet's contents", "scam": "ill-gotten gains"}
	var item: Dictionary = {"id": _next_item_id(), "name": str(names.get(jid, "stolen goods")), "value": value, "case": case_id, "day": SysUtil.day(), "car": car}
	list.append(item)
	var cap: int = int(CrimeLifeState.sect("general").get("stash_cap", 30))
	while list.size() > cap:
		list.pop_front()
	CrimeLifeState.stash[pid] = list
	return item

static func _next_item_id() -> int:
	CrimeLifeState.count("stash_items")
	return CrimeLifeState.counter("stash_items")

static func items_of(pid: int) -> Array:
	return CrimeLifeState.stash.get(pid, [])

static func stash_value(pid: int) -> int:
	var t: int = 0
	for it in items_of(pid):
		t += int(it["value"])
	return t

static func take_item(pid: int, item_id: int) -> Dictionary:
	var list: Array = items_of(pid)
	for i in list.size():
		if int(list[i]["id"]) == item_id:
			var it: Dictionary = list[i]
			list.remove_at(i)
			return it
	return {}

# ------------------------------------------------------------------ fences
## People who can fence for `pid`: contacts with the fence role, then other members of fence rank or above. Never a snitch.
static func fences_for(pid: int) -> Array:
	var out: Array = []
	for ct in CrimeLifeState.contacts.get(pid, []):
		var q: int = int(ct["pid"])
		if str(ct.get("role", "")) == "fence" and CrimePerson.alive(q) and not CrimePerson.in_custody(q) and not bool(CrimeLifePath.member(q).get("snitch", false)):
			out.append(q)
	return out

static func rate(seller: int, fence_pid: int) -> float:
	var k: Dictionary = cfg()
	if fence_pid < 0:
		return float(k.get("rate_street", 0.2))
	var r: float = float(k.get("rate", 0.4)) + float(CrimeLifePath.skill(seller, "charisma")) * float(k.get("rate_skill", 0.02))
	if CrimeLifePath.rank_index(seller) >= CrimeLifePath.rank_index_of_id("fence"):
		r += float(k.get("rate_boss", 0.1))
	return clampf(r, 0.1, 0.65)

## Chance that selling this item leads the police to the thief.
static func trace_chance(item: Dictionary, fence_pid: int) -> float:
	var k: Dictionary = cfg()
	var c: Dictionary = CaseStore.get_case(int(item.get("case", -1)))
	var hot: bool = not c.is_empty() and str(c["state"]) in ["open", "arrested", "charged"] and SysUtil.day() - int(c.get("disc_day", item.get("day", 0))) <= int(k.get("hot_days", 10))
	var base: float = float(k.get("trace_street", 0.25)) if fence_pid < 0 else float(k.get("trace", 0.12)) * (1.0 - float(k.get("fence_skill", 0.05)) * minf(CrimeLifePath.cred(fence_pid) / 10.0, 8.0))
	return clampf(base * (float(k.get("trace_hot", 1.5)) if hot else float(k.get("trace_cold", 0.7))) * clampf(Police.strength(), 0.3, 1.6), 0.0, 0.9)

## Sell items (all of them when `ids` is empty) to a fence (-1 = on the street). Returns {ok, coins, traced, sold, msg}.
static func sell(pid: int, ids: Array, fence_pid: int) -> Dictionary:
	if fence_pid >= 0 and not fences_for(pid).has(fence_pid):
		return {"ok": false, "msg": "You do not know a fence.", "coins": 0, "traced": 0, "sold": 0}
	var list: Array = items_of(pid).duplicate()
	var coins: int = 0
	var traced: int = 0
	var sold: int = 0
	for it in list:
		if not ids.is_empty() and not ids.has(int(it["id"])):
			continue
		take_item(pid, int(it["id"]))
		var pay: int = int(round(float(it["value"]) * rate(pid, fence_pid)))
		coins += pay
		sold += 1
		if CrimeLifeState.chance(trace_chance(it, fence_pid)):
			traced += 1
			_traced(pid, it, fence_pid)
	if coins > 0:
		CrimePerson.add_coins(pid, coins, "goods sold")
	var m: Dictionary = CrimeLifePath.member(pid)
	if not m.is_empty() and sold > 0:
		m["fenced"] = int(m.get("fenced", 0)) + sold
		CrimeLifePath.add_cred(pid, 0.5 * float(sold), "fenced")
	CrimeLifeState.count("fenced_items", sold)
	CrimeLifeState.count("fenced_traced", traced)
	if CrimePerson.is_player(pid) and sold > 0:
		SysUtil.notify("Sold %d lot%s for %d coins%s." % [sold, "" if sold == 1 else "s", coins, " - but one of them can be traced back" if traced > 0 else ""], "warn" if traced > 0 else "info")
	return {"ok": sold > 0, "coins": coins, "traced": traced, "sold": sold, "msg": "" if sold > 0 else "Nothing to sell."}

static func _traced(pid: int, item: Dictionary, fence_pid: int) -> void:
	var k: Dictionary = cfg()
	var c: Dictionary = CaseStore.get_case(int(item.get("case", -1)))
	var m: Dictionary = CrimeLifePath.member(pid)
	if not m.is_empty():
		m["heat"] = float(m.get("heat", 0.0)) + 2.0
	if c.is_empty():
		return
	c["tips"] = minf(float(c.get("tips", 0.0)) + float(k.get("trace_tip", 0.35)), 0.6)
	c["fenced_trace"] = true
	if str(c["state"]) == "hidden":
		CaseDiscovery.report(c, -1, "noticed")
	CaseStore.note(c, "Some of the stolen goods turned up at a fence%s." % ("" if fence_pid >= 0 else " (sold on the street)"))
	if str(c["state"]) == "cold":
		CaseInvestigation.reopen(c, "Stolen goods turned up.")

# ------------------------------------------------------------------ hiding
static func hide_quality(pid: int) -> float:
	var k: Dictionary = cfg()
	var q: float = float(k.get("hide_base", 0.3))
	var hid: int = CrimePerson.hid(pid)
	if hid > 0 and int(CrimeSecurity.home_profile(hid)["safe"]) > 0:
		q += float(k.get("hide_safe", 0.45))
	return clampf(q, 0.0, 0.9)

## Daily: police search the stash of a suspect; a fence-ranked player earns a commission; townie thieves sell off.
static func on_day() -> void:
	var k: Dictionary = cfg()
	for pid in CrimeLifeState.stash.keys():
		if not CrimePerson.alive(int(pid)):
			CrimeLifeState.stash.erase(pid)
			continue
		var list: Array = items_of(int(pid))
		if list.is_empty():
			continue
		if CrimePerson.folk(int(pid)) == null and CrimeLifePath.is_member(int(pid)):
			_townie_sells(int(pid))
			continue
		for it in list.duplicate():
			var c: Dictionary = CaseStore.get_case(int(it.get("case", -1)))
			if c.is_empty() or not (str(c["state"]) in ["open", "arrested", "charged"]):
				continue
			var suspect: bool = int(c.get("accused", -1)) == int(pid) or SysUtil.to_ints(c.get("suspect_ids", [])).has(int(pid))
			if suspect and CrimeLifeState.chance(float(k.get("search_daily", 0.12)) * clampf(Police.strength(), 0.3, 1.6) * (1.0 - hide_quality(int(pid)))):
				_found(int(pid), it, c)
	_boss_commission()

static func _found(pid: int, it: Dictionary, c: Dictionary) -> void:
	take_item(pid, int(it["id"]))
	c["recovered"] = true
	c["tips"] = minf(float(c.get("tips", 0.0)) + float(cfg().get("found_tip", 0.5)) * 0.4, 0.6)
	var victim: int = int(c.get("victim", -1))
	if victim >= 0:
		CrimePerson.add_coins(victim, int(it["value"]), "goods recovered")
	CaseStore.note(c, "Police found stolen goods hidden at %s's." % CrimePerson.name_of(pid), "arrest", 3)
	if CrimePerson.is_player(pid):
		SysUtil.notify("The police searched the place and found the stolen goods.", "bad")
	CrimeLifeState.count("stash_found")

static func _townie_sells(pid: int) -> void:
	var fences: Array = []
	for q in CrimeLifeState.members:
		if int(q) != pid and CrimeLifePath.rank_index(int(q)) >= CrimeLifePath.rank_index_of_id("fence") and CrimePerson.alive(int(q)) and not CrimePerson.in_custody(int(q)):
			fences.append(int(q))
	var f: int = int(fences[CrimeLifeState.rng.randi_range(0, fences.size() - 1)]) if not fences.is_empty() else -1
	var res: Dictionary = sell_to(pid, f)
	if f >= 0 and int(res.get("sold", 0)) > 0:
		var fm: Dictionary = CrimeLifePath.member(f)
		fm["fenced"] = int(fm.get("fenced", 0)) + int(res["sold"])
		CrimeLifePath.add_cred(f, 0.3 * float(res["sold"]))

## Townie sale (no contact check, no toast).
static func sell_to(pid: int, fence_pid: int) -> Dictionary:
	var coins: int = 0
	var traced: int = 0
	var sold: int = 0
	for it in items_of(pid).duplicate():
		take_item(pid, int(it["id"]))
		coins += int(round(float(it["value"]) * rate(pid, fence_pid)))
		sold += 1
		if CrimeLifeState.chance(trace_chance(it, fence_pid)):
			traced += 1
			_traced(pid, it, fence_pid)
	if coins > 0:
		CrimePerson.add_coins(pid, coins, "goods sold")
	CrimeLifeState.count("fenced_items", sold)
	CrimeLifeState.count("fenced_traced", traced)
	return {"sold": sold, "coins": coins, "traced": traced}

## A player of fence rank or above earns a commission when town thieves move goods: a small steady income with the risk of heat.
static func _boss_commission() -> void:
	for pid in CrimeLifeState.members.keys():
		if not CrimePerson.is_player(int(pid)) or CrimeLifePath.rank_index(int(pid)) < CrimeLifePath.rank_index_of_id("fence"):
			continue
		if CrimeLifeState.chance(0.2):
			var value: int = CrimeLifeState.rng.randi_range(40, 200)
			var cut: int = int(float(value) * float(cfg().get("boss_commission", 0.08)) * 3.0)
			CrimePerson.add_coins(int(pid), cut, "fence commission")
			CrimeLifeState.count("commission_coins", cut)
			if CrimeLifeState.chance(cfg().get("trace", 0.12)):
				CrimeLifePath.member(int(pid))["heat"] = float(CrimeLifePath.member(int(pid)).get("heat", 0.0)) + 1.5
