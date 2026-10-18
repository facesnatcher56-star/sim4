extends RefCounted
## In-engine deadman watchdog, independent of tools/godot_guard.ps1.
## A worker thread checks a wall-clock deadline every 200 ms; on expiry it prints "TIMEOUT in <label>" and kills this process
## with OS.kill (the only thing that works when a test is stuck in a synchronous loop). Exit code is not controllable that way,
## so the line TIMEOUT is the signal; the guard also reports the non-zero exit.
## Usage (in a SceneTree script):  const Watchdog := preload("res://tests/watchdog.gd")
##   var wd := Watchdog.start(Watchdog.budget_from(args, 300), "run_one")   # then wd.set_label("file.gd", 300) per file
##   ... wd.stop() before quit()
## Probes pass no --budget normally; the default budget applies. `Watchdog.user_args()` returns the args without --budget=.

var _mutex := Mutex.new()
var _thread := Thread.new()
var _stop := false
var _total_end_ms := 0
var _file_end_ms := 0
var _label := ""

static func budget_from(args: PackedStringArray, default_s: float) -> float:
	for a in args:
		if a.begins_with("--budget="):
			return float(a.substr(9))
	return default_s

static func user_args() -> PackedStringArray:
	var out := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--budget="):
			out.append(a)
	return out

static func start(total_s: float, label: String) -> RefCounted:
	var wd: RefCounted = load("res://tests/watchdog.gd").new()
	wd._label = label
	wd._total_end_ms = Time.get_ticks_msec() + int(total_s * 1000.0)
	wd._thread.start(wd._loop)
	return wd

## Sets the current file label and its own time limit (0 = only the total budget applies).
func set_label(label: String, file_s: float) -> void:
	_mutex.lock()
	_label = label
	_file_end_ms = Time.get_ticks_msec() + int(file_s * 1000.0) if file_s > 0.0 else 0
	_mutex.unlock()

func stop() -> void:
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	if _thread.is_started():
		_thread.wait_to_finish()

func _loop() -> void:
	while true:
		OS.delay_msec(200)
		_mutex.lock()
		var stop := _stop
		var now := Time.get_ticks_msec()
		var over_file := _file_end_ms > 0 and now > _file_end_ms
		var over_total := now > _total_end_ms
		var label := _label
		_mutex.unlock()
		if stop:
			return
		if over_file or over_total:
			print("TIMEOUT in %s (%s budget exceeded)" % [label, "per-file" if over_file else "total"])
			OS.kill(OS.get_process_id())
			return
