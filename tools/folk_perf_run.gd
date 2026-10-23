extends Node
## Folk model frame cost (not a test): solo game at 18:00, camera on the busiest spot of folk, frame time at play zoom and zoomed out.
##   powershell -File tools/quiet_godot.ps1 --script res://tools/sweep.gd -- run=res://tools/folk_perf_run.gd
var m
var lv


func _ready() -> void:
	TestFixture.isolate_user_files()
	get_window().unfocusable = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	m = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(m)
	_go.call_deferred()


func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _measure(label: String, n: int = 300) -> void:
	await _w(60)
	var vp := get_tree().root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var t0 := Time.get_ticks_usec()
	var prims := 0.0
	var gpu := 0.0
	for i in n:
		await get_tree().process_frame
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	print("FOLKPERF %-12s %.2f ms/frame, gpu %.2f ms, prims %.0fk, folk views %d" % [label, ms, gpu / n, prims / n / 1000.0, lv._folk_views.size()])


func _go() -> void:
	await _w(5)
	m.title.visible = false
	m.start_picker.select("solo")
	UIPrefs.set_flag("tips_seen", true)
	m.start_picker._emit_chosen()
	await _w(60)
	m.hud.tips.visible = false
	lv = m.find_child("LotView", true, false)
	var clk = get_tree().root.get_node("Clock")
	clk.total_minutes = clk.day() * 1440 + 17 * 60 + 40
	clk.set_speed(3)
	await _w(600)
	clk.set_speed(1)
	var best := Vector3.ZERO
	var most := -1
	for a in lv._folk_views.values():
		var n := 0
		for b in lv._folk_views.values():
			if a.position.distance_to(b.position) < 10.0:
				n += 1
		if n > most:
			most = n
			best = a.position
	lv._follow_id = -1
	lv._target = best
	print("FOLKPERF busiest spot has %d folk within 10 m" % most)
	lv.set_zoom(12.0)
	await _measure("zoom12")
	lv.set_zoom(24.0)
	await _measure("zoom24")
	get_tree().root.get_texture().get_image().save_jpg("user://folk_perf.jpg", 0.8)
	get_tree().quit(0)
