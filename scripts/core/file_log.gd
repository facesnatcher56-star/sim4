class_name FileLog
extends Logger
## Playtest log: in an exported build, everything the game prints (and every engine error) is also written to `folk.log` next to the exe.
## The previous run's log is kept as `folk.old.log`; one run is capped at MAX_BYTES so a runaway error cannot fill the disk.
## Editor runs do nothing (the editor already has its own output panel).
const MAX_BYTES := 8 * 1024 * 1024

static var _installed := false
var _file: FileAccess = null
var _bytes := 0
var _mutex := Mutex.new()

static func install() -> void:
	if _installed or OS.has_feature("editor"):
		return
	var dir := OS.get_executable_path().get_base_dir()
	var path := dir.path_join("folk.log")
	var old := dir.path_join("folk.old.log")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(old)
		DirAccess.rename_absolute(path, old)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return                       # read-only folder: just play without a file log
	var l := FileLog.new()
	l._file = f
	l._write("folk.log  %s  Godot %s  %s" % [Time.get_datetime_string_from_system(), Engine.get_version_info().get("string", "?"), OS.get_name()])
	OS.add_logger(l)
	_installed = true

func _write(line: String) -> void:
	_mutex.lock()
	if _file != null and _bytes < MAX_BYTES:
		_file.store_line(line)
		_file.flush()
		_bytes += line.length() + 1
		if _bytes >= MAX_BYTES:
			_file.store_line("-- log full, further lines dropped --")
			_file.flush()
	_mutex.unlock()

func _log_message(message: String, error: bool) -> void:
	_write(("ERR " if error else "") + message.strip_edges(false, true))

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
	var kind := "ERROR"
	match error_type:
		Logger.ERROR_TYPE_WARNING: kind = "WARNING"
		Logger.ERROR_TYPE_SCRIPT: kind = "SCRIPT ERROR"
		Logger.ERROR_TYPE_SHADER: kind = "SHADER ERROR"
	_write("%s: %s %s\n   at %s (%s:%d)" % [kind, code, rationale, function, file, line])
