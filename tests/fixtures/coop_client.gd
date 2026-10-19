extends SceneTree
## Headless co-op CLIENT process for tests/coop_net_test.gd (never run by the test runner itself).
##   Godot --headless --path <wt> --script res://tests/fixtures/coop_client.gd -- <port> <result file> <mode> <name> [token] [iid] [target id] --budget=<s>
## modes: stay (join, sync, idle), cmd (join, sync, send one command, wait for the ack, then re-sync when the host publishes a
## "resync" event), rejoin (like stay, with the saved token). Progress is written as JSON to <result file> (stage + facts).
const Watchdog := preload("res://tests/watchdog.gd")

var _wd
var _ses: CoopSession
var _args: PackedStringArray
var _result := {}
var _path := ""
var _mode := ""
var _iid := ""
var _tid := -1
var _stage := 0
var _cmd_seq := -1
var _t0 := 0
var _started := false
var _manager: SystemsManager

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_start()
	elif _ses != null:
		_ses.pump(0.01)
		_step()
		OS.delay_msec(5)
	return false

func _start() -> void:
	_args = Watchdog.user_args()
	_wd = Watchdog.start(Watchdog.budget_from(OS.get_cmdline_user_args(), 40.0), "coop_client")
	var port := int(_args[0])
	_path = _args[1]
	_mode = _args[2]
	var pname := _args[3]
	var token := _args[4] if _args.size() > 4 and _args[4] != "-" else ""      # "-" = none (an empty argument would be lost on the way through the guard)
	_iid = _args[5] if _args.size() > 5 else ""
	_tid = int(_args[6]) if _args.size() > 6 else -1
	TestFixture.reset()
	_manager = SystemsManager.new()
	_manager.autosave_enabled = false
	_manager.setup()
	CoopProto.build_override = "test-build"
	_ses = CoopSession.new()
	var err := _ses.join("127.0.0.1:%d" % port, pname)
	if err != "":
		_write("error", {"err": err})
		_finish(2)
		return
	_ses.client.token = token
	_ses.client.state_changed.connect(func(st, tx): print("[coop_client] %s: %s" % [st, tx]))
	_ses.client.event_received.connect(_on_event)
	_ses.client.command_result.connect(_on_result)
	_ses.client.snapshot_loaded.connect(func(h): _result["loaded_hash"] = h)
	_t0 = Time.get_ticks_msec()
	_write("connecting", {})

func _step() -> void:
	var c := _ses.client
	if c == null:
		return
	if c.state in ["refused", "ended", "failed"]:
		_write("refused", {"state": c.state, "text": c.status})
		_finish(0)
		return
	if _stage == 0 and c.state == "synced":
		_stage = 1
		_write("synced", {"hash": CoopHash.of_world(), "minute": SimEnv.now_min(), "token": c.token, "pid": c.player_id,
			"loads": c.loads, "host_hash": c.host_hash, "folk": _first_folk()})
		if _mode == "cmd":
			_cmd_seq = c.send_command(_first_folk(), "interact", {"interaction_id": _iid, "target_id": _tid}, 0.0)
	elif _stage == 3 and c.state == "synced" and c.loads >= 2:
		_stage = 4
		_write("resynced", {"hash": CoopHash.of_world(), "minute": SimEnv.now_min(), "loads": c.loads, "host_hash": c.host_hash})

func _first_folk() -> int:
	for f in WorldIface.all_folk():
		if int(f.household_id) == 1:
			return int(f.id)
	return -1

func _on_result(seq: int, ok: bool, msg: String) -> void:
	if seq == _cmd_seq:
		_stage = 2
		_write("acked", {"ok": ok, "msg": msg})

func _on_event(kind: String, text: String, _data: Dictionary) -> void:
	_result["last_event"] = kind
	if kind == "command":
		_result["saw_command_event"] = true
		_write("event", {"text": text})
	elif kind == "resync" and _stage == 2:
		_stage = 3
		_ses.client.request_snapshot()

func _write(stage: String, extra: Dictionary) -> void:
	_result["stage"] = stage
	var st: Array = _result.get("stages", [])
	if not st.has(stage):
		st.append(stage)
	_result["stages"] = st
	_result["ms"] = Time.get_ticks_msec() - _t0
	for k in extra:
		_result[k] = extra[k]
	var fa := FileAccess.open(_path, FileAccess.WRITE)       # a half-written file simply fails to parse in the reader, which retries
	if fa != null:
		fa.store_string(JSON.stringify(_result))
		fa.close()

func _finish(code: int) -> void:
	if _wd != null:
		_wd.stop()
	if _ses != null:
		_ses.stop()
	quit(code)
