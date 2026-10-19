extends RefCounted
## Task 21 part 1: selling the goods. Stolen things go through a fence (lower price, each item may be TRACED to the thief at a data-driven rate) or stay
## HIDDEN where police searches can find them once the thief is a suspect. A fence-ranked player earns a commission.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_stash(f)
	_sale(f)
	_trace_rate(f)
	_traced_case(f)
	_search(f)
	_boss(f)
	_townie(f)
	return f

func _fence_contact(w: StubWorld) -> int:
	var fence: int = int(C.adults()[0])
	CrimeLifePath.join(fence, "chose")
	CrimeLifePath.member(fence)["cred"] = 60.0
	CrimeLifePath.member(fence)["rank"] = "fence"
	CrimeLifeContacts.add(1, fence, "fence", 0.6)
	return fence

func _stash(f: Array) -> void:
	var w := C.town(12)
	var a: Dictionary = CrimeLifeFence.add_stash(1, "burglary", 200, 5, false)
	var b: Dictionary = CrimeLifeFence.add_stash(1, "car_theft", 400, 6, true)
	K.expect(f, CrimeLifeFence.stash_value(1) == 600 and int(a["id"]) != int(b["id"]), "goods pile up in the stash with their own ids")
	K.expect(f, bool(b["car"]) and CrimeLifeFence.take_item(1, int(a["id"])).size() > 0 and CrimeLifeFence.stash_value(1) == 400, "items can be taken out")
	K.teardown()

func _sale(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	CrimeLifeFence.add_stash(1, "burglary", 500, -1, false)
	var street: Dictionary = CrimeLifeFence.sell(1, [], -1)
	K.expect(f, bool(street["ok"]) and int(street["coins"]) == 100, "on the street goods fetch a fifth (%d)" % int(street["coins"]))
	var nofence: Dictionary = CrimeLifeFence.sell(1, [], 99)
	K.expect(f, not bool(nofence["ok"]), "you cannot use a fence you do not know")
	var fence: int = _fence_contact(w)
	CrimeLifeFence.add_stash(1, "burglary", 500, -1, false)
	var coins: int = WorldIface.get_coins(1)
	var res: Dictionary = CrimeLifeFence.sell(1, [], fence)
	K.expect(f, int(res["coins"]) > 100 and WorldIface.get_coins(1) == coins + int(res["coins"]), "a fence pays more than the street (%d)" % int(res["coins"]))
	K.expect(f, CrimeLifePath.member(1)["fenced"] == 2, "fenced goods count towards the fence rank")
	CrimeLifeFence.add_stash(1, "burglary", 500, -1, false)
	CrimeLifePath.member(fence)["snitch"] = true
	K.expect(f, not CrimeLifeFence.fences_for(1).has(fence), "a snitch is not a fence any more")
	var cmd: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimelife", "args": {"action": "fence", "ids": [], "fence_pid": -1}})
	K.expect(f, bool(cmd["ok"]) and CrimeLifeFence.items_of(1).is_empty(), "selling arrives as a command")
	K.teardown()

func _trace_rate(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	var fence: int = _fence_contact(w)
	var cold_case: Dictionary = CaseStore.create("burglary", 1, -1, "town:2", {})
	var hot_case: Dictionary = CaseStore.create("burglary", 1, -1, "town:2", {})
	hot_case["state"] = "open"
	hot_case["disc_day"] = SysUtil.day()
	var item_cold: Dictionary = {"id": 1, "value": 100, "case": int(cold_case["id"]), "day": SysUtil.day()}
	var item_hot: Dictionary = {"id": 2, "value": 100, "case": int(hot_case["id"]), "day": SysUtil.day()}
	var p_cold: float = CrimeLifeFence.trace_chance(item_cold, fence)
	var p_hot: float = CrimeLifeFence.trace_chance(item_hot, fence)
	var p_street: float = CrimeLifeFence.trace_chance(item_hot, -1)
	K.expect(f, p_hot > p_cold and p_street > p_hot, "tracing is likelier for a reported theft and for street sales (%.3f / %.3f / %.3f)" % [p_cold, p_hot, p_street])
	var n: int = 1500
	var traced: int = 0
	for i in n:
		if CrimeLifeState.chance(CrimeLifeFence.trace_chance(item_hot, fence)):
			traced += 1
	var expected: float = p_hot * float(n)
	K.expect(f, absf(float(traced) - expected) < 4.0 * sqrt(expected), "fencing traces goods to the thief at the expected rate (%d of %d, expected %.0f)" % [traced, n, expected])
	# and the real sale path at that rate
	var via_sale: int = 0
	var total: int = 0
	for i in 600:
		var c: Dictionary = CaseStore.create("burglary", 1, -1, "town:2", {})
		c["state"] = "open"
		c["disc_day"] = SysUtil.day()
		CrimeLifeFence.add_stash(1, "burglary", 100, int(c["id"]), false)
		var r: Dictionary = CrimeLifeFence.sell(1, [], fence)
		via_sale += int(r["traced"])
		total += int(r["sold"])
		if bool(c.get("fenced_trace", false)) != (int(r["traced"]) == 1):
			K.expect(f, false, "the case notes exactly the traced sales")
			break
	var exp2: float = p_hot * float(total)
	K.expect(f, absf(float(via_sale) - exp2) < 4.5 * sqrt(exp2) + 2.0, "the sale path traces at the same rate (%d of %d, expected %.0f)" % [via_sale, total, exp2])
	K.teardown()

func _traced_case(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	var c: Dictionary = CaseStore.create("burglary", 1, -1, "town:2", {})
	var it: Dictionary = {"id": 1, "value": 100, "case": int(c["id"]), "day": SysUtil.day()}
	CrimeLifeFence._traced(1, it, -1)
	K.expect(f, float(c["tips"]) >= 0.3 and bool(c["fenced_trace"]) and str(c["state"]) == "open", "a traced sale gives the police a tip and reveals a hidden case")
	K.expect(f, float(CrimeLifePath.member(1)["heat"]) >= 2.0, "and the thief runs hotter")
	K.expect(f, CaseEvidence.hard(1, c) > 0.2, "the tip is hard evidence against the thief")
	K.teardown()

func _search(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	var found: Callable = func() -> int:
		var n: int = 0
		for i in 80:
			var c: Dictionary = CaseStore.create("burglary", 1, int(C.adults()[0]), "town:2", {})
			c["state"] = "open"
			c["accused"] = 1
			c["disc_day"] = SysUtil.day()
			CrimeLifeState.stash.erase(1)
			CrimeLifeFence.add_stash(1, "burglary", 100, int(c["id"]), false)
			CrimeLifeFence.on_day()
			if bool(c["recovered"]):
				n += 1
		return n
	var open_stash: int = found.call()
	w.add_object("vault_safe", Vector2i(10, 14))
	Economy.refresh_objects()
	var hidden: int = found.call()
	K.expect(f, open_stash > 3, "police searches find stolen goods at a suspect's home (%d of 80)" % open_stash)
	K.expect(f, hidden < open_stash, "a safe hides them better (%d vs %d)" % [hidden, open_stash])
	var other: Dictionary = CaseStore.create("burglary", 1, -1, "town:2", {})
	other["state"] = "open"
	CrimeLifeState.stash.erase(1)
	CrimeLifeFence.add_stash(1, "burglary", 100, int(other["id"]), false)
	var seen: int = 0
	for i in 60:
		CrimeLifeFence.on_day()
		if CrimeLifeFence.items_of(1).is_empty():
			seen += 1
			break
	K.expect(f, seen == 0, "nobody searches for someone who is not a suspect")
	K.teardown()

func _boss(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["rank"] = "fence"
	CrimeLifeState.members[1]["cred"] = 60.0
	var before: int = WorldIface.get_coins(1)
	for d in 60:
		CrimeLifeFence._boss_commission()
	K.expect(f, WorldIface.get_coins(1) > before + 10, "a fence earns a steady commission from the town's thieves (+%d)" % (WorldIface.get_coins(1) - before))
	K.teardown()

func _townie(f: Array) -> void:
	var w := C.town(12)
	var thief: int = int(C.adults()[1])
	CrimeLifePath.join(thief, "chose")
	var c: Dictionary = CaseStore.create("burglary", thief, -1, "town:2", {})
	CrimeLifeFence.add_stash(thief, "burglary", 300, int(c["id"]), false)
	var coins: int = CrimePerson.coins(thief)
	CrimeLifeFence.on_day()
	K.expect(f, CrimeLifeFence.items_of(thief).is_empty() and CrimePerson.coins(thief) > coins, "townie thieves sell their goods on their own")
	K.teardown()
