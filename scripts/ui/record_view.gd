class_name RecordView
extends RefCounted
## The "Record" tab of a folk's panel (task 20): charges, verdicts and sentences on file, time served, and what is still in force (jail, probation,
## protective orders, courses). Works for household folk and for known townies alike (everything is keyed by person id).

static func lines(pid: int) -> Array:
	var out: Array = []     # [text, muted]
	var inside: Dictionary = JusticeState.inmates.get(pid, {})
	if not inside.is_empty():
		var until: String = "for a long time" if int(inside.get("until", 0)) >= 100000 else "until day %d" % (int(inside.get("until", 0)) + 1)
		out.append(["Now: %s, %s." % [{"custody": "in custody", "remand": "held for trial", "jail": "in jail", "prison": "in prison"}.get(str(inside.get("kind", "")), "in custody"), until], false])
	if JusticeState.probation.has(pid) and int(JusticeState.probation[pid]) >= SysUtil.day():
		out.append(["On probation until day %d." % (int(JusticeState.probation[pid]) + 1), false])
	for o in JusticeOrders.orders_against(pid):
		out.append(["Protective order: must stay away from %s until day %d." % [CrimePerson.name_of(int(o["victim"])), int(o["until"]) + 1], false])
	for o2 in JusticeOrders.orders_for(pid):
		out.append(["Protected by an order against %s until day %d." % [CrimePerson.name_of(int(o2["offender"])), int(o2["until"]) + 1], true])
	var labels: Dictionary = JusticeGuideline.cfg().get("course_labels", {})
	for co in JusticeState.courses.get(pid, []):
		out.append(["Court-ordered course: %s (%s left)." % [str(labels.get(str(co["kind"]), "a course")), SysUtil.count_text(int(co["days_left"]), "session")], false])
	if JusticeState.service.has(pid):
		out.append(["Community service: %s left." % SysUtil.count_text(int(JusticeState.service[pid]["days_left"]), "day"), false])
	var list: Array = JusticeRecords.entries(pid)
	if list.is_empty() and out.is_empty():
		return [["A clean record.", true]]
	for i in range(list.size() - 1, -1, -1):
		var r: Dictionary = list[i]
		var cd: Dictionary = JusticeProcess.charge_def(str(r.get("charge", "")))
		var v: int = int(r.get("victim", -1))
		var text: String = "Day %d: %s%s, %s" % [int(r.get("day", 0)) + 1, str(cd.get("label", r.get("charge", "?"))), (" (against %s)" % CrimePerson.name_of(v)) if v >= 0 else "",
			{"guilty": "found guilty", "plea": "pleaded guilty", "petty": "dealt with on the spot"}.get(str(r.get("result", "")), str(r.get("result", "")))]
		if str(r.get("sentence", "")) != "":
			text += ": " + str(r["sentence"])
		if r.has("served"):
			text += ". Served %s" % SysUtil.count_text(int(r["served"]), "day")
		if bool(r.get("expunged", false)):
			text += " (cleared from the record)"
		out.append([text + ".", bool(r.get("expunged", false))])
	return out

static func fill(box: Control, pid: int) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	if pid < 0:
		return
	for row in lines(pid):
		var l := UIU.make_label(str(row[0]), 13, UITheme.MUTED if bool(row[1]) else UITheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(300, 0)
		box.add_child(l)
