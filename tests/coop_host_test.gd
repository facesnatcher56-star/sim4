extends RefCounted
## CoopHost + CoopClient over an in-memory link (no sockets): handshake, refusals, lobby limit, heartbeats, reconnect,
## hostile packets, rate limit, command idempotence, snapshot delivery under reordering / duplicates.

const Kit := preload("res://tests/coop_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	CoopProto.build_override = "test-build"
	_join_and_snapshot()
	_reordered_snapshot()
	_mismatch()
	_limit()
	_heartbeat()
	_reconnect()
	_hostile()
	_rate_limit()
	_commands()
	_kick_and_close()
	CoopProto.build_override = ""
	return fails

func _join_and_snapshot() -> void:
	var n := Kit.FakeNet.new()
	var c := n.add_client(10, "Sam")
	n.pump()
	_check(c.state == "synced", "client synced (%s: %s)" % [c.state, c.status])
	_check(c.player_id == 2 and c.token != "", "player id 2 and a token")
	_check(c.loads == 1 and c.last_hash == "h-1" and c.host_hash == "h-1", "snapshot loaded once, hash matches")
	_check(n.host.player_count() == 2, "host sees two players")
	var lob := n.host.lobby_dict()
	_check((lob["peers"] as Array).size() == 1 and lob["peers"][0]["name"] == "Sam" and lob["peers"][0]["ready"] == true, "lobby lists Sam, ready after sync")
	_check(c.lobby.get("peers", []).size() == 1, "client got the lobby")
	# a hash mismatch is reported and retried
	var n2 := Kit.FakeNet.new()
	var c2 := n2.add_client(11, "Bo")
	c2.hash_fn = func() -> String: return "different"
	n2.pump()
	_check(c2.state == "desync", "wrong hash: client reports desync (%s)" % c2.state)
	n2.advance(10.0)
	_check(n2.host.snapshots_sent >= 3, "wrong hash: the client asks again (%d sends)" % n2.host.snapshots_sent)
	_check(c2.state == "ended", "after repeated mismatches the client gives up with a message (%s)" % c2.status)
	# fresh snapshot on request
	n.snap_hash = "h-2"
	n.advance(2.0)
	c.request_snapshot()
	n.pump()
	_check(c.loads == 2 and c.last_hash == "h-2" and c.state == "synced", "fresh snapshot on request (%d loads)" % c.loads)
	c.request_snapshot()          # too soon after the last one: answered once the gap is over, not dropped
	n.pump()
	_check(c.loads == 2, "a too-early request waits (%d loads)" % c.loads)
	n.advance(3.0)
	_check(c.loads == 3 and c.state == "synced", "and is answered later (%d loads)" % c.loads)

func _reordered_snapshot() -> void:
	var n := Kit.FakeNet.new()
	n.reorder = true
	n.duplicate = true
	n.snapshot_bytes = 400000
	var c := n.add_client(10, "Sam")
	n.pump()
	_check(c.state == "synced" and c.loads == 1, "reordered and duplicated chunks still give one clean load (%s, %d)" % [c.state, c.loads])

func _mismatch() -> void:
	var n := Kit.FakeNet.new()
	var c := n.add_client(10, "Old")
	n.pump()
	_check(c.state == "synced", "baseline joins")
	# wrong protocol version
	var n2 := Kit.FakeNet.new()
	n2.host.peer_connected(5, 0.0)
	var hello := CoopProto.encode(CoopProto.HELLO, {"proto": CoopProto.VERSION + 1, "build": "test-build", "name": "X", "token": ""})
	n2.host.on_packet(5, hello, 0.0)
	var msgs := Kit.decode_all(n2.to_client.get(5, []))
	_check(msgs.size() == 1 and msgs[0]["t"] == CoopProto.REFUSE and msgs[0]["m"]["code"] == "version", "version mismatch refused")
	_check("Update" in str(msgs[0]["m"]["reason"]), "reason is plain language: " + str(msgs[0]["m"]["reason"]))
	n2.host.tick(1.0)
	_check(n2.dropped.has(5), "refused peer is disconnected shortly after")
	_check(n2.host.player_count() == 1, "refused peer takes no seat")
	# wrong build
	n2.host.peer_connected(6, 2.0)
	n2.host.on_packet(6, CoopProto.encode(CoopProto.HELLO, {"proto": CoopProto.VERSION, "build": "other-build", "name": "X", "token": ""}), 2.0)
	msgs = Kit.decode_all(n2.to_client.get(6, []))
	_check(msgs.size() == 1 and msgs[0]["m"]["code"] == "build" and "other-build" in str(msgs[0]["m"]["reason"]), "build mismatch refused with both versions named")
	# the client shows the refusal text
	var n3 := Kit.FakeNet.new()
	CoopProto.build_override = "host-build"
	var host_msgs := n3.host
	CoopProto.build_override = "test-build"
	var c3 := n3.add_client(7, "Late")      # client says test-build; host compares with its own build_id() at hello time
	CoopProto.build_override = "newer"
	n3.pump()
	CoopProto.build_override = "test-build"
	_check(c3.state == "refused" and c3.status != "", "client ends in 'refused' with a message (%s: %s)" % [c3.state, c3.status])
	_check(host_msgs.player_count() == 1, "no seat taken")

func _limit() -> void:
	var n := Kit.FakeNet.new()
	var cs: Array = []
	for i in 3:
		cs.append(n.add_client(10 + i, "P%d" % i))
	n.pump()
	var ids: Array = cs.map(func(c): return c.player_id)
	_check(ids == [2, 3, 4], "three clients get players 2,3,4 (%s)" % str(ids))
	var c5 := n.add_client(20, "Fifth")
	n.pump()
	_check(c5.state == "refused" and "full" in c5.status, "5th player refused: " + c5.status)
	_check(n.host.player_count() == 4, "lobby stays at four")
	# a seat frees up (leave) and the next one gets it
	cs[0].leave()
	n.pump()
	var c6 := n.add_client(21, "Sixth")
	n.pump()
	_check(c6.state == "synced" and c6.player_id == 2, "freed seat is reused (%d)" % c6.player_id)

func _heartbeat() -> void:
	var n := Kit.FakeNet.new()
	var quiet := n.add_client(10, "Quiet")
	var chatty := n.add_client(11, "Chatty")
	n.pump()
	# the quiet one stops talking (no ticks for it): only the chatty client ticks
	var t := 0.0
	while t < 15.0:
		t += 1.0
		n.now += 1.0
		n.host.tick(n.now)
		chatty.tick(n.now)
		n.pump()
	_check(n.dropped.has(10) and not n.dropped.has(11), "silent peer dropped, chatty one kept")
	_check(n.host.peer_of_player(quiet.player_id) == -1 and n.host.peer_of_player(chatty.player_id) == 11, "silent peer removed from the lobby")
	var lob := n.host.lobby_dict()
	var away := 0
	for p in lob["peers"]:
		if p["away"]:
			away += 1
	_check(away == 1, "its seat is held (shown as away)")
	# client side: a silent host is noticed
	var n2 := Kit.FakeNet.new()
	var c := n2.add_client(10, "Sam")
	n2.pump()
	var tt := 0.0
	while tt < 15.0:
		tt += 1.0
		n2.now += 1.0
		c.tick(n2.now)
	_check(c.state == "lost", "client notices a silent host (%s)" % c.state)
	# a peer that never says hello is dropped
	var n3 := Kit.FakeNet.new()
	n3.host.peer_connected(30, 0.0)
	n3.host.tick(20.0)
	_check(n3.dropped.has(30), "no hello within the time limit: dropped")

func _reconnect() -> void:
	var n := Kit.FakeNet.new()
	var c := n.add_client(10, "Sam")
	n.pump()
	var token := c.token
	var pid := c.player_id
	n.host.peer_disconnected(10, n.now)
	n.clients.erase(10)
	_check(n.host.reserved.has(token), "dropped seat reserved")
	n.advance(5.0)
	var c2 := n.add_client(12, "Sam", token)
	n.pump()
	_check(c2.state == "synced" and c2.player_id == pid and c2.loads == 1, "rejoin with the token: same seat, fresh snapshot (%s, p%d)" % [c2.state, c2.player_id])
	_check(n.host.reserved.is_empty() and n.host.player_count() == 2, "seat is live again, not doubled")
	# the old connection still looks alive: the token takes it over
	var c3 := n.add_client(13, "Sam", token)
	n.pump()
	_check(c3.player_id == pid and n.host.player_count() == 2 and n.dropped.has(12), "takeover of a half-dead connection")
	# the window ends
	var n2 := Kit.FakeNet.new()
	var d := n2.add_client(10, "Late")
	n2.pump()
	var tok2 := d.token
	n2.host.peer_disconnected(10, n2.now)
	n2.advance(65.0, 5.0)
	_check(not n2.host.reserved.has(tok2), "reservation expires")
	var d2 := n2.add_client(14, "Late", tok2)
	n2.pump()
	_check(d2.state == "synced", "after the window the token is just a new join")

func _hostile() -> void:
	var n := Kit.FakeNet.new()
	var c := n.add_client(10, "Sam")
	n.pump()
	var cmd := {"t": CoopProto.CMD, "player_id": 2, "folk_id": 3, "action": "interact", "args": {}, "game_minute": 1, "seq": 1}
	var before := n.host.invalid_total
	var obj := RefCounted.new()
	var bad: Array = [
		PackedByteArray(), PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9]),
		var_to_bytes({"t": 77}), var_to_bytes({"t": CoopProto.PING, "n": "x"}),
		var_to_bytes(cmd).slice(0, 20), var_to_bytes_with_objects(obj), var_to_bytes_with_objects({"t": CoopProto.PING, "n": obj}),
		var_to_bytes({"t": CoopProto.CMD, "player_id": 2, "folk_id": 3, "action": "interact", "args": {"x": NAN}, "game_minute": 1, "seq": 2}),
		var_to_bytes({"t": CoopProto.PONG, "n": 1}),                      # a host->client type
		var_to_bytes({"t": CoopProto.HELLO, "proto": 1, "build": "x", "name": "n", "token": ""}).slice(0, 30),
	]
	var huge := PackedByteArray()
	huge.resize(CoopProto.MAX_PACKET + 10)
	bad.append(huge)
	for b in bad:
		n.host.on_packet(10, b, n.now)
	_check(n.host.invalid_total - before >= bad.size() - 1, "hostile packets counted and dropped (%d)" % (n.host.invalid_total - before))
	n.host.on_packet(10, CoopProto.encode(CoopProto.PING, {"n": 9}), n.now)
	var msgs := Kit.decode_all(n.to_client.get(10, []))
	var pong := msgs.filter(func(m): return m["t"] == CoopProto.PONG)
	_check(pong.size() >= 1, "the host still answers after the garbage")
	_check(n.host.peers.has(10) and not n.dropped.has(10), "occasional garbage does not kick a peer")
	# a flood of garbage does
	for i in 40:
		n.now += 0.1
		n.host.on_packet(10, PackedByteArray([9, 9, 9, 9, 9, 9, 9, 9, 9]), n.now)
	_check(n.host.peers[10]["st"] != "in", "persistent garbage gets the peer removed")
	# traffic before the hello
	var n2 := Kit.FakeNet.new()
	n2.host.peer_connected(40, 0.0)
	n2.host.on_packet(40, CoopProto.encode(CoopProto.CMD, {"player_id": 2, "folk_id": 3, "action": "interact", "args": {}, "game_minute": 1, "seq": 1}), 0.0)
	_check(n2.host.player_count() == 1 and n2.host.invalid_total == 1, "commands before the hello are rejected")
	c.state = c.state

func _rate_limit() -> void:
	var n := Kit.FakeNet.new()
	n.add_client(10, "Sam")
	n.pump()
	n.to_client[10] = []
	for i in 150:
		n.host.on_packet(10, CoopProto.encode(CoopProto.PING, {"n": i}), n.now)
	var pongs := Kit.decode_all(n.to_client[10]).filter(func(m): return m["t"] == CoopProto.PONG)
	_check(pongs.size() <= 70 and pongs.size() >= 30, "a burst of 150 pings is cut to the burst size (%d answered)" % pongs.size())
	_check((n.host.peers[10]["rate"] as CoopRate).dropped >= 70, "drops counted")
	n.to_client[10] = []
	n.now += 5.0
	n.host.on_packet(10, CoopProto.encode(CoopProto.PING, {"n": 1}), n.now)
	_check(Kit.decode_all(n.to_client[10]).size() == 1, "service resumes after a pause")
	for i in 400:      # a sustained flood gets the peer removed
		n.host.on_packet(10, CoopProto.encode(CoopProto.PING, {"n": i}), n.now)
	_check(n.host.peers[10]["st"] != "in", "a sustained flood removes the peer")

func _commands() -> void:
	var n := Kit.FakeNet.new()
	var applied: Array = []
	n.host.apply_fn = func(env: Dictionary) -> Dictionary:
		applied.append(env)
		return {"ok": int(env["folk_id"]) == 3, "msg": "" if int(env["folk_id"]) == 3 else "No."}
	var c := n.add_client(10, "Sam")
	n.pump()
	var results: Array = []
	c.command_result.connect(func(seq, ok, msg): results.append([seq, ok, msg]))
	var events: Array = []
	c.event_received.connect(func(k, t, d): events.append(k))
	var s1 := c.send_command(3, "interact", {"interaction_id": "eat", "target_id": 4}, n.now)
	n.pump()
	_check(applied.size() == 1 and results.size() == 1 and results[0][1] == true, "command applied once and acked")
	_check(events.has("command"), "the host published the result as an event")
	# re-send of the same envelope (lost ack): not applied twice, acked again
	var e: Dictionary = c.pending.get(s1, {})
	_check(e.is_empty(), "acked command no longer pending")
	var again := CoopProto.encode(CoopProto.CMD, {"player_id": 2, "folk_id": 3, "action": "interact", "args": {"interaction_id": "eat", "target_id": 4}, "game_minute": 0, "seq": s1})
	n.to_host.append([10, again])
	n.pump()
	_check(applied.size() == 1, "duplicate seq is not applied twice (%d)" % applied.size())
	# failed command comes back with the host's reason
	c.send_command(9, "interact", {}, n.now)
	n.pump()
	_check(results.size() == 2 and results[1][1] == false and results[1][2] == "No.", "failure reason is returned")
	# spoofed player id
	var spoof := CoopProto.encode(CoopProto.CMD, {"player_id": 3, "folk_id": 3, "action": "interact", "args": {}, "game_minute": 0, "seq": 50})
	n.to_client[10] = []
	n.host.on_packet(10, spoof, n.now)
	var acks := Kit.decode_all(n.to_client[10])
	_check(applied.size() == 2 and acks.size() == 1 and acks[0]["m"]["ok"] == false, "an order claiming another player is refused (%d applied)" % applied.size())
	# lost ack: the client re-sends after the delay and the host answers from its cache
	var lost := Kit.FakeNet.new()
	var applied2 := [0]
	lost.host.apply_fn = func(_env: Dictionary) -> Dictionary:
		applied2[0] += 1
		return {"ok": true, "msg": ""}
	var lc := lost.add_client(10, "Lo")
	lost.pump()
	var lseq := lc.send_command(3, "interact", {}, lost.now)
	var pkt: PackedByteArray = lc.pending[lseq]["bytes"]
	lost.to_host.clear()
	lost.host.on_packet(10, pkt, lost.now)
	lost.to_client[10] = []                       # the ack is lost
	lost.advance(3.0)
	_check(applied2[0] == 1 and lc.pending.is_empty(), "lost ack: re-sent, applied once, then acked (%d applied)" % applied2[0])
	# seats survive a reconnect: orders already applied are not applied again
	var tok := lc.token
	lost.host.peer_disconnected(10, lost.now)
	var lc2 := lost.add_client(11, "Lo", tok)
	lc2.next_seq = 1                              # a client that restarts its counter is treated as a replay
	lost.pump()
	lc2.send_command(3, "interact", {}, lost.now)
	lost.pump()
	_check(applied2[0] == 1, "seq history survives a reconnect (%d applied)" % applied2[0])

func _kick_and_close() -> void:
	var n := Kit.FakeNet.new()
	var c := n.add_client(10, "Sam")
	var d := n.add_client(11, "Bo")
	n.pump()
	_check(n.host.kick(c.player_id), "kick returns true")
	n.pump()
	_check(c.state == "ended" and c.token == "", "kicked client is told and gets no rejoin token (%s)" % c.state)
	n.host.tick(n.now + 1.0)
	_check(n.dropped.has(10), "kicked peer disconnected")
	_check(not n.host.kick(99), "kicking nobody returns false")
	n.host.close()
	n.pump()
	_check(d.state == "ended" and "host" in d.status.to_lower(), "host closing tells the client (%s)" % d.status)
