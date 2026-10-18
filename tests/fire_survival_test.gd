extends RefCounted
## Survival depends on causes: a shout wakes sleepers rooms away (walls muffle), thick smoke wakes sooner than haze (heavy sleepers / exhaustion
## lower it, drunk or passed-out cannot wake), frail people succumb at lower smoke doses, smoke is per ROOM (a closed door slows it a lot,
## an open one a little, windows vent, big rooms dilute).

const K = preload("res://tests/systems_kit.gd")
const FK = preload("res://tests/fire_kit.gd")

func run() -> Array:
	var f: Array = []
	_wake_chance(f)
	_shout(f)
	_dose(f)
	_rooms(f)
	return f

func _root() -> Window:
	return Engine.get_main_loop().root

func _wake_chance(f: Array) -> void:
	var w := FK.setup()
	var s := K.make_folk(w, "Sleepy", [], 1, Vector2i(30, 30))
	var thin: float = FireFolk._wake_chance(s, 0.15, 0, 99)
	var thick: float = FireFolk._wake_chance(s, 0.8, 0, 99)
	var flames: float = FireFolk._wake_chance(s, 0.0, 2, 1)
	K.expect(f, thick > 8.0 * thin and thin < 0.03, "thick smoke wakes sooner than haze (%.3f vs %.3f per minute)" % [thick, thin])
	K.expect(f, flames > thin, "flames in the room wake too (%.3f)" % flames)
	s.add_buff("exhausted")
	K.expect(f, FireFolk._wake_chance(s, 0.8, 0, 99) < thick, "exhaustion lowers it")
	s.remove_buff("exhausted")
	var early := K.make_folk(w, "Bird", ["early_bird"], 1, Vector2i(30, 31))
	var lazy := K.make_folk(w, "Lazy", ["lazy"], 1, Vector2i(30, 32))
	K.expect(f, FireFolk._wake_chance(early, 0.8, 0, 99) > thick and FireFolk._wake_chance(lazy, 0.8, 0, 99) < thick, "early birds wake easier, lazy sleepers heavier")
	if not SimEnv.data().buff_def("drunk").is_empty():
		s.add_buff("drunk")
		K.expect(f, FireFolk._wake_chance(s, 1.0, 3, 0) == 0.0, "drunk cannot wake")
	var baby := K.make_folk(w, "Bean", [], 1, Vector2i(31, 30), "baby")
	K.expect(f, FireFolk._wake_chance(baby, 1.0, 3, 0) == 0.0, "a baby stays helpless")
	FK.teardown()

func _shout(f: Array) -> void:
	var woke: int = 0
	var woke_far: int = 0
	var n: int = 40
	var hops: int = -1
	for i in n:
		var w := FK.setup()
		Fire.rng.seed = 400 + i
		FireRules.cfg()["wake_scale"] = 0.0
		var adult := K.make_folk(w, "Dad", [], 1, Vector2i(30, 24))
		var o := FK.house(w)
		var near_s := K.make_folk(w, "Near", [], 1, Vector2i(28, 20))
		var far_s := K.make_folk(w, "Far", [], 1, Vector2i(30, 8))        # 16 tiles from the shouter: two "rooms" in the stub
		var far_bed = w.add_object("bed", Vector2i(30, 8))
		var near_bed = w.add_object("bed", Vector2i(28, 20))
		hops = FireSmoke.hops(Vector2i(30, 24), Vector2i(30, 8))
		for pair in [[near_s, near_bed], [far_s, far_bed]]:
			pair[0].needs["energy"].set_value(15.0)
			pair[0].enqueue(Interaction.create("sleep_bed", pair[0], pair[1].id, true))
		FK.dir.tick_minute(1)
		FK.run(2)
		if not FireRules.asleep(far_s) or not FireRules.asleep(near_s):
			f.append("test setup: sleepers are not asleep")
			FK.teardown()
			return
		Fire.ignite(o["stove"], "cooking")
		FireFolk._shout(Fire.blazes["home"], adult, SysUtil.now())
		if not FireRules.asleep(far_s):
			woke_far += 1
		if not FireRules.asleep(near_s):
			woke += 1
		FK.teardown()
	K.expect(f, hops == 2, "the far sleeper is two rooms away (%d)" % hops)
	K.expect(f, woke_far >= int(0.25 * n) and woke_far <= int(0.8 * n), "a shout wakes a sleeper two rooms away about half the time (%d/%d)" % [woke_far, n])
	K.expect(f, woke >= woke_far, "closer sleepers wake at least as often (%d/%d)" % [woke, n])

func _dose(f: Array) -> void:
	var w := FK.setup()
	var o := FK.house(w)
	var elder := K.make_folk(w, "Edda", [], 1, Vector2i(13, 14), "elder")
	var fit := K.make_folk(w, "Fitz", [], 1, Vector2i(14, 14))
	fit.skills["fitness"]["level"] = 6
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(15, 14), "child")
	Fire.ignite(o["stove"], "cooking", {"stage": 2})
	var b: Dictionary = Fire.blazes["home"]
	var died: Dictionary = {}
	for m in 60:
		for folk in [elder, fit, kid]:
			if died.has(folk.id) or w.get_folk(folk.id) == null:
				continue
			var r: Dictionary = FireFolk.rec(b, folk)
			FireFolk._exposure(b, folk, r, 2, true, false)
			if w.get_folk(folk.id) == null:
				died[folk.id] = m
	K.expect(f, died.has(elder.id) and died.has(fit.id) and died.has(kid.id), "all three eventually succumb to a roaring fire in their room (%s)" % str(died))
	K.expect(f, int(died.get(elder.id, 99)) < int(died.get(fit.id, 0)), "an elder dies at a lower dose than a fit adult (minute %s vs %s)" % [str(died.get(elder.id)), str(died.get(fit.id))])
	K.expect(f, int(died.get(kid.id, 99)) < int(died.get(fit.id, 0)), "a child too (minute %s)" % str(died.get(kid.id)))
	var hurt := K.make_folk(w, "Sam", [], 1, Vector2i(16, 14))
	hurt.add_buff("injured")
	var plain := K.make_folk(w, "Hal", [], 1, Vector2i(17, 14))
	K.expect(f, FireRules.dose_mult(hurt) < FireRules.dose_mult(plain), "injured people have lower thresholds")
	FK.teardown()

## Real World, three rooms in a row joined by doors: smoke spreads room to room, slowly through a closed door.
func _rooms(f: Array) -> void:
	var W = _root().get_node_or_null("World")
	if W == null:
		f.append("World autoload missing")
		return
	var res: Array = []
	for door_open in [false, true]:
		TestFixture.reset()
		WorldIface.stub = null
		W.reset(30, 14)
		IncidentDefs.reset()
		IncidentContent.install()
		Fire.reset()
		FireSmoke.reset()
		W.add_wall(Vector2i(8, 0), Vector2i(8, 14))
		W.add_wall(Vector2i(14, 0), Vector2i(14, 14))
		W.set_edge(Vector3i(8, 3, 1), "door")
		W.set_edge(Vector3i(14, 3, 1), "door")
		var stove: int = W.place_object("stove", Vector2i(4, 3))
		Fire.ignite(stove, "cooking", {"stage": 3})
		var fire: Dictionary = Fire.active()[0]
		fire["burn"] = 9999.0
		FireRules.cfg()["room_ref_tiles"] = 100
		if door_open:
			FireSmoke._open[str(Vector3i(8, 3, 1))] = 1 << 30
		var b: Dictionary = Fire.blazes["home"]
		var minute_b: int = -1
		for m in 30:
			fire["age"] = 12.0
			FireSmoke.step(b, Fire.fires_in("home"))
			if minute_b < 0 and FireSmoke.at(b, Vector2i(10, 5)) >= 0.2:
				minute_b = m
		res.append({"b": FireSmoke.at(b, Vector2i(10, 5)), "c": FireSmoke.at(b, Vector2i(20, 5)), "a": FireSmoke.at(b, Vector2i(4, 5)), "t": minute_b})
		if not door_open:
			K.expect(f, FireSmoke.hops(Vector2i(4, 5), Vector2i(20, 5)) == 2, "two rooms away through two doors = 2 hops")
			K.expect(f, FireSmoke.hops(Vector2i(4, 5), Vector2i(4, 5)) == 0, "same room = 0 hops")
	var closed: Dictionary = res[0]
	var open: Dictionary = res[1]
	K.expect(f, float(closed["a"]) > 0.3, "the room with the fire fills with smoke (%.2f)" % float(closed["a"]))
	K.expect(f, float(open["b"]) > 2.0 * float(closed["b"]) + 0.01, "behind a closed door the next room stays much clearer (%.2f closed vs %.2f open)" % [float(closed["b"]), float(open["b"])])
	K.expect(f, int(closed["t"]) < 0 or int(open["t"]) < int(closed["t"]), "smoke reaches the next room sooner through an open door (minute %d vs %d)" % [int(open["t"]), int(closed["t"])])
	K.expect(f, float(closed["c"]) <= float(closed["b"]) + 0.001, "and the third room is clearer still")
	FireSmoke.reset()
	W.reset()
	Fire.reset()
