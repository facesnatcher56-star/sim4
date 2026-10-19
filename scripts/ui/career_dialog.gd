class_name CareerDialog
extends UIDialog
## Job, level, performance, shift hours, today's tasks, next promotion and "Skip work today";
## also pending job offers (Accept / Decline), school and retirement.

func _ready() -> void:
	dialog_width = 440.0
	super._ready()

static func hours_text(h: float) -> String:
	return "%02d:%02d" % [int(h) % 24, int(round((h - floorf(h)) * 60.0))]

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
		line("Use a computer's \"Look for Jobs\" to find an offer. You can accept or decline it here or from the pop-up.", 13, UITheme.MUTED)
		return
	offer_card(self, folk_id)

## Offer summary + Accept / Decline buttons (also reused by the pop-up toast).
static func offer_card(dlg: UIDialog, fid: int) -> void:
	var o: Dictionary = Careers.pending_offer(fid)
	if o.is_empty():
		return
	var ld: Dictionary = Careers.level_def(str(o["career"]), int(o["level"]))
	dlg.heading("Job offer")
	dlg.line("%s (%s)" % [str(ld.get("title", "?")), str(Careers.career_def(str(o["career"])).get("label", ""))], 18)
	dlg.line("%d coins/hour, %s to %s. The offer ends on day %d." % [int(ld.get("pay", 0)), hours_text(float(ld.get("start", 0))), hours_text(float(ld.get("end", 0))), int(o.get("expires_day", 0))], 13, UITheme.MUTED)
	var row := HBoxContainer.new()
	dlg.body.add_child(row)
	var ok := Button.new()
	ok.text = "Accept"
	ok.pressed.connect(func():
		Commands.run({"folk_id": fid, "action": "career_accept"})
		dlg.refresh())
	row.add_child(ok)
	var no := Button.new()
	no.text = "Decline"
	no.pressed.connect(func():
		Commands.run({"folk_id": fid, "action": "career_decline"})
		dlg.refresh())
	row.add_child(no)

func _job(info: Dictionary) -> void:
	line("%s, %s" % [str(info["title"]), str(info["career_label"])], 18)
	if str(info["branch_label"]) != "":
		line("Track: %s" % str(info["branch_label"]), 12, UITheme.MUTED)
	line("Level %d of %d   |   %d coins/hour" % [int(info["level"]), int(info["max_level"]), int(info["pay_hour"])], 14)
	var shift_txt := "Shift: %s to %s" % [hours_text(float(info["start"])), hours_text(float(info["end"]))]
	if (info["shifts"] as Array).size() > 1:
		shift_txt += "  (%s shift)" % str(info["shift"])
	line(shift_txt, 14)
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
			line("Requirements met. Keep performance up to 100.", 12, UITheme.ACCENT)
		else:
			line("Still needed: " + ", ".join(miss.map(func(x): return nice_requirement(str(x)))), 12, UITheme.MUTED)
	_skip_button()

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
		line("Skipping costs %d performance and today's pay." % penalty, 11, Color("#e8913d"))
