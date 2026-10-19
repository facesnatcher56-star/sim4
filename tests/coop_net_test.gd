extends RefCounted
## End to end over real sockets on localhost: this process is the HOST (the real game world); a second headless Godot
## (tests/fixtures/coop_client.gd, started through tools/godot_guard.ps1 with a short budget) is the CLIENT.
## 1) join -> snapshot -> same state hash -> command -> the host applies it -> result event on the client -> fresh snapshot -> same hash.
## 2) kill the client process, start another with the saved token: same seat, fresh snapshot, same hash.
## 3) a client built from another game version is refused with a plain-language reason.

const HoodKit := preload("res://tests/hood_kit.gd")
const Kit := preload("res://tests/coop_kit.gd")
var fails: Array = []
var _pids: Array = []
var _ses: CoopSession

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_clean_files()
	CoopProto.build_override = "test-build"
	HoodKit.new_game("classic")
	HoodKit.set_time(2, 9)
	HoodKit.run(30)
	var cmd := Kit.find_command()
	_check(not cmd.is_empty(), "found a runnable command")
	if not cmd.is_empty():
		_ses = CoopSession.new()
		var port := _open_lobby()
		if port > 0:
			_scenario(port, cmd)
		_ses.stop()
	for pid in _pids:
		OS.kill(pid)
	_pids.clear()
	_clean_files()
	CoopProto.build_override = ""
	HoodKit.teardown()
	return fails

func _open_lobby() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 12:
		var port := rng.randi_range(20000, 58000)
		if _ses.start_host(port, "Hosty") == "":
			return port
	_check(false, "could not open a lobby on any random port")
	return 0

func _scenario(port: int, cmd: Dictionary) -> void:
	var f: Folk = cmd["folk"]
	var res_a := _tmp("a")
	_spawn([str(port), res_a, "cmd", "Ann", "-", str(cmd["iid"]), str(cmd["tid"])])
	var a := _wait_stage(res_a, "synced", 60.0)
	_check(not a.is_empty(), "client A joined and received the snapshot")
	if a.is_empty():
		return
	var host_hash := CoopHash.of_world()
	_check(a["hash"] == host_hash, "client A's state hash equals the host's (%s vs %s)" % [a["hash"], host_hash])
	_check(a["host_hash"] == host_hash, "the hash the host announced matches too")
	_check(int(a["pid"]) == 2 and str(a["token"]) != "", "client A is player 2 with a token")
	_check(_ses.host.player_count() == 2, "the host sees two players")
	var lob := _ses.host.lobby_dict()
	_check((lob["peers"] as Array).size() == 1 and lob["peers"][0]["name"] == "Ann" and lob["peers"][0]["ready"], "lobby shows Ann ready")
	# the command (sent by the fixture right after syncing)
	var b := _wait_stage(res_a, "acked", 30.0)
	_check(not b.is_empty() and bool(b["ok"]), "the host acknowledged the command as applied (%s)" % str(b.get("msg", "")))
	_check(f.current != null or f.queue.size() > 0, "the host's authoritative state changed: the folk has the order")
	var ev := _wait_flag(res_a, "saw_command_event", 10.0)
	_check(not ev.is_empty(), "the command result was published to the client as an event")
	# the host simulates on, then asks the client to refresh
	HoodKit.run(20)
	var h2 := CoopHash.of_world()
	_check(h2 != host_hash, "the host world moved on")
	_ses.host.publish_event("resync", "")
	var c := _wait_stage(res_a, "resynced", 40.0)
	_check(not c.is_empty(), "the client fetched a fresh snapshot on request")
	if not c.is_empty():
		_check(c["hash"] == h2, "after the fresh snapshot the hashes match again (%s vs %s)" % [c["hash"], h2])
		_check(int(c["loads"]) == 2, "exactly two loads")
	# reconnect: kill the client process, start a new one with the same token
	var token := str(a["token"])
	for pid in _pids:
		OS.kill(pid)
	_pids.clear()
	var res_b := _tmp("b")
	_spawn([str(port), res_b, "rejoin", "Ann", token])
	var r := _wait_stage(res_b, "synced", 60.0)
	_check(not r.is_empty(), "the rejoining client received a snapshot")
	if not r.is_empty():
		_check(int(r["pid"]) == 2, "it got its old seat back (player %s)" % str(r["pid"]))
		_check(r["hash"] == CoopHash.of_world(), "its hash matches the host's again")
		_check(_ses.host.player_count() == 2, "still two players, no ghost seat (%d)" % _ses.host.player_count())
	for pid in _pids:
		OS.kill(pid)
	_pids.clear()
	# version mismatch, real sockets, in-process client: it says another build, the host expects this one
	var odd := CoopSession.new()
	CoopProto.build_override = "old-build"
	odd.join("127.0.0.1:%d" % port, "Old")
	var t0 := Time.get_ticks_msec()
	while odd.client.state == "connecting" and Time.get_ticks_msec() - t0 < 8000:
		_pump()
		odd.pump(0.02)
		OS.delay_msec(5)
	CoopProto.build_override = "test-build"           # hello was sent as old-build; the host now compares with test-build
	t0 = Time.get_ticks_msec()
	while odd.client.state == "handshake" and Time.get_ticks_msec() - t0 < 8000:
		_pump()
		odd.pump(0.02)
		OS.delay_msec(5)
	_check(odd.client.state == "refused", "a mismatching build is refused (%s)" % odd.client.state)
	_check("version" in odd.client.status.to_lower() and "host" in odd.client.status.to_lower(), "with a plain-language reason: " + odd.client.status)
	_check(_ses.host.player_count() == 2, "the refused client took no seat")
	odd.stop()

# ------------------------------------------------------------------ plumbing
func _clean_files() -> void:
	for tag in ["a", "b"]:
		DirAccess.remove_absolute(_tmp(tag))

func _tmp(tag: String) -> String:
	return OS.get_temp_dir().path_join("coop_%d_%s.json" % [OS.get_process_id(), tag])

func _spawn(client_args: Array) -> void:
	var wt := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var guard := ProjectSettings.globalize_path("res://tools/godot_guard.ps1")
	var godot_args := ["--headless", "--path", wt, "--script", "res://tests/fixtures/coop_client.gd", "--"]
	godot_args.append_array(client_args)
	godot_args.append("--budget=50")
	var pid: int
	if OS.get_name() == "Windows" and FileAccess.file_exists(guard):
		pid = OS.create_process("powershell", ["-NoProfile", "-File", guard, "-Seconds", "60", "-MaxSeconds", "75", "-Args", ",".join(PackedStringArray(godot_args))])
	else:
		pid = OS.create_process(OS.get_executable_path(), PackedStringArray(godot_args))    # no PowerShell (Linux/Mac): the in-engine --budget watchdog bounds the client
	_check(pid > 0, "spawned a client process")
	if pid > 0:
		_pids.append(pid)

var _last_ms := 0
func _pump() -> void:
	var now := Time.get_ticks_msec()
	_ses.pump(0.02 if _last_ms == 0 else minf(5.0, float(now - _last_ms) / 1000.0))
	_last_ms = now

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var v: Variant = JSON.parse_string(txt)
	return v if v is Dictionary else {}

## Pump the host's network until the client's result file has reached `stage` (or the time is up). {} on timeout.
func _wait_stage(path: String, stage: String, seconds: float) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		_pump()
		var d := _read(path)
		if (d.get("stages", []) as Array).has(stage):
			return d
		OS.delay_msec(10)
	return {}

func _wait_flag(path: String, key: String, seconds: float) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		_pump()
		var d := _read(path)
		if d.get(key, false):
			return d
		OS.delay_msec(10)
	return {}
