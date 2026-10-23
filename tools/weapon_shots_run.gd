extends Node
## Task 57b review shots (not a test): in the running game, the pawn holds each weapon out, idle and then threatening; a close-up of each.
##   powershell -File tools/quiet_godot.ps1 --script res://tools/sweep.gd -- run=res://tools/weapon_shots_run.gd <out dir> [yaw=0..3] [only=pistol,shotgun]
var _out := "user://weapon_shots/"
var m
var lv
var fid := -1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--") and not a.begins_with("run=") and not a.begins_with("yaw=") and not a.begins_with("only="):
			_out = a.trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(_out)
	TestFixture.isolate_user_files()
	var w := get_window()
	w.unfocusable = true
	w.size = Vector2i(1200, 900)
	m = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(m)
	_go.call_deferred()


func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## A close-up: the frame cropped round the pawn's chest and scaled up.
func _shot(n: String) -> void:
	await _w(20)
	var img := get_tree().root.get_texture().get_image()
	var fv = lv._folk_views[fid]
	var c: Vector2 = lv.screen_pos("folk", fid) * (Vector2(img.get_size()) / get_viewport().get_visible_rect().size)
	var r := Rect2i(int(c.x) - 170, int(c.y) + 40, 340, 420).intersection(Rect2i(Vector2i.ZERO, img.get_size()))          # from the head down to the knees
	var crop := img.get_region(r)
	crop.resize(r.size.x * 2, r.size.y * 2, Image.INTERPOLATE_LANCZOS)
	crop.save_jpg(_out + n + ".jpg", 0.9)
	print("SHOT ", n, " clip ", fv.clip)


func _go() -> void:
	await _w(5)
	m.title.visible = false
	m.start_picker.select("solo")
	UIPrefs.set_flag("tips_seen", true)
	m.start_picker._emit_chosen()
	await _w(60)
	get_tree().root.get_node("Clock").set_speed(1)          # clips play at the game's speed: paused, a new clip never blends in
	m.hud.visible = false
	lv = m.find_child("LotView", true, false)
	fid = Pawn.of()
	var f = WorldIface.get_folk(fid)
	var clk = get_tree().root.get_node("Clock")
	clk.total_minutes = 12 * 60          # midday light
	var yaws: int = 0
	var only: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("yaw="):
			yaws = int(a.substr(4))
		elif a.begins_with("only="):
			only = a.substr(5)
	lv.rotate_camera(yaws)
	await _w(30)
	for wid in (SysUtil.table("weapons").get("hold", {}) as Dictionary).keys():
		if str(wid) == "_doc" or (only != "" and not (str(wid) in only.split(","))):
			continue
		for e in Inventory.items(fid).duplicate():
			Inventory.take(fid, str(e["id"]))
		Inventory.add(fid, str(wid), {"shown": true})
		WeaponShop._posed.erase(fid)
		lv.focus_on("folk", fid)
		lv._zoom = 3.0
		lv._zoom_target = 3.0
		await _w(40)
		await _shot("%s_idle" % wid)
		WeaponShop._posed[fid] = SysUtil.now() + 100000
		await _w(40)
		await _shot("%s_threaten" % wid)
	get_tree().quit(0)
