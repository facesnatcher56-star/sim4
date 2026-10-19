extends RefCounted
## Task 22: the holiday dialog builds, lists the destinations, shows a live price and leave warnings, books through the command door, shows a trip
## in progress with the cruise route and the go-ashore buttons, and the "Plan a Holiday" interaction opens it (game event vacation_open_booking).

const K = preload("res://tests/vacation_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _all_text(n: Node) -> String:
	var s: String = ""
	if n is Label:
		s += (n as Label).text + "\n"
	elif n is Button:
		s += (n as Button).text + "\n"
	for c in n.get_children():
		s += _all_text(c)
	return s

func run() -> Array:
	fails = []
	var folk: Array = K.new_game("small")
	var mira: Folk = folk[0]
	Careers.hire(mira, "coder", 1)
	var dlg := VacationDialog.new()
	K.Kit.root().add_child(dlg)
	dlg.show_for(int(mira.id))
	var txt: String = _all_text(dlg)
	_check(txt.contains("Sunny Cove") and txt.contains("Pinecrest") and txt.contains("Harbour City") and txt.contains("Fernhollow") and txt.contains("Starlight"), "all five holidays are offered")
	_check(txt.contains("Total") and txt.contains("coins"), "a live price is shown")
	_check(txt.contains("house-sitter"), "the house-sitter option is offered")
	_check(txt.contains("work days off"), "work leave is explained for a working folk (%s)" % txt.substr(0, 40))
	dlg.dest = "cruise"
	dlg.days = 4
	dlg.refresh()
	txt = _all_text(dlg)
	_check(txt.contains("Ocean-view") or txt.contains("Inside cabin"), "cruise cabin classes shown")
	_check(txt.contains("Standard cruise"), "packages shown")
	K.Kit.set_time(6, 8, 0)                             # a Saturday: nobody is out at work, so the departure is not postponed`n	# book through the command door
	var res: Dictionary = Vacation.command({"player_id": 1, "folk_id": int(mira.id), "action": "book", "args": dlg._book_args(), "game_minute": SysUtil.now()})
	_check(bool(res["ok"]), "booked through Vacation.command: %s" % str(res.get("reason", "")))
	dlg.refresh()
	txt = _all_text(dlg)
	_check(txt.to_lower().contains("starlight voyager") and txt.contains("Booked"), "the dialog shows the booked trip")
	K.run(70)
	dlg.refresh()
	txt = _all_text(dlg)
	_check(txt.to_lower().contains("route") and txt.contains("Sail from home"), "the cruise route is shown once aboard")
	# the interaction opens it
	var got: Array = []
	var cb: Callable = func(n, p): if n == "vacation_open_booking": got.append(p)
	Events.game_event.connect(cb)
	SysUtil.game_event("plan_vacation", {"folk_id": int(folk[1].id)})
	Events.game_event.disconnect(cb)
	_check(got.size() == 1 and int(got[0]["folk_id"]) == int(folk[1].id), "'Plan a Holiday' asks the HUD to open the booking")
	var def: Dictionary = SimEnv.data().interaction_def("plan_vacation")
	_check(not def.is_empty() and (SimEnv.data().object_def("computer").get("interactions", []) as Array).has("plan_vacation"), "computers offer Plan a Holiday")
	_check((SimEnv.data().object_def("travel_desk").get("interactions", []) as Array).has("plan_vacation"), "so does the travel desk")
	dlg.queue_free()
	K.teardown()
	return fails
