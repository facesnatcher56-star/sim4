extends SceneTree
## Not a unit test: windowed screenshots of the starter house with the folk doing different things.
## godot --path . --resolution 1600x900 --script res://tests/anim_shot.gd -- out_prefix [scene_names...]
## Scenes: house (overview), then per-activity close-ups. Output: <prefix>_<scene>.png
var _prefix := "user://anim"
var _main: Node = null


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _secs(s: float) -> void:
	await create_timer(s).timeout


func _obj(def_id: String, nth: int = 0) -> int:
	var arr: Array = root.get_node("World").objects_of_def(def_id)
	if arr.size() <= nth:
		return -1
	return arr[nth].id


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
	var clock = root.get_node("Clock")
	for i in 60:
		if f.current != null and str(f.current.state) == "running":
			return
		clock.advance_minutes(1)


func _shot(name: String, focus_fid: int, zoom: float) -> void:
	var lv = _main.lot_view
	lv.set_zoom(zoom)
	var fv = lv.get_folk_view(focus_fid)
	if fv != null:
		lv.focus_tile(root.get_node("World").pos_to_tile(fv.position))
	await _secs(0.8)
	var img := root.get_texture().get_image()
	var p := "%s_%s.png" % [_prefix, name]
	img.save_png(p)
	print("saved ", p)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	_main.start_new_game(_main.default_household())
	await _frames(20)
	for f in root.get_node("World").all_folk():
		f.idle_until_min = 1 << 30
	_main.hud.visible = false
	var clock = root.get_node("Clock")
	var W = root.get_node("World")
	var ids: Array = []
	for f in W.all_folk():
		ids.append(f.id)
	# overview
	await _shot("house", ids[0], 22.0)
	# a list of scenes: [name, [[folk_idx, interaction, target def or "folk:<idx>"]...], focus folk idx, zoom]
	var scenes := [
		["sleep_cook_tv", [[0, "sleep_bed", "bed"], [1, "cook_meal", "stove"], [2, "watch_tv", "tv"]], 0, 7.0],
		["sleep", [[0, "sleep_bed", "bed"]], 0, 5.0],
		["cook", [[1, "cook_meal", "stove"]], 1, 5.0],
		["tv", [[2, "watch_tv", "tv"]], 2, 5.0],
		["shower", [[0, "take_shower", "shower"], [1, "use_toilet", "toilet"], [2, "take_bath", "bathtub"]], 0, 7.0],
		["computer_paint", [[0, "work_computer", "computer"], [1, "paint_canvas", "easel"], [2, "read_book", "bookshelf"]], 1, 7.0],
		["chat", [[0, "chat", "folk:1"]], 0, 5.0],
		["eat_chair", [[2, "sit_chair", "chair"], [1, "exercise", "treadmill"], [0, "wash_hands", "sink"]], 2, 7.0],
	]
	var only: Array = args.slice(1) if args.size() > 1 else []
	if "lineup" in only:
		var stages := ["baby", "toddler", "child", "teen", "adult", "elder"]
		var fids: Array = []
		for i in 6:
			var nf := Folk.create("L%d" % i)
			nf.age_stage = stages[i]
			nf.appearance["hair_style"] = i
			nf.idle_until_min = 1 << 30
			W.add_folk(nf, Vector2i(18 + i, 19))
			fids.append(nf.id)
		await _secs(1.5)
		var lv = _main.lot_view
		lv.focus_tile(Vector2i(20, 19))
		lv.set_zoom(5.5)
		await _secs(1.0)
		var moods := ["happy", "sad", "angry", "flirty", "focused", "tense"]
		for i in 6:
			var nm: Folk = W.get_folk(fids[i])
			nm.mood_name = moods[i]
			nm.mood_intensity = 3
		await _frames(3)
		root.get_texture().get_image().save_png("%s_lineup.png" % _prefix)
		quit(0)
		return
	for sc in scenes:
		if not only.is_empty() and not (sc[0] in only):
			continue
		for fid in ids:
			var ff = W.get_folk(fid)
			ff.queue.clear()
			if ff.current != null:
				ff.current.finish(false)
			ff.current = null
			ff.idle_until_min = 1 << 30
		await _secs(0.5)
		for cmd in sc[1]:
			var fid: int = ids[cmd[0]]
			var tgt: int = -1
			var t: String = cmd[2]
			if t.begins_with("folk:"):
				tgt = ids[int(t.substr(5))]
			else:
				tgt = _obj(t)
			if tgt < 0 or not _cmd(fid, cmd[1], tgt):
				print("could not command ", cmd, " tgt=", tgt)
		for cmd in sc[1]:
			_until_running(ids[cmd[0]])
		await _secs(3.0)
		await _shot(sc[0], ids[sc[2]], sc[3])
		for cmd in sc[1]:
			var fv = _main.lot_view.get_folk_view(ids[cmd[0]])
			print("  ", W.get_folk(ids[cmd[0]]).name, " ", cmd[1], " -> clip=", fv.clip, " pose=", fv.pose, " variant=", fv.variant)
	quit(0)
