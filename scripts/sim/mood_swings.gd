class_name MoodSwings
extends RefCounted
## Wider moods: groggy after a short or poor night, an "off day" now and then (more for pessimists / the lonely), work stress after
## a bad shift. Numbers in data/mood_swings.json. Hooks (SystemsManager): on_started / on_finished for interactions, on_game_event.

static var sleep_since: Dictionary = {}      # folk_id -> minute the sleep began

static func reset() -> void:
	sleep_since.clear()

static func cfg() -> Dictionary:
	return SysUtil.table("mood_swings")

static func on_started(folk_id: int, iid: String) -> void:
	if iid == "sleep_bed":
		sleep_since[folk_id] = SysUtil.now()

static func on_finished(folk_id: int, iid: String, _success: bool) -> void:
	if iid != "sleep_bed" or not sleep_since.has(folk_id):
		return
	var f = SysUtil.folk(folk_id)
	var slept_h: float = float(SysUtil.now() - int(sleep_since[folk_id])) / 60.0
	sleep_since.erase(folk_id)
	if f == null or not SysUtil.is_resident(f):
		return
	var c: Dictionary = cfg()
	if slept_h < float(c.get("short_sleep_h", 6.0)) or f.get_stat_value("energy") < float(c.get("groggy_energy_below", 45)):
		f.add_buff("groggy")
	if slept_h >= 3.0 and SysUtil.chance(_off_day_chance(f, c)):
		f.add_buff("off_day")

static func _off_day_chance(f, c: Dictionary) -> float:
	var p: float = float(c.get("off_day_chance", 0.12))
	var tm: Dictionary = c.get("off_day_trait_mult", {})
	for t in tm:
		if f.has_trait(str(t)):
			p *= float(tm[t])
	var bm: Dictionary = c.get("off_day_buff_mult", {})
	for b in bm:
		if f.has_buff(str(b)):
			p *= float(bm[b])
	return p

static func on_game_event(ev: String, payload: Dictionary) -> void:
	if ev != "returned_from_work":
		return
	var f = SysUtil.folk(int(payload.get("folk_id", -1)))
	if f == null:
		return
	var ws: Dictionary = cfg().get("work_stress", {})
	var p: float = float(ws.get("chance_normal", 0.06))
	if bool(payload.get("skipped", false)):
		p = float(ws.get("chance_skipped", 0.9))
	elif float(payload.get("performance", 100.0)) < float(ws.get("performance_below", 42)):
		p = float(ws.get("chance_low", 0.6))
	if SysUtil.chance(p):
		f.add_buff("work_stress")
