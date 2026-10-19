class_name CityCmd
extends RefCounted
## The command layer of the city track (multiplayer-ready rule 1): `Commands.run({action: "city", args: {action, args}})`. The household always comes from
## the folk that acts (never "household 1"); the interactions at the mailbox end in the same calls (CityCmd.on_event), so the pie menu and the command layer
## do the same thing. Actions: buy_car {model} | sell_car {car} | refuel {car} | repair_car {car} | collect_car {car} | buy_bike | bus_times.
## set_tax {value} | focus {dept, amount} (the mayor's levers of the Town panel). (the government slice adds vote, run_for_mayor, ...).

static func _hid(folk_id: int) -> int:
	var f = SysUtil.folk(folk_id)
	return int(f.household_id) if f != null else -1

static func run(e: Dictionary) -> Dictionary:
	var a: Dictionary = e["args"]
	return act(int(e["player_id"]), int(e["folk_id"]), str(a.get("action", "")), a.get("args", {}))

static func act(_player_id: int, folk_id: int, action: String, args: Dictionary) -> Dictionary:
	var hid: int = _hid(folk_id)
	if hid <= 0:
		return {"ok": false, "msg": "Nobody is acting."}
	var res: Dictionary = {"ok": false, "reason": "That is not possible."}
	match action:
		"buy_car":
			res = TransportCars.buy(hid, str(args.get("model", Transport.sect("cars").get("starter_model", "hatch"))))
		"sell_car":
			res = TransportCars.sell(hid, _car(hid, args))
		"refuel":
			res = TransportCars.refuel(hid, _car(hid, args))
		"repair_car":
			res = TransportCars.repair(hid, _car(hid, args))
		"collect_car":
			res = TransportCars.collect(hid, _car(hid, args))
		"buy_bike":
			res = TransportCars.buy_bike(hid)
		"bus_times":
			var f = SysUtil.folk(folk_id)
			var lot: String = NeighborhoodLots.lot_at(f.tile) if f != null else ""
			var lines: Array = TransportBus.timetable_text(lot)
			res = {"ok": not lines.is_empty(), "reason": "No bus stops here.", "lines": lines}
		"set_tax", "focus":
			res = _mayor_lever(folk_id, action, args)
		_:
			res = {"ok": false, "reason": "That is not possible."}
	res["msg"] = str(res.get("reason", ""))
	return res

## The Town panel's levers (taxes, where the budget goes): only a player who is the mayor can pull them (the same rule as the mailbox interactions).
static func _mayor_lever(folk_id: int, action: String, args: Dictionary) -> Dictionary:
	if not (bool(CityGov.mayor.get("player", false)) and int(CityGov.mayor.get("id", -1)) == folk_id):
		return {"ok": false, "reason": "Only the mayor can change the budget."}
	if action == "set_tax":
		CityGov.set_tax(float(args.get("value", CityGov.tax)))
		return {"ok": true, "tax": CityGov.tax, "reason": ""}
	var dept: String = str(args.get("dept", ""))
	if not CityGov.alloc.has(dept) or dept == "reserve":
		return {"ok": false, "reason": "That is not a part of the budget."}
	CityGov.shift(dept, float(args.get("amount", float(CityGov.cfg().get("alloc_step", 0.03)))))
	return {"ok": true, "reason": ""}

## The car the command means: its id, else the household's first car that fits the action.
static func _car(hid: int, args: Dictionary) -> int:
	if args.has("car"):
		return int(args["car"])
	for c in Transport.cars_of(hid):
		return int(c["id"])
	return -1

## Mailbox interactions (data/incidents/12_city.json) end in game events: the same actions, with a toast.
static func on_event(ev: String, payload: Dictionary) -> void:
	var fid: int = int(payload.get("folk_id", -1))
	if fid < 0:
		return
	var action: String = ""
	var args: Dictionary = {}
	if ev.begins_with("buy_car_"):
		action = "buy_car"
		args = {"model": ev.substr(8)}
	elif ev in ["sell_car", "refuel_car", "repair_car", "collect_car", "buy_bike", "bus_times"]:
		action = "refuel" if ev == "refuel_car" else ev
	else:
		return
	var res: Dictionary = act(Players.LOCAL, fid, action, args)
	if action == "bus_times":
		for line in res.get("lines", []):
			SysUtil.notify(str(line), "info")
		if not bool(res["ok"]):
			SysUtil.notify(str(res["reason"]), "info")
		return
	if not bool(res["ok"]):
		SysUtil.notify(str(res["reason"]), "warn")
		return
	var text: String = ""
	match action:
		"buy_car":
			text = "You bought a %s for %d coins. It is parked at home." % [str(Transport.model_def(str(args["model"])).get("label", "car")), int(res["cost"])]
		"sell_car":
			text = "You sold the car for %d coins." % int(res["value"])
		"refuel":
			text = "The tank is full. That cost %d coins." % int(res["cost"])
		"repair_car":
			text = "The garage will have the car back in a few days. You paid %d coins%s." % [int(res["paid"]), "" if int(res["covered"]) <= 0 else " (insurance paid %d)" % int(res["covered"])]
		"collect_car":
			text = "You got the car back from the pound for %d coins." % int(res["paid"])
		"buy_bike":
			text = "You bought a bike for %d coins." % int(res["cost"])
	SysUtil.notify(text, "good")
