extends RefCounted
## Task 33c (logic rule: an action needs a reason and a thing): the idle fillers that imply an object are only offered where that object is. In a bare home
## (the default start) a folk does not sweep an empty house, fold washing that is not there, do a puzzle without a table or flip through recipes without a kitchen;
## the fillers that need nothing (stretch, look around, hum, check the phone ...) stay. With the object present they are offered again.

const Kit = preload("res://tests/sim_testkit.gd")
## filler id -> object defs of which at least one must be near (data/content_dynamic.json, Cond `has_object`)
const NEEDS := {
	"tidy_up": "sofa", "polish_up": "mirror", "rearrange_shelf": "bookshelf", "fold_the_washing": "washing_machine", "do_a_puzzle": "table",
	"crossword": "desk", "flip_recipes": "stove", "flick_magazine": "coffee_table", "plan_tomorrow": "desk", "write_a_postcard": "table",
	"doodle": "coffee_table", "sip_water": "sink", "gaze_out_window": "window", "people_watch": "window",
}
## need nothing but the folk themselves
const FREE := ["stretch", "look_around", "check_phone", "hum_tune", "sing_softly", "fidget_and_think", "ponder_the_day", "shake_a_leg", "look_through_photos",
	"stretch_on_wall", "pace_and_think", "count_coins", "floor_todo_list", "listen_to_neighbours", "imagine_furniture", "practise_speech_air", "shadow_box", "do_sit_ups"]

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _offered(f, minutes: int) -> Dictionary:
	var seen: Dictionary = {}
	for i in minutes:
		Kit.set_time(1 + i / 6, 8 + i % 6)               # daytime, and a different five-minute slice every time (the fillers are dealt in rotating slices)
		SimEnv.clock().advance_minutes((i % 12) * 5)
		f.cooldowns.clear()
		for c in Autonomy.gather(f, []):      # a `closed` array makes gather apply the target-independent tests (has_object) up front
			seen[str(c["id"])] = true
	return seen


func _world(objs: Array) -> Array:
	var w := Kit.setup(4242)
	DynLife.install()
	SysContent.gate_late_content()
	w.add_object("door", Vector2i(10, 9))
	for i in objs.size():
		w.add_object(str(objs[i]), Vector2i(10 + 2 * i, 12))
	var f := Folk.create("Ada", ["social"])
	f.household_id = 1
	w.add_folk(f, Vector2i(12, 10))
	Kit.set_time(1, 10)
	return [w, f]


func run() -> Array:
	fails = []
	var old_off: bool = DynLife.off
	DynLife.off = false
	var defs: Dictionary = {}
	# bare home: nothing offered that needs a thing, the free ones still are
	var w0 := _world([])
	defs = SimEnv.data().interactions()
	for id in NEEDS:
		_check(defs.has(id) and _has_test(defs[id], "has_object"), "%s has no has_object test" % id)
	for id in FREE:
		_check(defs.has(id) and not _has_test(defs[id], "has_object"), "%s should need no object" % id)
	var seen0 := _offered(w0[1], 120)
	for id in NEEDS:
		_check(not seen0.has(id), "bare home: %s was offered with nothing to act on" % id)
	var free_seen := 0
	for id in FREE:
		free_seen += 1 if seen0.has(id) else 0
	_check(free_seen >= 8, "bare home: only %d of the free fillers were offered (%s)" % [free_seen, str(seen0.keys())])
	Kit.teardown()
	# every object present: they are offered again
	var wp := _world(NEEDS.values())
	var seen1 := _offered(wp[1], 240)
	var back := 0
	for id in NEEDS:
		back += 1 if seen1.has(id) else 0
	_check(back >= 10, "with the objects present only %d of %d fillers came back (%s)" % [back, NEEDS.size(), str(seen1.keys())])
	_check(seen1.has("doodle") or seen1.has("write_a_postcard"), "writing fillers missing next to a table")
	# one object at a time: a sink brings the sip of water and nothing else of the list
	Kit.teardown()
	var ws := _world(["sink"])
	var seen2 := _offered(ws[1], 240)
	_check(not seen2.has("tidy_up") and not seen2.has("do_a_puzzle"), "a sink alone brought back tidying or puzzles")
	Kit.teardown()
	DynLife.off = old_off
	return fails


func _has_test(d: Dictionary, key: String) -> bool:
	for t in d.get("tests", []):
		if t is Dictionary and (t as Dictionary).has(key):
			return true
	return false
