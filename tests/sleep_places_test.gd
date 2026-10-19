extends RefCounted
## Task 19h: nobody is left without a place to sleep. Three adults in a one-bed studio all sleep at 03:00 (the extras on a sofa or the floor,
## with the "slept badly" moodlet), and every move-in path (friend, partner, story arrival, adoption, returning heir) finds or buys a bed.

const K = preload("res://tests/systems_kit.gd")
const Hood = preload("res://tests/hood_kit.gd")

func run() -> Array:
	var f: Array = []
	_night(f)
	_paths(f)
	_no_money(f)
	return f

func _studio() -> Array:
	var folk: Array = Hood.new_game("small", 777, 1)
	Players.set_player(Players.LOCAL, 1, "Test")
	return folk

func _townie(stage: String = "adult") -> Dictionary:
	return Story.add_townie(float(Aging.stage_def(stage).get("from_day", 0)) + 2.0, "", ["neat"], "", 1)

func _beds_ok(f: Array, what: String) -> void:
	var cap: int = SleepPlaces.capacity(1)
	var n: int = SleepPlaces.sleepers(1)
	K.expect(f, cap >= n, "%s: %d lying places for %d residents" % [what, cap, n])

func _night(f: Array) -> void:
	var folk: Array = _studio()
	K.expect(f, SleepPlaces.capacity(1) < folk.size(), "the studio has fewer beds than people (%d for %d)" % [SleepPlaces.capacity(1), folk.size()])
	for p in folk:
		(p.needs["energy"] as Stat).set_value(-60.0)
	Hood.set_time(3, 21)
	Hood.run(6 * 60)                                   # until 03:00
	var asleep: int = 0
	var rough: int = 0
	var idle: Array = []
	for p in folk:
		var cur = p.current
		if cur == null:
			idle.append(str(p.name))
		elif str(cur.def_id) in ["sleep_bed", "sleep_sofa", "sleep_floor"]:
			asleep += 1
			if str(cur.def_id) != "sleep_bed":
				rough += 1
		elif str(cur.def_id) == "go_here" or str(cur.def_id).begins_with("walk"):
			pass
	K.expect(f, idle.is_empty(), "at 03:00 nobody is awake and idle (%s)" % ", ".join(idle))
	K.expect(f, asleep == folk.size(), "at 03:00 all %d sleep (%d)" % [folk.size(), asleep])
	K.expect(f, rough >= 1 or SleepPlaces.capacity(1) >= folk.size(), "somebody sleeps on a sofa or the floor when the beds are full")
	Hood.run(8 * 60)
	var bad: int = 0
	for p in folk:
		if p.has_buff("slept_badly"):
			bad += 1
	K.expect(f, rough == 0 or bad >= 1, "sleeping rough gives the slept badly moodlet (%d)" % bad)
	Hood.teardown()

func _paths(f: Array) -> void:
	_studio()
	WorldIface.add_coins(1, 3000)
	# friend moves in (needs two extra places in this studio)
	var t1: Dictionary = _townie()
	K.expect(f, FamilyHousehold.invite_to_household(int(t1["id"]), 1), "a friend moves in")
	_beds_ok(f, "friend")
	K.expect(f, Hood.has_note("needs a bed"), "the player is told a sofa bed was added")
	K.expect(f, Hood.has_note("coins"), "the toast names the price")
	# partner (a townie marries a resident)
	var a: int = int(SysUtil.residents()[0].id)
	var t2: Dictionary = _townie()
	Family.spouses.erase(a)
	K.expect(f, FamilyMarriage.marry(a, int(t2["id"]), "", true), "a partner marries in")
	_beds_ok(f, "partner")
	# adoption
	var kids: Array = FamilyHousehold.spawn_orphans(1)
	var res: Dictionary = FamilyHousehold.adopt(int(kids[0]["id"]), a)
	K.expect(f, bool(res.get("ok", false)), "an orphan is adopted (%s)" % str(res.get("reason", "")))
	_beds_ok(f, "adoption")
	# story arrival (19f household arrival goes through the same door)
	var t3: Dictionary = _townie()
	K.expect(f, FamilyHousehold.invite_to_household(int(t3["id"]), 1), "a story arrival moves in")
	_beds_ok(f, "arrival")
	# returning heir
	var t4: Dictionary = _townie()
	var cand := {"id": int(t4["id"]), "kind": "relative", "in_household": false}
	K.expect(f, SuccessionTake.take(Players.LOCAL, 1, cand, "Someone"), "a returning heir takes over")
	_beds_ok(f, "heir")
	Hood.teardown()

func _no_money(f: Array) -> void:
	var folk: Array = _studio()
	WorldIface.coins[1] = 10
	var n: int = SleepPlaces.sleepers(1)
	var t: Dictionary = _townie()
	K.expect(f, not FamilyHousehold.invite_to_household(int(t["id"]), 1), "with no money and no bed the move-in does not happen")
	K.expect(f, SleepPlaces.sleepers(1) == n and bool(Story.townies[int(t["id"])]["alive"]), "the newcomer stays where they were")
	Hood.teardown()
