class_name IncidentRisk
extends RefCounted
## Rate maths. base_rate_per_year (events per subject per game year, a year = config.year_days = 28 days) x the Surprises
## multiplier x every matching risk_mults / prevent entry -> an effective yearly rate -> a chance for ONE check
## (hour or day): p = rate / checks_per_year (so the expected number of events per year is exactly the rate), capped at config.max_chance.

static func year_days() -> float:
	return maxf(float(IncidentDefs.cfg("year_days", 28)), 1.0)

static func checks_per_year(check: String) -> float:
	return year_days() * (24.0 if check == "hour" else 1.0)

static func rate_to_chance(rate_per_year: float, check: String) -> float:
	if rate_per_year <= 0.0:
		return 0.0
	var p: float = rate_per_year / checks_per_year(check)
	return minf(p, float(IncidentDefs.cfg("max_chance", 0.9)))

static func chance_to_rate(p: float, check: String) -> float:
	return p * checks_per_year(check)

## [{label, mult, kind: "risk"|"prevent", block}] for every entry whose `when` holds for the subject.
static func breakdown(def: Dictionary, subj, phase: String = "") -> Array:
	var out: Array = []
	for kind in ["risk_mults", "prevent"]:
		for e in def.get(kind, []):
			var per_lot: bool = bool(e.get("per_lot", false))
			if (phase == "occ" and per_lot) or (phase == "lot" and not per_lot):
				continue
			if IncidentCond.check(e.get("when", []), subj):
				out.append({"label": str(e.get("label", "")), "mult": float(e.get("mult", 1.0)), "kind": "risk" if kind == "risk_mults" else "prevent",
					"block": bool(e.get("block", false))})
	return out

## phase: "" every entry | "occ" town-scope occurrence (entries without per_lot) | "lot" the per_lot entries only.
static func risk_factor(def: Dictionary, subj, phase: String = "") -> float:
	var f: float = 1.0
	for e in breakdown(def, subj, phase):
		if bool(e["block"]):
			return 0.0
		f *= float(e["mult"])
	return f

## Effective events per year for this subject (0 when the conditions fail). `surprise` = apply the Surprises setting.
static func effective_rate(def: Dictionary, subj, surprise: bool = true, conditions_checked: bool = false) -> float:
	if not conditions_checked and not IncidentCond.check(def.get("conditions", []), subj):
		return 0.0
	var r: float = float(def.get("base_rate_per_year", 0.0)) * risk_factor(def, subj, "occ" if str(def.get("scope", "")) == "town" else "")
	r *= VacationHome.rate_mult(def, subj)          # task 22: an empty house is a better target (incidents tagged "burglary_odds")
	if surprise and bool(def.get("surprise", true)):
		r *= Incidents.surprise_mult()
	return r

static func chance(def: Dictionary, subj) -> float:
	return rate_to_chance(effective_rate(def, subj), str(def.get("check", "day")))
