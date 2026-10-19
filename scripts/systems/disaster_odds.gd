class_name DisasterOdds
extends RefCounted
## How likely is a town incident on a given day? Derived from the incident's own rate, risk multipliers and conditions for the
## forecast weather/season, so a watch only appears when the danger is real and the words say how real (data/forecast.json).

static func _holds(conds: Array, wx: String, season: String, unknown_ok: bool) -> bool:
	for c in conds:
		if not (c is Dictionary):
			continue
		for key in c:
			var v: Variant = c[key]
			match str(key):
				"season_is":
					if not (v as Array).has(season):
						return false
				"weather_is":
					if not (v as Array).has(wx):
						return false
				"disaster":
					for dk in (v as Dictionary):
						if dk == "rain_days_at_least" and DisasterState.rain_days < int(v[dk]):
							return false
						if dk == "dry_days_at_least" and DisasterState.dry_days < int(v[dk]):
							return false
				_:
					if not unknown_ok:
						return false
	return true

## Chance (0..1) that the incident occurs somewhere in town during a day with this weather.
static func day_chance(incident_id: String, wx: String, season: String) -> float:
	var def: Dictionary = IncidentDefs.get_def(incident_id)
	if def.is_empty() or not _holds(def.get("conditions", []), wx, season, true):
		return 0.0
	var rate: float = float(def.get("base_rate_per_year", 0.0)) * Incidents.surprise_mult()
	for e in def.get("risk_mults", []):
		if _holds(e.get("when", []), wx, season, false):
			rate *= float(e.get("mult", 1.0))
	var p_hour: float = IncidentRisk.rate_to_chance(rate, "hour")
	return 1.0 - pow(1.0 - p_hour, 24.0)

static func cfg() -> Dictionary:
	return SysUtil.table("forecast")

static func words(p: float) -> String:
	for t in cfg().get("tiers", []):
		if p < float(t["below"]):
			return str(t["words"])
	return "likely:"

## [{kind, text, chance}] for tomorrow, only the kinds whose chance reaches min_chance.
static func watches_for(wx: String, season: String) -> Array:
	var out: Array = []
	var c: Dictionary = cfg()
	var kinds: Dictionary = c.get("kinds", {})
	for k in kinds:
		var kd: Dictionary = kinds[k]
		var parts: Array = []
		var best: float = 0.0
		for iid in kd.get("incidents", []):
			var p: float = day_chance(str(iid), wx, season)
			if p >= float(c.get("min_chance", 0.01)):
				parts.append(str(kd["what"].get(iid, iid)))
				best = maxf(best, p)
		if parts.is_empty():
			continue
		var w: String = words(best)
		var what: String = " or ".join(parts)
		var text: String = ("Tomorrow: %s %s. %s" % [w, what, kd.get("tip", "")]) if w != "likely:" else "Tomorrow: %s is likely. %s" % [what.capitalize(), kd.get("tip", "")]
		out.append({"kind": k, "text": text.replace("  ", " "), "chance": best})
	return out
