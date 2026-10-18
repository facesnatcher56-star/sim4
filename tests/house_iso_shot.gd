extends SceneTree
## Not a unit test: in-game (isometric camera) screenshots of generated lots built into the real World.
## godot --path . --resolution 1600x900 --script res://tests/house_iso_shot.gd -- out_prefix id[:zoom[:rot]] ...   e.g. small_01 medium_03:14 large_02:18:1
const Kit = preload("res://tests/house_kit.gd")
var _main: Node = null

func _initialize() -> void:
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://iso"
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	_main.start_new_game(_main.default_household())
	await _frames(20)
	var clock = root.get_node("Clock")
	var W = root.get_node("World")
	clock.set_speed(0)
	NeighborhoodContent.install()
	var lv = _main.lot_view
	_main.hud.visible = false
	var cur_rot := 0
	for i in range(1, args.size()):
		var p: PackedStringArray = args[i].split(":")
		var t: Dictionary = HouseGenerator.template(p[0])
		if t.is_empty():
			print("unknown lot ", p[0])
			continue
		for f in W.all_folk().duplicate():
			W.remove_folk(f.id)
		Kit.apply(t, W)
		await _frames(10)
		var sh: Rect2i = Kit.shell_of(t)
		lv.set_zoom(float(p[1]) if p.size() > 1 else 16.0)
		var rot := int(p[2]) if p.size() > 2 else 0
		if rot != cur_rot:
			lv.rotate_camera(rot - cur_rot)
			cur_rot = rot
		lv.select("none", -1)
		lv.focus_tile(sh.position + sh.size / 2)
		await create_timer(1.0).timeout
		root.get_texture().get_image().save_png("%s_%s.png" % [prefix, p[0]])
		print("saved ", p[0])
	quit(0)
