extends RefCounted
## An elder whose flu "is getting worse": a household with money calls the doctor on its own part-way through the warning, so the flu
## rarely kills (here never); a household with no money still can lose them. The death text names the flu, not "a long illness".

const K = preload("res://tests/systems_kit.gd")

func _trial(seed_v: int, coins: int) -> bool:
	var w: StubWorld = K.setup(seed_v)
	var elder := K.make_folk(w, "Madrina", [], 1, Vector2i(12, 12), "elder")
	K.make_folk(w, "Kenneth", [], 1, Vector2i(14, 12))
	WorldIface.coins[1] = coins
	Incidents.rng.seed = seed_v
	Incidents.force("catch_flu", {"folk_id": elder.id})
	K.set_time(5, 0, 16)
	Incidents.force("illness_worsens", {"folk_id": elder.id, "warn": true})
	for m in range(0, 8 * 60, 5):
		K.set_time(5 + (16 + m) / 1440, ((16 + m) / 60) % 24, (16 + m) % 60)
		Incidents.on_minute()
	var alive: bool = w.get_folk(elder.id) != null
	K.teardown()
	return alive

func run() -> Array:
	var f: Array = []
	var rich_alive := 0
	var poor_alive := 0
	var n := 40
	for i in n:
		if _trial(100 + i, 600):
			rich_alive += 1
		if _trial(100 + i, 0):
			poor_alive += 1
	print("  elder with flu getting worse, someone at home: %d of %d survive with money, %d of %d without" % [rich_alive, n, poor_alive, n])
	K.expect(f, rich_alive >= n - 2, "with money the household calls the doctor and the elder survives (%d of %d)" % [rich_alive, n])
	K.expect(f, poor_alive < n, "without money the flu can still be fatal (%d of %d)" % [poor_alive, n])
	# the words
	var cd: Dictionary = DeathCauses.def("flu")
	K.expect(f, str(cd.get("text", "")).find("flu") >= 0 and str(cd.get("text", "")).find("long illness") < 0, "the death text names the flu")
	return f
