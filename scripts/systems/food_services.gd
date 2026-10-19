class_name FoodServices
extends RefCounted
## The handlers (PlaceHandlers) of the food and nightlife places:
##   drink       alcohol (service.alcohol = strength): adults only; the 4th strong drink of a day gives a hangover and the barkeeper refuses at the 5th
##   pantry      takes the food home: `units` go to the household fridge (Neighborhood.add_pantry)
##   sell_crafts the farmers' market buys the household's crafts and garden produce at full price (MarketWork.sell_crafts)
## Drinks are counted per person per day in FoodServices.drinks (not saved: a day resets it, so a load mid-evening only forgets the tally).

static var drinks: Dictionary = {}       # person id -> {day, n}

static func reset() -> void:
	drinks.clear()

static func cfg() -> Dictionary:
	return LifeDefs.cfg("food").get("drinks", {})

static func tally(id: int) -> int:
	var d: Dictionary = drinks.get(id, {})
	return int(d.get("n", 0)) if int(d.get("day", -1)) == _night() else 0

## A night belongs to the day it started on until 06:00 (a drink at 01:00 counts with the evening before).
static func _night() -> int:
	return SysUtil.day() - (1 if SysUtil.hour_f() < 6.0 else 0)

static func check(handler: String, f, _pid: String, _sid: String, _svc: Dictionary) -> String:
	match handler:
		"drink":
			if tally(int(f.id)) >= int(cfg().get("refuse_after", 5)):
				return "The barkeeper says %s has had enough for tonight." % f.name
		"sell_crafts":
			var hid: int = int(f.household_id)
			var any := false
			for kind in (MarketWork.cfg().get("crafts", {}) as Dictionary):
				if MarketWork.craft_count(hid, str(kind)) > 0:
					any = true
			if not any:
				return "%s has nothing to sell." % f.name
	return ""

static func finish(handler: String, f, _pid: String, _sid: String, svc: Dictionary) -> Dictionary:
	var id: int = int(f.id)
	match handler:
		"drink":
			var d: Dictionary = drinks.get(id, {})
			if int(d.get("day", -1)) != _night():
				d = {"day": _night(), "n": 0}
			d["n"] = int(d["n"]) + int(svc.get("alcohol", 1))
			drinks[id] = d
			if int(d["n"]) >= int(cfg().get("hangover_after", 4)):
				f.add_buff(str(cfg().get("hangover_buff", "hangover")))
				return {"text": "%s had a few too many and will feel it in the morning." % f.name, "kind": "warn"}
		"pantry":
			Neighborhood.add_pantry(int(svc.get("units", 1)))
		"sell_crafts":
			var r: Dictionary = MarketWork.sell_crafts(int(f.household_id), id, true)
			return {"text": "%s sold %d things at the market for %d coins." % [f.name, int(r.get("units", 0)), int(r.get("paid", 0))] if bool(r.get("ok", false)) else ""}
	return {}
