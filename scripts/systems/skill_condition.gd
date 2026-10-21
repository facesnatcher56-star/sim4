class_name SkillCondition
extends RefCounted
## Task 54b-light: the ONE shared body/condition modifier every SkillCheck uses, from real state only: age, injury, drunk or high, tired, hungry, sick.
## Numbers: data/skills.json "conditions" and "age". Also how much worse a failure gets (catastrophe_mult): drunk, high, injured or exhausted hands slip badly.
##   SkillCondition.modifier(pid) -> float (added to the chance)      SkillCondition.catastrophe_mult(pid) -> float (>= 1)

static func cfg() -> Dictionary:
	return SysUtil.table("skills")

## The states that apply to this person right now (ids of data "conditions").
static func states(pid: int) -> Array:
	var out: Array = []
	var f = SysUtil.folk(pid)
	if f == null:
		return out          # a townie off the lot: no body state is simulated, so nothing applies
	if f.get_stat_value("energy") < -40.0:
		out.append("tired")
	if f.get_stat_value("hunger") < -50.0:
		out.append("hungry")
	if f.has_buff("drunk"):
		out.append("drunk")
	elif f.has_buff("tipsy"):
		out.append("tipsy")
	if f.has_buff("high") or f.has_buff("withdrawal"):
		out.append("high")
	if Health.is_injured(f):
		out.append("injured")
	if Health.is_ill(f):
		out.append("sick")
	return out

static func modifier(pid: int) -> float:
	var c: Dictionary = cfg().get("conditions", {})
	var s: float = 0.0
	for k in states(pid):
		s += float(c.get(k, 0.0))
	s += float((cfg().get("age", {}) as Dictionary).get(RomanceRules.stage_of(pid), 0.0))
	return s

static func catastrophe_mult(pid: int) -> float:
	var c: Dictionary = cfg().get("catastrophe", {}).get("condition_mult", {})
	var m: float = 1.0
	for k in states(pid):
		m *= float(c.get(k, 1.0))
	return m
