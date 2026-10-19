class_name TownLaw
extends RefCounted
## The in-game "Town Law" book (task 20): every charge by class, in plain words. Pure data -> text; the dialog (TownLawDialog) only lays it out.
## Reachable from the case board, the help screen and the "Read the Town Law" interaction on the computers and bookcases of the courthouse.

const CLASSES := ["petty", "misdemeanour", "felony"]
const CLASS_LABEL := {"petty": "Petty offences", "misdemeanour": "Misdemeanours", "felony": "Felonies"}
const CLASS_BLURB := {"petty": "Small offences. A fine or community service on the spot, no jury, no trial.",
	"misdemeanour": "Middle-sized crimes. A trial with a jury; fines, probation, courses and short jail terms.",
	"felony": "Serious crimes. A jury trial; long jail or prison terms, and the record stays."}

static func all_ids() -> Array:
	var ids: Array = (JusticeState.sect("charges") as Dictionary).keys()
	ids.sort_custom(func(a, b):
		var ca: Dictionary = JusticeProcess.charge_def(str(a))
		var cb: Dictionary = JusticeProcess.charge_def(str(b))
		var ra: int = CLASSES.find(str(ca.get("class", "misdemeanour")))
		var rb: int = CLASSES.find(str(cb.get("class", "misdemeanour")))
		if ra != rb:
			return ra < rb
		if int(ca.get("grade", 1)) != int(cb.get("grade", 1)):
			return int(ca.get("grade", 1)) < int(cb.get("grade", 1))
		return str(ca.get("label", a)) < str(cb.get("label", b)))
	return ids

static func range_text(g: Dictionary) -> String:
	var bits: Array = []
	if g.has("fine"):
		bits.append("a fine of %d to %d coins" % [int(g["fine"][0]), int(g["fine"][1])])
	if g.has("service"):
		bits.append("%d to %d days of community service" % [int(g["service"][0]), int(g["service"][1])])
	if g.has("probation"):
		bits.append("%d to %d days of probation" % [int(g["probation"][0]), int(g["probation"][1])])
	if g.has("jail"):
		bits.append("%d to %d days in jail" % [int(g["jail"][0]), int(g["jail"][1])])
	if g.has("prison"):
		bits.append("%d to %d days in prison" % [int(g["prison"][0]), int(g["prison"][1])])
	if g.has("life_at"):
		bits.append("life in prison for the worst cases")
	return CaseText.join_and(bits)

static func factors_text(ids: Array, table: Dictionary) -> String:
	return ", ".join(ids.map(func(k): return str((table.get(k, {}) as Dictionary).get("label", k))))

## One entry of the book. All strings, plain words.
static func entry(id: String) -> Dictionary:
	var cd: Dictionary = JusticeProcess.charge_def(id)
	var K: Dictionary = JusticeGuideline.cfg()
	var rec: Dictionary = cd.get("record", {})
	var cls: String = str(cd.get("class", "misdemeanour"))
	var extras: Array = []
	for co in (cd.get("courses", []) as Array):
		extras.append(str((K.get("course_labels", {}) as Dictionary).get(co, "a course")))
	if bool(cd.get("order", false)):
		extras.append("a protective order")
	if bool(cd.get("restitution", false)):
		extras.append("paying the victim back")
	if bool(cd.get("custody_loss", false)):
		extras.append("loss of custody")
	var expunge: int = int(rec.get("expunge_days", 0))
	var bans: Array = rec.get("job_bans", [])
	return {"id": id, "label": str(cd.get("label", id)), "class": cls, "grade": int(cd.get("grade", 1)), "description": str(cd.get("description", "")),
		"elements": ", ".join(cd.get("elements", [])), "bail": int(cd.get("bail", 0)), "jury": bool(cd.get("jury", true)), "stub": bool(cd.get("stub", false)),
		"sentence": range_text(cd.get("guideline", {})), "also": CaseText.join_and(extras),
		"aggravating": factors_text(cd.get("aggravating", []), K.get("aggravating", {})), "mitigating": factors_text(cd.get("mitigating", []), K.get("mitigating", {})),
		"record": ("Cleared from the record after %d clean days." % expunge) if expunge > 0 else "Stays on the record for good.",
		"bans": ", ".join(bans.map(func(b): return str(b).replace("_", " "))), "consecutive": bool(cd.get("consecutive", false))}

static func entries() -> Array:
	return all_ids().map(func(i): return entry(str(i)))

static func grade_label(e: Dictionary) -> String:
	return "%s, grade %d" % [str(e["class"]).capitalize(), int(e["grade"])]
