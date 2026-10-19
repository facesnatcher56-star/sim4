class_name EduGate
extends RefCounted
## What a degree is worth (task 14). Two small hooks into the career system:
##   * extra_missing(folk, career, level) -> reasons a job level stays closed without the right degree (Careers.qualify adds them to "missing"):
##     data/life/10_education.json "gates": {career: {from_level, degrees: [..]}}, e.g. a doctor above the first rungs needs a medicine degree.
##   * pay_mult(folk, career) -> 1 + the degree wage bonus when the degree belongs to the career (a business degree helps in every career).
## Townies and the statistical world never use Careers.qualify, so nothing here touches them.

static func gate_of(cid: String) -> Dictionary:
	return LifeDefs.get_in("gates", cid)

static func extra_missing(folk_id: int, cid: String, level: int) -> Array:
	var g: Dictionary = gate_of(cid)
	if g.is_empty() or level < int(g.get("from_level", 99)):
		return []
	for d in g.get("degrees", []):
		if EduState.has_degree(folk_id, str(d)):
			return []
	var names: Array = (g.get("degrees", []) as Array).map(func(d): return EduCollege.major_label(str(d)))
	return ["a degree in %s" % " or ".join(names)]

static func pay_mult(folk_id: int, cid: String) -> float:
	var r: Dictionary = EduState.peek(folk_id)
	if r.is_empty() or (r.get("degrees", []) as Array).is_empty():
		return 1.0
	var bonus: float = float(EduState.cfg().get("college", {}).get("pay_bonus", 0.08))
	for d in r["degrees"]:
		if str(d) == "business" or (EduCollege.major_def(str(d)).get("careers", []) as Array).has(cid):
			return 1.0 + bonus
	return 1.0

## Careers a degree holder can now reach, as labels (for the UI).
static func opened_by(degree: String) -> Array:
	return (EduCollege.major_def(degree).get("careers", []) as Array).map(func(cid): return str(Careers.career_def(str(cid)).get("label", cid)))
