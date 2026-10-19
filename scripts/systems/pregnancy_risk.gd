class_name PregnancyRisk
extends RefCounted
## Risk factors of a pregnancy (task 18 parts 3-4). A running pregnancy has `risk` points: the sum of
##   * age (elder-ish adults), twins / triplets, and the current state of her body (buffs: injured, flu, starving, stress, exhausted, tipsy ...),
##   * one-off events (a fall on the stairs, an injury, an illness, a collapse) that fade by `event_decay_per_day`,
## minus care (prenatal visits, bed rest, resting well, eating well). `multiplier()` is what the loss dice (PregnancyLoss) and the labour
## complications (PregnancyBirth) scale their base rates with. All numbers: data/pregnancy.json "risk" and "care". Nothing runs per minute:
## the points are recomputed once a day per pregnant folk, events add to the record when they happen.

static func cfg() -> Dictionary:
	return Pregnancy.cfg("risk")

## Recompute today's points for mother `id` and store them in the record. Returns the value.
static func on_day(id: int, r: Dictionary) -> float:
	var c: Dictionary = cfg()
	var pts: float = 0.0
	var age: float = Family.age_days_of(id)
	if age >= float(c.get("age_from", 140)):
		pts += float(c.get("age_points", 1.0))
	if int(r.get("kids", 1)) > 1:
		pts += float(c.get("multiples_points", 1.0))
	var f = SysUtil.folk(id)
	if f != null:
		var bp: Dictionary = c.get("points", {})
		for b in f.buffs:
			pts += float(bp.get(str(b["id"]), 0.0))
	var keep: Array = []
	var decay: float = float(c.get("event_decay_per_day", 0.5))
	for e in r.get("events", []):
		var left: float = float(e["points"]) - decay * float(SysUtil.day() - int(e["day"]))
		if left > 0.0:
			pts += left
			keep.append(e)
	r["events"] = keep
	var care: Dictionary = Pregnancy.cfg("care")
	var cut: float = float(care.get("visit_risk_cut", 0.25)) * float(int(r.get("visits", 0)))
	if f != null:
		if f.has_buff("bed_rest"):
			cut += float(care.get("bed_rest_cut", 0.3))
		if f.has_buff("well_rested") or f.has_buff("nap_refreshed"):
			cut += float(care.get("rest_risk_cut", 0.15))
		if f.has_buff("well_fed") or f.has_buff("well_fed_hearty") or f.has_buff("well_fed_gourmet"):
			cut += float(care.get("healthy_food_cut", 0.1))
	r["risk"] = pts
	r["care"] = cut
	return pts

## Loss / complication multiplier: 1 with no risk, up and down with the points and the care (never below 0.25).
static func multiplier(r: Dictionary) -> float:
	return clampf(1.0 + 0.6 * float(r.get("risk", 0.0)) - float(r.get("care", 0.0)), 0.25, 8.0)

static func add_event(id: int, ev: String) -> void:
	var r: Dictionary = Pregnancy.rec(id)
	var pts: float = float(cfg().get("event_points", {}).get(ev, 0.0))
	if r.is_empty() or pts <= 0.0:
		return
	(r["events"] as Array).append({"event": ev, "points": pts, "day": SysUtil.day()})
	r["risk"] = float(r.get("risk", 0.0)) + pts

static func on_game_event(ev: String, payload: Dictionary) -> void:
	if (cfg().get("event_points", {}) as Dictionary).has(ev):
		add_event(int(payload.get("folk_id", -1)), ev)
