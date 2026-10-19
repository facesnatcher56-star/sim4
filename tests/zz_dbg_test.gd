extends RefCounted
const K = preload("res://tests/vacation_kit.gd")
func run() -> Array:
	var folk = K.new_game("small", 9000, true)
	var res = Vacation.book_and_go(1, "cruise", {"length_days": 3, "cabin_class": "ocean", "seed": 5})
	K.run(40)
	for h in 20:
		K.run(60)
		var s := ""
		for f in folk:
			s += "%s %.0f lvl%d %s | " % [f.name, f.get_stat_value("bladder"), f.level, f.current.def_id if f.current != null else "-"]
		print(h, ": ", s)
	K.teardown()
	return []
