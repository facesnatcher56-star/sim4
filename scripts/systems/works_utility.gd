class_name WorksUtility
extends RefCounted
## Utility techs and the utility networks (task 12.1, task 31): every power and utility tech in town (residents and townies) makes the repair crews
## quicker. UtilityEvents divides outage hours by `CityBudget.repair_speed("utilities") * crew_mult()`.

static func techs() -> int:
	var n: int = 0
	for cid in Works.career_ids():
		if bool(Careers.career_def(str(cid)).get("utility_crew", false)):
			n += Works.headcount(str(cid))
	return n

## 1.0 with no techs; +crew_per_tech each, up to +crew_cap. A strike by the grid workers stops the bonus.
static func crew_mult() -> float:
	var k: Dictionary = Works.cfg().get("utility", {})
	var n: int = 0
	for cid in Works.career_ids():
		if bool(Careers.career_def(str(cid)).get("utility_crew", false)) and not WorksEvents.on_strike(str(cid)):
			n += Works.headcount(str(cid))
	return 1.0 + minf(float(k.get("crew_cap", 0.3)), float(n) * float(k.get("crew_per_tech", 0.06)))
