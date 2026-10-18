extends SceneTree
## Not a unit test: folk of every age on every seat / bed type, in rows, close-up from the 4 camera rotations.
## godot --path . --resolution 1600x900 --script res://tests/furniture_shot.gd -- out_prefix [zoom]
var _main: Node = null

# [interaction, def, age stage]
const CASES := [
	["sleep_bed", "single_bed", "adult"], ["sleep_bed", "bed", "adult"], ["sleep_bed", "bunk_bed", "child"],
	["crib_sleep", "crib", "baby"], ["sit_chair", "chair", "adult"], ["sit_chair", "dining_chair", "child"],
	["sit_chair", "bar_stool", "adult"], ["sit_sofa", "sofa", "adult"], ["sit_sofa", "sofa", "toddler"],
	["sit_armchair", "armchair", "elder"], ["read_armchair", "armchair", "teen"], ["soak_hot_tub", "hot_tub", "adult"],
	["play_piano", "piano", "adult"], ["do_homework", "desk", "child"], ["use_toilet", "toilet", "adult"],
	["take_bath", "bathtub", "adult"], ["nap_sofa", "sofa", "adult"], ["sit_chair", "chair", "toddler"],
]

func _initialize() -> void:
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "user://fur"
	var zoom := float(args[1]) if args.size() > 1 else 9.0
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	_main.start_new_game(_main.default_household())
	await _frames(10)
	var W = root.get_node("World")
	var clock = root.get_node("Clock")
	for f in W.all_folk().duplicate():
		W.remove_folk(f.id)
	W.reset(30, 20)
	var i := 0
	var fids: Array = []
	for c in CASES:
		var col := i % 6
		var row := i / 6
		var t := Vector2i(3 + col * 4, 3 + row * 5)
		var oid: int = W.place_object(c[1], t, 0)
		var f := Folk.create("F%d" % i)
		f.age_stage = c[2]
		f.idle_until_min = 1 << 30
		W.add_folk(f, t + Vector2i(0, 2))
		fids.append([f.id, oid, c[0]])
		i += 1
	await _frames(10)
	for e in fids:
		var f = W.get_folk(e[0])
		for n in f.needs:
			f.needs[n].set_value(10.0)
		var ir := Interaction.create(e[2], f, e[1], true)
		if ir == null:
			print("cannot create ", e[2])
			continue
		f.enqueue(ir)
		root.get_node("SimDirector")._fill(f)
	for k in 30:
		var all_on := true
		for e in fids:
			var f = W.get_folk(e[0])
			if f.current == null or str(f.current.state) != "running":
				all_on = false
		if all_on:
			break
		clock.advance_minutes(1)
		await _frames(2)
	var lv = _main.lot_view
	_main.hud.visible = false
	clock.set_speed(1)
	Weather.force("sunny", 0.0)
	clock.total_minutes = 12 * 60
	lv.focus_tile(Vector2i(14, 8))
	lv.set_zoom(zoom)
	await create_timer(8.0).timeout
	for e in fids:
		var f = W.get_folk(e[0])
		var fvv = _main.lot_view.get_folk_view(e[0])
		print(f.name, " clip=", fvv.clip, " pose=", fvv.pose, " pos=", fvv.position, " ", e[2], " cur=", (f.current.def_id if f.current != null else "-"), " state=", (str(f.current.state) if f.current != null else "-"))
	for r in 4:
		if r > 0:
			lv.rotate_camera(1)
		await create_timer(1.5).timeout
		root.get_texture().get_image().save_png("%s_%d.png" % [prefix, r])
		print("saved ", r)
	for k in range(2, args.size()):       # extra close-ups: "x,y" tile
		var xy: PackedStringArray = args[k].split(",")
		lv.focus_tile(Vector2i(int(xy[0]), int(xy[1])))
		lv.set_zoom(4.5)
		await create_timer(1.0).timeout
		root.get_texture().get_image().save_png("%s_c%d.png" % [prefix, k - 2])
	quit(0)
