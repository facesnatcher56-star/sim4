extends RefCounted
## The "Go to..." panel on the one map: open / closed + walking minutes from the selected folk, who is where (derived from
## tiles), Go walks (a go_here to the lot's door), Fast travel hides the folk for a short trip, a click on a lot moves the camera.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("small")
	var mira: Folk = folk[0]
	Neighborhood.selected = mira.id
	Kit.set_time(2, 12)
	WorldIface.coins[1] = 500
	var panel := TravelPanel.new()
	Kit.root().add_child(panel)
	panel.open_panel()
	_check(panel.is_open() and panel.tiles.size() == 19, "panel lists the 19 lots (%d)" % panel.tiles.size())
	var cafe_txt: String = (panel.tiles["cafe"] as Button).text
	_check(cafe_txt.find("Open") >= 0 and cafe_txt.find("min walk") >= 0, "cafe tile: open + walking time (%s)" % cafe_txt.replace("\n", " | "))
	_check((panel.tiles["home"] as Button).text.find("You are here") >= 0, "home tile says you are here")
	_check(panel.where_label.text.find("Mira") >= 0 and panel.where_label.text.find("Home") >= 0, "header: %s" % panel.where_label.text)
	Kit.set_time(2, 3)
	panel.refresh()
	_check((panel.tiles["cafe"] as Button).text.find("Closed") >= 0, "closed at 03:00")
	Kit.set_time(2, 12)
	panel.select_lot("cafe")
	_check(panel.travel_button.text.find("Go (") >= 0 and not panel.travel_button.disabled, "Go button with minutes: %s" % panel.travel_button.text)
	var walk_min: int = int(panel.travel_button.text.get_slice("(", 1).get_slice(" ", 0))
	panel.fast_check.button_pressed = true
	panel.refresh()
	var fast_min: int = int(panel.travel_button.text.get_slice("(", 1).get_slice(" ", 0))
	_check(fast_min != walk_min and fast_min >= 5, "fast travel shows its own time (%d vs walking %d)" % [fast_min, walk_min])
	panel.fast_check.button_pressed = false
	var res: Dictionary = panel.do_travel("cafe")
	_check(bool(res["ok"]) and not mira.has_meta("away") and Neighborhood.heading_to(mira.id) == "cafe", "Go sends the folk walking")
	Kit.run(int(res["minutes"]) + 12)
	_check(Neighborhood.where(mira.id) == "cafe", "walked to the cafe")
	panel.refresh()
	_check((panel.tiles["cafe"] as Button).text.find("You are here") >= 0 and (panel.tiles["cafe"] as Button).text.find("of yours") >= 0, "cafe tile shows the household")
	var home_btn_visible: bool = panel.home_button.visible
	_check(home_btn_visible, "Go Home is offered")
	panel.fast_check.button_pressed = true
	panel._on_home()
	_check(mira.has_meta("away") and Neighborhood.where(mira.id) == "home", "fast Go Home hides the folk and puts it at the door")
	panel.queue_free()
	Kit.teardown()
	return fails