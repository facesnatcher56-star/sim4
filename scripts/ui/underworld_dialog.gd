class_name UnderworldDialog
extends UIDialog
## The criminal life (task 21): rank and the two reputations, jobs with a plain-words look at the odds, planning a heist (watch the place, a crew,
## kit, a getaway car), the stash and fence, contacts and the ledger of victims. Opened from the case board. Everything goes through the command layer
## (action `crimelife`). Plain words only: no numbers except coins; no real-world methods.

var _targets: Dictionary = {}          # job id -> chosen target index
var _heist_target: String = "jeweller"

func _ready() -> void:
	dialog_width = 600.0
	super._ready()

static func open_from(from: Node, fid: int) -> void:
	var host: Node = from.get_parent() if from.get_parent() != null else from
	for c in host.get_children():
		if c is UnderworldDialog:
			(c as UnderworldDialog).show_for(fid)
			return
	var d := UnderworldDialog.new()
	host.add_child(d)
	d.show_for(fid)

func _cmd(args: Dictionary) -> void:
	var r: Dictionary = Commands.run({"player_id": Players.local_id, "folk_id": folk_id, "action": "crimelife", "args": args})
	if str(r.get("msg", "")) != "":
		SysUtil.notify(str(r["msg"]), "info" if bool(r.get("ok", false)) else "warn")
	refresh()

static func odds_words(o: Dictionary) -> String:
	var pull: float = float(o["pull_off"])
	var det: float = float(o["detect"])
	var a: String = "looks easy" if pull >= 0.8 else ("doable" if pull >= 0.55 else ("risky" if pull >= 0.35 else "a long shot"))
	var b: String = "likely to be seen" if det >= 0.6 else ("a fair chance of being seen" if det >= 0.3 else "should stay quiet")
	return "%s, %s" % [a, b]

func build() -> void:
	title_label.text = "The criminal life"
	var f = folk_obj()
	if f == null:
		return
	var pid: int = int(f.id)
	if not CrimeLifePath.is_member(pid):
		line("%s has not turned to crime. It can start small, with a pocket, a shelf or a lock. The law, a record and the people who get hurt are all real." % f.name, 13, UITheme.MUTED)
		var go := Button.new()
		go.text = "Take up the criminal life"
		go.pressed.connect(func(): _cmd({"action": "join"}))
		body.add_child(go)
		_gear(pid)
		return
	_status(pid)
	_jobs(pid)
	_heist(pid)
	_stash(pid)
	_contacts(pid)
	_ledger(pid)
	var leave := Button.new()
	leave.text = "Go straight"
	leave.tooltip_text = "Leave the criminal life. The record and the legacy stay."
	leave.pressed.connect(func(): _cmd({"action": "leave"}))
	body.add_child(leave)

func _status(pid: int) -> void:
	var s: Dictionary = CrimeLifePath.summary(pid)
	heading("Standing")
	var rk: Dictionary = (CrimeLifePath.ranks()[maxi(CrimeLifePath.rank_index(pid), 0)] as Dictionary)
	line("%s. %s" % [str(s["rank"]), str(rk.get("blurb", ""))], 14)
	bar(float(s["cred"]), 100.0, "Street name in the underworld.")
	line("Street name %d. Town reputation %d. Criminal record: %d. Police attention: %s." % [int(s["cred"]), int(s["town_rep"]), int(s["record"]), "high" if int(s["heat"]) >= 12 else ("some" if int(s["heat"]) >= 4 else "little")], 12, UITheme.MUTED)
	var nxt: int = CrimeLifePath.rank_index(pid) + 1
	if nxt < CrimeLifePath.ranks().size():
		var r: Dictionary = CrimeLifePath.ranks()[nxt]
		var need: Array = ["street name %d" % int(r.get("cred", 0))]
		for sk in (r.get("skills", {}) as Dictionary):
			need.append("%s %d" % [ContentRules.skill_label(str(sk)), int(r["skills"][sk])])
		if int(r.get("jobs", 0)) > 0:
			need.append("%d jobs done" % int(r["jobs"]))
		if int(r.get("heists", 0)) > 0:
			need.append("%d heist%s" % [int(r["heists"]), "" if int(r["heists"]) == 1 else "s"])
		if int(r.get("fenced", 0)) > 0:
			need.append("%d lots fenced" % int(r["fenced"]))
		line("Next: %s - needs %s." % [str(r["label"]), ", ".join(need)], 12, UITheme.MUTED)

func _jobs(pid: int) -> void:
	heading("Jobs")
	if SysUtil.is_away(CrimePerson.folk(pid)):
		line("Busy right now.", 12, UITheme.MUTED)
	for jid in CrimeLifeJobs.ids():
		var j: Dictionary = CrimeLifeJobs.job(str(jid))
		if bool(j.get("planned", false)) or not CrimeLifeJobs.unlocked(pid, str(jid)):
			continue
		var ts: Array = CrimeLifeJobs.targets(pid, str(jid), 5)
		if ts.is_empty():
			continue
		var idx: int = clampi(int(_targets.get(jid, 0)), 0, ts.size() - 1)
		var o: Dictionary = CrimeLifeRoll.odds(pid, str(jid), str(ts[idx]["scene"]))
		var row := HBoxContainer.new()
		body.add_child(row)
		var ob := OptionButton.new()
		for t in ts:
			ob.add_item(str(t["label"]))
		ob.select(idx)
		ob.item_selected.connect(func(i): _targets[jid] = i; refresh())
		row.add_child(UIU.make_label(str(j["label"]) + ":", 13))
		row.add_child(ob)
		var go := Button.new()
		go.text = "Go"
		go.tooltip_text = "Takes about %d minutes away from home." % int(j.get("minutes", 30))
		go.pressed.connect(func(): _cmd({"action": "job", "job": str(jid), "target": ts[idx]}))
		row.add_child(go)
		if bool(j.get("casable", false)):
			var cb := Button.new()
			cb.text = "Watch it"
			cb.tooltip_text = "Learn the place first."
			cb.pressed.connect(func(): _cmd({"action": "case", "target": str(ts[idx]["scene"])}))
			row.add_child(cb)
		line("   %s%s" % [odds_words(o), ". Known: " + CrimeLifeCasing.word(float(o["cased"])) if bool(j.get("casable", false)) else ""], 11, UITheme.MUTED)

func _heist(pid: int) -> void:
	heading("A planned job")
	var h: Dictionary = CrimeLifeHeist.plan_of(pid)
	if h.is_empty():
		if not CrimeLifeHeist.can_plan(pid):
			line("Nobody backs a big plan from an unproven thief. Work as a burglar first.", 12, UITheme.MUTED)
			return
		var ob := OptionButton.new()
		var ids: Array = CrimeLifeHeist.target_ids()
		for t in ids:
			ob.add_item(UIU.sentence(str(CrimeLifeHeist.target_def(str(t)).get("label", t))))
		ob.select(maxi(ids.find(_heist_target), 0))
		ob.item_selected.connect(func(i): _heist_target = str(ids[i]))
		body.add_child(ob)
		var pb := Button.new()
		pb.text = "Start planning"
		pb.pressed.connect(func(): _cmd({"action": "plan", "target": _heist_target}))
		body.add_child(pb)
		_gear(pid)
		return
	var td: Dictionary = CrimeLifeHeist.target_def(str(h["target"]))
	line("Planning a job on %s." % str(td.get("label", "")), 14)
	var scene: String = str(h["scene"])
	line("Knowledge of the place: %s." % CrimeLifeCasing.word(CrimeLifeCasing.amount(pid, scene)), 12)
	for l in CrimeLifeCasing.report(pid, scene):
		line("  " + str(l), 11, UITheme.MUTED)
	var wb := Button.new()
	wb.text = "Watch the place"
	wb.pressed.connect(func(): _cmd({"action": "case", "target": scene}))
	body.add_child(wb)
	for e in h["crew"]:
		var row := HBoxContainer.new()
		body.add_child(row)
		row.add_child(UIU.make_label("%s - %s, %d%%" % [CrimePerson.name_of(int(e["pid"])), str((CrimeLifeHeist.cfg().get("roles", {})[e["role"]] as Dictionary).get("label", e["role"])), int(float(e["cut"]) * 100.0)], 12))
		var rb := Button.new()
		rb.text = "Drop"
		rb.pressed.connect(func(): _cmd({"action": "drop_crew", "heist": int(h["id"]), "pid": int(e["pid"])}))
		row.add_child(rb)
	for ct in CrimeLifeContacts.list(pid):
		if CrimeLifeHeist.crew_entry(h, int(ct["pid"])) != null or (h["crew"] as Array).size() >= int(CrimeLifeHeist.cfg().get("crew_max", 4)):
			continue
		var rowc := HBoxContainer.new()
		body.add_child(rowc)
		var role: String = str(ct["role"]) if str(ct["role"]) != "fence" else "lookout"
		var roles: Dictionary = CrimeLifeHeist.cfg().get("roles", {})
		var rbn := Button.new()
		rbn.text = "Ask %s to join as %s" % [CrimePerson.name_of(int(ct["pid"])), str((roles[role] as Dictionary).get("label", role)).to_lower()]
		rbn.pressed.connect(func(): _cmd({"action": "recruit", "heist": int(h["id"]), "pid": int(ct["pid"]), "role": role, "cut": float(CrimeLifeHeist.cfg().get("cut_default", 0.15))}))
		rowc.add_child(rbn)
	var ph: Dictionary = CrimeLifeHeistRun.phases(h)
	line("Getting in %s. Getting the vault open %s. Getting away %s." % [_w(float(ph["entry"])), _w(float(ph["vault"])), _w(float(ph["escape"]))], 12)
	var gb := Button.new()
	gb.text = "Use a stolen car as the getaway car" if not bool(h["getaway"]) else "Getaway car ready"
	gb.disabled = bool(h["getaway"])
	gb.pressed.connect(func(): _cmd({"action": "getaway", "heist": int(h["id"])}))
	body.add_child(gb)
	_gear(pid)
	var why: String = CrimeLifeHeist.missing(h)
	if why != "":
		line(why, 12, UITheme.MUTED)
	var row2 := HBoxContainer.new()
	body.add_child(row2)
	var go := Button.new()
	go.text = "Do the job"
	go.disabled = why != ""
	go.pressed.connect(func(): _cmd({"action": "go", "heist": int(h["id"])}))
	row2.add_child(go)
	var ab := Button.new()
	ab.text = "Call it off"
	ab.pressed.connect(func(): _cmd({"action": "abort"}))
	row2.add_child(ab)

static func _w(p: float) -> String:
	return "looks sure" if p >= 0.85 else ("is likely" if p >= 0.65 else ("is chancy" if p >= 0.4 else "is a long shot"))

func _gear(pid: int) -> void:
	var row := HFlowContainer.new()
	body.add_child(row)
	for gid in CrimeLifeRoll.gear_cfg():
		if CrimeLifeRoll.has_gear(pid, str(gid)):
			continue
		var g: Dictionary = CrimeLifeRoll.gear_cfg()[gid]
		var b := Button.new()
		b.text = "%s (%d)" % [str(g["label"]), int(g["price"])]
		b.pressed.connect(func(): _cmd({"action": "gear", "gear": str(gid)}))
		row.add_child(b)

func _stash(pid: int) -> void:
	var items: Array = CrimeLifeFence.items_of(pid)
	heading("Stolen goods")
	if items.is_empty():
		line("Nothing hidden away.", 12, UITheme.MUTED)
		return
	for it in items:
		line("%s (worth about %d)" % [str(it["name"]), int(it["value"])], 12)
	line("Hidden at home, the police may find it if you become a suspect. A fence pays a fraction but a sale can be traced.", 11, UITheme.MUTED)
	var fences: Array = CrimeLifeFence.fences_for(pid)
	for fp in fences:
		var b := Button.new()
		b.text = "Sell it all to %s" % CrimePerson.name_of(int(fp))
		b.pressed.connect(func(): _cmd({"action": "fence", "ids": [], "fence_pid": int(fp)}))
		body.add_child(b)
	var sb := Button.new()
	sb.text = "Sell it on the street (worst price, easiest to trace)"
	sb.pressed.connect(func(): _cmd({"action": "fence", "ids": [], "fence_pid": -1}))
	body.add_child(sb)

func _contacts(pid: int) -> void:
	heading("People you know")
	var list: Array = CrimeLifeContacts.list(pid)
	if list.is_empty():
		line("Nobody yet. Choose Ask Around (Underworld) on a townie who might know people.", 12, UITheme.MUTED)
	for ct in list:
		line("%s - %s" % [CrimePerson.name_of(int(ct["pid"])), "a fence" if str(ct["role"]) == "fence" else str((CrimeLifeHeist.cfg().get("roles", {})[ct["role"]] as Dictionary).get("label", ct["role"])).to_lower()], 12)

func _ledger(pid: int) -> void:
	var rows: Array = CrimeLifeMoral.ledger_of(pid)
	if rows.is_empty():
		return
	var t: Dictionary = CrimeLifeMoral.totals(pid)
	heading("Who paid for it")
	line("%d people have lost %d coins because of %s." % [int(t["victims"]), int(t["loss"]), CrimePerson.name_of(pid)], 12)
	for r in rows.slice(maxi(rows.size() - 4, 0)):
		line(CrimeLifeMoral.line(r), 11, UITheme.MUTED)
