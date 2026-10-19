extends SceneTree
## Not a unit test: windowed close-ups of the task-27b hand props (family seed 101 home): reading in the armchair, typing at the computer and writing at
## the desk (both seated on their chair), eating at the table, the shower with somebody talking to the showerer.
## godot --path . --resolution 1280x720 --script res://tests/visual27b_shot.gd -- docs/visual27/closeup
var _prefix := "user://v27"
var _main: Node = null


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


var _home := Vector2i.ZERO


## The object of that kind nearest to the household (the home, not a venue across town).
func _obj(def_id: String, nth: int = 0) -> int:
	var best := -1
	var best_d := 1 << 30
	for o in root.get_node("World").objects_of_def(def_id):
		var d: int = absi(o.tile.x - _home.x) + absi(o.tile.y - _home.y)
		if d < best_d:
			best_d = d
			best = o.id
	return best


func _cmd(fid: int, iid: String, target: int) -> bool:
	var f = root.get_node("World").get_folk(fid)
	for n in ["energy", "hygiene", "bladder", "social", "hunger", "fun"]:
		if f.needs.has(n):
			f.needs[n].set_value(10.0)
	var ir := Interaction.create(iid, f, target, true)
	if ir == null:
		return false
	f.idle_until_min = 0
	f.enqueue(ir)
	root.get_node("SimDirector")._fill(f)
	return true


func _until_running(fid: int) -> void:
	var f = root.get_node("World").get_folk(fid)
	for i in 80:
		if f.current != null and str(f.current.state) == "running":
			return
		root.get_node("Clock").advance_minutes(1)


func _shot(name: String, fid: int, zoom: float) -> void:
	var lv = _main.lot_view
	lv.set_zoom(zoom)
	var fv = lv.get_folk_view(fid)
	if fv != null:
		lv.focus_tile(root.get_node("World").pos_to_tile(fv.position))
	await _secs(1.2)
	var p := "%s_%s.png" % [_prefix, name]
	root.get_texture().get_image().save_png(p)
	var f = root.get_node("World").get_folk(fid)
	print("saved %s: %s %s pose %s clip %s" % [p, f.name, str(f.current.def_id) if f.current != null else "-", str(fv.pose), str(fv.clip)])


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	var r := RandomNumberGenerator.new()
	r.seed = 101
	_main.start_new_game(HouseholdSetup.make_household("family", r), str(Scenario.def("family").get("start_id", "classic")), {"scenario": "family", "difficulty": "normal", "world_seed": 101})
	await _frames(20)
	var W = root.get_node("World")
	_main.hud.visible = false
	var hh: Array = []
	for f in W.all_folk():
		if int(f.household_id) == 1:
			hh.append(f.id)
	for fid in hh:
		W.get_folk(fid).idle_until_min = 1 << 30
	_home = W.get_folk(hh[0]).tile
	var scenes := [
		["read_armchair", [[0, "read_armchair", "armchair"]], 0, 3.2],
		["play_computer", [[0, "play_computer", "computer"]], 0, 3.2],
		["brew_coffee", [[0, "brew_coffee", "coffee_maker"]], 0, 3.2],
	]
	for sc in scenes:
		for fid in hh:
			var ff = W.get_folk(fid)
			ff.queue.clear()
			if ff.current != null:
				ff.current.finish(false)
			ff.current = null
			ff.idle_until_min = 1 << 30
		await _secs(0.4)
		var ok := true
		for cmd in sc[1]:
			var fid: int = hh[cmd[0]]
			var t: String = cmd[2]
			var tgt: int = hh[int(t.substr(5))] if t.begins_with("folk:") else _obj(t)
			if tgt < 0 or not _cmd(fid, cmd[1], tgt):
				print("could not command ", cmd)
				ok = false
		if not ok:
			continue
		for cmd in sc[1]:
			_until_running(hh[cmd[0]])
		await _secs(2.5)
		await _shot(sc[0], hh[sc[2]], sc[3])
	quit(0)
