class_name PlaceAutoTownies
extends RefCounted
## The townies (task 14b, STATISTICAL tier): they have no body on the map, so using the places is one dice a day with the same kinds and weights, which
## only counts the visit at the place (the counter the place news reads). Teens and grown-ups; nothing else is simulated for them.

static func on_day(_day: int) -> void:
	var p: float = float(PlaceAuto.cfg().get("townie_daily", 0.18))
	var kinds: Array = []
	var ws: Array = []
	for kid in PlaceAutoPlan.kind_ids():
		var d: Dictionary = PlaceAutoPlan.kind_def(str(kid))
		if d.has("gate") or bool(d.get("essential", false)) or d.get("services", []).is_empty():
			continue
		kinds.append(str(kid))
		ws.append(float(d.get("base", 0.0)))
	if kinds.is_empty():
		return
	var ids: Array = []
	for t in Story.alive_townies():
		ids.append(int(t["id"]))
	ids.sort()
	for id in ids:
		var t2: Dictionary = Story.townies.get(id, {})
		var stage: String = Story.stage_of(t2)
		if not stage in ["teen", "adult", "elder"] or PlaceAuto.rng.randf() >= p:
			continue
		var kid2: Variant = PlaceAutoGate._weighted(kinds, ws)
		if kid2 == null:
			continue
		var sid: String = str(PlaceAutoPlan.kind_def(str(kid2))["services"][0])
		var pid: String = PlaceAutoPlan.place_of(sid)
		if pid != "" and Places.place_reason(stage, pid) == "" and Places.stage_reason(stage, Places.services(pid).get(sid, {})) == "":
			PlaceUse.visits[pid] = int(PlaceUse.visits.get(pid, 0)) + 1
