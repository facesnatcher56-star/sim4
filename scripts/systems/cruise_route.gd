class_name CruiseRoute
extends RefCounted
## The itinerary and the timeline of one cruise (data/cruise_ship.json). Day 0 = the day the ship sails from the home quay; odd days
## (1, 3, ...) are port days, even days sea days, day L (= length in nights) is arrival at the home quay at 07:00 and disembarking at 09:00.
## The whole cruise is a list of timed entries {min, kind, day, port?, id?} built once at booking and consumed in order (saved with the trip):
##   board_open | all_aboard | sail | dock | ashore | last_call | auto_board | sea_day | program (id) | home_dock | disembark

static func cfg() -> Dictionary:
	return SysUtil.table("cruise_ship")

static func ship() -> Dictionary:
	return (cfg().get("ship", {}) as Dictionary)

## Kind of day d of a cruise of `length` nights: embark | port | sea | home.
static func day_kind(d: int, length: int) -> String:
	if d == 0:
		return "embark"
	if d >= length:
		return "home"
	return "port" if d % 2 == 1 else "sea"

static func port_for(d: int, ports: Array) -> String:
	return str(ports[((d - 1) / 2) % ports.size()])

static func build(sail_min: int, length: int, rng: RandomNumberGenerator) -> Dictionary:
	var s: Dictionary = ship()
	var order: Array = cfg().get("route_order", ["sunny_cove"])
	var day0: int = (sail_min / 1440) * 1440
	var route: Array = []
	var tl: Array = []
	var first_sea: int = -1
	for d in range(0, length + 1):
		var kind: String = day_kind(d, length)
		var port: String = port_for(d, order) if kind == "port" else ""
		if kind == "sea" and first_sea < 0:
			first_sea = d
		route.append({"day": d, "kind": kind, "port": port, "label": str((cfg().get("ports", {}) as Dictionary).get(port, {}).get("label", ""))})
		var base: int = day0 + d * 1440
		match kind:
			"embark":
				tl.append(_e(base + _m(s.get("board_open_hour", 13.0)), "board_open", d))
				tl.append(_e(base + _m(s.get("all_aboard_hour", 16.5)), "all_aboard", d))
				tl.append(_e(sail_min, "sail", d))
			"port":
				tl.append(_e(base + _m(s.get("dock_hour", 8.0)), "dock", d, port))
				tl.append(_e(base + _m(s.get("ashore_hour", 9.0)), "ashore", d, port))
				tl.append(_e(base + _m(s.get("last_call_hour", 15.5)), "last_call", d, port))
				tl.append(_e(base + _m(s.get("auto_board_hour", 16.0)), "auto_board", d, port))
				tl.append(_e(base + _m(s.get("all_aboard_hour", 16.5)), "all_aboard", d, port))
				tl.append(_e(base + _m(s.get("sail_hour", 17.0)), "sail", d, port))
			"sea":
				tl.append(_e(base + 6 * 60, "sea_day", d))
			"home":
				tl.append(_e(base + _m(s.get("home_arrive_hour", 7.0)), "home_dock", d))
				tl.append(_e(base + _m(s.get("disembark_hour", 9.0)), "disembark", d))
	# the programme: every item on the days its token names
	for item in cfg().get("program", []):
		var tok: String = str(item.get("day", "any"))
		for d2 in range(0, length):
			var dk: String = day_kind(d2, length)
			var ok: bool = false
			match tok:
				"embark": ok = d2 == 0
				"port": ok = dk == "port"
				"sea": ok = dk == "sea"
				"first_sea": ok = dk == "sea" and d2 == first_sea
				"last_night": ok = d2 == length - 1
				_: ok = true
			if ok:
				var theme: String = ""
				var themes: Array = cfg().get("theme_nights", ["Party"])
				if str(item["id"]) == "theme_night":
					theme = str(themes[rng.randi_range(0, themes.size() - 1)])
				var pe: Dictionary = _e(day0 + d2 * 1440 + _m(item.get("hour", 12.0)), "program", d2)
				pe["id"] = str(item["id"])
				pe["theme"] = theme
				tl.append(pe)
	tl.sort_custom(func(a, b): return int(a["min"]) < int(b["min"]) or (int(a["min"]) == int(b["min"]) and str(a["kind"]) < str(b["kind"])))
	return {"route": route, "timeline": tl}

static func _m(hour: Variant) -> int:
	return int(round(float(hour) * 60.0))

static func _e(minute: int, kind: String, day: int, port: String = "") -> Dictionary:
	var e: Dictionary = {"min": minute, "kind": kind, "day": day}
	if port != "":
		e["port"] = port
	return e

static func ports_of(route: Array) -> Array:
	var out: Array = []
	for r in route:
		if str(r["kind"]) == "port":
			out.append({"day": int(r["day"]), "port": str(r["port"]), "label": str(r["label"])})
	return out

static func first_min(timeline: Array, kind: String) -> int:
	for e in timeline:
		if str(e["kind"]) == kind:
			return int(e["min"])
	return -1
