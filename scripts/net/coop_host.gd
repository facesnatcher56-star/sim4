class_name CoopHost
extends RefCounted
## Host-side lobby and message handling. Transport-free: CoopSession (or a test) feeds it packets and a clock and gives it
## `send_fn(peer, bytes, channel)` / `drop_fn(peer)`. The host sim keeps running as normal; this class only answers peers.
## Players: the host is player 1; joining clients get 2..4. A dropped client keeps its seat (and token) for `rejoin_s` seconds
## and can come back with the same token: it then receives a fresh snapshot like any new joiner.

signal lobby_changed
signal peer_joined(player_id: int, player_name: String)
signal peer_left(player_id: int, reason: String)
signal command_done(player_id: int, env: Dictionary, result: Dictionary)
signal local_alert(text: String, folk_id: int, data: Dictionary)      # a big moment for the host's own player (stage 3)

var send_fn: Callable
var drop_fn: Callable
var snapshot_fn: Callable = CoopSnapshot.pack_world       # () -> {data, raw, sum, hash}; empty/invalid => no snapshots yet
var apply_fn: Callable = CoopCommands.apply               # (env) -> {ok, msg}
var host_name: String = "Host"
var max_players: int = CoopProto.MAX_PEERS
var timeout_s: float = 10.0
var hello_timeout_s: float = 8.0
var rejoin_s: float = 60.0
var snapshot_gap_s: float = 1.5
var rate_per_s: float = 30.0
var rate_burst: float = 60.0
var live := CoopLive.new()                                  # stage 2: live state deltas
var time: CoopTime = null                                   # stage 3: the time model (set by CoopSession / tests)
var household_fn: Callable = CoopHouseholds.join            # (player_id, name, household dict, lot id) -> {ok, msg, hid, lot, folk_ids}
var live_enabled: bool = true
var peers: Dictionary = {}        # transport peer id -> record
var reserved: Dictionary = {}     # token -> {pid, name, at}: dropped clients that may come back
var invalid_total: int = 0
var desyncs_total: int = 0
var last_bad_minute: int = -1
var snapshots_sent: int = 0
var _now: float = 0.0
var _xfer: int = 0

func now() -> float:
	return _now

# ------------------------------------------------------------------ transport events
func peer_connected(id: int, now_s: float) -> void:
	_now = now_s
	peers[id] = {"st": "new", "at": now_s, "seen": now_s, "name": "", "pid": 0, "token": "", "ready": false, "synced": false,
		"rate": CoopRate.new(rate_per_s, rate_burst), "bad": 0, "limited": 0, "xh": {}, "last_seq": 0, "results": {},
		"snap_at": -100.0, "kill_at": 0.0, "live": live.new_peer(), "hh_at": -100.0, "desyncs": 0}

func peer_disconnected(id: int, now_s: float) -> void:
	_now = now_s
	if peers.has(id):
		_remove(id, "connection lost", true)

func on_packet(id: int, bytes: PackedByteArray, now_s: float) -> void:
	_now = now_s
	var p: Dictionary = peers.get(id, {})
	if p.is_empty() or p["st"] == "refused":
		return
	if not (p["rate"] as CoopRate).allow(now_s):
		p["limited"] += 1
		if p["limited"] > 300:
			_kick_record(id, "flood", "You were disconnected for sending too many messages.")
		return
	var r := CoopProto.decode(bytes)
	if not r["ok"]:
		_bad(id, p)
		return
	var t: int = r["t"]
	var m: Dictionary = r["m"]
	if p["st"] == "new" and t != CoopProto.HELLO:
		_bad(id, p)
		return
	p["bad"] = 0
	p["seen"] = now_s
	match t:
		CoopProto.HELLO: _hello(id, p, m)
		CoopProto.PING: _send(id, CoopProto.PONG, {"n": m["n"]})
		CoopProto.CMD: _cmd(id, p, m)
		CoopProto.SNAP_REQ: _snap_req(id, p)
		CoopProto.HASH: _hash(id, p, m)
		CoopProto.READY: _set_ready(p, bool(m["ready"]))
		CoopProto.HOUSEHOLD: _household(id, p, m)
		CoopProto.VOTE: _vote(p, m)
		CoopProto.ACTIVE:
			if time != null:
				time.note_input(int(p["pid"]), now_s)
		CoopProto.BYE: _remove(id, "left the game", false)
		_: _bad(id, p)      # a host->client type sent to the host

func tick(now_s: float) -> void:
	_now = now_s
	for id in peers.keys():
		var p: Dictionary = peers[id]
		match str(p["st"]):
			"new":
				if now_s - float(p["at"]) > hello_timeout_s:
					_drop(id)
			"refused":
				if now_s >= float(p["kill_at"]):
					_drop(id)
			"in":
				if now_s - float(p["seen"]) > timeout_s:
					_remove(id, "timed out", true)
				elif float(p.get("snap_due", 0.0)) > 0.0 and now_s >= float(p["snap_due"]):
					p["snap_due"] = 0.0
					send_snapshot(id)
				elif live_enabled and p["synced"]:
					_live_tick(id, p, now_s)
	for tok in reserved.keys():
		if now_s - float(reserved[tok]["at"]) > rejoin_s:
			reserved.erase(tok)
			lobby_changed.emit()

# ------------------------------------------------------------------ public actions
func kick(player_id: int) -> bool:
	for id in peers:
		if int(peers[id]["pid"]) == player_id and peers[id]["st"] == "in":
			_kick_record(id, "kicked", "The host removed you from the game.")
			return true
	return false

func close() -> void:
	for id in peers.keys():
		if peers[id]["st"] == "in":
			_send(id, CoopProto.KICK, {"code": "host_left", "reason": "The host ended the co-op session."})
			peers[id]["st"] = "refused"
			peers[id]["kill_at"] = _now + 0.5

func publish_event(kind: String, text: String, data: Dictionary = {}) -> void:
	for id in peers:
		if peers[id]["st"] == "in":
			_send(id, CoopProto.EVENT, {"kind": kind, "text": text, "data": data})

func lobby_dict() -> Dictionary:
	var list: Array = []
	for id in peers:
		var p: Dictionary = peers[id]
		if p["st"] == "in":
			list.append({"id": int(p["pid"]), "name": str(p["name"]), "ready": bool(p["ready"]), "away": false})
	for tok in reserved:
		list.append({"id": int(reserved[tok]["pid"]), "name": str(reserved[tok]["name"]), "ready": false, "away": true})
	return {"host": host_name, "max": max_players, "peers": list}

func player_count() -> int:
	var n := 1 + reserved.size()
	for id in peers:
		if peers[id]["st"] == "in":
			n += 1
	return n

## Player ids taking part right now: the host (1) and every connected client.
func connected_pids() -> Array:
	var out: Array = [Players.LOCAL]
	for id in peers:
		if peers[id]["st"] == "in":
			out.append(int(peers[id]["pid"]))
	out.sort()
	return out

func peer_of_player(pid: int) -> int:
	for id in peers:
		if int(peers[id]["pid"]) == pid and peers[id]["st"] == "in":
			return id
	return -1

func send_snapshot(id: int) -> bool:
	if not snapshot_fn.is_valid() or not peers.has(id):
		return false
	var pk: Dictionary = snapshot_fn.call()
	if pk.is_empty():
		return false
	_xfer += 1
	var p: Dictionary = peers[id]
	p["xh"][_xfer] = str(pk["hash"])
	if p["xh"].size() > 4:
		p["xh"].erase(p["xh"].keys()[0])
	p["synced"] = false
	p["snap_due"] = 0.0
	p["snap_at"] = _now
	live.reset_peer(p["live"])
	var chunks := CoopSnapshot.split(pk["data"])
	for i in chunks.size():
		_send(id, CoopProto.CHUNK, {"xfer": _xfer, "idx": i, "total": chunks.size(), "raw": int(pk["raw"]), "sum": str(pk["sum"]),
			"hash": str(pk["hash"]), "data": chunks[i]}, CoopProto.CH_SNAPSHOT)
	snapshots_sent += 1
	return true

# ------------------------------------------------------------------ handlers
func _hello(id: int, p: Dictionary, m: Dictionary) -> void:
	if p["st"] != "new":
		return
	if int(m["proto"]) != CoopProto.VERSION:
		_refuse(id, "version", "Your game speaks co-op version %d but the host uses version %d. Update the game so you both have the same one." % [int(m["proto"]), CoopProto.VERSION])
		return
	if str(m["build"]) != CoopProto.build_id():
		_refuse(id, "build", "Your game version (%s) is not the host's (%s). Both players need the same version of the game." % [str(m["build"]), CoopProto.build_id()])
		return
	var token := str(m["token"])
	var pid := 0
	var resumed := false
	var carry := {}
	if token != "" and reserved.has(token):
		pid = int(reserved[token]["pid"])
		carry = reserved[token]
		reserved.erase(token)
		resumed = true
	elif token != "":
		for oid in peers:                     # the old connection is still there (silent): the same player takes it over
			if oid != id and peers[oid]["st"] == "in" and peers[oid]["token"] == token:
				pid = int(peers[oid]["pid"])
				carry = {"ls": peers[oid]["last_seq"], "res": peers[oid]["results"]}
				_remove(oid, "reconnected", false)
				resumed = true
				break
	if pid == 0:
		if player_count() >= max_players:
			_refuse(id, "full", "The lobby is full (%d of %d players)." % [player_count(), max_players])
			return
		pid = _free_pid()
		token = _new_token()
	p["st"] = "in"
	p["pid"] = pid
	p["token"] = token
	p["name"] = _clean_name(str(m["name"]), pid)
	p["last_seq"] = int(carry.get("ls", 0))        # orders already applied before a drop are never applied again
	p["results"] = carry.get("res", {})
	_send(id, CoopProto.WELCOME, {"proto": CoopProto.VERSION, "build": CoopProto.build_id(), "player_id": pid, "token": token,
		"resumed": resumed, "host": host_name})
	peer_joined.emit(pid, p["name"])
	_broadcast_lobby()
	send_snapshot(id)

func _cmd(id: int, p: Dictionary, m: Dictionary) -> void:
	var seq: int = m["seq"]
	if seq <= int(p["last_seq"]):                         # a re-send: answer again, never apply twice
		var old: Dictionary = p["results"].get(seq, {"seq": seq, "ok": false, "msg": "Already handled.", "minute": SimEnv.now_min()})
		_send(id, CoopProto.ACK, old)
		return
	var ack := {"seq": seq, "ok": false, "msg": "", "minute": SimEnv.now_min()}
	if seq < 1 or int(m["player_id"]) != int(p["pid"]):
		ack["msg"] = "That order did not come from your player."
	else:
		var res: Dictionary = apply_fn.call(m)
		ack["ok"] = bool(res.get("ok", false))
		ack["msg"] = str(res.get("msg", ""))
		command_done.emit(int(p["pid"]), m, res)
		if ack["ok"]:
			var f = WorldIface.get_folk(int(m["folk_id"]))
			publish_event("command", "%s gave an order to %s." % [p["name"], f.name if f != null else "someone"],
				{"player_id": int(p["pid"]), "folk_id": int(m["folk_id"])})
	p["last_seq"] = seq
	p["results"][seq] = ack
	if p["results"].size() > 32:
		p["results"].erase(p["results"].keys()[0])
	_send(id, CoopProto.ACK, ack)

func _snap_req(id: int, p: Dictionary) -> void:
	if _now - float(p["snap_at"]) >= snapshot_gap_s:
		send_snapshot(id)
	else:
		p["snap_due"] = float(p["snap_at"]) + snapshot_gap_s      # too soon after the last one: answer when the gap is over

func _hash(id: int, p: Dictionary, m: Dictionary) -> void:
	var xfer: int = m["xfer"]
	if xfer == 0:                       # the periodic check from a live client
		_periodic_hash(id, p, m)
		return
	if not p["xh"].has(xfer):
		return
	var host_hash: String = p["xh"][xfer]
	var ok: bool = host_hash == str(m["hash"])
	p["synced"] = ok
	if ok:
		p["ready"] = true
	_send(id, CoopProto.SYNC, {"xfer": xfer, "ok": ok, "host_hash": host_hash})
	if ok and time != null:
		_send(id, CoopProto.TIME, {"d": time.state()})
	_broadcast_lobby()

## Stage 2: live deltas. One per peer per `live.min_gap_s` at most; a periodic full snapshot as the safety net.
func _live_tick(id: int, p: Dictionary, now_s: float) -> void:
	var st: Dictionary = p["live"]
	if str(st["need_snap"]) != "":
		st["need_snap"] = ""
		_snap_req(id, p)
		return
	var d := live.build(st, int(p["pid"]), now_s)
	if d.is_empty():
		return
	var hash_s := live.hash_due(int(d["m"]))
	var data := live.encode(d)
	if data.size() > CoopProto.MAX_DELTA_BYTES:           # too big for one message: fall back to a snapshot
		_snap_req(id, p)
		return
	live.deltas_sent += 1
	live.bytes_sent += data.size()
	_send(id, CoopProto.DELTA, {"minute": int(d["m"]), "hash": hash_s, "data": data})

func _periodic_hash(id: int, p: Dictionary, m: Dictionary) -> void:
	var mine: String = str(live.hash_log.get(int(m["minute"]), ""))
	if mine == "":
		return                              # too old to compare
	var ok: bool = mine == str(m["hash"])
	_send(id, CoopProto.SYNC, {"xfer": 0, "ok": ok, "host_hash": mine})
	if not ok:
		p["desyncs"] = int(p["desyncs"]) + 1
		desyncs_total += 1
		last_bad_minute = int(m["minute"])
		_snap_req(id, p)

## Client asks for a snapshot because its view cannot follow (unknown folk, other object count).
func request_resync(id: int) -> void:
	if peers.has(id):
		_snap_req(id, peers[id])

func _household(id: int, p: Dictionary, m: Dictionary) -> void:
	var pid: int = int(p["pid"])
	if _now - float(p["hh_at"]) < 3.0:
		return
	p["hh_at"] = _now
	var res: Dictionary
	if Players.table.has(pid):                  # reconnect / second request: they already live here, just refresh them
		res = {"ok": true, "msg": "", "hid": Players.household_of(pid), "lot": PlayerLots.lot_of(pid), "folk_ids": []}
	else:
		var raw := CoopHouseholds.parse(m["data"])
		res = household_fn.call(pid, str(p["name"]), raw, str(m["lot"]))
		if bool(res["ok"]):
			var lot_label := Neighborhood.label_of(str(res["lot"]))
			publish_event("info", "%s moved into %s." % [p["name"], lot_label], {"player_id": pid})
	_send(id, CoopProto.EVENT, {"kind": "household", "text": str(res.get("msg", "")), "data": {"ok": bool(res["ok"]), "hid": int(res["hid"]),
		"lot": str(res["lot"])}})
	if bool(res["ok"]):
		send_snapshot(id)
		_broadcast_time()

func _vote(p: Dictionary, m: Dictionary) -> void:
	if time == null:
		return
	var pid: int = int(p["pid"])
	match str(m["kind"]):
		"pause":
			if bool(m["yes"]) and time.vote.is_empty():
				time.call_vote(pid, _now)
			else:
				time.answer_vote(pid, bool(m["yes"]))
		"resume":
			time.resume(pid)

## Tell one player about a big moment (stage 3): a toast with a camera offer. Player 1 (the host) is told locally.
func send_alert(pid: int, text: String, folk_id: int, kind: String = "alert") -> void:
	var f = WorldIface.get_folk(folk_id)
	var data := {"player_id": pid, "folk_id": folk_id, "x": f.tile.x if f != null else -1, "y": f.tile.y if f != null else -1}
	if pid == Players.LOCAL:
		local_alert.emit(text, folk_id, data)
		return
	var peer := peer_of_player(pid)
	if peer >= 0:
		_send(peer, CoopProto.EVENT, {"kind": kind, "text": text.left(200), "data": data})

func broadcast_time() -> void:
	_broadcast_time()

func _broadcast_time() -> void:
	if time == null:
		return
	var st := time.state()
	for id in peers:
		if peers[id]["st"] == "in":
			_send(id, CoopProto.TIME, {"d": st})

func _set_ready(p: Dictionary, v: bool) -> void:
	p["ready"] = v
	_broadcast_lobby()

# ------------------------------------------------------------------ helpers
func _bad(id: int, p: Dictionary) -> void:
	invalid_total += 1
	p["bad"] += 1
	if p["bad"] >= 20:
		_kick_record(id, "garbage", "You were disconnected because your game sent data the host could not understand.")

func _send(id: int, type: int, fields: Dictionary, channel: int = CoopProto.CH_CONTROL) -> void:
	var b := CoopProto.encode(type, fields)
	if not b.is_empty() and send_fn.is_valid():
		send_fn.call(id, b, channel)

func _refuse(id: int, code: String, reason: String) -> void:
	_send(id, CoopProto.REFUSE, {"code": code, "reason": reason})
	peers[id]["st"] = "refused"
	peers[id]["kill_at"] = _now + 0.5

func _kick_record(id: int, code: String, reason: String) -> void:
	if not peers.has(id):
		return
	var p: Dictionary = peers[id]
	_send(id, CoopProto.KICK, {"code": code, "reason": reason})
	var was_in: bool = p["st"] == "in"
	var pid: int = int(p["pid"])
	p["st"] = "refused"
	p["kill_at"] = _now + 0.5
	if was_in:
		peer_left.emit(pid, "removed")
		_broadcast_lobby()

func _drop(id: int) -> void:
	if drop_fn.is_valid():
		drop_fn.call(id)

## Forget a peer. `keep_seat`: reserve its seat for a rejoin (connection problems) instead of freeing it (deliberate leave).
func _remove(id: int, reason: String, keep_seat: bool) -> void:
	var p: Dictionary = peers.get(id, {})
	if p.is_empty():
		return
	peers.erase(id)
	if p["st"] == "in":
		if keep_seat and rejoin_s > 0.0:
			reserved[p["token"]] = {"pid": p["pid"], "name": p["name"], "at": _now, "ls": p["last_seq"], "res": p["results"]}
		peer_left.emit(int(p["pid"]), reason)
		_broadcast_lobby()
	if reason != "connection lost":
		_drop(id)

func _broadcast_lobby() -> void:
	lobby_changed.emit()
	var d := lobby_dict()
	for id in peers:
		if peers[id]["st"] == "in":
			_send(id, CoopProto.LOBBY, d)

func _free_pid() -> int:
	var used := {}
	for id in peers:
		if peers[id]["st"] == "in":
			used[int(peers[id]["pid"])] = true
	for tok in reserved:
		used[int(reserved[tok]["pid"])] = true
	for n in range(2, max_players + 2):
		if not used.has(n):
			return n
	return max_players + 1

func _new_token() -> String:
	return Crypto.new().generate_random_bytes(12).hex_encode()

func _clean_name(raw: String, pid: int) -> String:
	var out := ""
	for ch in raw.strip_edges():
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	out = out.strip_edges()
	return out if out != "" else "Player %d" % pid
