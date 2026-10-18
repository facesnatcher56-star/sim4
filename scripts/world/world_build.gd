class_name WorldBuild
extends RefCounted
## Build-mode economy: buy / sell with the household funds, plus undo.
## Back-references the World autoload as `world`; World keeps one-line delegates for the public API.

var world: WorldGrid
var _undo: Array = []


func _init(w: WorldGrid) -> void:
	world = w


# ------------------------------------------------------------------ economy guard

func _economy() -> Node:
	var r := world._root()
	return r.get_node_or_null("Economy") if r != null else null

func can_afford(household_id: int, amount: int) -> bool:
	if amount <= 0:
		return true
	var eco := _economy()
	if eco != null:
		if eco.has_method("can_afford"):
			return bool(eco.call("can_afford", household_id, amount))
		if eco.has_method("get_coins"):
			return int(eco.call("get_coins", household_id)) >= amount
	return true

func _spend(household_id: int, amount: int) -> bool:
	if amount <= 0:
		return true
	if world.coin_spend.is_valid():
		return bool(world.coin_spend.call(household_id, amount))
	var eco := _economy()
	if eco != null:
		if eco.has_method("spend"):
			return bool(eco.call("spend", household_id, amount))
		if eco.has_method("can_afford") and not bool(eco.call("can_afford", household_id, amount)):
			return false
	return true

func _refund(household_id: int, amount: int) -> void:
	if amount <= 0:
		return
	if world.coin_refund.is_valid():
		world.coin_refund.call(household_id, amount)
		return
	var eco := _economy()
	if eco != null:
		for m in ["refund", "earn", "add_coins"]:
			if eco.has_method(m):
				eco.call(m, household_id, amount)
				return

# ------------------------------------------------------------------ build tools + undo

func object_price(def_id: String) -> int:
	return int(world.get_def(def_id).get("price", 0))

## Buy and place. Returns object id, or -1 (see last_error).
func buy_place(def_id: String, tile: Vector2i, rot: int = 0, household_id: int = -1) -> int:
	var hid := world.current_household_id if household_id < 0 else household_id
	if not world.can_place(def_id, tile, rot):
		return -1
	var price := object_price(def_id)
	if not _spend(hid, price):
		world.last_error = "not enough coins"
		return -1
	var id := world._create_object(def_id, tile, posmod(rot, 4), -1)
	_push_undo({"t": "place", "id": id, "price": price, "hid": hid})
	return id

## Sell (delete) an object for SELL_RATIO of its price.
func sell_object(object_id: int, household_id: int = -1) -> bool:
	var o = world.objects.get(object_id, null)
	if o == null:
		return false
	if not world.regions.can_build(o.tile):
		return world.regions.deny()
	var hid := world.current_household_id if household_id < 0 else household_id
	var refund := int(floor(object_price(o.def_id) * world.SELL_RATIO))
	var data: Dictionary = o.to_dict()
	if not world.remove_object(object_id):
		return false
	_refund(hid, refund)
	_push_undo({"t": "remove", "data": data, "refund": refund, "hid": hid})
	return true

func sell_object_at(t: Vector2i, household_id: int = -1) -> bool:
	var o = world.object_at(t)
	return o != null and sell_object(o.id, household_id)

func _push_undo(op: Dictionary) -> void:
	_undo.append(op)
	while _undo.size() > world.UNDO_LIMIT:
		_undo.pop_front()

func undo_count() -> int:
	return _undo.size()

func clear_undo() -> void:
	_undo.clear()

## Undo the most recent build operation. Refunds / re-charges coins accordingly.
func undo_last() -> bool:
	if _undo.is_empty():
		return false
	var op: Dictionary = _undo.pop_back()
	match op["t"]:
		"place":
			world.remove_object(op["id"])
			_refund(op["hid"], op["price"])
		"remove":
			var d: Dictionary = op["data"]
			_spend(op["hid"], op["refund"])
			var t: Array = d["tile"]
			var nid := world._create_object(d["def_id"], Vector2i(t[0], t[1]), int(d["rot"]), int(d["id"]))
			if nid != -1:
				world.objects[nid].state = (d["state"] as Dictionary).duplicate(true)
		"walls":
			var changes: Array = op["changes"]
			for i in range(changes.size() - 1, -1, -1):
				var c: Dictionary = changes[i]
				world.set_edge(c["e"], c["old"])
				var od: Dictionary = c["obj"]
				if not od.is_empty():
					var t2: Array = od["tile"]
					var nid2 := world._create_object(od["def_id"], Vector2i(t2[0], t2[1]), int(od["rot"]), int(od["id"]))
					if nid2 != -1:
						world.objects[nid2].state = (od["state"] as Dictionary).duplicate(true)
			_refund(op["hid"], op["cost"])
		"floor":
			for c in op["changes"]:
				world.floors[c["t"].y * world.width + c["t"].x] = c["old"]
				world.regions.mark_floor_dirty(c["t"])
				world.rooms.mark_dirty(c["t"])
			world._emit("floors_changed")
			_refund(op["hid"], op["cost"])
	return true
