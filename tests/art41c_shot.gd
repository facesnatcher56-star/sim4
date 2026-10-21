extends SceneTree
## Not a unit test: task 41 part C screenshots (lighting and weather mood under the grounded look), windowed, Forward+.
## godot --path . --rendering-method forward_plus --script res://tests/art41c_shot.gd -- <out dir> <WxH> <look> <case>
## One case per process (windowed runs can hang): cases night_street night_nb0 night_nb100 night_selected dusk dawn rain_night overcast fog snow_night interior_night day
var _main: Node = null

# case -> [day, hour (-1 = sunset - 0.2, -2 = sunrise + 0.2), weather, snow cover, zoom, target, lamps on, night brightness %, select folk]
const CASES := {
	"day": [3, 12.0, "sunny", 0.0, 20.0, Vector3(60, 0, 84), false, 35, false],
	"night_street": [3, 22.5, "sunny", 0.0, 20.0, Vector3(60, 0, 84), false, 35, false],
	"night_nb0": [3, 22.5, "sunny", 0.0, 20.0, Vector3(60, 0, 84), false, 0, false],
	"night_nb100": [3, 22.5, "sunny", 0.0, 20.0, Vector3(60, 0, 84), false, 100, false],
	"night_selected": [3, 23.5, "sunny", 0.0, 12.0, Vector3(56, 0, 76), false, 0, true],
	"dusk": [3, -1.0, "sunny", 0.0, 20.0, Vector3(60, 0, 84), false, 35, false],
	"dawn": [3, -2.0, "sunny", 0.0, 20.0, Vector3(60, 0, 84), false, 35, false],
	"rain_night": [3, 22.0, "rain", 0.0, 20.0, Vector3(60, 0, 84), false, 35, false],
	"overcast": [3, 13.0, "cloudy", 0.0, 20.0, Vector3(60, 0, 84), false, 35, false],
	"fog": [3, 10.0, "fog", 0.0, 20.0, Vector3(60, 0, 84), false, 35, false],
	"snow_night": [24, 21.0, "snow", 0.8, 20.0, Vector3(60, 0, 84), false, 35, false],
	"interior_night": [3, 23.0, "sunny", 0.0, 9.0, Vector3(56, 0, 75), true, 35, false],
}


func _initialize() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var res := args[1].split("x")
	var look := args[2]
	var c: String = args[3]
	var size := Vector2i(int(res[0]), int(res[1]))
	DisplayServer.window_set_size(size)
	root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	var W = root.get_node("World")
	_main.start_new_game(_main.default_household(), "classic", {"world_seed": 7, "home_state": "furnished"})
	await _frames(30)
	Looks.set_look(look)
	await _frames(10)
	var clock = root.get_node("Clock")
	clock.set_speed(0)
	_main.hud.tips.visible = false
	var s: Array = CASES[c]
	for f in W.all_folk():
		f.queue.clear()
		f.idle_until_min = 1 << 30
	var lv = _main.lot_view
	var wv = lv.get_node("WeatherView")
	var hour: float = float(s[1])
	clock.total_minutes = (int(s[0]) - 1) * 1440 + 720
	if hour == -1.0:
		hour = Seasons.sunset(Seasons.year_pos(-1, 12.0)) - 0.2
	elif hour == -2.0:
		hour = Seasons.sunrise(Seasons.year_pos(-1, 12.0)) + 0.2
	clock.total_minutes = (int(s[0]) - 1) * 1440 + int(hour * 60.0)
	clock.minute_passed.emit(clock.total_minutes)
	Weather.force(str(s[2]), float(s[3]))
	Weather._wet = 1.0 if str(s[2]) == "rain" else 0.0
	GameSettings.set_value("night_brightness", int(s[7]), false)
	if bool(s[6]):
		for o in W.all_objects():
			if o.def_id in ["lamp", "pendant_light", "nightstand", "tv", "computer"] and o.state.has("on"):
				o.state["on"] = true
				root.get_node("Events").object_state_changed.emit(o.id, "on")
	lv.set_zoom(float(s[4]))
	lv._target = s[5]
	lv._zoom = lv._zoom_target
	if bool(s[8]):
		var f0 = W.all_folk()[0]
		lv.select("folk", f0.id)
		var fv = lv.get_folk_view(f0.id)
		if fv != null:
			lv._target = Vector3(fv.position.x, 0, fv.position.z)
	else:
		lv.select("none", -1)
	wv._apply(100.0, true)
	await _frames(3)
	wv._apply(100.0, true)
	wv._lamp_timer = 0.0
	await create_timer(4.0).timeout
	for hd in _main.hud.find_children("*", "WeatherHud", true, false):
		hd.refresh(true)
	await _frames(3)
	var img: Image = root.get_texture().get_image()
	if img.get_size() != size:
		img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var p := "%s/art41c_%s_%dx%d.png" % [out, c, size.x, size.y]
	img.save_png(p)
	print("saved ", p, " hour ", hour, " lights ", wv._lamp_lights.size(), " amb ", wv.env.ambient_light_energy)
	OS.kill(OS.get_process_id())
