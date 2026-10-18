extends RefCounted
## UI flow test (headless): faces for every mood, toast policy, pie filtering, Goals / Career / Household / Help dialogs, Go Here, prefs.
const S = preload("res://tests/social_kit.gd")

func _labels(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		if c is Button:
			out.append("[" + (c as Button).text + "]")
		_labels(c, out)
	return out

func _joined(n: Node) -> String:
	return "\n".join(_labels(n))

func run() -> Array:
	var f: Array = []
	var root: Window = Engine.get_main_loop().root
	_faces(f)
	_toast_policy(f)
	_pie(f)
	var w := S.setup(902)
	var a := S.folk(w, "Ann", ["neat", "bookworm", "active"])
	var b := S.folk(w, "Bo", ["gamer"])
	_goals(f, root, a)
	_career(f, root, a)
	_household(f, root)
	_help(f, root)
	_go_here(f, w, a)
	_prefs(f)
	S.teardown()
	return f

func _faces(f: Array) -> void:
	for m in Emotions.mood_defs():
		S.expect(f, FaceIcon.LOOKS.has(str(m)), "face icon has an expression for mood '%s'" % m)
	S.expect(f, FolkPanel.mood_name("neutral") == "Calm", "neutral mood reads as Calm")
	S.expect(f, FolkPanel.mood_name("confident") == "Confident", "mood names are labels, not ids")

func _toast_policy(f: Array) -> void:
	var p := ToastPolicy.new()
	var r1: Dictionary = p.filter("Mira is a widow(er) now.", "death", 100.0)
	S.expect(f, r1["action"] == "show" and str(r1["text"]).find("widow(er)") < 0, "system wording is polished: %s" % r1["text"])
	S.expect(f, p.filter("Mira is a widow(er) now.", "death", 105.0)["action"] == "drop", "identical toast within 12s is dropped")
	S.expect(f, p.filter("Mira is a widow(er) now.", "death", 120.0)["action"] == "show", "identical toast shows again later")
	S.expect(f, p.filter("Ann got a job offer: x", "job_offer", 1.0)["action"] == "offer", "job offers go to the offer card")
	for i in 5:
		S.expect(f, p.filter("Mira fulfilled a whim: Eat something (+20)", "goal", 200.0 + i)["action"] == "whim", "whim toast collapses")
	S.expect(f, not p.whim_due(210.0) and p.whim_due(230.0), "whim digest is due after the quiet period")
	var d := p.take_whim_digest()
	S.expect(f, d.find("5 whims") >= 0 and d.find("+100") >= 0, "digest sums whims and points: %s" % d)
	S.expect(f, p.whim_count == 0, "digest resets")

func _pie(f: Array) -> void:
	var entries := [
		{"id": "a", "label": "Eat", "category": "Food", "enabled": true, "reason": ""},
		{"id": "b", "label": "Nap", "category": "Rest", "enabled": false, "reason": "Not tired enough"},
		{"id": "c", "label": "Kiss", "category": "Romantic", "enabled": false, "reason": "You are already together."},
		{"id": "d", "label": "Spar", "category": "Mean", "enabled": false, "reason": "not for kind Folk"},
	]
	var out := PieEntries.prepare(entries)
	S.expect(f, out.size() == 2, "never-available entries are hidden (got %d)" % out.size())
	S.expect(f, out[0]["id"] == "a" and out[1]["reason"] == "Not tired enough", "almost-available entries stay with their reason")
	S.expect(f, PieEntries.polish_reason("needs trait glutton") == "needs the Glutton trait", "trait ids become labels: %s" % PieEntries.polish_reason("needs trait glutton"))
	S.expect(f, PieEntries.polish_reason("not in the mood (hunger too high)") == "Not hungry enough", "need ids become words")
	PieEntries.remember("b")
	var out2 := PieEntries.prepare([{"id": "x", "label": "A", "category": "Fun", "enabled": true, "reason": ""}, {"id": "b", "label": "Z", "category": "Fun", "enabled": true, "reason": ""}])
	S.expect(f, out2[0]["id"] == "b", "recently used actions float to the top")
	PieEntries.recent.clear()
	S.expect(f, InteractionQuery.category_for({"kind": "super", "tags": ["food", "cook"]}) == "Food", "object interactions group by tag, never 'Super'")
	S.expect(f, InteractionQuery.category_for({"kind": "super", "tags": ["zzz"]}) == "Other", "unknown tag falls back to Other")

func _goals(f: Array, root: Window, a: Folk) -> void:
	var g := GoalsDialog.new()
	root.add_child(g)
	g.show_for(a.id)
	var txt := _joined(g)
	var info := Goals.active_for(a.id)
	S.expect(f, txt.find(str(info["aspiration_label"])) >= 0, "goals dialog shows the aspiration")
	S.expect(f, txt.to_lower().find("perk shop") >= 0 and txt.to_lower().find("whims") >= 0, "goals dialog has whims and the perk shop")
	var other := ""
	for aid in Goals.aspiration_ids():
		if str(aid) != str(info["aspiration"]):
			other = str(aid)
			break
	g.picking = true
	g.refresh()
	S.expect(f, _joined(g).find("Choose a different aspiration") >= 0 or _joined(g).find("Never mind") >= 0, "aspiration picker is reachable")
	Goals.set_aspiration(a.id, other)
	g.picking = false
	g.refresh()
	S.expect(f, _joined(g).find(Goals.aspiration_label(a.id)) >= 0, "dialog follows an aspiration change")
	S.expect(f, GoalsDialog.time_left_text(125) == "2h 05m left" and GoalsDialog.time_left_text(30) == "30 min left", "whim time text")
	g.queue_free()

func _career(f: Array, root: Window, a: Folk) -> void:
	var c := CareerDialog.new()
	root.add_child(c)
	c.show_for(a.id)
	S.expect(f, _joined(c).find("No job yet") >= 0, "jobless Folk sees how to find a job")
	Careers.make_offer(a, "cook", 1)
	c.refresh()
	var t := _joined(c)
	S.expect(f, t.find("[Accept]") >= 0 and t.find("[Decline]") >= 0, "pending offer shows Accept / Decline: %s" % t)
	Careers.accept_offer(a.id)
	c.refresh()
	t = _joined(c)
	S.expect(f, t.to_lower().find("performance") >= 0 and t.find("Skip work today") >= 0 and t.to_lower().find("next promotion") >= 0, "job panel shows performance, promotion and skip: %s" % t)
	S.expect(f, t.find("Skipping costs") >= 0, "skip warns about the penalty")
	S.expect(f, CareerDialog.nice_requirement("cooking 2") == "Cooking skill level 2", "requirements read as words")
	c.queue_free()
	Careers.quit_job(a)
	# offer card on the toast
	var o := OfferToast.new()
	root.add_child(o)
	Careers.make_offer(a, "cook", 1)
	o.show_offer(a.id)
	S.expect(f, o.visible and o.text_label.text.find("job offer") >= 0, "offer toast appears")
	o._answer(false)
	S.expect(f, not o.visible and Careers.pending_offer(a.id).is_empty(), "declining clears the offer")
	o.queue_free()

func _household(f: Array, root: Window) -> void:
	var h := HouseholdDialog.new()
	root.add_child(h)
	h.show_for(1)
	var t := _joined(h)
	S.expect(f, t.find("Coins") >= 0 and t.to_lower().find("bills") >= 0 and t.to_lower().find("last 7 days") >= 0, "household dialog: coins, bills, week: %s" % t)
	h.queue_free()

func _help(f: Array, root: Window) -> void:
	var h := HelpDialog.new()
	root.add_child(h)
	h.show_for(-1)
	var t := _joined(h)
	for key in ["W A S D", "Q / E", "Space", "1 / 2 / 3", "Ctrl+Z", "F1 or ?"]:
		S.expect(f, t.find(key) >= 0, "help lists '%s'" % key)
	h.queue_free()

func _go_here(f: Array, w, a: Folk) -> void:
	var dest := Vector2i(a.tile.x + 3, a.tile.y)
	var it := Interaction.create_goto(a, dest, true)
	S.expect(f, it != null, "go_here interaction can be created")
	if it == null:
		return
	S.expect(f, it.start(), "go_here starts")
	var n := 0
	while it.state != "finished" and it.state != "cancelled" and n < 60:
		it.tick(1.0)
		n += 1
	S.expect(f, it.state == "finished" and a.tile == dest, "Folk walked to the clicked tile (state %s, at %s)" % [it.state, str(a.tile)])
	S.expect(f, not (SimEnv.data().interaction_def("go_here").get("autonomous", true)), "go_here is never chosen by autonomy")

func _prefs(f: Array) -> void:
	UIPrefs.set_flag("test_flag_x", true)
	S.expect(f, UIPrefs.get_flag("test_flag_x", false), "prefs flag persists")
	UIPrefs.set_flag("test_flag_x", false)
	S.expect(f, FirstRunTips.TIPS.size() >= 3 and FirstRunTips.TIPS.size() <= 5, "3-5 first-run tips")
