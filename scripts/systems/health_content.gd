class_name HealthContent
extends RefCounted
## Runtime patch for the health layer (idempotent): interactions tagged with one of config.health.injury.blocked_tags get tests so nobody
## who is injured or has the flu starts a workout. The buffs / interactions themselves come from the `content` of
## data/incidents/02_needs_health.json (installed by IncidentContent).

const MARK := "_health_patch"

static func install() -> void:
	var inter: Dictionary = SimEnv.data().interactions()
	if inter.is_empty():
		return
	var tags: Array = Health.cfg("injury").get("blocked_tags", [])
	for iid in inter:
		var d: Dictionary = inter[iid]
		if bool(d.get(MARK, false)):
			continue
		d[MARK] = true
		for t in d.get("tags", []):
			if tags.has(str(t)):
				var tests: Array = d.get("tests", [])
				tests.append({"lacks_buff": "injured"})
				tests.append({"lacks_buff": "flu"})
				d["tests"] = tests
				break
