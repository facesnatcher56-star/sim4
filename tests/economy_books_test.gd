extends RefCounted
## Economy.objects_of no longer scans the whole town twice per call (task 17.4): the books are refreshed only when objects were added or removed;
## IncidentSubject.household_objects caches the list for one incident slice.

const HoodKit := preload("res://tests/hood_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	HoodKit.teardown()
	HoodKit.new_game("classic", 5, 5)
	var w = WorldIface.world()
	var hid := 1
	var before: int = Economy.objects_of(hid).size()
	_check(before > 0, "the home has objects")
	_check(Economy._refresh_stamp == Economy._books_stamp() and not Economy._refresh_stamp.is_empty(), "after a call the books stamp is current")
	# a new object is picked up (placed through the world, then through the books' hook or the next refresh)
	var id := -1
	for y in range(2, w.height - 2):
		for x in range(2, w.width - 2):
			id = w.place_object("plant", Vector2i(x, y))
			if id >= 0:
				break
		if id >= 0:
			break
	_check(id >= 0, "a plant was placed")
	var after: int = Economy.objects_of(hid).size()
	_check(after == before + 1, "the new object is in the household's objects (%d -> %d)" % [before, after])
	# an object registered behind the books' back (no hook): the stamp changes with the world, so the next call still finds it
	var id2 := -1
	for y2 in range(2, w.height - 2):
		for x2 in range(2, w.width - 2):
			id2 = w.place_object("plant", Vector2i(x2, y2))
			if id2 >= 0:
				break
		if id2 >= 0:
			break
	Economy.owner.erase(id2)
	_check(Economy.objects_of(hid).size() == after + 1, "an unregistered object is registered by the next call")
	# removal
	w.sell_object_at(w.get_object(id2).tile, hid)
	_check(Economy.objects_of(hid).size() == after, "a removed object leaves the list")
	# the slice cache
	IncidentSubject.clear_cache()
	IncidentSubject.caching = false
	var a: Array = IncidentSubject.household_objects(hid)
	var b: Array = IncidentSubject.household_objects(hid)
	_check(not is_same(a, b), "without a pass nothing is cached")
	IncidentSubject.caching = true
	var c: Array = IncidentSubject.household_objects(hid)
	var d: Array = IncidentSubject.household_objects(hid)
	_check(is_same(c, d) and c.size() == after, "inside a pass the list is built once")
	IncidentSubject.clear_cache()
	_check(not is_same(c, IncidentSubject.household_objects(hid)), "a hit (clear_cache) drops it")
	IncidentSubject.caching = false
	IncidentSubject.clear_cache()
	HoodKit.teardown()
	return fails
