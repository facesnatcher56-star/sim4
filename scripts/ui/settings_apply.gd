class_name SettingsApply
extends RefCounted
## Pushes GameSettings values into the engine (window, rendering, audio, economy). Safe in headless mode and
## with missing / odd values; every call is idempotent.

const SIZES := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const TEXT_MULT := [0.9, 1.0, 1.2]
const MIN_UI_WIDTH := 1200.0
const BUSES := ["Music", "SFX"]
static var _lights_hooked := false
static var _size_hooked := false

static func headless() -> bool:
	return DisplayServer.get_name() == "headless"

static func root() -> Window:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree != null else null

static func apply_all() -> void:
	GameSettings.ensure_loaded()
	ensure_buses()
	var leave_window := GameSettings.get_int("window_mode") == 0 and GameSettings.get_str("resolution") == "auto"      # untouched defaults: keep the window as launched
	for d in GameSettings.DEFS:
		if leave_window and d["k"] in ["window_mode", "resolution"]:
			continue
		apply_key(d["k"])
	_hook_lights()

static func apply_key(key: String) -> void:
	match key:
		"window_mode", "resolution": apply_window()
		"vsync": apply_vsync()
		"max_fps": Engine.max_fps = GameSettings.get_int("max_fps")
		"ui_scale", "text_size": apply_ui_scale()
		"render_scale", "aa": apply_render()
		"shadows": apply_shadows()
		"master_vol", "music_vol", "sfx_vol", "mute": apply_audio()
		"auto_pay": Economy.auto_pay = GameSettings.get_bool("auto_pay")
		"tooltip_delay": ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", GameSettings.get_float("tooltip_delay"))

# ------------------------------------------------------------ display
## Window sizes that fit the current screen, as ["native", "Native"] then ["WxH", "W x H"].
static func resolution_options() -> Array:
	var out: Array = [["auto", "Default (%d x %d)" % [_default_size().x, _default_size().y]], ["native", "Native (fit screen)"]]
	if headless():
		return out
	var scr := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	for s in SIZES:
		if s.x <= scr.x and s.y <= scr.y:
			out.append(["%dx%d" % [s.x, s.y], "%d x %d" % [s.x, s.y]])
	return out

static func apply_window() -> void:
	if headless():
		return
	var mode := GameSettings.get_int("window_mode")
	var win := DisplayServer.WINDOW_MODE_WINDOWED
	if mode == 1:
		win = DisplayServer.WINDOW_MODE_FULLSCREEN
	elif mode == 2:
		win = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(win)
	if mode != 0:
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	var scr := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(scr)
	var size := usable.size
	var res := GameSettings.get_str("resolution")
	if res == "auto":
		size = Vector2i(mini(_default_size().x, usable.size.x), mini(_default_size().y, usable.size.y))
	elif res != "native":
		var p := res.split("x")
		size = Vector2i(mini(int(p[0]), usable.size.x), mini(int(p[1]), usable.size.y))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)

static func apply_vsync() -> void:
	if headless():
		return
	var m := [DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ADAPTIVE]
	DisplayServer.window_set_vsync_mode(m[clampi(GameSettings.get_int("vsync"), 0, 2)])

## UI scale and text size multiply into the window's content scale factor (layout scales, 3D is untouched).
static func apply_ui_scale() -> void:
	var r := root()
	if r == null:
		return
	r.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	r.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	r.content_scale_factor = ui_factor()
	if not _size_hooked:
		_size_hooked = true
		r.size_changed.connect(apply_ui_scale)

## Never scale so far that the top bar no longer fits the window (it needs about MIN_UI_WIDTH scaled pixels).
static func ui_factor() -> float:
	var f: float = float(GameSettings.get_int("ui_scale")) / 100.0 * TEXT_MULT[clampi(GameSettings.get_int("text_size"), 0, 2)]
	var r := root()
	if r != null and r.size.x > 0:
		f = minf(f, maxf(float(r.size.x) / MIN_UI_WIDTH, 0.8))
	return f

static func apply_render() -> void:
	var r := root()
	if r == null:
		return
	r.scaling_3d_scale = float(GameSettings.get_int("render_scale")) / 100.0
	var aa := GameSettings.get_int("aa")
	r.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	r.msaa_3d = Viewport.MSAA_2X if aa == 2 else (Viewport.MSAA_4X if aa == 3 else Viewport.MSAA_DISABLED)

# ------------------------------------------------------------ shadows
static func apply_shadows() -> void:
	var q := GameSettings.get_int("shadows")
	if not headless():
		RenderingServer.directional_shadow_atlas_set_size([1024, 1024, 4096][clampi(q, 0, 2)], q == 2)
	var r := root()
	if r != null:
		_set_lights(r, q)

static func _set_lights(n: Node, q: int) -> void:
	if n is Light3D:
		_light_shadow(n, q)
	for c in n.get_children():
		_set_lights(c, q)

static func _light_shadow(l: Light3D, q: int) -> void:
	if not l.has_meta("shadow_orig"):
		l.set_meta("shadow_orig", l.shadow_enabled)
	l.shadow_enabled = q > 0 and bool(l.get_meta("shadow_orig"))

static func _hook_lights() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or _lights_hooked:
		return
	_lights_hooked = true
	tree.node_added.connect(func(n: Node):
		if n is Light3D:
			_light_shadow(n, GameSettings.get_int("shadows")))

# ------------------------------------------------------------ audio
static func ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")

static func apply_audio() -> void:
	ensure_buses()
	var vols := {"Master": "master_vol", "Music": "music_vol", "SFX": "sfx_vol"}
	for b in vols:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(GameSettings.get_int(vols[b])) / 100.0, 0.0001)))
	AudioServer.set_bus_mute(0, GameSettings.get_bool("mute"))

static func _default_size() -> Vector2i:
	return Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)), int(ProjectSettings.get_setting("display/window/size/viewport_height", 900)))
