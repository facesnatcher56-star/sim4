class_name LifeHubHealth
extends RefCounted
## The "Health" tab of LifeHub: fitness, diet and teeth of the selected person, stress, conditions with their medicine, check-ups and the flu shot,
## and what to do about each. Plain words only; the places that help (clinic, dentist, counselling, pharmacy counter, gym) are under Places.

static func build(dlg: LifeHub) -> void:
	var f = dlg.folk_obj()
	var id: int = dlg.folk_id
	var r: Dictionary = HealthLife.rec(id)
	dlg.heading(str(f.name))
	for m in [["fitness", "Fitness", "Exercise, the gym and sport raise it."], ["diet", "Diet", "Proper meals raise it. Snacks and fast food lower it."], ["dental", "Teeth", "Brush every day. The dentist fixes the rest."]]:
		dlg.line("%s: %s" % [m[1], HealthLife.label(str(m[0]), float(r[m[0]]))], 14)
		dlg.bar(float(r[m[0]]), 100.0, str(m[2]))
	var score: float = HealthLife.score(id)
	dlg.line("Overall health %d out of 100. %s" % [int(score), "A healthy life tends to be a longer one." if score >= 60.0 else "Better habits would add years."], 13, UITheme.MUTED)
	var strain: float = float(r["strain"])
	dlg.line("Stress from work: %s." % ("calm" if strain < 30.0 else ("building up" if strain < 60.0 else ("worn out" if strain < 85.0 else "burnt out"))), 14)
	if strain >= 50.0 or f.has_buff("burnt_out"):
		dlg.line("Rest, a holiday or a counsellor (Places > Health) will help.", 13, UITheme.MUTED)
	var conds: Array = HealthCond.list(id)
	for c in conds:
		var txt: String = "%s: %s" % [c["label"], ("medicine for %d more days" % int(c["doses"])) if bool(c["managed"]) else "no medicine. Flare-ups are likely."]
		dlg.line(txt, 14, UITheme.TEXT if bool(c["managed"]) else UITheme.sem("warn"))
	if int(r["shot_until"]) >= SysUtil.day():
		dlg.line("Flu shot: protected for %d more days." % (int(r["shot_until"]) - SysUtil.day() + 1), 13, UITheme.MUTED)
	if int(r["checkup_day"]) >= 0:
		dlg.line("Last check-up: day %d." % int(r["checkup_day"]), 13, UITheme.MUTED)
	else:
		dlg.line("No check-up yet. The clinic can find problems early.", 13, UITheme.MUTED)
	if f.has_buff("toothache"):
		dlg.line("A toothache: see the dentist.", 13, UITheme.sem("warn"))
