class_name TransportCars
extends RefCounted
## Cars of a household (task 12.2): buy and sell, fuel or charge, repair after a crash, the pound after a tow, insurance (the existing car policy of
## BankInsurance: premiums are on the weekly bill and it pays back a share of repairs). Plain-word results: every call returns {ok, reason, ...}.

static func new_plate() -> String:
	var n: int = CityState.rng.randi_range(100, 999)
	var l: String = "ABCDEFGHJKLMNPRSTUVWXYZ"
	return "%s%s %d" % [l[CityState.rng.randi_range(0, l.length() - 1)], l[CityState.rng.randi_range(0, l.length() - 1)], n]

static func home_lot(hid: int) -> String:
	return PlayerLots.home_of_household(hid)

static func price(model: String) -> int:
	return int(round(float(Transport.model_def(model).get("price", 1000)) * Transport.price_mult()))

static func buy(hid: int, model: String) -> Dictionary:
	var d: Dictionary = Transport.model_def(model)
	if d.is_empty():
		return {"ok": false, "reason": "There is no such car for sale."}
	if Transport.cars_of(hid).size() >= int(Transport.num("cars", "limit_per_household", 3)):
		return {"ok": false, "reason": "There is no room for another car."}
	var cost: int = price(model)
	if not Economy.spend(hid, cost, "car: %s" % str(d.get("label", model))):
		return {"ok": false, "reason": "A %s costs %d coins. Not enough coins." % [str(d.get("label", "car")), cost]}
	var id: int = Transport.seq
	Transport.seq += 1
	var c: Dictionary = {"id": id, "hid": hid, "model": model, "plate": new_plate(), "fuel": float(d.get("tank", 40)) * 0.5, "cond": float(d.get("cond", 1.0)),
		"at": home_lot(hid), "spot": "", "bought": SysUtil.day(), "wreck": false, "ready_day": -1, "towed": false, "pound_day": -1, "trips": 0}
	Transport.cars[str(id)] = c
	TransportParking.park(c, str(c["at"]))
	Transport.count("cars_bought")
	return {"ok": true, "reason": "", "car": id, "cost": cost}

## What the car is worth now (condition, age, the model's resale share).
static func value(c: Dictionary) -> int:
	var d: Dictionary = Transport.model_def(str(c["model"]))
	var age: int = maxi(SysUtil.day() - int(c["bought"]), 0)
	var share: float = float(d.get("resale", 0.5)) * pow(0.995, float(age)) * (0.15 if bool(c["wreck"]) else float(c["cond"]))
	return int(round(float(d.get("price", 1000)) * Transport.price_mult() * clampf(share, 0.02, 1.0)))

static func sell(hid: int, id: int) -> Dictionary:
	var c: Dictionary = Transport.car(id)
	if c.is_empty() or int(c["hid"]) != hid:
		return {"ok": false, "reason": "That is not your car."}
	if bool(c["towed"]):
		return {"ok": false, "reason": "The car is at the pound."}
	if bool(c.get("stolen", false)):
		return {"ok": false, "reason": "The dealer asks for the papers. There are none."}
	var v: int = value(c)
	TransportParking.leave(c)
	Transport.cars.erase(str(id))
	Economy.deposit(hid, v, "sold the car")
	Transport.count("cars_sold")
	return {"ok": true, "reason": "", "value": v}

static func fuel_unit_price(c: Dictionary, at_home: bool) -> float:
	var d: Dictionary = Transport.model_def(str(c["model"]))
	var kind: String = str(d.get("fuel", "petrol"))
	var p: float = float((Transport.sect("cars").get("fuel_price", {}) as Dictionary).get(kind, 2.0)) * Transport.price_mult()
	if kind == "electric" and at_home:
		p *= float(Transport.sect("cars").get("home_charge_mult", 0.6))
	return p

## Fill the tank (or charge). Electric cars charge cheaper on the home lot.
static func refuel(hid: int, id: int) -> Dictionary:
	var c: Dictionary = Transport.car(id)
	if c.is_empty() or int(c["hid"]) != hid:
		return {"ok": false, "reason": "That is not your car."}
	var d: Dictionary = Transport.model_def(str(c["model"]))
	var missing: float = float(d.get("tank", 40)) - float(c["fuel"])
	if missing < 1.0:
		return {"ok": false, "reason": "The tank is already full."}
	var cost: int = maxi(int(ceil(missing * fuel_unit_price(c, str(c["at"]) == home_lot(hid)))), 1)
	if not Economy.spend(hid, cost, "fuel" if str(d.get("fuel", "")) != "electric" else "charging"):
		return {"ok": false, "reason": "Filling up costs %d coins. Not enough coins." % cost}
	c["fuel"] = float(d.get("tank", 40))
	Transport.count("refuels")
	return {"ok": true, "reason": "", "cost": cost}

static func repair_quote(c: Dictionary) -> int:
	var missing: float = 1.0 - float(c["cond"]) if not bool(c["wreck"]) else 1.0
	return int(round(missing * float(Transport.num("cars", "repair_per_cond", 600)) * Transport.price_mult()))

## Pay for repairs: the garage has it back in a few days; the car policy pays its share. Returns what the household really paid.
static func repair(hid: int, id: int) -> Dictionary:
	var c: Dictionary = Transport.car(id)
	if c.is_empty() or int(c["hid"]) != hid:
		return {"ok": false, "reason": "That is not your car."}
	if int(c["ready_day"]) > SysUtil.day():
		return {"ok": false, "reason": "The garage is already working on it."}
	if float(c["cond"]) >= 0.95 and not bool(c["wreck"]):
		return {"ok": false, "reason": "The car does not need repairs."}
	var quote: int = repair_quote(c)
	var covered: int = int(floor(float(quote) * BankInsurance.ratio(hid, "car")))
	var pay: int = quote - covered
	if not Economy.spend(hid, pay, "car repairs"):
		return {"ok": false, "reason": "The repairs cost %d coins. Not enough coins." % pay}
	var days: Array = Transport.sect("cars").get("repair_days", [1, 3])
	c["ready_day"] = SysUtil.day() + CityState.range_i(days)
	c["cond"] = 1.0 if str(c["model"]) != "banger" else 0.7
	c["wreck"] = false
	Transport.count("repairs")
	return {"ok": true, "reason": "", "paid": pay, "covered": covered, "ready_day": c["ready_day"]}

## Usable now: not wrecked, not in the garage, not at the pound, has fuel.
static func ready(c: Dictionary) -> bool:
	return not bool(c["wreck"]) and not bool(c["towed"]) and int(c["ready_day"]) <= SysUtil.day() and float(c["fuel"]) >= float(Transport.num("cars", "min_trip_fuel", 0.5))

static func fuel_use(c: Dictionary, tiles: int) -> float:
	return float(Transport.model_def(str(c["model"])).get("per_tile", 0.05)) * float(tiles)

## The pound: the fee grows each day.
static func pound_fee(c: Dictionary) -> int:
	var t: Dictionary = Transport.sect("parking").get("tow", {})
	return int(round((float(t.get("fee", 60)) + float(t.get("pound_per_day", 10)) * float(maxi(SysUtil.day() - int(c["pound_day"]), 0))) * Transport.price_mult()))

static func collect(hid: int, id: int) -> Dictionary:
	var c: Dictionary = Transport.car(id)
	if c.is_empty() or int(c["hid"]) != hid or not bool(c["towed"]):
		return {"ok": false, "reason": "There is no car of yours at the pound."}
	var fee: int = pound_fee(c)
	if not Economy.spend(hid, fee, "the pound"):
		return {"ok": false, "reason": "Getting the car back costs %d coins. Not enough coins." % fee}
	c["towed"] = false
	c["pound_day"] = -1
	c["at"] = home_lot(hid)
	TransportParking.park(c, str(c["at"]))
	return {"ok": true, "reason": "", "paid": fee}

static func buy_bike(hid: int) -> Dictionary:
	var cost: int = int(round(float((Transport.sect("modes").get("bike", {}) as Dictionary).get("price", 140)) * Transport.price_mult()))
	if not Economy.spend(hid, cost, "bike"):
		return {"ok": false, "reason": "A bike costs %d coins. Not enough coins." % cost}
	Transport.bikes[str(hid)] = Transport.bikes_of(hid) + 1
	return {"ok": true, "reason": "", "cost": cost}

## Daily: a car in the garage becomes usable again, cars never leave the town.
static func on_day(_day: int) -> void:
	for k in Transport.cars:
		var c: Dictionary = Transport.cars[k]
		if int(c["ready_day"]) >= 0 and int(c["ready_day"]) <= SysUtil.day():
			c["ready_day"] = -1
