extends SceneTree
## Not a unit test: every object def laid out on an empty lot, shot from the 4 camera rotations (+ optional folk seated/lying on them).
## godot --path . --resolution 1600x900 --script res://tests/gallery_shot.gd -- out_prefix [zoom] [rows_start]
var _main: Node = null

func _initialize() -> void:
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://gal"
	var zoom := float(args[1]) if args.size() > 1 else 11.0
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	_main.start_new_game(_main.default_household())
	await _frames(10)
	var W = root.get_node("World")
	W.reset(44, 30)
	var ids: Array = []
	for k in W.defs.keys():
		var d: Dictionary = W.defs[k]
		if str(d.get("mount", "")) == "wall":
			continue
		ids.append(k)
	ids.sort()
	var i := 0
	for k in ids:
		var s: Array = W.defs[k].get("size", [1, 1])
		var col := i % 9
		var row := i / 9
		W.place_object(k, Vector2i(3 + col * 4, 3 + row * 4), 0)
		i += 1
	print("placed ", i, " of ", ids.size())
	var lv = _main.lot_view
	_main.hud.visible = false
	root.get_node("Clock").set_speed(0)
	Weather.force("sunny", 0.0)
	root.get_node("Clock").total_minutes = 12 * 60
	lv.focus_tile(Vector2i(22, 15))
	lv.set_zoom(zoom)
	for r in 4:
		if r > 0:
			lv.rotate_camera(1)
		await create_timer(1.2).timeout
		root.get_texture().get_image().save_png("%s_%d.png" % [prefix, r])
		print("saved ", r)
	quit(0)
