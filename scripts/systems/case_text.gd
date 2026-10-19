class_name CaseText
extends RefCounted
## The words of the justice system (tasks 19.2 / 20): every notice and chronicle line names the charge, the victim and the sentence.
## "Ivo was found guilty of domestic violence against Tess: 6 days in jail, an anger management course and a protective order."
## Wording is plain, clinical and non-graphic; people are named (no "someone" when the name is known); they/them where a pronoun is needed.

## "the death of Ivo" / "domestic violence against Tess" / "the break-in at the Orr house" for a charge of the case.
static func phrase(c: Dictionary, charge_id: String = "") -> String:
	var id: String = charge_id if charge_id != "" else str(c.get("charge", c.get("kind", "")))
	var cd: Dictionary = JusticeProcess.charge_def(id)
	var victim: int = int(c.get("victim", -1))
	var tpl: String = str(cd.get("phrase", str(cd.get("label", id)).to_lower()))
	if tpl.find("{victim}") >= 0 and victim < 0:
		return str(cd.get("label", id)).to_lower()
	return tpl.replace("{victim}", victim_name(c) if victim >= 0 else "").replace("{place}", CaseStore.house_label(str(c.get("scene", ""))))

## The victim's name, also when they are crew or somebody who is no longer on the map (the case remembered it when it was opened).
static func victim_name(c: Dictionary) -> String:
	var n: String = CrimePerson.name_of(int(c.get("victim", -1)))
	if (n == "Someone" or n == "") and str(c.get("victim_name", "")) != "":
		return str(c["victim_name"])
	return n

## All charges as one phrase ("domestic violence against Tess and breaking probation").
static func phrases(c: Dictionary) -> String:
	var list: Array = JusticeGuideline.charges_of(c)
	var out: Array = []
	for id in list:
		out.append(phrase(c, str(id)))
	return join_and(out)

static func join_and(items: Array) -> String:
	if items.is_empty():
		return ""
	if items.size() == 1:
		return str(items[0])
	return "%s and %s" % [", ".join(items.slice(0, items.size() - 1)), str(items[items.size() - 1])]

## "6 days in jail, a fine of 60 coins, an anger management course and a protective order".
static func sentence(s: Dictionary) -> String:
	var bits: Array = []
	var days: int = int(s.get("days", 0))
	var t: String = str(s.get("type", "fine"))
	if bool(s.get("life", false)):
		bits.append("life in prison")
	elif t in ["jail", "prison"] and days > 0:
		bits.append("%d day%s in %s" % [days, "" if days == 1 else "s", t])
	var pd: int = int(s.get("probation_days", days if t == "probation" else 0))
	var sd: int = int(s.get("service_days", days if t == "service" else 0))
	if pd > 0:
		bits.append("%s of probation" % SysUtil.count_text(pd, "day"))
	if sd > 0:
		bits.append("%s of community service" % SysUtil.count_text(sd, "day"))
	if int(s.get("fine", 0)) > 0:
		bits.append("a fine of %d coins" % int(s["fine"]))
	if int(s.get("restitution", 0)) > 0:
		bits.append("%d coins paid back to the victim" % int(s["restitution"]))
	var labels: Dictionary = JusticeGuideline.cfg().get("course_labels", {})
	for co in (s.get("courses", []) as Array):
		bits.append(str(labels.get(str(co["kind"]), "a course")))
	if bool(s.get("order", false)):
		bits.append("a protective order")
	if bool(s.get("custody_loss", false)):
		bits.append("loss of custody")
	if bits.is_empty():
		bits.append("a warning")
	return join_and(bits)

static func arrested(c: Dictionary, pid: int) -> String:
	return "%s was arrested over %s." % [CrimePerson.name_of(pid), case_phrase(c)]

## The crime itself as a noun phrase, from the case kind (known before any charge: "the death of Ivo").
static func case_phrase(c: Dictionary) -> String:
	if str(c.get("kind", "")) in ["murder", "serial", "manslaughter"] and int(c.get("victim", -1)) >= 0:
		return "the death of %s" % victim_name(c)
	return phrase(c, JusticeProcess.charge_for(c))

static func charged(c: Dictionary, pid: int) -> String:
	if str(c.get("kind", "")) in ["murder", "serial", "manslaughter"] and int(c.get("victim", -1)) >= 0:
		return "%s was charged with %s over the death of %s." % [CrimePerson.name_of(pid), str(JusticeProcess.charge_def(str(c.get("charge", ""))).get("label", "murder")).to_lower(), victim_name(c)]
	return "%s was charged with %s." % [CrimePerson.name_of(pid), phrases(c)]

static func convicted(c: Dictionary, pid: int, s: Dictionary, plea: bool) -> String:
	return "%s %s %s: %s." % [CrimePerson.name_of(pid), "pleaded guilty to" if plea else "was found guilty of", phrases(c), sentence(s)]

static func acquitted(c: Dictionary, pid: int) -> String:
	var tail: String = "; the case stays open" if not bool(c.get("wrongful", false)) else "; the police are looking for whoever did it"
	return "%s was found not guilty of %s%s." % [CrimePerson.name_of(pid), neutral(c), tail]

static func mistrial(c: Dictionary, pid: int) -> String:
	return "The trial of %s over %s ended in a mistrial: the jury could not agree." % [CrimePerson.name_of(pid), neutral(c)]

## Before a guilty verdict a killing is "the death of Ivo", never the accusation of murder.
static func neutral(c: Dictionary) -> String:
	if str(c.get("kind", "")) in ["murder", "serial", "manslaughter"] and int(c.get("victim", -1)) >= 0:
		return case_phrase(c)
	return phrases(c)
