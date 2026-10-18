extends SceneTree
## Not a unit test: windowed screenshots of the neighbourhood UI and venues.
## godot --path . --resolution 1600x900 --script res://tests/hood_shot.gd -- out_prefix
## Output: <prefix>_picker.png, _map.png, _cafe.png, _park.png, _gym.png, _library.png
var _prefix := "user://hood"
var _main: Node = null

func _initialize() -> void:
	_run()

func _secs(s: float) -> void:
	await create_timer(s).timeout

func _save(name: String) -> void:
	var p := "%s_%s.png" % [_prefix, name]
	root.get_texture().get_image().save_png(p)
	print("saved ", p)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _secs(0.5)
	# 1) lot picker over the title
	_main.picker.visible = true
	_main.title.visible = true
	await _secs(0.6)
	_save("picker")
	_main.picker.select("medium")
	await _secs(0.3)
	_save("picker_medium")
	# 2) start the game on the medium home
	_main.picker.visible = false
	_main.start_new_game(_main.default_household(), "medium")
	root.get_node("Clock").total_minutes = 1440 + 12 * 60       # Tuesday noon
	await _secs(1.0)
	var hud = _main.hud
	hud.travel_panel.open_panel()
	await _secs(0.5)
	_save("map")
	hud.travel_panel.select_lot("cafe")
	await _secs(0.3)
	_save("map_cafe")
	hud.travel_panel.close_panel()
	# 3) travel to the cafe with everyone
	var ids: Array = []
	for f in SysUtil.residents():
		ids.append(int(f.id))
	var clock = root.get_node("Clock")
	var res: Dictionary = Neighborhood.travel(ids, "cafe", {"instant": true})
	print("travel: ", res)
	for i in 40:
		clock.advance_minutes(1)
	_main.lot_view.set_zoom(14.0)
	_main.lot_view.focus_tile(Vector2i(15, 11))
	await _secs(1.2)
	for i in 20:
		clock.advance_minutes(1)
	await _secs(0.8)
	print("crowd: ", Crowd.count(), " staff: ", Crowd.staff_folk().size())
	_save("cafe")
	# park
	Neighborhood.travel(ids, "park", {"instant": true})
	for i in 40:
		clock.advance_minutes(1)
	_main.lot_view.set_zoom(16.0)
	_main.lot_view.focus_tile(Vector2i(15, 12))
	await _secs(1.2)
	_save("park")
	Neighborhood.travel(ids, "gym", {"instant": true, "free": true})
	for i in 40:
		clock.advance_minutes(1)
	_main.lot_view.set_zoom(14.0)
	_main.lot_view.focus_tile(Vector2i(15, 11))
	await _secs(1.2)
	_save("gym")
	Neighborhood.travel(ids, "library", {"instant": true})
	for i in 40:
		clock.advance_minutes(1)
	_main.lot_view.focus_tile(Vector2i(15, 11))
	await _secs(1.2)
	_save("library")
	hud.travel_panel.open_panel()
	await _secs(0.5)
	_save("map_away")
	quit(0)
