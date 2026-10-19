class_name TransportParking
extends RefCounted
## Parking (task 12.2): every lot has a number of spaces (data), other people take some of them by day (ambient, no objects), the player's cars use the rest.
## A full lot means a search (minutes), the car park (a daily fee, safe), or the street (free, but venue streets are tow zones at night and ticketed by day).
##   TransportParking.capacity(lot) / free(lot, hour) / park(car, lot) -> {spot, extra_min, fee}   spot: drive | lot | garage | street
## Cadence: on parking and once a day for cars on the street / in the car park (a handful of cars). Nothing per minute.

static func cfg() -> Dictionary:
	return Transport.sect("parking")

static func reset() -> void:
	pass

static func to_dict() -> Dictionary:
	return {}

static func from_dict(_d: Dictionary) -> void:
	pass

static func lot_type(lot_id: String) -> String:
	if lot_id == Neighborhood.HOME:
		return "home"
	return str(Neighborhood.lot(lot_id).get("type", "default"))

static func capacity(lot_id: String) -> int:
	var caps: Dictionary = cfg().get("capacity", {})
	return int(caps.get(lot_type(lot_id), caps.get("default", 6)))

## Share of the spaces other people (townies, customers) take at this hour.
static func ambient(lot_id: String, hour: float) -> float:
	var a: Dictionary = cfg().get("ambient", {})
	var t: String = lot_type(lot_id)
	if t == "home":
		return float(a.get("home", 0.0))
	if t == "townie_home":
		return float(a.get("townie_home", 0.3))
	if (a.get("business_types", []) as Array).has(t):
		return float(a.get("business", 0.7)) if hour >= float(a.get("day_from", 7.5)) and hour < float(a.get("day_to", 18.5)) else float(a.get("default", 0.15)) * 0.5
	return float(a.get("default", 0.15))

static func parked_at(lot_id: String) -> int:
	var n: int = 0
	for k in Transport.cars:
		var c: Dictionary = Transport.cars[k]
		if str(c["at"]) == lot_id and (str(c["spot"]) == "drive" or str(c["spot"]) == "lot"):
			n += 1
	return n

static func spaces_free(lot_id: String, hour: float = -1.0) -> int:
	var h: float = SysUtil.hour_f() if hour < 0.0 else hour
	return capacity(lot_id) - int(ceil(ambient(lot_id, h) * float(capacity(lot_id)))) - parked_at(lot_id)

static func garage_has_room() -> bool:
	var n: int = 0
	for k in Transport.cars:
		if str(Transport.cars[k]["spot"]) == "garage":
			n += 1
	return n < int((cfg().get("garage", {}) as Dictionary).get("capacity", 120))

## Park `c` at `lot_id` (the trip arrived). Sets c.at / c.spot and returns what it cost in time and coins.
static func park(c: Dictionary, lot_id: String) -> Dictionary:
	leave(c)
	c["at"] = lot_id
	var g: Dictionary = cfg().get("garage", {})
	var home: bool = lot_type(lot_id) == "home"
	if spaces_free(lot_id) > 0:
		c["spot"] = "drive" if home else "lot"
		return {"spot": c["spot"], "extra_min": 0, "fee": 0}
	var search: int = CityState.range_i(cfg().get("search_min", [3, 10]))
	var fee: int = int(round(float(g.get("fee_per_day", 6)) * Transport.price_mult()))
	if garage_has_room() and Economy.balance(int(c["hid"])) >= fee * 3:
		c["spot"] = "garage"
		Transport.count("garage_parks")
		return {"spot": "garage", "extra_min": int(g.get("walk_min", 4)), "fee": fee}
	c["spot"] = "street"
	Transport.count("street_parks")
	return {"spot": "street", "extra_min": search, "fee": 0}

static func leave(c: Dictionary) -> void:
	c["spot"] = ""

## Daily: car park fees, tickets and night tows for the cars standing on venue streets.
static func on_day(_day: int) -> void:
	var t: Dictionary = cfg().get("tow", {})
	var g: Dictionary = cfg().get("garage", {})
	for k in Transport.cars.keys():
		var c: Dictionary = Transport.cars[k]
		var hid: int = int(c["hid"])
		match str(c["spot"]):
			"garage":
				Economy.record(hid, -int(round(float(g.get("fee_per_day", 6)) * Transport.price_mult())), "car park")
			"street":
				var tow_zone: bool = (t.get("tow_types", []) as Array).has(lot_type(str(c["at"])))
				if tow_zone and CityState.chance(float(t.get("chance", 0.4))):
					tow(c)
				elif tow_zone and CityState.chance(float(t.get("ticket_chance", 0.15))):
					ticket(c)
		if bool(c["towed"]) and hid > 0 and (SysUtil.day() - int(c["pound_day"])) == 7:
			SysUtil.notify("Your car is still at the pound. The fee grows every day.", "warn")

static func tow(c: Dictionary) -> void:
	c["towed"] = true
	c["spot"] = ""
	c["pound_day"] = SysUtil.day()
	Transport.count("tows")
	SysUtil.notify(str((Transport.sect("text")).get("towed", "Your car was towed.")), "warn")
	SysUtil.game_event("car_towed", {"household_id": int(c["hid"]), "car": int(c["id"]), "folk_id": -1})

static func ticket(c: Dictionary) -> void:
	var fee: int = int(round(float(cfg().get("tow", {}).get("street_ticket", 25)) * Transport.price_mult()))
	Economy.record(int(c["hid"]), -fee, "parking ticket")
	Transport.count("tickets")
	SysUtil.notify(str(Transport.sect("text").get("ticket", "A parking ticket.")).replace("{fee}", str(fee)), "warn")
