class_name SettingsKeys
extends RefCounted
## Rebindable input actions (InputMap). Action names are the contract for any script that reads input:
## use Input.is_action_pressed("sim_pan_left") / event.is_action_pressed("sim_pause") instead of raw keys.
## Bindings persist in settings.cfg under [keys].

## [action, label, group, default events as text]. Event text: "k:<keycode>[:ctrl|shift|alt]" or "m:<mouse button>".
const ACTIONS := [
	["sim_pan_up", "Pan up", "Camera", ["k:%d" % KEY_W]],
	["sim_pan_down", "Pan down", "Camera", ["k:%d" % KEY_S]],
	["sim_pan_left", "Pan left", "Camera", ["k:%d" % KEY_A]],
	["sim_pan_right", "Pan right", "Camera", ["k:%d" % KEY_D]],
	["sim_rotate_left", "Rotate view left", "Camera", ["k:%d" % KEY_Q]],
	["sim_rotate_right", "Rotate view right", "Camera", ["k:%d" % KEY_E]],
	["sim_zoom_in", "Zoom in", "Camera", ["m:%d" % MOUSE_BUTTON_WHEEL_UP]],
	["sim_zoom_out", "Zoom out", "Camera", ["m:%d" % MOUSE_BUTTON_WHEEL_DOWN]],
	["sim_wall_mode", "Cycle wall view", "Camera", ["k:%d" % KEY_TAB]],
	["sim_level_up", "Floor up", "Camera", ["k:%d" % KEY_PAGEUP]],
	["sim_level_down", "Floor down", "Camera", ["k:%d" % KEY_PAGEDOWN]],
	["sim_pause", "Pause / resume", "Time", ["k:%d" % KEY_SPACE]],
	["sim_speed_1", "Normal speed", "Time", ["k:%d" % KEY_1]],
	["sim_speed_2", "Fast", "Time", ["k:%d" % KEY_2]],
	["sim_speed_3", "Fastest", "Time", ["k:%d" % KEY_3]],
	["sim_build", "Build / Buy mode", "Windows", ["k:%d" % KEY_B]],
	["sim_map", "Neighbourhood map", "Windows", ["k:%d" % KEY_M]],
	["sim_help", "Controls help", "Windows", ["k:%d" % KEY_F1]],
	["sim_undo", "Undo build action", "Build / Buy", ["k:%d:ctrl" % KEY_Z]],
	["sim_build_rotate", "Rotate item", "Build / Buy", ["k:%d" % KEY_R]],
]

static var _custom: Dictionary = {}     # action -> Array[String] when the player changed it

static func event_from_text(t: String) -> InputEvent:
	var p := t.split(":")
	if p.size() < 2 or not p[1].is_valid_int():
		return null
	if p[0] == "m":
		var m := InputEventMouseButton.new()
		m.button_index = int(p[1]) as MouseButton
		return m
	if p[0] == "k":
		var k := InputEventKey.new()
		k.keycode = int(p[1]) as Key
		k.ctrl_pressed = p.size() > 2 and "ctrl" in p[2]
		k.shift_pressed = p.size() > 2 and "shift" in p[2]
		k.alt_pressed = p.size() > 2 and "alt" in p[2]
		return k
	return null

static func event_to_text(e: InputEvent) -> String:
	if e is InputEventMouseButton:
		return "m:%d" % e.button_index
	if e is InputEventKey:
		var mods := ""
		if e.ctrl_pressed: mods += "ctrl"
		if e.shift_pressed: mods += "shift"
		if e.alt_pressed: mods += "alt"
		var code: int = e.keycode if e.keycode != KEY_NONE else e.physical_keycode
		return "k:%d" % code if mods == "" else "k:%d:%s" % [code, mods]
	return ""

static func default_events(action: String) -> Array:
	for a in ACTIONS:
		if a[0] == action:
			return a[3]
	return []

static func events_of(action: String) -> Array:
	return _custom.get(action, default_events(action))

## Human text for the current binding, e.g. "W", "Ctrl+Z", "Mouse Wheel Up".
static func binding_text(action: String) -> String:
	var parts: Array = []
	for t in events_of(action):
		var e := event_from_text(t)
		if e != null:
			parts.append(e.as_text().replace(" (Physical)", ""))
	return " / ".join(parts) if parts.size() > 0 else "Unbound"

## Creates / refreshes every InputMap action from defaults + custom bindings.
static func apply() -> void:
	for a in ACTIONS:
		var name: String = a[0]
		if not InputMap.has_action(name):
			InputMap.add_action(name)
		InputMap.action_erase_events(name)
		for t in events_of(name):
			var e := event_from_text(t)
			if e != null:
				InputMap.action_add_event(name, e)

## Binds one event to an action. Anything else using the same event loses it (it is swapped, never double-bound).
## Returns the action that was displaced ("" if none).
static func rebind(action: String, e: InputEvent) -> String:
	var t := event_to_text(e)
	if t == "":
		return ""
	var displaced := ""
	for a in ACTIONS:
		var other: String = a[0]
		if other != action and t in events_of(other):
			var rest: Array = events_of(other).filter(func(x): return x != t)
			_custom[other] = rest
			displaced = other
	_custom[action] = [t]
	apply()
	GameSettings.bus.changed.emit("keys", action)
	GameSettings._dirty = true
	return displaced

static func reset_all() -> void:
	_custom.clear()
	apply()
	GameSettings.bus.changed.emit("keys", "")

static func load_from(cf: ConfigFile) -> void:
	_custom.clear()
	if cf != null and cf.has_section("keys"):
		for a in ACTIONS:
			var raw = cf.get_value("keys", a[0]) if cf.has_section_key("keys", a[0]) else null
			if raw is Array:
				var ok: Array = []
				for t in raw:
					if t is String and event_from_text(t) != null:
						ok.append(t)
				_custom[a[0]] = ok
	apply()

static func save_to(cf: ConfigFile) -> void:
	if cf.has_section("keys"):
		cf.erase_section("keys")
	for action in _custom:
		cf.set_value("keys", action, _custom[action])

## Makes sure the actions exist (default bindings) without touching saved settings; for scenes built outside Main.
static func ensure_actions() -> void:
	for a in ACTIONS:
		if not InputMap.has_action(a[0]):
			apply()
			return
