class_name CaseBoard
extends UIDialog
## The police case board (F10, action `sim_case_board`): the town's crime rate, open and cold cases (a detective's view), cases that involve the
## household, who is locked away (with a Visit button for folk the household knows), civil cases, and recent verdicts. Plain words only.
const ACTION := "sim_case_board"

static func ensure_action() -> void:
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var e := InputEventKey.new()
		e.keycode = KEY_F10
		InputMap.action_add_event(ACTION, e)

func _ready() -> void:
	dialog_width = 560.0
	super._ready()

func build() -> void:
	title_label.text = "Police case board"
	var law := Button.new()
	law.text = "Town Law (every charge and sentence)"
	law.pressed.connect(func(): TownLawDialog.open_from(self))
	body.add_child(law)
	line("Crime in town: %s (%d)%s" % [CrimeRate.label(), int(JusticeState.rate_now), "   |   neighbourhood watch active" if CrimeRate.watch_active() else ""], 14)
	if Police.is_uneasy():
		line("Folk are uneasy after dark until the case is solved.", 12, UITheme.MUTED)
	var open: Array = CaseStore.in_state(["open", "cold"])
	heading("Open and cold cases (%d)" % open.size())
	if open.is_empty():
		line("No open cases. The town is quiet.", 13, UITheme.MUTED)
	for c in open.slice(maxi(open.size() - 8, 0)):
		_case_row(c)
	heading("In court and recent verdicts")
	var shown: int = 0
	var all: Array = JusticeState.cases.values()
	all.sort_custom(func(a, b): return int(a["id"]) > int(b["id"]))
	for c2 in all:
		if str(c2["state"]) in ["trial", "charged", "arrested"] or (str(c2["state"]) == "closed" and str(c2["verdict"]) != ""):
			_case_row(c2)
			shown += 1
			if shown >= 6:
				break
	if shown == 0:
		line("Nothing before the court.", 13, UITheme.MUTED)
	heading("Locked away")
	var any: bool = false
	for pid in JusticeState.inmates:
		var ins: Dictionary = JusticeState.inmates[pid]
		if str(ins["kind"]) not in ["jail", "prison", "remand"]:
			continue
		any = true
		var row := HBoxContainer.new()
		body.add_child(row)
		var until: String = "for life" if int(ins["until"]) >= 100000 else "until day %d" % (int(ins["until"]) + 1)
		row.add_child(UIU.make_label("%s - %s %s" % [CrimePerson.name_of(int(pid)), str(ins["kind"]), until], 13))
		var visitor: int = _visitor_for(int(pid))
		if visitor >= 0 and str(ins["kind"]) != "remand":
			var b := Button.new()
			b.text = "Visit"
			b.tooltip_text = "%s visits for a couple of hours." % CrimePerson.name_of(visitor)
			b.pressed.connect(func():
				Prison.visit(visitor, int(pid))
				refresh())
			row.add_child(b)
	if not any:
		line("Nobody.", 13, UITheme.MUTED)
	if not JusticeState.civil.is_empty():
		heading("Civil cases")
		for cv in JusticeState.civil.slice(maxi(JusticeState.civil.size() - 4, 0)):
			line("%s (%s)" % [str(cv["text"]), str(cv["state"])], 12, UITheme.MUTED)

func _case_row(c: Dictionary) -> void:
	var s: String = "%s - %s" % [CaseStore.title(c), CaseStore.state_label(c)]
	if str(c["state"]) == "closed" and str(c["verdict"]) != "":
		s += ", " + {"guilty": "found guilty", "plea": "pleaded guilty", "not_guilty": "not guilty", "mistrial": "mistrial", "petty": "dealt with"}.get(str(c["verdict"]), str(c["verdict"]))
	var l := line(s, 13)
	var det: String = CaseBoard.details(c)
	if det != "":
		line(det, 11, UITheme.MUTED)
	var tips: PackedStringArray = []
	for n in (c["notes"] as Array).slice(maxi((c["notes"] as Array).size() - 4, 0)):
		tips.append("Day %d: %s" % [int(n["day"]) + 1, str(n["text"])])
	l.tooltip_text = "\n".join(tips)
	l.mouse_filter = Control.MOUSE_FILTER_STOP

## A household folk the inmate knows well enough to visit.
func _visitor_for(inmate: int) -> int:
	for r in SysUtil.residents():
		if not SysUtil.is_away(r) and RelationshipService.knows(int(r.id), inmate) and RelationshipService.value(int(r.id), inmate, "friendship") >= 20.0:
			return int(r.id)
	return -1

## Charges, who is held or accused, evidence and the outcome of a case, in one plain line. Cold cases keep their names ("Death of Ivo, open: no suspect").
static func details(c: Dictionary) -> String:
	var bits: Array = []
	if str(c.get("charge", "")) != "":
		bits.append("Charges: " + CaseText.phrases(c))
	var acc: int = int(c.get("accused", -1))
	match str(c["state"]):
		"cold": bits.append("cold case, no suspect" if acc < 0 else "cold case")
		"open": bits.append("open, no suspect yet" if acc < 0 else "open")
	if acc >= 0:
		bits.append("accused: " + CrimePerson.name_of(acc))
	var acq: Array = SysUtil.to_ints(c.get("acquitted", []))
	if not acq.is_empty():
		bits.append("%s was found not guilty; the case stays open" % CrimePerson.name_of(int(acq[acq.size() - 1])))
	var ev: Array = []
	if bool(c.get("witnessed", false)):
		ev.append("a witness")
	if float(c.get("trace", 0.0)) >= 0.3:
		ev.append("physical traces")
	if bool(c.get("recovered", false)):
		ev.append("recovered goods")
	if not ev.is_empty():
		bits.append("evidence: " + ", ".join(ev))
	if c.get("sentence", {}) is Dictionary and not (c["sentence"] as Dictionary).is_empty() and str(c.get("verdict", "")) in ["guilty", "plea"]:
		bits.append("sentence: " + CaseText.sentence(c["sentence"]))
	return "; ".join(bits)