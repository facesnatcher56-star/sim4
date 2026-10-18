class_name SimEnv
extends RefCounted
## Resolves the Events / Data / Clock singletons WITHOUT referencing autoload identifiers at compile time,
## so sim code compiles and runs under `--script` (headless tests) as well as in the full game.
## Looks the autoload node up in the scene tree; falls back to a private standalone instance.

static var _events = null
static var _data = null
static var _clock = null

static func _tree_node(node_name: String):
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var root: Window = (ml as SceneTree).root
		if root != null:
			return root.get_node_or_null(node_name)
	return null

static func events():
	if _events == null or not is_instance_valid(_events):
		_events = _tree_node("Events")
		if _events == null:
			_events = load("res://scripts/core/events.gd").new()
	return _events

static func data():
	if _data == null or not is_instance_valid(_data):
		_data = _tree_node("Data")
		if _data == null:
			_data = load("res://scripts/core/data.gd").new()
			_data.load_all()
	return _data

static func clock():
	if _clock == null or not is_instance_valid(_clock):
		_clock = _tree_node("Clock")
		if _clock == null:
			_clock = load("res://scripts/core/clock.gd").new()
	return _clock

## Replace all three with fresh private instances (for tests). Autoload nodes are never freed.
static func use_standalone() -> void:
	_release(_events)
	_release(_data)
	_release(_clock)
	_events = load("res://scripts/core/events.gd").new()
	_data = load("res://scripts/core/data.gd").new()
	_data.load_all()
	_clock = load("res://scripts/core/clock.gd").new()

static func release_standalone() -> void:
	_release(_events)
	_release(_data)
	_release(_clock)
	_events = null
	_data = null
	_clock = null

static func _release(n) -> void:
	if n != null and is_instance_valid(n) and n is Node and not (n as Node).is_inside_tree():
		(n as Node).free()

## Current game minute counter and hour-of-day helpers.
static func now_min() -> int:
	return int(clock().total_minutes)

static func hour_f() -> float:
	return float(clock().hour_f())

static func emit(sig: String, a = null, b = null, c = null) -> void:
	var ev = events()
	if a == null:
		ev.emit_signal(sig)
	elif b == null:
		ev.emit_signal(sig, a)
	elif c == null:
		ev.emit_signal(sig, a, b)
	else:
		ev.emit_signal(sig, a, b, c)
