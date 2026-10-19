class_name CityBudget
extends RefCounted
## The town budget (task 12.4 grows this; the utilities and services already read it). funding(dept) is 1.0 at the standard allocation, below 1 when the
## department is starved, above 1 when it is favoured. maintenance_mult / repair_speed turn it into "how often things break" and "how fast crews work".
##   CityBudget.funding("utilities" | "fire" | "police" | "health" | "roads" | "parks" | "schools")

static var _override: Dictionary = {}       # dept -> funding (tests and the government slice)

static func reset() -> void:
	_override.clear()

static func funding(dept: String) -> float:
	return float(_override.get(dept, CityGov.funding_of(dept)))

static func set_funding(dept: String, v: float) -> void:
	_override[dept] = v

## Breakage multiplier for rates: starved departments let things fall apart (data: utilities.maintenance).
static func maintenance_mult(dept: String) -> float:
	var m: Dictionary = (CityState.cfg().get("utilities", {}) as Dictionary).get("maintenance", {})
	var aged: float = 1.0 + (CityPublic.age * float((CityState.cfg().get("public", {}) as Dictionary).get("age", {}).get("maintenance", 0.6)) if dept == "utilities" else 0.0)      # ageing pipes and cables
	return clampf(1.0 / maxf(funding(dept), 0.1) * aged, float(m.get("min_mult", 0.5)), float(m.get("max_mult", 2.2)))

## Crew speed multiplier (repairs take hours / speed).
static func repair_speed(dept: String) -> float:
	var r: Dictionary = (CityState.cfg().get("utilities", {}) as Dictionary).get("repair", {})
	return clampf(funding(dept), float(r.get("funding_min_speed", 0.6)), float(r.get("funding_max_speed", 1.4)))
