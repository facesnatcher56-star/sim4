class_name PlaceNews
extends RefCounted
## Each place has its own small news items (task 14): `news: ["{place} has {special_main} as today's special.", ...]` in the place data. Once in a while
## (config.food.news_chance_per_day per place per day, about once a week) one line goes to the town chronicle (public, severity 1, no toast).
## Placeholders: {place}, {staff} (the first member of staff), {special_main} (the restaurant's main-course special today).
## Tier: TOWN, daily, one dice per place that has news and is open for business that day. Uses PlaceStaff.rng (saved with the staff).

static func on_day(day: int) -> void:
	var p: float = float(LifeDefs.cfg("food").get("news_chance_per_day", 0.14))
	for pid in Places.all():
		var lines: Array = Places.def(pid).get("news", [])
		if lines.is_empty():
			continue
		var open_today := false
		for h in [10, 14, 19, 23]:
			if Places.open_at(pid, (day - 1) * 1440 + h * 60):
				open_today = true
		if not open_today or PlaceStaff.rng.randf() >= float(Places.def(pid).get("news_chance", p)):
			continue
		var line: String = str(lines[PlaceStaff.rng.randi_range(0, lines.size() - 1)])
		var special: String = ""
		var sp: Dictionary = FoodMenu.specials(pid, day)
		if sp.has("main"):
			special = str(Places.services(pid)[sp["main"]].get("label", ""))
		if line.find("{special_main}") >= 0 and special == "":
			continue
		var staff: String = PlaceStaff.who(pid)
		if line.find("{staff}") >= 0 and staff == "":
			continue
		line = line.replace("{place}", Places.label(pid)).replace("{staff}", staff).replace("{special_main}", special)
		for slot in Places.def(pid).get("programme", {}).get("slots", []):
			line = line.replace("{title_%s}" % slot, Programme.title(pid, str(slot), day))
		LifeNote.news(pid, line)
