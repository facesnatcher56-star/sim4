class_name CareerDialog
extends UIDialog
## Job, level, performance, shift hours, today's tasks, next promotion and "Skip work today";
## also pending job offers (Accept / Decline), school and retirement.

func _ready() -> void:
	dialog_width = 440.0
	super._ready()

static func hours_text(h: float) -> String:
	return "%02d:%02d" % [int(h) % 24, int(round((h - floorf(h)) * 60.0))]

const SKILL_WORDS := {"charisma": "handle customers better", "cooking": "cook with more care", "logic": "think problems through", "handiness": "fix things properly",
	"fitness": "keep up on your feet", "writing": "write more clearly", "painting": "paint with a surer hand", "gardening": "look after the plants better",
	"mechanics": "know engines better", "first_aid": "stay calm with patients", "driving": "drive more surely", "perception": "notice more"}

## The next promotion's missing pieces as the manager would put it: no skill names or numbers.
static func manager_wants(miss: Array) -> String:
	var bits: Array = []
	for r in miss:
		var m := RegEx.create_from_string("^([a-z_]+) (\\d+)$").search(str(r))
		if m != null:
			bits.append(str(SKILL_WORDS.get(m.get_string(1), "get better at " + m.get_string(1).replace("_", " "))))
	if bits.is_empty():
		return "Your manager wants more time from you before a step up."
	return "Your manager wants to see you %s." % " and ".join(bits.slice(0, 2))

## "cooking 2" -> "Cooking skill level 2"; "trait: creative or neat" -> "Trait: Creative or Neat".
static func nice_requirement(r: String) -> String:
	var rx := RegEx.create_from_string("^([a-z_]+) (\\d+)$")
	var m := rx.search(r)
	if m != null:
		return "%s skill level %s" % [UIU.sentence(m.get_string(1)), m.get_string(2)]
	if r.begins_with("trait: "):
		var parts: Array = []
		for t in r.substr(7).split(" or "):
			parts.append(PieEntries.label_of_trait(t.strip_edges()))
		return "Trait: " + " or ".join(parts)
	if r.begins_with("not "):
		return "Must not be " + PieEntries.label_of_trait(r.substr(4)).to_lower()
	return r.substr(0, 1).to_upper() + r.substr(1)

func build() -> void:
	var f = folk_obj()
	title_label.text = "%s's Work" % str(UIU.prop(f, "name", "Folk"))
	var info: Dictionary = Careers.info_for(folk_id)
	if bool(info.get("employed", false)):
		_job(info)
	elif bool(info.get("student", false)):
		line("In school. Current grade: %s" % str(info["letter"]), 16)
		line("Attending class on school days keeps the grade up. Skipping lowers it.", 12, UITheme.MUTED)
	elif bool(info.get("retired", false)):
		line("Retired. Pension: %d coins per day." % int(info["pension"]), 16)
	else:
		_jobless(info)

func _jobless(info: Dictionary) -> void:
	var f = folk_obj()
	if str(UIU.prop(f, "age_stage", "adult")) in ["baby", "toddler", "child"]:
		line("Too young to work.", 15, UITheme.MUTED)
		return
	if (info.get("offer", {}) as Dictionary).is_empty():
		line("No job yet.", 16)
		line("Use a computer's \"Look for Jobs\", or the Phone's Jobs app, to find work. A job offer can be accepted or declined here, in the Jobs app or from the pop-up.", 13, UITheme.MUTED)
		_applications()
		return
	offer_card(self, folk_id)

## Task 61B: the applications still waiting for an answer, and an interview when there is one.
func _applications() -> void:
	var waiting: Array = JobApps.pending(folk_id)
	if waiting.is_empty():
		return
	heading("Applications")
	for a in waiting:
		var p: String = JobApps.place(str(a["cid"]))
		if str(a["state"]) == "interview":
			var m: int = int(a["iv_min"])
			line("%s: interview %s" % [p, JobApps.when(m / 1440 + 1, float(m % 1440) / 60.0)], 14, UITheme.ACCENT)
		else:
			line("%s: waiting to hear back" % p, 14, UITheme.MUTED)

## Offer summary + Accept / Decline buttons (also reused by the pop-up toast).
static func offer_card(dlg: UIDialog, fid: int) -> void:
	var o: Dictionary = Careers.pending_offer(fid)
	if o.is_empty():
		return
	var ld: Dictionary = Careers.level_def(str(o["career"]), int(o["level"]))
	var cdef: Dictionary = Careers.career_def(str(o["career"]))
	dlg.heading("Job offer")
	var inner: VBoxContainer = UICard.card(dlg.body, dlg.dialog_width - 50.0, "%s  (%s)" % [str(ld.get("title", "?")), str(cdef.get("label", ""))], "OFFER", str(cdef.get("description", "")))
	UICard.chips(inner, [["Pay", "%d/h" % int(ld.get("pay", 0))], ["Hours", "%s-%s" % [hours_text(float(ld.get("start", 0))), hours_text(float(ld.get("end", 0)))]], ["Ends", "day %d" % int(o.get("expires_day", 0))]])
	UICard.action(inner, "Accept", func():
		Commands.run({"folk_id": fid, "action": "career_accept"})
		dlg.refresh())
	var no := Button.new()
	no.text = "Decline"
	no.pressed.connect(func():
		Commands.run({"folk_id": fid, "action": "career_decline"})
		dlg.refresh())
	inner.add_child(no)

func _job(info: Dictionary) -> void:
	line("%s, %s" % [str(info["title"]), str(info["career_label"])], 18)
	if str(info["branch_label"]) != "":
		line("Track: %s" % str(info["branch_label"]), 12, UITheme.MUTED)
	line("Level %d of %d   |   %d coins/hour" % [int(info["level"]), int(info["max_level"]), int(info["pay_hour"])], 14)
	var shift_txt := "Shift: %s to %s" % [hours_text(float(info["start"])), hours_text(float(info["end"]))]
	if (info["shifts"] as Array).size() > 1:
		shift_txt += "  (%s shift)" % str(info["shift"])
	line(shift_txt, 14)
	_when_where()
	if bool(info["away"]):
		line("Currently at work.", 13, UITheme.ACCENT)
	heading("Performance")
	var perf := float(info["performance"])
	bar(perf, 100.0, "%d / 100. Reaching 100 earns a promotion; falling to 0 risks a demotion." % int(perf))
	line("%d / 100. Good days raise it, skipped days lower it." % int(perf), 11, UITheme.MUTED)
	heading("Today's tasks (do them at home for a performance boost)")
	var tasks: Array = info["tasks"]
	if tasks.is_empty():
		line("None at this level.", 13, UITheme.MUTED)
	for t in tasks:
		var done := bool(t.get("done", false))
		var prog := "  (%d/%d)" % [int(t.get("progress", 0)), int(t.get("count", 1))] if int(t.get("count", 1)) > 1 else ""
		line("%s %s%s   +%d" % ["[x]" if done else "[ ]", str(t.get("label", "")), prog, int(t.get("bonus", 5))], 13, UITheme.MUTED if done else UITheme.TEXT)
	heading("Next promotion")
	if str(info["next_title"]) == "":
		line("Already at the top of this career.", 13, UITheme.MUTED)
	else:
		line(str(info["next_title"]), 15)
		var miss: Array = info["next_missing"]
		if miss.is_empty():
			line("Keep turning up and doing the work well.", 12, UITheme.MUTED)
		else:
			line(manager_wants(miss), 12, UITheme.MUTED)          # task 61b: a promotion is performance and time; skills help, said in words
	_skip_button()

## Task 61B: the work days, the next shift (day and time), where it is, and a Go there button.
func _when_where() -> void:
	var j: Dictionary = Careers.jobs.get(folk_id, {})
	if j.is_empty():
		return
	var cid: String = str(j["career"])
	var sv: Dictionary = Careers.shift_def(cid, str(j.get("shift", "day")))
	var pt: Array = CareerShifts.part_time_days(folk_id)
	line("Work days: %s%s" % [LifeHubJobs._days_text(pt if not pt.is_empty() else sv.get("days", Careers.career_def(cid).get("days", [])) as Array),
		"  (part-time until a promotion)" if not pt.is_empty() else ""], 14)
	var ns: Dictionary = CalendarBook.next_shift(folk_id)
	if ns.is_empty():
		return
	var d: int = int(ns["day"])
	var day_txt: String = "today" if d == SysUtil.day() else ("tomorrow" if d == SysUtil.day() + 1 else Seasons.weekday_long(d))
	line("Next shift: %s, %s%s" % [day_txt, hours_text(float(ns["hour"])), (" at " + str(ns["place"])) if str(ns["place"]) != "" else ""], 14, UITheme.ACCENT)
	var lot: String = str(ns["lot"])
	if lot != "" and NeighborhoodLots.lot_at(folk_obj().tile) != lot:
		var go := Button.new()
		go.text = "Go there"
		go.tooltip_text = "Walk to %s now." % str(ns["place"])
		go.pressed.connect(func():
			Commands.run({"folk_id": folk_id, "action": "travel", "args": {"folk_ids": [folk_id], "lot_id": lot}})
			hide_dialog())
		body.add_child(go)

func _skip_button() -> void:
	var penalty := int(Careers.settings().get("skip_penalty", 15))
	var skipping := int(Careers.skip_flags.get(folk_id, -1)) == SysUtil.day()
	var b := Button.new()
	b.text = "Skip work today" if not skipping else "Skipping work today (click to undo)"
	b.tooltip_text = "Staying home costs %d performance and the day's pay." % penalty
	b.pressed.connect(func():
		if skipping:
			Commands.run({"folk_id": folk_id, "action": "career_unskip"})
		else:
			Commands.run({"folk_id": folk_id, "action": "career_skip"})
		refresh())
	body.add_child(b)
	if not skipping:
		line("Skipping costs %d performance and today's pay." % penalty, 11, UITheme.sem("warn"))
