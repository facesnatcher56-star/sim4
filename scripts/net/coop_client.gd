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

var send_fn: Callable                                  # (bytes, channel)
var load_fn: Callable = CoopSnapshot.load_text         # (json text) -> "" or reason
var hash_fn: Callable = CoopHash.of_world
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

func request_snapshot() -> void:
	_send(CoopProto.SNAP_REQ, {"why": "refresh"})

func set_ready(v: bool) -> void:
	_send(CoopProto.READY, {"ready": v})

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
			event_received.emit(str(m["kind"]), str(m["text"]), m["data"])
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
	host_hash = ras.state_hash
	last_hash = str(hash_fn.call())
	snapshot_loaded.emit(last_hash)
	_send(CoopProto.HASH, {"xfer": ras.xfer, "hash": last_hash, "minute": SimEnv.now_min()})

func _sync(m: Dictionary) -> void:
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
