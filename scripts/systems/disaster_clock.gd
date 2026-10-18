class_name DisasterClock
extends RefCounted
## Clock hooks of the disaster layer (called from SystemsManager): running events (tornado impact after the siren, outage /
## blizzard / flood / wildfire upkeep and their end), forecast watches, mould, far-lot repairs, neighbours and shared grief.

static func on_minute() -> void:
	DisasterInsurance.ensure()
	if DisasterState.active.is_empty():
		return
	var now: int = SysUtil.now()
	for rec in DisasterState.active.duplicate():
		if str(rec["phase"]) == "siren" and now >= int(rec["due"]):
			DisasterBig.tornado_impact(rec)
		if now >= int(rec["end"]) and str(rec["phase"]) != "siren":
			_finish(rec)

static func on_hour(_hour: int = 0) -> void:
	DisasterContent.ensure()
	DisasterForecast.on_hour()
	var now: int = SysUtil.now()
	for rec in DisasterState.active.duplicate():
		if int(rec["end"]) <= now:
			continue
		match str(rec["kind"]):
			"outage":
				DisasterEvents.tick_outage(rec)
			"blizzard":
				DisasterEvents.tick_blizzard(rec)
			"wildfire":
				DisasterEvents.tick_wildfire(rec)

static func on_day(day: int) -> void:
	DisasterForecast.on_day(day)
	DisasterAftermath.on_day(day)
	DisasterFar.on_day(day)
	_prune_lots()

static func on_game_event(ev: String, payload: Dictionary) -> void:
	DisasterAftermath.on_game_event(ev, payload)

static func _finish(rec: Dictionary) -> void:
	DisasterState.active.erase(rec)
	var kind: String = str(rec["kind"])
	var homes: bool = not (rec["hids"] as Array).is_empty()
	match kind:
		"outage":
			for hid in rec["hids"]:
				DisasterEvents.power_up(int(hid), rec)
			if homes:
				SysUtil.notify("The power is back on.", "good")
		"flood":
			DisasterBig.flood_end(rec)
		"blizzard":
			if homes:
				SysUtil.notify("The blizzard has passed. The roads are open again.", "good")
		"wildfire":
			if homes:
				SysUtil.notify("The wildfire is out and the smoke is clearing.", "good")
	SysUtil.game_event("disaster", {"kind": kind, "phase": "end", "folk_id": -1})

## Records of repaired, clean lots do not need to live in the save forever.
static func _prune_lots() -> void:
	for key in DisasterState.lots.keys():
		var r: Dictionary = DisasterState.lots[key]
		if int(r["cost"]) <= 0 and float(r["mould"]) <= 0.0 and int(r["debris"]) <= 0 and (r["events"] as Array).is_empty():
			DisasterState.lots.erase(key)
		elif (r["events"] as Array).size() > 0 and str(key).begins_with("town:") and int(r["cost"]) <= 0 and int(r["repair_day"]) < 0:
			(r["events"] as Array).clear()
