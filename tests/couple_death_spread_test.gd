extends RefCounted
## Old-age deaths: an elder couple of the same age does not usually die on the same night; when it does it is the explicit "broken heart".

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	var same_night := 0
	var heart := 0
	var both_died := 0
	var n := 60
	var dc: Dictionary = Aging.cfg().get("death", {})
	for i in n:
		var w: StubWorld = K.setup(500 + i)
		var a := K.make_folk(w, "Ann", [], 1, Vector2i(12, 12), "elder")
		var b := K.make_folk(w, "Bo", [], 1, Vector2i(14, 12), "elder")
		Family.spouses[a.id] = b.id
		Family.spouses[b.id] = a.id
		var ids: Array = [a.id, b.id]
		for id in ids:
			(Aging.records[id] as Dictionary)["age_days"] = float(dc.get("start_day", 202)) + 20.0
		var died_day: Dictionary = {}
		var causes: Dictionary = {}
		var gone_cb := func(n2, p): if n2 == "died": died_day[int(p.get("folk_id", -1))] = SysUtil.day(); causes[int(p.get("folk_id", -1))] = str(p.get("cause", ""))
		SimEnv.events().game_event.connect(gone_cb)
		for d in 60:
			K.set_time(2 + d, 0, 0)
			for id in ids:
				if Aging.records.has(id):
					(Aging.records[id] as Dictionary)["age_days"] = float(dc.get("start_day", 202)) + 20.0 + d
			Aging._check_deaths()
			if died_day.size() == 2:
				break
		SimEnv.events().game_event.disconnect(gone_cb)
		if died_day.size() == 2:
			both_died += 1
			if died_day[a.id] == died_day[b.id]:
				same_night += 1
				if str(causes[a.id]) == "broken_heart" or str(causes[b.id]) == "broken_heart":
					heart += 1
		K.teardown()
	print("  %d couples: %d both died, %d on the same night (%d of them of a broken heart)" % [n, both_died, same_night, heart])
	K.expect(f, both_died >= n / 2, "most couples were both gone within 60 days (%d)" % both_died)
	K.expect(f, same_night <= both_died / 10, "same-night couple deaths are rare (%d of %d)" % [same_night, both_died])
	K.expect(f, same_night == heart, "every same-night death is the explicit broken-heart story (%d vs %d)" % [same_night, heart])
	var cd: Dictionary = DeathCauses.def("broken_heart")
	K.expect(f, str(cd.get("text", "")).find("broken heart") >= 0, "the broken-heart text exists")
	return f
