extends RefCounted
## Slow tier: the town does not die out. Story.on_day for 168 days (three seeds): the townie count at the end is at least the start, with births and arrivals.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	for s in [101, 202, 303]:
		var w := K.setup(s)
		K.make_folk(w, "Ann")
		Story.generate_townies()
		var start: int = Story.alive_townies().size()
		var peak: int = start
		for d in range(2, 170):
			K.set_time(d, 0)
			Story.on_day(d)
			peak = maxi(peak, Story.alive_townies().size())
		var born: int = Story.news.filter(func(n): return str(n["text"]).find("had a baby") >= 0).size()
		var end: int = Story.alive_townies().size()
		print("  townies seed %d: start %d, end %d, peak %d, babies in the last 60 news lines %d" % [s, start, end, peak, born])
		K.expect(f, end >= start, "seed %d: townie count after 168 days %d >= start %d" % [s, end, start])
		K.teardown()
	return f
