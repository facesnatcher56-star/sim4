extends RefCounted
## Over seven game days of real autonomy, folk do not walk to shut doors: "is closed. Heading home" for autonomous trips is rare.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func run() -> Array:
	fails = []
	Kit.new_game("classic")
	WorldIface.coins[1] = 3000
	Kit.set_time(2, 6)
	for d in 7:
		Kit.run(1440)
		WorldIface.coins[1] = maxi(WorldIface.coins[1], 3000)
	var shut := 0
	var early := 0
	for n in Kit.notes:
		var t: String = str(n[0])
		if t.contains("is closed. Heading home"):
			shut += 1
		if t.contains("left early"):
			early += 1
	print("closed_trips_longrun: closed-heading-home=%d left-early=%d" % [shut, early])
	if shut > 3:
		fails.append("too many closed-door trips in 7 days: %d" % shut)
	if early > 3:
		fails.append("too many cut-short visits in 7 days: %d" % early)
	Kit.teardown()
	return fails
