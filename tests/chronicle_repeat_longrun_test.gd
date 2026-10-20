extends RefCounted
## 56 game days (2 years): no Chronicle line text appears more than once a day, the parade at most once a game year.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func run() -> Array:
	fails = []
	Kit.new_game("classic")
	WorldIface.coins[1] = 3000
	Kit.set_time(1, 6)
	for d in 56:
		Kit.run(1440)
		WorldIface.coins[1] = maxi(WorldIface.coins[1], 3000)
		print("day %d done" % (d + 1))          # keeps the hung-run guard fed
	var per_day: Dictionary = {}
	var parade: Dictionary = {}
	var lines := 0
	for e in Kit.events:
		if e[0] != "chronicle":
			continue
		lines += 1
		var p: Dictionary = e[1]
		var k: String = "%d|%s" % [int(p["day"]), str(p["text"])]
		per_day[k] = int(per_day.get(k, 0)) + 1
		if str(p["kind"]) == "place_news" and str(p["text"]).to_lower().contains("parade"):          # the event itself (a later post about it is not a second parade)
			var yr: int = (int(p["day"]) - 1) / 28
			parade[yr] = int(parade.get(yr, 0)) + 1
	for k in per_day:
		if int(per_day[k]) > 1:
			fails.append("chronicle line told %d times in a day: %s" % [int(per_day[k]), k])
	for yr in parade:
		if int(parade[yr]) > 1:
			fails.append("parade told %d times in game year %d" % [int(parade[yr]), int(yr)])
	print("chronicle_repeat_longrun: %d lines, parade by year %s" % [lines, str(parade)])
	Kit.teardown()
	return fails
