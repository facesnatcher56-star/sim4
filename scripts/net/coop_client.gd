class_name CoopClient
extends RefCounted
## Client-side protocol logic (transport-free, like CoopHost). Handshake, snapshot download + load, state hash report,
## heartbeats, command send with seq / ack / re-send. States: idle, handshake, loading, synced, desync, refused, ended, lost.

signal state_changed(state: String, text: String)
signal progress(fraction: float)
signal lobby_updated(lobby: Dictionary)
signal event_received(kind: String, text: String, data: Dictionary)
signal command_result(seq: int, ok: bool, msg: String)
signal snapshot_loaded(hash: String)
signal time_updated(state: Dictionary)          # stage 3: pace / skip / pause / vote
signal household_result(ok: bool, msg: String, lot: String)
signal alert_received(text: String, data: Dictionary)
signal delta_applied(minute: int)

var send_fn: Callable                                  # (bytes, channel)
var load_fn: Callable = CoopSnapshot.load_text         # (json text) -> "" or reason
var hash_fn: Callable = CoopHash.of_world
var view_fn: Callable = CoopView.apply                 # (delta dict) -> "" or why a snapshot is needed
var time_state: Dictionary = {}
var deltas: int = 0
var resyncs: int = 0
var hash_checks: int = 0
var hash_mismatches: int = 0
var last_delta_minute: int = -1
var player_name: String = "Player"
var token: String = ""
var player_id: int = 0
var host_name: String = ""
var state: String = "idle"
var status: String = ""
var lobby: Dictionary = {}
var ping_s: float = 2.0
var timeout_s: float = 10.0
var resend_s: float = 2.0
var max_tries: int = 6
var next_seq: int = 1
var pending: Dictionary = {}          # seq -> {bytes, sent, tries}
var ras := CoopReassembler.new()
var loads: int = 0
var last_hash: String = ""
var host_hash: String = ""
var last_ack_ms: int = 0
var _last_rx: float = 0.0
var _next_ping: float = 0.0
var _ping_n: int = 0
var _desync_retries: int = 0
var _resync_at: float = -1.0       # when to ask again after a damaged / mismatching snapshot (the host spaces requests out)

func hello(now: float) -> void:
	ras.clear()
	_last_rx = now
	_next_ping = now + ping_s
	_go("handshake", "Joining the host...")
	_send(CoopProto.HELLO, {"proto": CoopProto.VERSION, "build": CoopProto.build_id(), "name": player_name, "token": token})

func leave() -> void:
	if state != "idle":
		_send(CoopProto.BYE)
	_go("idle", "You left the game.")

## Queue an order for one of your folk. Returns its sequence number (re-sent until the host acknowledges it).
func send_command(folk_id: int, action: String, args: Dictionary, now: float) -> int:
	var seq := next_seq
	next_seq += 1
	var b := CoopProto.encode(CoopProto.CMD, {"player_id": player_id, "folk_id": folk_id, "action": action, "args": args,
		"game_minute": SimEnv.now_min(), "seq": seq})
	if b.is_empty():
		command_result.emit(seq, false, "That order could not be sent.")
		return seq
	pending[seq] = {"bytes": b, "sent": now, "tries": 1}
	if state in ["synced", "desync", "loading"]:
		_raw(b, CoopProto.CH_CONTROL)
	return seq

## Stage 2: from now on Commands.run (the one door the UI uses) sends orders to the host instead of running them here.
func install_remote() -> void:
	Commands.remote = Callable(self, "_remote_run")

func uninstall_remote() -> void:
	Commands.remote = Callable()

func _remote_run(env: Dictionary) -> Dictionary:
	if state != "synced":
		return {"ok": false, "msg": "Not connected to the host yet."}
	var seq := send_command(int(env.get("folk_id", -1)), str(env["action"]), CoopCommands.to_wire(env.get("args", {})), _last_rx)
	return {"ok": true, "msg": "", "pending": true, "seq": seq}

func request_snapshot() -> void:
	_send(CoopProto.SNAP_REQ, {"why": "refresh"})

func set_ready(v: bool) -> void:
	_send(CoopProto.READY, {"ready": v})

## Stage 2: ask the host to make my household (HouseholdSetup dictionary) on `lot_id` ("" = any free home).
func send_household(h: Dictionary, lot_id: String = "") -> bool:
	var data := CoopHouseholds.pack(h)
	if data.size() > CoopProto.MAX_DELTA_BYTES:
		return false
	_send(CoopProto.HOUSEHOLD, {"lot": lot_id, "data": data})
	return true

## Stage 3: "pause" + yes = call (or accept) a pause vote, "pause" + no = decline, "resume" = carry on.
func send_vote(kind: String, yes: bool = true) -> void:
	_send(CoopProto.VOTE, {"kind": kind, "yes": yes})

func send_active(n: int = 0) -> void:
	_send(CoopProto.ACTIVE, {"n": n})

func tick(now: float) -> void:
	if state in ["idle", "connecting", "refused", "ended", "lost", "failed"]:
		return
	if now - _last_rx > timeout_s:
		pending_fail_keep()
		_go("lost", "Lost contact with the host.")
		return
	if _resync_at >= 0.0 and now >= _resync_at:
		_resync_at = -1.0
		request_snapshot()
	if now >= _next_ping:
		_next_ping = now + ping_s
		_ping_n += 1
		_send(CoopProto.PING, {"n": _ping_n})
	for seq in pending.keys():
		var e: Dictionary = pending[seq]
		if now - float(e["sent"]) >= resend_s and state in ["synced", "desync"]:
			if int(e["tries"]) >= max_tries:
				pending.erase(seq)
				command_result.emit(seq, false, "The host did not answer that order.")
			else:
				e["tries"] += 1
				e["sent"] = now
				_raw(e["bytes"], CoopProto.CH_CONTROL)

## The transport reports a dead / unreachable connection.
func mark_lost(text: String) -> void:
	pending_fail_keep()
	_go("lost", text)

func mark_connecting(text: String) -> void:
	_go("connecting", text)

func mark_failed(text: String) -> void:
	_go("failed", text)

## Called after a lost connection so the same seats / pending orders carry over to the next hello().
func pending_fail_keep() -> void:
	for seq in pending:
		pending[seq]["sent"] = -100.0

func on_packet(bytes: PackedByteArray, now: float) -> void:
	var r := CoopProto.decode(bytes)
	if not r["ok"]:
		return
	_last_rx = now
	var m: Dictionary = r["m"]
	match int(r["t"]):
		CoopProto.WELCOME:
			token = str(m["token"])
			player_id = int(m["player_id"])
			host_name = str(m["host"])
			_go("loading", "Waiting for the town from %s..." % host_name)
			for seq in pending:
				pending[seq]["sent"] = -100.0
		CoopProto.REFUSE:
			_go("refused", str(m["reason"]))
		CoopProto.KICK:
			token = ""
			_go("ended", str(m["reason"]))
		CoopProto.LOBBY:
			lobby = {"host": m["host"], "max": m["max"], "peers": m["peers"]}
			lobby_updated.emit(lobby)
		CoopProto.CHUNK:
			_chunk(m)
		CoopProto.SYNC:
			_sync(m)
		CoopProto.ACK:
			var seq2: int = m["seq"]
			last_ack_ms = int(m["minute"])
			if pending.erase(seq2):
				command_result.emit(seq2, bool(m["ok"]), str(m["msg"]))
		CoopProto.EVENT:
			match str(m["kind"]):
				"household": household_result.emit(bool(m["data"].get("ok", false)), str(m["text"]), str(m["data"].get("lot", "")))
				"alert": alert_received.emit(str(m["text"]), m["data"])
			event_received.emit(str(m["kind"]), str(m["text"]), m["data"])
		CoopProto.DELTA:
			_delta(m)
		CoopProto.TIME:
			time_state = m["d"]
			time_updated.emit(time_state)
		_:
			pass            # PONG and anything else: the heartbeat clock above is all we need

func _chunk(m: Dictionary) -> void:
	var why := ras.add(int(m["xfer"]), int(m["idx"]), int(m["total"]), int(m["raw"]), str(m["sum"]), str(m["hash"]), m["data"])
	if why != "":
		return
	progress.emit(ras.progress())
	_go("loading", "Downloading the town... %d%%" % roundi(ras.progress() * 100.0))
	if not ras.complete():
		return
	var a := ras.assemble()
	if not a["ok"]:
		_go("desync", "The town download was damaged. Asking again...")
		_resync_at = _last_rx + resend_s
		return
	var text := CoopSnapshot.unpack(a["data"], ras.raw)
	if text == "":
		_go("desync", "The town download could not be unpacked. Asking again...")
		_resync_at = _last_rx + resend_s
		return
	var err: String = load_fn.call(text)
	if err != "":
		_go("ended", err)
		return
	loads += 1
	if player_id > 0:
		Players.local_id = player_id       # a snapshot load resets the systems; this machine's player is still us
	host_hash = ras.state_hash
	last_hash = str(hash_fn.call())
	snapshot_loaded.emit(last_hash)
	_send(CoopProto.HASH, {"xfer": ras.xfer, "hash": last_hash, "minute": SimEnv.now_min()})

## Stage 2: a live delta. Applied to the local view; a periodic hash goes back; a view that cannot follow asks for a snapshot.
func _delta(m: Dictionary) -> void:
	if state != "synced":
		return
	var d := CoopLive.decode(m["data"])
	var why: String = str(view_fn.call(d))
	deltas += 1
	last_delta_minute = int(m["minute"])
	delta_applied.emit(last_delta_minute)
	if why != "":
		resyncs += 1
		if _resync_at < 0.0:
			_resync_at = _last_rx + 0.2
		return
	if str(m["hash"]) != "":
		hash_checks += 1
		_send(CoopProto.HASH, {"xfer": 0, "hash": str(hash_fn.call()), "minute": int(m["minute"])})

func _sync(m: Dictionary) -> void:
	if int(m["xfer"]) == 0:                 # answer to a periodic check
		if not bool(m["ok"]):
			hash_mismatches += 1
		return
	if bool(m["ok"]):
		_desync_retries = 0
		_go("synced", "Connected to %s." % host_name)
	elif _desync_retries < 2:
		_desync_retries += 1
		_go("desync", "Your town did not match the host's. Fetching it again...")
		_resync_at = _last_rx + resend_s
	else:
		_go("ended", "Your town keeps differing from the host's. Please leave and join again.")

func _go(s: String, text: String) -> void:
	if s != state or text != status:
		state = s
		status = text
		state_changed.emit(s, text)

func _send(type: int, fields: Dictionary = {}) -> void:
	var b := CoopProto.encode(type, fields)
	if not b.is_empty():
		_raw(b, CoopProto.CH_CONTROL)

func _raw(b: PackedByteArray, channel: int) -> void:
	if send_fn.is_valid():
		send_fn.call(b, channel)
