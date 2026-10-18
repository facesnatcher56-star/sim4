extends RefCounted
## Case prompt (queue, default on Esc/close), case board (rows, visit button), the F10 action and the folk panel status chips.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_prompt(f)
	_board(f)
	return f

func _prompt(f: Array) -> void:
	var w := C.town(10)
	var p := CasePrompt.new()
	Engine.get_main_loop().root.add_child(p)
	var got: Array = []
	var got2: Array = []
	p.ask(1, "Robbery!", "A stranger demands your coins.", [{"id": "hand", "label": "Hand it over"}, {"id": "run", "label": "Run"}], func(c): got.append(c), "hand")
	p.ask(1, "Bail", "Pay?", [{"id": "pay", "label": "Pay"}, {"id": "stay", "label": "Stay"}], func(c): got2.append(c), "pay")
	K.expect(f, p.visible and p.title_label.text == "Robbery!", "the first prompt is shown")
	var buttons: int = 0
	for ch in p.body.get_children():
		if ch is Button:
			buttons += 1
	K.expect(f, buttons == 2, "one button per choice")
	p._pick("run")
	K.expect(f, got == ["run"] and p.visible and p.title_label.text == "Bail", "choosing answers it and the next prompt follows")
	p.hide_dialog()
	K.expect(f, got2 == ["pay"] and not p.visible, "closing a prompt picks its default")
	# wiring: JusticePlayer.ask uses the dialog
	JusticePlayer.ask_fn = p.ask
	var seen: Array = []
	JusticePlayer.ask(1, "Hello", "Text", [{"id": "ok", "label": "OK"}], func(c): seen.append(c), "ok")
	K.expect(f, p.visible and seen.is_empty(), "JusticePlayer.ask shows the dialog for a player folk")
	p._pick("ok")
	K.expect(f, seen == ["ok"], "and the answer comes back")
	JusticePlayer.ask_fn = Callable()
	p.queue_free()
	K.teardown()

func _board(f: Array) -> void:
	var w := C.town(10)
	CaseBoard.ensure_action()
	K.expect(f, InputMap.has_action(CaseBoard.ACTION), "F10 action exists")
	var b := CaseBoard.new()
	Engine.get_main_loop().root.add_child(b)
	var ids: Array = C.adults()
	var c: Dictionary = CaseStore.create("burglary", int(ids[0]), -1, "town:2", {})
	CaseDiscovery.report(c, int(ids[1]), "noticed")
	var m: Dictionary = CaseStore.create("murder", int(ids[2]), int(ids[3]), "street", {})
	m["state"] = "closed"
	m["verdict"] = "guilty"
	RelationshipService.add_both(1, int(ids[4]), "friendship", 50.0)
	var c3: Dictionary = CaseStore.create("robbery", int(ids[4]), -1, "street", {})
	Prison.admit(int(ids[4]), c3, 12, "prison")
	b.show_for(1)
	var text: String = ""
	for ch in b.body.get_children():
		if ch is Label:
			text += (ch as Label).text + "\n"
		elif ch is HBoxContainer:
			for g in ch.get_children():
				if g is Label:
					text += (g as Label).text + "\n"
	K.expect(f, text.find("Police case board") >= 0 or b.title_label.text == "Police case board", "board has a title")
	K.expect(f, text.find("Crime in town") >= 0 and text.find("Break-in") >= 0, "board lists the open burglary")
	K.expect(f, text.find("found guilty") >= 0 and text.find("prison") >= 0, "board shows verdicts and the prisoner")
	var visit: int = 0
	for ch in b.body.get_children():
		if ch is HBoxContainer:
			for g in ch.get_children():
				if g is Button and (g as Button).text == "Visit":
					visit += 1
	K.expect(f, visit == 1, "a Visit button for a prisoner the household knows")
	b.queue_free()
	var chips: Array = JusticePlayer.status_chips(w.get_folk(1))
	K.expect(f, chips.is_empty(), "no status chips for a free folk")
	JusticeState.probation[1] = SysUtil.day() + 5
	K.expect(f, JusticePlayer.status_chips(w.get_folk(1)).size() == 1, "probation shows as a chip")
	K.teardown()
