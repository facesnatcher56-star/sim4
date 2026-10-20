class_name SoloContent
extends RefCounted
## Data patches of one-character play (data/solo.json): cooking costs ingredients for the pawn, the welcome basket is not for the pawn.
## Idempotent (a patched def carries `_solo`). Called by SysContent.install_all().

static func install() -> void:
	var inter: Dictionary = SimEnv.data().interactions()
	if inter.is_empty():
		return
	ContentMerge.install(SimEnv.data().get_table("content_solo"))
	var dl: Dictionary = SoloCfg.sect("day_labour")
	var dd: Dictionary = inter.get("day_labour", {})
	if not dd.is_empty() and not dd.has("_solo"):
		dd["_solo"] = 1
		dd["duration_min"] = float(dl.get("minutes", 240))
		dd["tests"] = [{"is_pawn": true}, {"at_lot": str(dl.get("lot", "works"))}, {"time_between": dl.get("hours", [7, 9])}]
		dd["on_finish"] = [{"pawn_wage": int(round(float(dl.get("pay_per_hour", 10)) * float(dl.get("minutes", 240)) / 60.0))}, {"solo_hook": "day_labour"}]
	var food: Dictionary = SoloCfg.sect("food")
	var unit: int = int(food.get("ingredient_cost", 3))
	for iid in (food.get("ingredients", {}) as Dictionary):
		var d: Dictionary = inter.get(iid, {})
		if d.is_empty() or d.has("_solo"):
			continue
		var cost: int = unit * int(food["ingredients"][iid])
		d["_solo"] = cost
		(d["tests"] as Array).append({"pays_ingredients": cost})
		var fin: Array = d.get("on_finish", [])
		fin.append({"pawn_coins_add": -cost})
		d["on_finish"] = fin
	for iid2 in food.get("no_free_food_for_pawn", []):
		var d2: Dictionary = inter.get(iid2, {})
		if not d2.is_empty() and not d2.has("_solo"):
			d2["_solo"] = 1
			(d2["tests"] as Array).append({"is_pawn": false})
