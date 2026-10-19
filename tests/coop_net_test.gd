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
		Players.set_player(1, 1, "Hosty")
		Players.set_player(2, 1, "Ann")         # stage-1 scenario: the first client may command household 1
		_ses = CoopSession.new()
		var port := _open_lobby()
		if port > 0:
			_ses.time.paused = true             # the test moves game time itself (HoodKit.run); Clock's own process must not
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
	_live_scenario(port)
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
	_check(_ses.host.player_count() == 3, "the refused client took no seat")
	odd.stop()

## Stage 2: a second client makes its own household on its own lot, its order for the host's folk is refused, and live deltas make its view
## track the host (positions exactly, clock, periodic hash check without a mismatch, no extra snapshot). Then it drops and comes back as the same player.
func _live_scenario(port: int) -> void:
	Players.remove_player(2)
	var host_hh := Players.household_of(1)
	_ses.host.live.min_gap_s = 0.03
	_ses.host.live.hash_every_min = 5
	_ses.host.live.full_every_min = 100000
	var res := _tmp("c")
	_spawn([str(port), res, "live", "Bea"])
	var s := _wait_stage(res, "synced", 60.0)
	_check(not s.is_empty(), "live client joined")
	if s.is_empty():
		return
	var pid := int(s["pid"])
	var h := _wait_stage(res, "housed", 40.0)
	_check(not h.is_empty(), "the client made a household and received the new town")
	if h.is_empty():
		return
	var hh := Players.household_of(pid)
	_check(hh > 0 and hh != host_hh, "the host's Players table has a household of its own for the client (%d vs %d)" % [hh, host_hh])
	_check(int(h["local_id"]) == pid and int(h["hh"]) == hh and int(h["host_hh"]) == host_hh, "the client sees the same table: it is player %d with household %d (%s)" % [pid, int(h["hh"]), str(h)])
	_check(Players.primary_household() == host_hh, "the host's own primary household is untouched")
	_check(PlayerLots.lot_of(pid) != "" and PlayerLots.lot_of(pid) != "home", "the client has its own lot (%s)" % PlayerLots.lot_of(pid))
	var fr := _wait_stage(res, "foreign", 30.0)
	_check(not fr.is_empty() and not bool(fr["ok"]), "an order for the host's folk is rejected (%s)" % str(fr.get("msg", "")))
	var own := _wait_stage(res, "own", 30.0)
	_check(not own.is_empty() and bool(own["ok"]), "an order for its own folk is accepted (%s)" % str(own.get("msg", "")))
	var snaps0 := _ses.host.snapshots_sent
	# the host plays 25 game minutes; deltas flow
	for i in 25:
		HoodKit.run(1)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 120:
			_pump()
			OS.delay_msec(5)
	var minute := SimEnv.now_min()
	var tick := {}
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 15000:
		_pump()
		tick = _read(res)
		if int(tick.get("minute", -1)) == minute and tick.get("stage", "") == "tick":
			break
		OS.delay_msec(10)
	_check(int(tick.get("minute", -1)) == minute, "the client's clock follows the host's (%s vs %d)" % [str(tick.get("minute", -1)), minute])
	var off := 0
	var tiles: Dictionary = tick.get("tiles", {})
	for f in WorldIface.all_folk():
		if int(f.household_id) > 0:
			var tt: Array = tiles.get(str(f.id), [])
			if tt.size() != 2 or int(tt[0]) != f.tile.x or int(tt[1]) != f.tile.y:
				off += 1
	_check(off == 0 and tiles.size() >= 4, "every household folk is where the host has it (%d of %d off)" % [off, tiles.size()])
	_check(int(tick.get("deltas", 0)) >= 10, "state deltas arrived (%s)" % str(tick.get("deltas", 0)))
	_check(int(tick.get("hc", 0)) >= 3 and int(tick.get("hm", 0)) == 0 and _ses.host.desyncs_total == 0, "periodic hash checks matched (checks %s, mismatches %s)" % [str(tick.get("hc", 0)), str(tick.get("hm", 0))])
	_check(_ses.host.snapshots_sent == snaps0 and int(tick.get("loads", 0)) == 2, "no extra snapshot was needed (loads %s)" % str(tick.get("loads", 0)))
	_check(_ses.host.live.bytes_sent / maxi(1, _ses.host.live.deltas_sent) < 4000, "deltas are small (%d bytes on average)" % (_ses.host.live.bytes_sent / maxi(1, _ses.host.live.deltas_sent)))
	if _ses.host.desyncs_total > 0:
		var hc: String = str(_ses.host.live.canon_log.get(_ses.host.last_bad_minute, ""))
		var cc: String = str(tick.get("bad", ""))
		var hp := hc.split("|")
		var cp := cc.split("|")
		for i in mini(hp.size(), cp.size()):
			if hp[i] != cp[i]:
				print("DESYNC part ", i, " host=", hp[i], " client=", cp[i])
		print("DESYNC sizes ", hp.size(), " ", cp.size(), " minute ", _ses.host.last_bad_minute)
	# TIME reached the client
	var ts: Dictionary = tick.get("time_state", {})
	_check(ts.has("pace") and ts.get("paused", false), "the client knows the pace and pause state (%s)" % str(ts))
	# reconnect: same player, same household
	var token := str(s["token"])
	for p in _pids:
		OS.kill(p)
	_pids.clear()
	var res2 := _tmp("d")
	_spawn([str(port), res2, "rejoin", "Bea", token])
	var r := _wait_stage(res2, "synced", 60.0)
	_check(not r.is_empty() and int(r["pid"]) == pid, "the dropped player came back as the same player")
	_check(Players.household_of(pid) == hh and _ses.host.player_count() == 3, "with the same household, no ghost seat (%d)" % _ses.host.player_count())
	for p in _pids:
		OS.kill(p)
	_pids.clear()

# ------------------------------------------------------------------ plumbing
func _clean_files() -> void:
	for tag in ["a", "b", "c", "d"]:
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
