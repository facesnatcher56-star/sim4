extends RefCounted
## Fire on the REAL World (not the stub): objects with footprints, walls that stop the spread, burnt objects removed with burnt remains placed
## (ash_pile from the content section), rooms deciding who notices, and the hover tooltip lines.

func _root() -> Window:
	return Engine.get_main_loop().root

func _tick(n: int) -> void:
	for i in n:
		_root().get_node("Clock").advance_minutes(1)
		Fire.on_minute()

func _count(W, def_id: String) -> int:
	return W.objects_of_def(def_id).size()

func run() -> Array:
	var f: Array = []
	var W = _root().get_node_or_null("World")
	if W == null:
		return ["World autoload missing"]
	TestFixture.reset()
	WorldIface.stub = null
	W.reset(24, 14)
	IncidentDefs.reset()
	IncidentContent.install()
	Fire.reset()
	if W.get_def("ash_pile").is_empty() or W.get_def("sprinkler").is_empty():
		return ["content objects missing from the real World defs"]
	# two rooms split by a wall at x=8; a stove + counter + sofa on the left, a sofa on the right
	W.add_wall(Vector2i(8, 0), Vector2i(8, 14))
	var stove: int = W.place_object("stove", Vector2i(5, 5))
	var counter: int = W.place_object("counter", Vector2i(6, 5))
	var sofa_l: int = W.place_object("sofa", Vector2i(5, 8))
	var sofa_r: int = W.place_object("sofa", Vector2i(10, 5))
	if stove < 0 or counter < 0 or sofa_l < 0 or sofa_r < 0:
		return ["could not place the test furniture"]
	var s_obj = W.get_object(stove)
	f.append_array(_check(Fire.ignite(stove, "cooking"), "ignite by object id on the real World"))
	f.append_array(_check(Fire.is_burning(Vector2i(5, 5)) and Fire.fires_in("home").size() == 1, "tile query + lot of the fire"))
	_tick(40)
	f.append_array(_check(not Fire.is_burning(sofa_r) and W.get_object(sofa_r) != null, "a wall stops the fire spreading to the other room"))
	f.append_array(_check(int(Fire.stats["spread_events"]) >= 1, "it spread to the counter beside it (%d events)" % int(Fire.stats["spread_events"])))
	f.append_array(_check(_count(W, "ash_pile") >= 1, "burnt remains where objects burnt down (%d)" % _count(W, "ash_pile")))
	f.append_array(_check(W.get_object(stove) == null, "the burnt stove is removed from the World"))
	f.append_array(_check(int(Fire.stats["loss"]) >= 450, "its price is lost (%d)" % int(Fire.stats["loss"])))
	# rooms: same room / other room
	f.append_array(_check(FireRules.same_room(Vector2i(5, 6), Vector2i(6, 7)) and not FireRules.same_room(Vector2i(5, 6), Vector2i(10, 6)), "rooms: same room beside the stove, a different one behind the wall"))
	# tooltips on real objects
	var ash = W.objects_of_def("ash_pile")[0] if _count(W, "ash_pile") > 0 else null
	f.append_array(_check(ash != null and FireRules.hover_text(ash) == "Sweep it up", "burnt remains tooltip"))
	# sweeping the ashes removes them and the scorch mark
	if ash != null:
		var t: Vector2i = ash.tile
		FireEvents.on_game_event("fire_swept", {"object_id": ash.id})
		f.append_array(_check(W.get_object(ash.id) == null and not Fire.scorch.has(Fire.key(t)), "sweeping clears the remains and the soot"))
	# a foot-print object burns as one fire: the 2x1 sofa
	var sofa_obj = W.get_object(sofa_l)
	Fire.ignite(sofa_obj, "candle")
	var rec: Dictionary = Fire.active()[Fire.active().size() - 1]
	f.append_array(_check((rec["tiles"] as Array).size() == 2, "a two-tile sofa burns on both tiles"))
	Fire.reset()
	W.reset()
	return f

func _check(cond: bool, msg: String) -> Array:
	return [] if cond else [msg]
