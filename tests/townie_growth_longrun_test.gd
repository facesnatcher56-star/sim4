extends RefCounted
## Slow tier: the town does not die out. Story.on_day for 168 days (three seeds): the townie count at the end is at least the start, with births and arrivals.
## 19i: and the townies keep having babies - 5 to 10 births per 168 days in a town of about a dozen (counted from the chronicle, not the short news list).

const K = preload("res://tests/systems_kit.gd")

var _births := 0

func _on_event(ev: String, p: Dictionary) -> void:
	if ev == "chronicle" and str(p.get("kind", "")) == "birth":
		_births += 1

func run() -> Array:
	var f: Array = []
	var total_births := 0
	for s in [101, 202, 303]:
		var w := K.setup(s)
		K.make_folk(w, "Ann")
		_births = 0
		SimEnv.events().game_event.connect(_on_event)
		Story.generate_townies()
		var start: int = Story.alive_townies().size()
		var peak: int = start
		for d in range(2, 170):
			K.set_time(d, 0)
			Story.on_day(d)
			peak = maxi(peak, Story.alive_townies().size())
		var end: int = Story.alive_townies().size()
		print("  townies seed %d: start %d, end %d, peak %d, townie births %d" % [s, start, end, peak, _births])
		K.expect(f, end >= start, "seed %d: townie count after 168 days %d >= start %d" % [s, end, start])
		K.expect(f, _births >= 3 and _births <= 14, "seed %d: townie births in 168 days %d (about 5 to 10)" % [s, _births])
		total_births += _births
		SimEnv.events().game_event.disconnect(_on_event)
		K.teardown()
	K.expect(f, total_births >= 15 and total_births <= 30, "three seeds together: %d townie births (5 to 10 each)" % total_births)
	return f
