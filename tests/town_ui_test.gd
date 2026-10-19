extends RefCounted
## Task 12b: the Town panel. It shows the mayor, the budget as sliders the player can see but only the mayor can move (through the command layer), the next election, the projects,
## outages with the time left and the bus times; the storyteller slot is there.

const Kit = preload("res://tests/hood_kit.gd")

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

func _find(n: Node, nm: String) -> Node:
	if str(n.name) == nm:
		return n
	for c in n.get_children():
		var r: Node = _find(c, nm)
		if r != null:
			return r
	return null

func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("small")
	StoryPacing.enabled = false
	CityState.reset()
	UtilityEvents.dice_on = false
	Story.generate_townies()
	CityGov.install()
	CityGov.ensure()
	var mira: Folk = folk[0]
	CityPlan.projects.append({"id": 1, "zone": "east", "plot": "plot_1", "kind": "civic", "state": "scaffold", "start": 1, "scaffold_end": 5, "ready": 15, "workers": 0})
	Utilities.begin("power", CityState.zone_of_household(1), 3.0, "fault")
	var dlg := TownDialog.new()
	Kit.root().add_child(dlg)
	dlg.show_for(int(mira.id))
	var txt: String = _all_text(dlg)
	_check(txt.contains("Mayor " + str(CityGov.mayor["name"])), "the mayor is named")
	_check(txt.contains("Taxes:") and txt.contains("percent"), "taxes are shown")
	_check(_find(dlg, "TaxSlider") != null and _find(dlg, "Alloc_fire") != null and _find(dlg, "Alloc_police") != null, "taxes and every part of the budget are sliders")
	_check(not (_find(dlg, "TaxSlider") as HSlider).editable and not (_find(dlg, "Alloc_fire") as HSlider).editable, "a folk who is not the mayor can see the sliders but not move them")
	_check(txt.contains("next election") or txt.contains("campaign"), "the next election is shown")
	_check(txt.contains("Scaffolding is up"), "the project is listed")
	_check(txt.contains("off in") and txt.contains("Back in about"), "an outage shows what and how long")
	_check(txt.contains("Next buses at") or txt.contains("No bus stops"), "bus times are shown")
	_check(_find(dlg, "StorytellerSlot") != null, "the storyteller slot is there")
	# the command layer refuses a non-mayor and accepts the mayor
	var tax0: float = CityGov.tax
	var res: Dictionary = Commands.run({"player_id": 1, "folk_id": int(mira.id), "action": "city", "args": {"action": "set_tax", "args": {"value": 1.4}}})
	_check(not bool(res.get("ok", false)) and is_equal_approx(CityGov.tax, tax0), "taxes cannot be changed by a folk who is not the mayor")
	CityGov.mayor["player"] = true
	CityGov.mayor["id"] = int(mira.id)
	dlg.refresh()
	var sl: HSlider = _find(dlg, "TaxSlider") as HSlider
	_check(sl.editable, "the mayor's sliders can be moved")
	sl.value = 1.4
	_check(is_equal_approx(CityGov.tax, 1.4), "moving the tax slider changes the tax through the command layer (%.2f)" % CityGov.tax)
	var fire0: float = float(CityGov.alloc["fire"])
	dlg.refresh()
	var fs: HSlider = _find(dlg, "Alloc_fire") as HSlider
	fs.value = fire0 + 0.05
	_check(float(CityGov.alloc["fire"]) > fire0 + 0.03, "moving a budget slider gives that service more (%.3f -> %.3f)" % [fire0, float(CityGov.alloc["fire"])])
	dlg.get_parent().remove_child(dlg)
	dlg.free()
	Kit.teardown()
	return fails
