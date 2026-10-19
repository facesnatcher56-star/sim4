extends RefCounted
## Task 21 UI: the Security and Underworld dialogs (opened from the case board). Content in plain words, buttons go through the command layer.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_security(f)
	_underworld(f)
	_board_buttons(f)
	return f

func _texts(d: Control) -> String:
	var out: Array = []
	var stack: Array = [d]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			out.append((n as Label).text)
		elif n is Button:
			out.append("[" + (n as Button).text + "]")
		for ch in n.get_children():
			stack.append(ch)
	return "\n".join(out)

func _buttons(d: Control, fragment: String) -> Array:
	var out: Array = []
	var stack: Array = [d]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text.contains(fragment):
			out.append(n)
		for ch in n.get_children():
			stack.append(ch)
	return out

func _security(f: Array) -> void:
	var w := C.town(8)
	w.add_object("burglar_alarm", Vector2i(10, 14))
	w.add_object("security_camera", Vector2i(11, 14))
	Economy.refresh_objects()
	var b: Dictionary = BusinessState.make("cafe", "cafe", "own", "player", 1, "Ada's Cafe")
	var d := SecurityDialog.new()
	Engine.get_main_loop().root.add_child(d)
	d.show_for(1)
	var t: String = _texts(d)
	K.expect(f, t.contains("alarm") and t.contains("camera"), "the dialog describes the cover at home")
	K.expect(f, t.contains("Alarm monitoring") and t.contains("Hire a guard"), "services are offered")
	K.expect(f, t.contains("Ada's Cafe") and t.contains("Security camera"), "owned businesses get upgrades")
	WorldIface.coins[1] = 1000
	var mon: Array = _buttons(d, "Alarm monitoring: police")
	(mon[0] as Button).pressed.emit()
	K.expect(f, bool(CrimeSecurity.home_profile(1)["monitored"]), "pressing the button buys monitoring through the command layer")
	K.expect(f, _texts(d).contains("Stop alarm monitoring"), "and the dialog refreshes")
	var cam: Array = _buttons(d, "Security camera")
	(cam[0] as Button).pressed.emit()
	K.expect(f, CrimeSecurityUpgrade.level_of_biz(int(b["id"]), "camera") == 1, "a business upgrade can be bought from it")
	d.queue_free()
	K.teardown()

func _underworld(f: Array) -> void:
	var w := C.town(12)
	var d := UnderworldDialog.new()
	Engine.get_main_loop().root.add_child(d)
	d.show_for(1)
	K.expect(f, _texts(d).contains("Take up the criminal life"), "the path starts with a plain invitation, not a menu of crimes")
	(_buttons(d, "Take up")[0] as Button).pressed.emit()
	K.expect(f, CrimeLifePath.is_member(1), "joining works from the dialog")
	var t: String = _texts(d)
	K.expect(f, t.contains("Petty thief") and t.contains("Pick a pocket") and t.contains("Shoplift"), "ranks and the first jobs show up")
	K.expect(f, not t.contains("Rob a shop"), "bigger jobs wait for a higher rank")
	K.expect(f, t.contains("Next: Burglar"), "and the next rank says what it needs: %s" % t.get_slice("Next:", 1).get_slice("\n", 0))
	K.expect(f, t.contains("looks easy") or t.contains("doable") or t.contains("risky") or t.contains("long shot"), "odds are in plain words")
	var go: Array = _buttons(d, "Go")
	K.expect(f, not go.is_empty(), "each job has a Go button")
	CrimeLifePath.member(1)["rank"] = "burglar"
	CrimeLifePath.member(1)["jobs"] = 6
	CrimeLifePath.member(1)["cred"] = 30.0
	w.get_folk(1).add_skill_xp("stealth", 1500.0)
	d.refresh()
	t = _texts(d)
	K.expect(f, t.contains("Start planning") and t.contains("Watch it"), "burglars can plan and watch places")
	(_buttons(d, "Start planning")[0] as Button).pressed.emit()
	t = _texts(d)
	K.expect(f, t.contains("Planning a job") and t.contains("Knowledge of the place"), "a plan screen follows")
	K.expect(f, t.contains("Getting in"), "with the three phases in words")
	CrimeLifeFence.add_stash(1, "burglary", 300, -1, false)
	d.refresh()
	K.expect(f, _texts(d).contains("Sell it on the street"), "stolen goods can be sold")
	d.queue_free()
	K.teardown()

func _board_buttons(f: Array) -> void:
	var w := C.town(8)
	CaseBoard.ensure_action()
	var b := CaseBoard.new()
	Engine.get_main_loop().root.add_child(b)
	b.show_for(1)
	var t: String = _texts(b)
	K.expect(f, t.contains("Security of your home") and t.contains("The criminal life"), "the case board links to both screens")
	(_buttons(b, "Security of your home")[0] as Button).pressed.emit()
	var found: bool = false
	for c in b.get_parent().get_children():
		if c is SecurityDialog and (c as SecurityDialog).visible:
			found = true
	K.expect(f, found, "pressing it opens the security dialog")
	for c in b.get_parent().get_children():
		if c is SecurityDialog:
			c.queue_free()
	b.queue_free()
	K.teardown()
