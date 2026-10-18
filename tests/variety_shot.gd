extends SceneTree
## Not a unit test: windowed screenshots that check people read as different folk from the iso camera.
## godot --path . --resolution 1600x900 --script res://tests/variety_shot.gd -- out_prefix [lineup|crowd|stages|close]
## lineup: 16 unique adults in a row at normal zoom; crowd: the cafe with its crowd + staff; stages: every age group;
## close: a zoomed row (detail check).
var _prefix := "user://variety"
var _main: Node = null
const PARTS := [{"bag": 1}, {"bag": 2}, {"top": 1, "bottom": 1}, {"top": 2}, {"top": 3, "bottom": 2}, {"top": 4}, {"top": 5, "hat": 1}, {"top": 6, "scarf": 1}, {"hat": 2, "glasses": 1}, {"facial_hair": 3}, {"facial_hair": 2, "mark": 1}, {"hair_style": 11}, {"hair_style": 8, "mark": 2}, {"hair_style": 12, "glasses": 2}]


func _initialize() -> void:
	_run()


func _secs(s: float) -> void:
	await create_timer(s).timeout


func _save(name: String) -> void:
	var p := "%s_%s.png" % [_prefix, name]
	root.get_texture().get_image().save_png(p)
	print("saved ", p)


func _row(n: int, x0: int, y: int, stage: String, others: Array) -> Array:
	var W = root.get_node("World")
	var g := RandomNumberGenerator.new()
	g.seed = 4242
	var ids: Array = []
	for i in n:
		var nf := Folk.create("Folk%d" % i)
		nf.age_stage = stage
		nf.appearance = Genetics.unique_appearance(others, g)
		others.append(nf.appearance)
		nf.idle_until_min = 1 << 30
		W.add_folk(nf, Vector2i(x0 + i, y))
		ids.append(nf.id)
	return ids


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	var mode: String = args[1] if args.size() > 1 else "lineup"
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _secs(0.5)
	var W = root.get_node("World")
	var lv = null
	if mode == "crowd":
		_main.start_new_game(_main.default_household(), "medium")
		root.get_node("Clock").total_minutes = 1440 + 12 * 60
		await _secs(1.0)
		var ids: Array = []
		for f in SysUtil.residents():
			ids.append(int(f.id))
		Neighborhood.travel(ids, "cafe", {"instant": true})
		var clock = root.get_node("Clock")
		for i in 60:
			clock.advance_minutes(1)
		lv = _main.lot_view
		lv.set_zoom(float(args[2]) if args.size() > 2 else 12.0)
		lv.focus_tile(Vector2i(15, 11))
		await _secs(1.5)
		print("crowd ", Crowd.count(), " staff ", Crowd.staff_folk().size())
		_save("crowd")
		quit(0)
		return
	_main.start_new_game(_main.default_household())
	await _secs(1.0)
	for f in W.all_folk():
		f.idle_until_min = 1 << 30
	_main.hud.visible = false
	lv = _main.lot_view
	var others: Array = []
	for f in W.all_folk():
		others.append(f.appearance)
	if mode == "previews":
		var grid := GridContainer.new()
		grid.columns = 7
		var bg := ColorRect.new()
		bg.color = Color(0.5, 0.6, 0.5)
		bg.size = Vector2(1600, 900)
		root.add_child(bg)
		root.add_child(grid)
		var g := RandomNumberGenerator.new()
		g.seed = int(args[2]) if args.size() > 2 and args[2].is_valid_int() else 1
		var loth: Array = []
		var rot: float = PI + 0.35 + (PI if args.size() > 3 and args[3] == "back" else 0.0)
		var mode2: String = args[2] if args.size() > 2 and args[2] == "parts" else ""
		for i in 14:
			var pv: Control = load("res://scripts/ui/folk_preview.gd").new()
			pv.custom_minimum_size = Vector2(228, 440)
			grid.add_child(pv)
			var ap: Dictionary = Genetics.unique_appearance(loth, g)
			loth.append(ap)
			if mode2 == "parts":
				ap = Genetics.neutral_appearance()
				ap.merge(PARTS[i], true)
			pv.show_folk("adult", ap)
			pv._pivot.rotation.y = rot
		await _secs(0.5)
		for pv in grid.get_children():
			pv.set_process(false)
		await _secs(0.3)
		_save("previews")
		quit(0)
		return
	match mode:
		"lineup", "close":
			_row(8, 12, 19, "adult", others)
			_row(8, 12, 21, "adult", others)
			await _secs(1.5)
			lv.focus_tile(Vector2i(16, 20))
			lv.set_zoom(7.0 if mode == "close" else 12.0)
			await _secs(1.0)
			_save(mode)
		"stages":
			var x := 12
			for st in ["baby", "toddler", "child", "teen", "adult", "elder"]:
				_row(2, x, 19, st, others)
				x += 3
			_row(6, 12, 21, "child", others)
			await _secs(1.5)
			lv.focus_tile(Vector2i(19, 20))
			lv.set_zoom(10.0)
			await _secs(1.0)
			_save("stages")
	quit(0)
