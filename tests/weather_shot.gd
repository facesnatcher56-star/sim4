extends SceneTree
## Not a unit test: windowed screenshots of every weather type, day/night and the four seasons.
## godot --path . --resolution 1600x900 --script res://tests/weather_shot.gd -- out_prefix [scene names...]
## Output: <prefix>_<scene>.png  (default prefix user://wx). Scene names: see SCENES.
var _prefix := "user://wx"
var _main: Node = null

# name -> [day, hour, weather, snow cover (-1 = auto), zoom, hud visible]
const SCENES := {
	"sunny_noon": [3, 12.0, "sunny", 0.0, 17.0, true],
	"sunny_dawn": [3, 6.6, "sunny", 0.0, 17.0, false],
	"sunny_dusk": [3, 18.9, "sunny", 0.0, 17.0, false],
	"night": [3, 23.0, "cloudy", 0.0, 17.0, false],
	"cloudy": [3, 13.0, "cloudy", 0.0, 17.0, false],
	"rain": [3, 13.0, "rain", 0.0, 17.0, false],
	"storm": [3, 15.0, "thunderstorm", 0.0, 17.0, false],
	"fog": [3, 10.0, "fog", 0.0, 17.0, false],
	"snow": [24, 13.0, "snow", 0.9, 17.0, true],
	"heatwave": [11, 13.0, "heatwave", 0.0, 17.0, false],
	"cold_snap": [23, 12.0, "cold_snap", 0.3, 17.0, false],
	"storm_flash": [3, 15.0, "thunderstorm", 0.0, 17.0, false],
	"windy": [3, 14.0, "windy", 0.0, 17.0, false],
	"spring": [4, 12.0, "sunny", 0.0, 26.0, false],
	"summer": [11, 12.0, "sunny", 0.0, 26.0, false],
	"autumn": [19, 12.0, "cloudy", 0.0, 26.0, false],
	"winter": [24, 12.0, "cloudy", 0.7, 26.0, false],
	"rain_night": [3, 22.0, "rain", 0.0, 17.0, false],
	"snow_night": [24, 21.0, "snow", 0.8, 17.0, false],
}

func _initialize() -> void:
	_run()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_prefix = args[0]
	var names: Array = []
	for i in range(1, args.size()):
		names.append(args[i])
	if names.is_empty():
		names = SCENES.keys()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await _frames(5)
	_main.start_new_game(_main.default_household())
	await _frames(20)
	var clock = root.get_node("Clock")
	clock.set_speed(0)
	for f in root.get_node("World").all_folk():
		f.idle_until_min = 1 << 30
	var lv = _main.lot_view
	var wv = lv.get_node("WeatherView")
	for n in names:
		var s: Array = SCENES[n]
		clock.total_minutes = (int(s[0]) - 1) * 1440 + int(float(s[1]) * 60.0)
		Weather.force(str(s[2]), float(s[3]))
		_main.hud.visible = bool(s[5])
		lv.set_zoom(float(s[4]))
		wv._apply(100.0, true)
		await _frames(3)
		wv._apply(100.0, true)
		await create_timer(1.6).timeout
		for hd in _main.hud.find_children("*", "WeatherHud", true, false):
			hd.refresh(true)
		await _frames(3)
		if n == "storm_flash":
			wv.strike(1.0)
			await create_timer(0.08).timeout
		var img := root.get_texture().get_image()
		var p := "%s_%s.png" % [_prefix, n]
		img.save_png(p)
		print("saved ", p, "  ", Weather.label(), " ", Weather.temp_string(), " ", Seasons.date_string())
	quit(0)
