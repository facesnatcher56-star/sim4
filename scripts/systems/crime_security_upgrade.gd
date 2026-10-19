class_name CrimeSecurityUpgrade
extends RefCounted
## Buying cover (task 21). HOMES get their locks, alarm, cameras, motion sensors, safes, lights and guard-dog kennel as OBJECTS (build mode, see
## data/incidents/21_crimelife.json); two things are services here: alarm monitoring and a hired guard (weekly bill, CrimeSecurityAlarm.bill_extra).
## BUSINESSES (task 13: player or townie owners) buy upgrades by level (data/crimelife.json security.upgrades); a player owner pays from the household
## and a hired guard or store detective costs a weekly wage. The town budget (task 12) pays for police patrols: Police.patrol_factor.

static func defs() -> Dictionary:
	return CrimeSecurity.cfg().get("upgrades", {})

static func level_of_biz(biz_id: int, key: String) -> int:
	var b: Dictionary = BusinessState.get_biz(biz_id)
	var base: int = int(((CrimeSecurity.cfg().get("business", {}) as Dictionary).get(str(b.get("type", "")), {}) as Dictionary).get(key, 0))
	return maxi(base, int(CrimeLifeState.biz_sec.get(biz_id, {}).get(key, 0)))

## Price of the next level, or -1 at the maximum.
static func next_price(key: String, level: int) -> int:
	var d: Dictionary = defs().get(key, {})
	var prices: Array = d.get("price", [])
	if level >= int(d.get("max", 0)) or level + 1 >= prices.size():
		return -1
	return int(prices[level + 1])

## A business owner buys the next level of `key`. Returns {ok, msg}.
static func buy_business(hid: int, biz_id: int, key: String) -> Dictionary:
	var b: Dictionary = BusinessState.get_biz(biz_id)
	if b.is_empty() or str(b["owner_kind"]) != "player" or int(b["owner"]) != hid:
		return {"ok": false, "msg": "That is not your business."}
	if not defs().has(key):
		return {"ok": false, "msg": "Unknown upgrade."}
	var lvl: int = level_of_biz(biz_id, key)
	var price: int = next_price(key, lvl)
	if price < 0:
		return {"ok": false, "msg": "Already the best there is."}
	if WorldIface.get_coins(hid) < price:
		return {"ok": false, "msg": "That costs %d coins." % price}
	Economy.deposit(hid, -price, "security for %s" % str(b["name"]))
	var rec: Dictionary = CrimeLifeState.biz_sec.get(biz_id, {})
	rec[key] = lvl + 1
	CrimeLifeState.biz_sec[biz_id] = rec
	return {"ok": true, "msg": "%s: %s." % [str(defs()[key].get("label", key)), "installed"], "level": lvl + 1}

## A household turns a home service on: "monitored" (needs an alarm) or "guard" level 1..2.
static func set_home_service(hid: int, key: String, value: int) -> Dictionary:
	var rec: Dictionary = CrimeLifeState.home_sec.get(hid, {})
	if key == "monitored":
		if value > 0 and not bool(CrimeSecurity.home_profile(hid)["alarm"]):
			return {"ok": false, "msg": "Monitoring needs a burglar alarm first."}
		if value > 0 and not bool(rec.get("monitored", false)):
			var fee: int = int(((defs().get("monitored", {}) as Dictionary).get("price", [0, 0]) as Array)[1])
			if WorldIface.get_coins(hid) < fee:
				return {"ok": false, "msg": "That costs %d coins to set up." % fee}
			Economy.deposit(hid, -fee, "alarm monitoring")
		rec["monitored"] = value > 0
	elif key == "guard":
		var cur: int = int(rec.get("guard", 0))
		if value > cur:
			var price: int = next_price("guard", cur)
			if price < 0 or WorldIface.get_coins(hid) < price:
				return {"ok": false, "msg": "That costs %d coins." % price}
			Economy.deposit(hid, -price, "hired guard")
		rec["guard"] = clampi(value, 0, 2)
	else:
		return {"ok": false, "msg": "Unknown service."}
	CrimeLifeState.home_sec[hid] = rec
	return {"ok": true, "msg": ""}

## Townie owners react: after a robbery they buy cover, and a prosperous shop now and then adds a camera or an alarm.
static func townie_owners_day() -> void:
	for id in BusinessState.list:
		var b: Dictionary = BusinessState.list[id]
		if str(b["owner_kind"]) != "townie":
			continue
		var rec: Dictionary = CrimeLifeState.biz_sec.get(int(id), {})
		var robbed: bool = SysUtil.day() - int(rec.get("robbed_day", -999)) <= 14
		if not CrimeLifeState.chance(0.3 if robbed else 0.004):
			continue
		for key in ["camera", "alarm", "lock", "guard"]:
			var lvl: int = level_of_biz(int(id), key)
			var price: int = next_price(key, lvl)
			if price < 0 or CrimePerson.coins(int(b["owner"])) < price * 2:
				continue
			CrimePerson.pay(int(b["owner"]), price, "security")
			rec[key] = lvl + 1
			CrimeLifeState.biz_sec[int(id)] = rec
			break

## Weekly wages of business guards and store detectives, taken from the player owner.
static func on_day() -> void:
	townie_owners_day()
	if SysUtil.day() % 7 != 0:
		return
	for id in BusinessState.list:
		var b: Dictionary = BusinessState.list[id]
		if str(b["owner_kind"]) != "player":
			continue
		var up: Dictionary = CrimeLifeState.biz_sec.get(int(id), {})
		var wage: int = 0
		for key in ["guard", "detective"]:
			var lvl: int = int(up.get(key, 0))
			if lvl > 0:
				wage += int(((defs().get(key, {}) as Dictionary).get("weekly", [0]) as Array)[mini(lvl, 2)])
		if wage > 0:
			Economy.deposit(int(b["owner"]), -mini(wage, WorldIface.get_coins(int(b["owner"]))), "security wages")
