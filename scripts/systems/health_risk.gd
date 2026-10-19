class_name HealthRisk
extends RefCounted
## How a person's fitness, diet, flu shot and conditions change the chance of the health incidents (task 14). Called from
## IncidentRisk.effective_rate (and max_mult from IncidentRisk.max_rate, which bounds the rejection sampling). Only incidents that carry a
## tag listed in data/life/20_health.json config.health_life.risk_tags ("illness", "cardiac") are touched, so the hot path costs one empty-array test.
##   illness: colds and flu     fitness 0 -> x1.35, 100 -> x0.7; diet 0 -> x1.2, 100 -> x0.85; the flu shot cuts flu to a quarter and colds a little
##   cardiac: heart attacks     fitness 0 -> x2, 100 -> x0.5; diet 0 -> x1.6, 100 -> x0.7; high blood pressure x2.4 (x1.2 with medicine)

static func mult(def: Dictionary, subj) -> float:
	var tags: Array = def.get("tags", [])
	if tags.is_empty() or subj == null or subj.kind == "lot":
		return 1.0
	var table: Dictionary = HealthLife.cfg().get("risk_tags", {})
	var id: int = int(subj.id)
	if not HealthLife.recs.has(id):
		return 1.0
	var r: Dictionary = HealthLife.recs[id]
	var m := 1.0
	for t in tags:
		if table.has(t):
			var rows: Dictionary = table[t]
			for meter in rows:
				m *= lerpf(float(rows[meter][0]), float(rows[meter][1]), float(r.get(meter, 50.0)) / 100.0)
		if t == "cardiac":
			m *= HealthCond.cardiac_mult(id)
		elif int(r.get("shot_until", -1)) >= SysUtil.day() and (t == "flu" or t == "cold"):
			var shot: Dictionary = HealthLife.cfg().get("flu_shot", {})
			m *= float(shot.get("flu_mult", 0.25)) if t == "flu" else float(shot.get("cold_mult", 0.8))
	return m

## The largest value mult() can return for this incident (every bad factor at once): used by the sampling bound.
static func max_mult(def: Dictionary) -> float:
	var tags: Array = def.get("tags", [])
	if tags.is_empty():
		return 1.0
	var table: Dictionary = HealthLife.cfg().get("risk_tags", {})
	var m := 1.0
	for t in tags:
		if table.has(t):
			for meter in (table[t] as Dictionary):
				m *= maxf(maxf(float(table[t][meter][0]), float(table[t][meter][1])), 1.0)
		if t == "cardiac":
			for cid in HealthCond.defs():
				m *= maxf(float(HealthCond.def(str(cid)).get("cardiac_mult", 1.0)), 1.0)
	return m
