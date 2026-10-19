class_name SuccessionPick
extends RefCounted
## Who "nobody left" autopilot tries, in order (task 15b): adults first (a relative before a townie), then elders (relatives, then townies), then little
## relatives; an elder is never picked while an adult can move in. Returns [{id, pick ("relative" | "townie")}].

static func order(pid: int) -> Array:
	var adults: Array = []
	var elders: Array = []
	var little: Array = []
	var seen: Dictionary = {}
	for c in SuccessionNobody.relatives(pid):
		var id: int = int(c["id"])
		seen[id] = true
		var e := {"id": id, "pick": "relative"}
		match str(c["stage"]):
			"elder": elders.append(e)
			"adult": adults.append(e)
			_: little.append(e)
	var tadults: Array = []
	var telders: Array = []
	for t in SuccessionNobody.townies():
		if seen.has(int(t["id"])):
			continue
		(telders if Story.stage_of(t) == "elder" else tadults).append({"id": int(t["id"]), "pick": "townie"})
	return adults + tadults + elders + telders + little
