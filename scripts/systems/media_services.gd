class_name MediaServices
extends RefCounted
## Local radio, TV and the newspaper (task 14), from the town's own news (TownNews):
##   radio     the station's programme by the hour (data config.media.radio.by_hour) plus the top headline; music slots are good for the mood
##   tv_news   a bulletin of the top lines of the last two days, but only while a news programme is on (the TV schedule: config.media.tv.by_hour)
##   paper     the Fernwood Courier from the newsstand: the latest lines, whenever the stand is open
## The radio and the TV are places at HOME (lot "@home"): nothing to walk to, but you have to be in your own house.

static func cfg() -> Dictionary:
	return LifeDefs.cfg("media")

## Programme on air now: "The Morning Show". kind = radio | tv.
static func now(kind: String, hour: float = -1.0) -> String:
	if hour < 0.0:
		hour = SysUtil.hour_f()
	var cur := ""
	for row in (cfg().get(kind, {}) as Dictionary).get("by_hour", []):
		if hour >= float(row[0]):
			cur = str(row[1])
	return cur

## Next time (hour) a programme containing `word` starts after `hour` ("News" -> 18.0).
static func next_start(kind: String, word: String, hour: float = -1.0) -> float:
	if hour < 0.0:
		hour = SysUtil.hour_f()
	var rows: Array = (cfg().get(kind, {}) as Dictionary).get("by_hour", [])
	var best := -1.0
	for row in rows:
		if str(row[1]).find(word) >= 0 and float(row[0]) > hour:
			return float(row[0])
		if str(row[1]).find(word) >= 0 and best < 0.0:
			best = float(row[0])
	return best

static func lines(items: Array) -> String:
	return "  ".join(items.map(func(it): return "%s" % str(it["text"])))

static func check(handler: String, _f, _pid: String, _sid: String, _svc: Dictionary) -> String:
	match handler:
		"tv_news":
			if now("tv").find("News") < 0:
				var nx: float = next_start("tv", "News")
				return "No news on right now. The next bulletin is at %02d:00." % (int(nx) if nx >= 0.0 else 18)
			if TownNews.bulletin().is_empty():
				return "A quiet day: nothing in the news."
		"paper":
			if TownNews.items.is_empty():
				return "The Courier is just ads this morning."
	return ""

static func finish(handler: String, f, _pid: String, _sid: String, _svc: Dictionary) -> Dictionary:
	match handler:
		"radio":
			var prog: String = now("radio")
			var text: String = "%s listened to %s." % [f.name, prog]
			var latest: Array = TownNews.latest(1)
			if not latest.is_empty() and PhoneState.rng.randf() < 0.5:
				text += " In the news: " + str(latest[0]["text"])
			if prog.find("Music") >= 0 or prog.find("Jazz") >= 0:
				f.add_buff("melodic")
			return {"text": text}
		"tv_news":
			var b: Array = TownNews.bulletin()
			return {"text": "%s on TV: %s" % [now("tv"), lines(b)]}
		"paper":
			var l: Array = TownNews.latest(3)
			f.add_skill_xp("logic", 1.0)
			return {"text": "The Fernwood Courier: " + lines(l)}
	return {}
