class_name StorytellerCycles
extends RefCounted
## Town cycles: eras the town budget starts now and then (data storyteller.json cycles). One at a time, with a cooldown after each:
## crime wave (more burglaries and robberies, capped by the personality), flu season (colds and flu), boom times and hard times (the MarketEconomy phase from 13),
## heat wave and cold snap (the weather is held for a few days), election scandal (the town's mood about the council drops, CityMood reads mood_bias()).
## Each era announces itself and its end (Story news, the Chronicle) so the town has a feel of its own. Rate multipliers apply only to the listed incidents.

static var current: Dictionary = {}      # {id, started, until}
static var last_end: int = -99
static var mood: Dictionary = {"value": 0.0}

static func reset() -> void:
	current = {}
	last_end = -99
	mood = {"value": 0.0}

static func types() -> Dictionary:
	return Storyteller.cfg().get("cycles", {}).get("types", {})

static func active_id() -> String:
	return str(current.get("id", ""))

static func can_start(id: String) -> bool:
	var t: Dictionary = types().get(id, {})
	if t.is_empty() or not current.is_empty() or not Storyteller.cat_on(str(t.get("cat", ""))):
		return false
	if SysUtil.day() - last_end < int(Storyteller.cfg().get("cycles", {}).get("cooldown_days", 6)):
		return false
	if t.has("economy") and (not MarketEconomy.enabled or MarketEconomy.phase != "normal"):
		return false
	return true

static func start(id: String, ctx: Dictionary) -> Dictionary:
	var t: Dictionary = types().get(id, {})
	if t.is_empty():
		return {"text": "", "ok": false}
	var d: Array = t.get("days", [6, 12])
	var days: int = Storyteller.rng.randi_range(int(d[0]), int(d[1]))
	current = {"id": id, "started": SysUtil.day(), "until": SysUtil.day() + days}
	Storyteller.clear_mult_cache()
	if t.has("economy"):
		MarketEconomy.phase = str(t["economy"])
		MarketEconomy.phase_left = days
		SysUtil.game_event("economy_phase", {"phase": MarketEconomy.phase, "day": SysUtil.day()})
	if t.has("mood"):
		mood["value"] = float(mood.get("value", 0.0)) + float(t["mood"])
	for zone in CityState.zone_ids():
		for tag in (t.get("heat", {}) as Dictionary):
			StorytellerChaos.add_heat(str(zone), str(tag), float(t["heat"][tag]))
	_apply_weather()
	_announce(str(t.get("start", "")), id)
	Storyteller.bump("cycles")
	return {"text": str(t.get("start", "")), "ok": true, "silent": true}

static func _announce(text: String, id: String) -> void:
	if text == "":
		return
	Story._log(text)
	ChronicleHook.note("cycle_" + id, text, [], "town:0", 2, true)
	StorytellerLog.add("cycle", text, str(Storyteller.cfg().get("text", {}).get("why_cycle", "")), Storyteller.KEY_TOWN, [], "town", "cycle_" + id)
	for hid in CityState.full_households():
		StorytellerLog.toast(int(hid), text)

static func _apply_weather() -> void:
	var t: Dictionary = types().get(active_id(), {})
	if t.has("weather"):
		Weather.force(str(t["weather"]))

static func on_day(day: int) -> void:
	mood["value"] = float(mood.get("value", 0.0)) * 0.9
	if absf(float(mood["value"])) < 0.01:
		mood["value"] = 0.0
	if current.is_empty():
		return
	if day >= int(current["until"]):
		var t: Dictionary = types().get(active_id(), {})
		if t.has("weather") and Weather.forced == str(t["weather"]):
			Weather.unforce()
		_announce(str(t.get("end", "")), active_id())
		current = {}
		last_end = day
		Storyteller.clear_mult_cache()
	else:
		_apply_weather()

## Rate multiplier of incident `id` in the running era (1.0 when none); "_hard" is reserved for the capped hard-rule multiplier (eras never raise it).
static func mult(id: String) -> float:
	if current.is_empty() or id == "_hard":
		return 1.0
	return float((types().get(active_id(), {}).get("mult", {}) as Dictionary).get(id, 1.0))

static func add_mood(x: float) -> void:
	mood["value"] = clampf(float(mood.get("value", 0.0)) + x, -0.6, 0.4)

## Read by CityMood.update: how the town feels about the council because of recent storyteller events.
static func mood_bias() -> float:
	return float(mood.get("value", 0.0)) if Storyteller.enabled else 0.0

static func to_dict() -> Dictionary:
	return {"current": current.duplicate(), "last_end": last_end, "mood": mood.duplicate()}

static func from_dict(d: Dictionary) -> void:
	current = (d.get("current", {}) as Dictionary).duplicate()
	SysUtil.ints_in(current, ["started", "until"])
	last_end = int(d.get("last_end", -99))
	mood = (d.get("mood", {"value": 0.0}) as Dictionary).duplicate()
	mood["value"] = float(mood.get("value", 0.0))
