class_name GameSettings
extends RefCounted
## Player settings: defaults, validation, persistence (user://settings.cfg) and change notification.
## Static API, no autoload. Read with GameSettings.get_bool/get_int/get_str("key") or the named helpers below;
## listen with GameSettings.bus.changed(key, value). Applying to the engine lives in SettingsApply.
## Add a setting = add one line to DEFS (the Settings dialog builds its rows from this table).

class Bus extends RefCounted:
	signal changed(key: String, value)

static var bus := Bus.new()
static var path := "user://settings.cfg"
static var values: Dictionary = {}
static var _dirty := false

const TABS := [["display", "Display"], ["gameplay", "Gameplay"], ["access", "Accessibility"], ["audio", "Audio"], ["controls", "Controls"]]

const ON_OFF := [[true, "On"], [false, "Off"]]
const QUALITY := [[0, "Off"], [1, "Low"], [2, "High"]]

## k = key, t = enum | bool | range, def = default. enum: opts [[value, label]]. range: min, max, step, unit.
const DEFS := [
	{"k": "window_mode", "tab": "display", "t": "enum", "label": "Window mode", "def": 0, "opts": [[0, "Windowed"], [1, "Borderless fullscreen"], [2, "Fullscreen"]],
		"tip": "Windowed, a borderless window that fills the screen, or exclusive fullscreen."},
	{"k": "resolution", "tab": "display", "t": "enum", "label": "Window size", "def": "auto", "opts": [],
		"tip": "Size of the window when in Windowed mode. Default is the size the game ships with; Native fits your screen. Only sizes that fit this screen are listed."},
	{"k": "vsync", "tab": "display", "t": "enum", "label": "VSync", "def": 0, "opts": [[0, "On"], [1, "Off"], [2, "Adaptive"]],
		"tip": "Syncs frames to your monitor to stop tearing. Adaptive only syncs when the frame rate is at or above the refresh rate."},
	{"k": "max_fps", "tab": "display", "t": "enum", "label": "Max FPS", "def": 60, "opts": [[30, "30"], [60, "60"], [120, "120"], [144, "144"], [0, "Unlimited"]],
		"tip": "Caps the frame rate. Lower values save power and heat."},
	{"k": "ui_scale", "tab": "display", "t": "range", "label": "UI scale", "def": 100, "min": 80, "max": 150, "step": 5, "unit": "%",
		"tip": "Makes all menus and buttons bigger or smaller. Applies immediately. On small windows it is limited so the top bar still fits."},
	{"k": "render_scale", "tab": "display", "t": "range", "label": "3D render scale", "def": 100, "min": 50, "max": 100, "step": 5, "unit": "%",
		"tip": "Draws the world at a lower resolution and stretches it. Lower is faster but blurrier. The menus stay sharp."},
	{"k": "aa", "tab": "display", "t": "enum", "label": "Anti-aliasing", "def": 1, "opts": [[0, "Off"], [1, "FXAA"], [2, "MSAA 2x"], [3, "MSAA 4x"]],
		"tip": "Smooths jagged edges. FXAA is cheap and soft; MSAA is sharper but costs more."},
	{"k": "shadows", "tab": "display", "t": "enum", "label": "Shadows", "def": 2, "opts": QUALITY,
		"tip": "Shadow quality. Off is the fastest."},
	{"k": "effects", "tab": "display", "t": "enum", "label": "Effects quality", "def": 2, "opts": QUALITY,
		"tip": "Weather particles, fog and similar effects. Off is the fastest."},

	{"k": "autosave", "tab": "gameplay", "t": "bool", "label": "Autosave", "def": true, "tip": "Saves automatically to the Autosave slot at the start of a new day."},
	{"k": "autosave_days", "tab": "gameplay", "t": "range", "label": "Autosave every", "def": 1, "min": 1, "max": 7, "step": 1, "unit": " day(s)",
		"tip": "How many game days between autosaves."},
	{"k": "auto_pay", "tab": "gameplay", "t": "bool", "label": "Pay bills automatically", "def": false,
		"tip": "Pays a bill on its due date when your household has the Coins. Off by default: someone at home pays it from the mailbox (the neat ones first), or you can open the Coins button and pay it yourself. Other households always pay by themselves."},
	{"k": "auto_furnish", "tab": "gameplay", "t": "enum", "label": "Furnish for me when I am away", "def": "auto", "opts": [["auto", "Only if I never play"], ["on", "Yes"], ["off", "No"]],
		"tip": "A household with a bare home that nobody has given orders to for 2 days buys the basics (beds, toilet, fridge, shower, stove, seats) from its own coins. Only if I never play: a game you are not playing furnishes itself, a game you play never does. Yes: also when you go away. No: never."},
	{"k": "pause_on_dialog", "tab": "gameplay", "t": "bool", "label": "Pause when a window is open", "def": true,
		"tip": "Time stops while a window (Goals, Career, Household, Help, menus) is open and goes back to your speed when it closes."},
	{"k": "surprises", "tab": "gameplay", "t": "enum", "label": "Surprises", "def": "rare", "opts": [["off", "Off"], ["rare", "Rare"], ["normal", "Normal"], ["chaotic", "Chaotic"]],
		"tip": "How often unexpected things happen: accidents, illness, crime, disasters and lucky finds. Off = never, Rare = a few in a lifetime, Normal = 3x, Chaotic = 10x. Old age is not affected. Saved with each game; new games start from this value."},
	{"k": "storyteller", "tab": "gameplay", "t": "enum", "label": "Storyteller", "def": "classic", "opts": [["calm", "Calm"], ["classic", "Classic"], ["chaotic", "Chaotic"], ["custom", "Custom"]],
		"tip": "Decides how the unexpected plays out. Calm: long quiet stretches, mostly small good surprises. Classic: the usual mix, big events spaced out. Chaotic: anything, any time. Custom: use the four sliders below. Murder, disasters and the rarest crimes stay rare in every mode. In co-op the host's choice applies."},
	{"k": "storyteller_freq", "tab": "gameplay", "t": "range", "label": "Custom storyteller: how often", "def": 50, "min": 0, "max": 100, "step": 5, "unit": "%", "tip": "Only used when the Storyteller is Custom. More = more happens."},
	{"k": "storyteller_sev", "tab": "gameplay", "t": "range", "label": "Custom storyteller: how big", "def": 50, "min": 0, "max": 100, "step": 5, "unit": "%", "tip": "Only used when the Storyteller is Custom. Higher = bigger events more often."},
	{"k": "storyteller_good", "tab": "gameplay", "t": "range", "label": "Custom storyteller: good luck", "def": 50, "min": 0, "max": 100, "step": 5, "unit": "%", "tip": "Only used when the Storyteller is Custom. How much of what happens is good news."},
	{"k": "storyteller_mercy", "tab": "gameplay", "t": "range", "label": "Custom storyteller: mercy", "def": 50, "min": 0, "max": 100, "step": 5, "unit": "%", "tip": "Only used when the Storyteller is Custom. How long and how kindly things ease off after a disaster."},
	{"k": "story_cat_money", "tab": "gameplay", "t": "bool", "label": "Storyteller events: money and luck", "def": true, "tip": "Turn off to stop the Storyteller creating this kind of event. Things that happen on their own, outside the Storyteller, are not affected."},
	{"k": "story_cat_home", "tab": "gameplay", "t": "bool", "label": "Storyteller events: trouble at home", "def": true, "tip": "Turn off to stop the Storyteller creating this kind of event. Things that happen on their own, outside the Storyteller, are not affected."},
	{"k": "story_cat_crime", "tab": "gameplay", "t": "bool", "label": "Storyteller events: crime", "def": true, "tip": "Turn off to stop the Storyteller creating this kind of event. Things that happen on their own, outside the Storyteller, are not affected."},
	{"k": "story_cat_social", "tab": "gameplay", "t": "bool", "label": "Storyteller events: neighbours, strangers and secrets", "def": true, "tip": "Turn off to stop the Storyteller creating this kind of event. Things that happen on their own, outside the Storyteller, are not affected."},
	{"k": "story_cat_work", "tab": "gameplay", "t": "bool", "label": "Storyteller events: work", "def": true, "tip": "Turn off to stop the Storyteller creating this kind of event. Things that happen on their own, outside the Storyteller, are not affected."},
	{"k": "story_cat_health", "tab": "gameplay", "t": "bool", "label": "Storyteller events: illness", "def": true, "tip": "Turn off to stop the Storyteller creating this kind of event. Things that happen on their own, outside the Storyteller, are not affected."},
	{"k": "story_cat_town", "tab": "gameplay", "t": "bool", "label": "Storyteller events: town events", "def": true, "tip": "Turn off to stop the Storyteller creating this kind of event. Things that happen on their own, outside the Storyteller, are not affected."},
	{"k": "story_cat_arcs", "tab": "gameplay", "t": "bool", "label": "Storyteller events: longer stories", "def": true, "tip": "Turn off to stop the Storyteller creating this kind of event. Things that happen on their own, outside the Storyteller, are not affected."},
	{"k": "pick_for_me", "tab": "gameplay", "t": "bool", "label": "Pick for me after 2 days", "def": true,
		"tip": "When nobody is left in your household, someone is chosen for you after 2 days so the home is never empty for long. Off = you are only reminded each morning."},
	{"k": "mature_events", "tab": "gameplay", "t": "bool", "label": "Mature life events", "def": true,
		"tip": "Pregnancy loss and the early-pregnancy choice can happen in the story. Off = they never happen and the choice is not offered. Pregnancy and birth work either way."},
	{"k": "confirm_quit", "tab": "gameplay", "t": "bool", "label": "Confirm before quitting to title", "def": true,
		"tip": "Asks 'are you sure?' before leaving the game, because unsaved progress is lost."},
	{"k": "thought_bubbles", "tab": "gameplay", "t": "bool", "label": "Show thought bubbles", "def": true, "tip": "The little speech balloons above Folk heads."},
	{"k": "need_numbers", "tab": "gameplay", "t": "bool", "label": "Show need numbers", "def": true, "tip": "Percent values next to the need bars. Takes effect when you next select a Folk."},
	{"k": "tooltip_delay", "tab": "gameplay", "t": "range", "label": "Tooltip delay", "def": 0.5, "min": 0.0, "max": 1.5, "step": 0.1, "unit": " s",
		"tip": "How long you hover before a tooltip appears. May need a restart to take effect."},
	{"k": "notif_bills", "tab": "gameplay", "t": "bool", "label": "Notify: bills", "def": true, "tip": "Show pop-ups about bills and money."},
	{"k": "notif_whims", "tab": "gameplay", "t": "bool", "label": "Notify: whims and goals", "def": true, "tip": "Show pop-ups when Folk fulfil whims and goals."},
	{"k": "notif_social", "tab": "gameplay", "t": "bool", "label": "Notify: social", "def": true, "tip": "Show pop-ups about relationships, visits and invitations."},
	{"k": "notif_weather", "tab": "gameplay", "t": "bool", "label": "Notify: weather and holidays", "def": true, "tip": "Show pop-ups about weather and holidays."},
	{"k": "edge_pan", "tab": "gameplay", "t": "bool", "label": "Camera edge-pan", "def": false, "tip": "Move the camera by pushing the mouse to the screen edge."},
	{"k": "pan_sens", "tab": "gameplay", "t": "range", "label": "Camera pan speed", "def": 100, "min": 50, "max": 200, "step": 10, "unit": "%", "tip": "How fast the camera moves."},
	{"k": "zoom_sens", "tab": "gameplay", "t": "range", "label": "Camera zoom speed", "def": 100, "min": 50, "max": 200, "step": 10, "unit": "%", "tip": "How far each mouse-wheel step zooms."},
	{"k": "rotate_sens", "tab": "gameplay", "t": "range", "label": "Camera rotate speed", "def": 100, "min": 50, "max": 200, "step": 10, "unit": "%", "tip": "How fast the view turns."},
	{"k": "invert_zoom", "tab": "gameplay", "t": "bool", "label": "Invert zoom", "def": false, "tip": "Swap the mouse-wheel zoom direction."},

	{"k": "text_size", "tab": "access", "t": "enum", "label": "Text size", "def": 1, "opts": [[0, "Small"], [1, "Normal"], [2, "Large"]],
		"tip": "Makes the whole interface a little smaller or larger (on top of UI scale)."},
	{"k": "high_contrast", "tab": "access", "t": "bool", "label": "High-contrast UI", "def": false, "tip": "Brighter text and strong borders on opaque panels."},
	{"k": "colorblind", "tab": "access", "t": "bool", "label": "Colour-blind-safe palette", "def": false, "tip": "Need bars and moods use colours that stay apart for red-green and blue-yellow colour blindness."},
	{"k": "reduce_motion", "tab": "access", "t": "bool", "label": "Reduce motion", "def": false, "tip": "Turns off fades and camera smoothing."},
	{"k": "no_flash", "tab": "access", "t": "bool", "label": "No flashing effects", "def": false, "tip": "Turns off lightning flashes and similar bright pulses."},

	{"k": "master_vol", "tab": "audio", "t": "range", "label": "Master volume", "def": 80, "min": 0, "max": 100, "step": 5, "unit": "%", "tip": "Overall volume."},
	{"k": "music_vol", "tab": "audio", "t": "range", "label": "Music volume", "def": 80, "min": 0, "max": 100, "step": 5, "unit": "%", "tip": "Volume of the Music bus."},
	{"k": "sfx_vol", "tab": "audio", "t": "range", "label": "Effects volume", "def": 80, "min": 0, "max": 100, "step": 5, "unit": "%", "tip": "Volume of the SFX bus."},
	{"k": "mute", "tab": "audio", "t": "bool", "label": "Mute all", "def": false, "tip": "Silences everything."},
]

static var _by_key: Dictionary = {}

static func def_of(key: String) -> Dictionary:
	if _by_key.is_empty():
		for d in DEFS:
			_by_key[d["k"]] = d
	return _by_key.get(key, {})

static func defs_for(tab: String) -> Array:
	return DEFS.filter(func(d): return d["tab"] == tab)

static func default_of(key: String):
	return def_of(key).get("def")

# ------------------------------------------------------------ validation
## Returns a legal value for `key`: wrong type / out of range / unknown option falls back to the default or the nearest legal value.
static func sanitize(key: String, v):
	var d := def_of(key)
	if d.is_empty():
		return v
	match str(d["t"]):
		"bool":
			return v if v is bool else d["def"]
		"range":
			if not (v is int or v is float):
				return d["def"]
			var step := float(d["step"])
			var x := clampf(float(v), float(d["min"]), float(d["max"]))
			x = snappedf(x, step)
			return x if d["def"] is float else int(round(x))
		_:
			if key == "resolution":
				return v if (v is String and (v in ["auto", "native"] or _is_size_text(v))) else d["def"]
			for o in d["opts"]:
				if typeof(o[0]) == typeof(v) and o[0] == v:
					return v
			return d["def"]

static func _is_size_text(s: String) -> bool:
	var p := s.split("x")
	return p.size() == 2 and p[0].is_valid_int() and p[1].is_valid_int() and int(p[0]) >= 640 and int(p[1]) >= 360 and int(p[0]) <= 16384 and int(p[1]) <= 16384

# ------------------------------------------------------------ get / set
static func get_value(key: String):
	if values.has(key):
		return values[key]
	return default_of(key)

static func get_bool(key: String) -> bool:
	return bool(get_value(key))

static func get_int(key: String) -> int:
	return int(get_value(key))

static func get_float(key: String) -> float:
	return float(get_value(key))

static func get_str(key: String) -> String:
	return str(get_value(key))

## Validates, stores, applies to the engine, notifies listeners. Saves now unless `save_now` is false (call flush() later, e.g. while a slider drags).
static func set_value(key: String, v, save_now: bool = true) -> void:
	if def_of(key).is_empty():
		return
	v = sanitize(key, v)
	if values.has(key) and values[key] == v:
		return
	values[key] = v
	_dirty = true
	SettingsApply.apply_key(key)
	bus.changed.emit(key, v)
	if save_now:
		flush()

static func reset_tab(tab: String) -> void:
	if tab == "controls":
		SettingsKeys.reset_all()
		_dirty = true
	for d in defs_for(tab):
		set_value(d["k"], d["def"], false)
	flush()

static func reset_all() -> void:
	for t in TABS:
		reset_tab(t[0])

# ------------------------------------------------------------ persistence
static func load_settings() -> void:
	values = {}
	var cf := ConfigFile.new()
	var ok := cf.load(path) == OK
	for d in DEFS:
		var raw = cf.get_value("settings", d["k"], d["def"]) if ok else d["def"]
		values[d["k"]] = sanitize(d["k"], raw)
	SettingsKeys.load_from(cf if ok else null)
	_dirty = false

static func flush() -> void:
	if not _dirty:
		return
	var cf := ConfigFile.new()
	cf.load(path)
	for k in values:
		cf.set_value("settings", k, values[k])
	SettingsKeys.save_to(cf)
	if cf.save(path) == OK:
		_dirty = false

static func ensure_loaded() -> void:
	if values.is_empty():
		load_settings()

# ------------------------------------------------------------ named helpers other systems read
## 0 off, 1 low, 2 high. Weather particles, fog, etc.
static func effects_quality() -> int: return get_int("effects")
static func shadows_quality() -> int: return get_int("shadows")
static func reduce_motion() -> bool: return get_bool("reduce_motion")
static func flashing_allowed() -> bool: return not get_bool("no_flash")
static func high_contrast() -> bool: return get_bool("high_contrast")
static func colorblind() -> bool: return get_bool("colorblind")
static func edge_pan() -> bool: return get_bool("edge_pan")
## Multipliers (1.0 = default) for the camera.
static func pan_speed() -> float: return get_float("pan_sens") / 100.0
static func rotate_speed() -> float: return get_float("rotate_sens") / 100.0
static func zoom_speed() -> float: return get_float("zoom_sens") / 100.0
static func invert_zoom() -> bool: return get_bool("invert_zoom")

## Should the toast feed show this notification? (kind as sent on Events.notification)
static func notification_allowed(text: String, kind: String) -> bool:
	match kind:
		"bill": return get_bool("notif_bills")
		"goal": return get_bool("notif_whims") if " whim" in text else true
		"relationship", "visit", "invite": return get_bool("notif_social")
		"weather", "holiday": return get_bool("notif_weather")
	return true
