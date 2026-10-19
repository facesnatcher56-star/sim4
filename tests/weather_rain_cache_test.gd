extends RefCounted
## Regression for a determinism bug: WeatherWorld's rain index (_rain_by_lot) was keyed by (object count, id sum, world node), and the World node
## is reused between games, so a second game with the same layout watered the PREVIOUS game's plant objects (the new plants stayed dry, autonomy then
## chose differently and "same seed twice" gave two different states). Every plant in the index must be the live object of the current world.
const HoodKit := preload("res://tests/hood_kit.gd")

func _stale_count() -> Array:
	var live := 0
	var stale := 0
	var objs: Dictionary = HoodKit.world().objects
	var groups: Dictionary = WeatherWorld._rain_by_lot()
	for lot in groups:
		for kind in ["plots", "plants"]:
			for o in groups[lot][kind]:
				if objs.get(int(o.id), null) == o:
					live += 1
				else:
					stale += 1
	return [live, stale]

func run() -> Array:
	var fails: Array = []
	for round in 3:
		SimSeed.apply(555)
		HoodKit.new_game("classic", 555, 555)
		var c := _stale_count()
		if int(c[0]) == 0:
			fails.append("round %d: the rain index is empty (the town has plants, the test would prove nothing)" % round)
		if int(c[1]) != 0:
			fails.append("round %d: %d of the rain index entries are objects of an earlier game (live %d)" % [round, int(c[1]), int(c[0])])
		HoodKit.teardown()
	return fails
