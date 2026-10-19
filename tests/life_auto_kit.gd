extends RefCounted
## Shared world for the 14b tests (no run(), so the runner skips it): three households nobody plays, on the stub world with the life areas on.
##   H1  Ann (foodie, social) + Bo (cook, active) + Cy (child, school) + Di (teen, bookworm) + the dog Rex
##   H2  Eve (night owl) + Fay (elder) + Gil (toddler) + the cat Mittens
##   H3  Hal (bookworm, workaholic, wants a degree) + Ida (romantic)
## No Players table, no player input: everything below happens by itself.

const K = preload("res://tests/systems_kit.gd")

static func build(seed_value: int = 1414, with_pets: bool = true) -> Dictionary:
	var w := K.setup(seed_value)
	Autonomy.full_debug = false          # the game's setting: a row only for the best candidates (a debug row for every candidate costs most of the minute)
	var d := {}
	var objs: Dictionary = K.Kit.furnish(w, Vector2i(10, 10))
	d["objs"] = objs
	var who := {}
	who["ann"] = K.make_folk(w, "Ann Rowe", ["foodie", "social"], 1, Vector2i(12, 14))
	who["bo"] = K.make_folk(w, "Bo Rowe", ["active", "outdoorsy"], 1, Vector2i(14, 14))
	who["cy"] = K.make_folk(w, "Cy Rowe", [], 1, Vector2i(16, 14), "child")
	who["di"] = K.make_folk(w, "Di Rowe", ["bookworm"], 1, Vector2i(18, 14), "teen")
	who["eve"] = K.make_folk(w, "Eve Dunn", ["night_owl", "social"], 2, Vector2i(12, 16))
	who["fay"] = K.make_folk(w, "Fay Dunn", [], 2, Vector2i(14, 16), "elder")
	who["gil"] = K.make_folk(w, "Gil Dunn", [], 2, Vector2i(16, 16), "toddler")
	who["hal"] = K.make_folk(w, "Hal Park", ["bookworm", "workaholic"], 3, Vector2i(12, 18))
	who["ida"] = K.make_folk(w, "Ida Park", ["romantic"], 3, Vector2i(14, 18))
	Aging.set_age_days(who["cy"], 30.0)
	Aging.set_age_days(who["di"], 66.0)
	Aging.set_age_days(who["gil"], 12.0)
	Aging.set_age_days(who["fay"], 100.0)
	Aging.set_age_days(who["ann"], 90.0)
	Aging.set_age_days(who["bo"], 90.0)
	Aging.set_age_days(who["eve"], 90.0)
	Aging.set_age_days(who["hal"], 90.0)
	Aging.set_age_days(who["ida"], 90.0)
	for hid in [1, 2, 3]:
		WorldIface.coins[hid] = 3000
	Story.generate_townies(14)
	SysContent.install_all()
	K.set_time(1, 6)
	Careers.on_day(1)
	LifeTick.new_game()
	LifeDefs.ensure()
	Careers.hire(who["bo"], "cook", 1)
	if with_pets:
		d["rex"] = PetState.add_pet(1, "dog", "Rex", 30.0)
		d["mittens"] = PetState.add_pet(2, "cat", "Mittens", 30.0)
	d["who"] = who
	d["world"] = w
	d["dir"] = K.director()
	return d

## Run n game days with the director; `each_day` (Callable(day)) at the start of every day, `each_hour` (Callable()) after every hour.
static func run_days(d: Dictionary, days: int, each_day: Callable = Callable(), each_hour: Callable = Callable()) -> void:
	for i in days:
		if each_day.is_valid():
			each_day.call(SysUtil.day())
		for h in 24:
			K.run(d["dir"], 60)
			if each_hour.is_valid():
				each_hour.call()

## The place KINDS ("food", "culture" ...) a household has used.
static func kinds_used(hid: int) -> Array:
	var out: Array = []
	for pid in PlaceAuto.kinds_used(hid):
		var k: String = Places.kind_of(str(pid))
		if k != "" and not out.has(k):
			out.append(k)
	out.sort()
	return out
