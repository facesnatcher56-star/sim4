extends RefCounted
## Spoiled food: nobody eats or cooks from a fridge that holds it; it gets thrown away, and a low fridge is restocked when the household can pay.

const K = preload("res://tests/systems_kit.gd")
const Kit = preload("res://tests/sim_testkit.gd")

func run() -> Array:
	var f: Array = []
	_toss_first(f)
	_restock(f)
	return f

func _toss_first(f: Array) -> void:
	var w := K.setup(11)
	var o: Dictionary = Kit.furnish(w)
	var a := K.make_folk(w, "Mia Rowe", [], 1, Vector2i(11, 14))
	WorldIface.coins[1] = 2000
	WorldIface.state_set(o["fridge"], "stock", 8.0)
	WorldIface.state_set(o["fridge"], "spoiled", 3.0)
	(a.needs["hunger"] as Stat).set_value(-40.0)
	var dir = K.director()
	K.set_time(3, 12, 0)
	var ate_spoiled: bool = false
	for m in 240:
		K.run(dir, 1)
		if float(WorldIface.state_get(o["fridge"], "spoiled", 0.0)) > 0.0 and a.current != null and a.current.def_id in ["grab_snack", "cook_meal"]:
			ate_spoiled = true
	K.expect(f, not ate_spoiled, "nobody eats or cooks while the fridge holds spoiled food")
	K.expect(f, float(WorldIface.state_get(o["fridge"], "spoiled", 3.0)) == 0.0, "the spoiled food is thrown away on their own")
	K.expect(f, (a.needs["hunger"] as Stat).value > -40.0, "and then they eat")
	K.teardown()

func _restock(f: Array) -> void:
	var w := K.setup(12)
	var o: Dictionary = Kit.furnish(w)
	var a := K.make_folk(w, "Mia Rowe", [], 1, Vector2i(11, 14))
	WorldIface.coins[1] = 2000
	WorldIface.state_set(o["fridge"], "stock", 0.0)
	(a.needs["hunger"] as Stat).set_value(-40.0)
	var dir = K.director()
	K.set_time(3, 12, 0)
	K.run(dir, 360)
	K.expect(f, (a.needs["hunger"] as Stat).value > -40.0 or float(WorldIface.state_get(o["fridge"], "stock", 0.0)) > 0.0, "an empty fridge is restocked when they can afford it")
	K.teardown()
