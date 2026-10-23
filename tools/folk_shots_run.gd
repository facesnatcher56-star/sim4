extends Node
## Folk model review: close-ups of the household and nearby folk of every age in the real game, plus one shot at the
## normal play zoom (not a test).
##   powershell -File tools/quiet_godot.ps1 --script res://tools/sweep.gd -- run=res://tools/folk_shots_run.gd <out dir>
var _out := "user://folk_shots/"
var m
var lv


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--") and not a.begins_with("run="):
			_out = a.trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(_out)
	TestFixture.isolate_user_files()
	var w := get_window()
	w.unfocusable = true
	w.size = Vector2i(1600, 900)
	m = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(m)
	_go.call_deferred()


func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	await _w(8)
	get_tree().root.get_texture().get_image().save_jpg(_out + n + ".jpg", 0.85)
	print("SHOT ", n)


func _go() -> void:
	await _w(5)
	m.title.visible = false
	m.start_picker.select("solo")
	UIPrefs.set_flag("tips_seen", true)
	m.start_picker._emit_chosen()
	await _w(60)
	var hud = m.hud
	hud.tips.visible = false
	lv = m.find_child("LotView", true, false)
	var me = hud._resolve(hud.selected_folk_id)
	get_tree().root.get_node("Clock").set_speed(1)
	await _w(90)
	lv.focus_on("folk", int(me.id))
	lv.set_zoom(12.0)
	await _shot("00_play_zoom")
	lv.set_zoom(4.0)
	for r in 4:
		await _shot("01_me_%d" % r)
		lv.rotate_camera(1)
		await _w(30)
	# one close-up per age stage among the folk the game has loaded
	var seen := {}
	for f in WorldIface.all_folk():
		var st := str(f.age_stage)
		if seen.has(st) or not lv._folk_views.has(int(f.id)):
			continue
		seen[st] = true
		lv.focus_on("folk", int(f.id))
		await _w(20)
		await _shot("02_%s_%d" % [st, int(f.id)])
	get_tree().quit(0)
