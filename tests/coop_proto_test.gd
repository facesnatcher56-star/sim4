extends RefCounted
## CoopProto: round trips, strict rejection of hostile packets (nothing may crash), join codes, the rate limiter.

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _samples() -> Array:
	return [
		[CoopProto.HELLO, {"proto": 1, "build": "x", "name": "Sam", "token": ""}],
		[CoopProto.PING, {"n": 5}],
		[CoopProto.CMD, {"player_id": 2, "folk_id": 3, "action": "interact", "args": {"interaction_id": "eat", "target_id": 12, "x": 1.5}, "game_minute": 900, "seq": 1}],
		[CoopProto.SNAP_REQ, {"why": "refresh"}],
		[CoopProto.HASH, {"xfer": 1, "hash": "abc", "minute": 5}],
		[CoopProto.BYE, {}],
		[CoopProto.READY, {"ready": true}],
		[CoopProto.WELCOME, {"proto": 1, "build": "x", "player_id": 2, "token": "t", "resumed": false, "host": "H"}],
		[CoopProto.REFUSE, {"code": "full", "reason": "no"}],
		[CoopProto.PONG, {"n": 5}],
		[CoopProto.LOBBY, {"host": "H", "max": 4, "peers": [{"id": 2, "name": "Sam", "ready": true, "away": false}]}],
		[CoopProto.KICK, {"code": "kicked", "reason": "bye"}],
		[CoopProto.CHUNK, {"xfer": 1, "idx": 0, "total": 1, "raw": 10, "sum": "s", "hash": "h", "data": PackedByteArray([1, 2, 3])}],
		[CoopProto.ACK, {"seq": 1, "ok": true, "msg": "", "minute": 7}],
		[CoopProto.EVENT, {"kind": "command", "text": "hi", "data": {"a": 1}}],
		[CoopProto.SYNC, {"xfer": 1, "ok": true, "host_hash": "h"}],
	]

func run() -> Array:
	fails = []
	for s in _samples():
		var b := CoopProto.encode(s[0], s[1])
		_check(not b.is_empty(), "encode type %d" % s[0])
		var r := CoopProto.decode(b)
		_check(r["ok"] and r["t"] == s[0], "decode type %d (%s)" % [s[0], str(r.get("err", ""))])
	_hostile()
	_address()
	_rate()
	return fails

func _rejects(bytes: PackedByteArray, what: String) -> void:
	var r := CoopProto.decode(bytes)
	_check(not r["ok"], "should reject: " + what)

func _hostile() -> void:
	var ping := {"t": CoopProto.PING, "n": 1}
	_check(CoopProto.decode(var_to_bytes(ping))["ok"], "valid ping decodes")
	_rejects(PackedByteArray(), "empty")
	_rejects(PackedByteArray([1, 2, 3]), "tiny")
	var big := PackedByteArray()
	big.resize(CoopProto.MAX_PACKET + 1)
	_rejects(big, "oversized")
	var garbage := PackedByteArray()
	for i in 200:
		garbage.append((i * 37 + 11) & 0xFF)
	_rejects(garbage, "garbage")
	_rejects(var_to_bytes([1, 2, 3]), "array at top level")
	_rejects(var_to_bytes(42), "int at top level")
	_rejects(var_to_bytes({"n": 1}), "no type")
	_rejects(var_to_bytes({"t": 999, "n": 1}), "unknown type")
	_rejects(var_to_bytes({"t": "2", "n": 1}), "type as string")
	_rejects(var_to_bytes({"t": CoopProto.PING, "n": "1"}), "string where int")
	_rejects(var_to_bytes({"t": CoopProto.PING, "n": 1.5}), "float where int")
	_rejects(var_to_bytes({"t": CoopProto.PING, "n": 1, "extra": 1}), "extra field")
	_rejects(var_to_bytes({"t": CoopProto.PING}), "missing field")
	_rejects(var_to_bytes({"t": CoopProto.HELLO, "proto": 1, "build": "x".repeat(65), "name": "a", "token": ""}), "long string")
	_rejects(var_to_bytes({"t": CoopProto.PING, "n": 1 << 60}), "huge int")
	var cmd := {"t": CoopProto.CMD, "player_id": 2, "folk_id": 3, "action": "interact", "args": {}, "game_minute": 1, "seq": 1}
	var nan_cmd := cmd.duplicate(true)
	nan_cmd["args"] = {"x": NAN}
	_rejects(var_to_bytes(nan_cmd), "NaN in args")
	var inf_cmd := cmd.duplicate(true)
	inf_cmd["args"] = {"x": INF}
	_rejects(var_to_bytes(inf_cmd), "inf in args")
	var vec_cmd := cmd.duplicate(true)
	vec_cmd["args"] = {"v": Vector2(1, 2)}
	_rejects(var_to_bytes(vec_cmd), "Vector2 in args (only plain data)")
	var deep := cmd.duplicate(true)
	deep["args"] = {"a": {"b": {"c": {"d": {"e": 1}}}}}
	_rejects(var_to_bytes(deep), "too deep")
	var many := cmd.duplicate(true)
	var md := {}
	for i in 40:
		md["k%d" % i] = i
	many["args"] = md
	_rejects(var_to_bytes(many), "too many args")
	var keyed := cmd.duplicate(true)
	keyed["args"] = {1: 2}
	_rejects(var_to_bytes(keyed), "non-string key")
	# object-encoded payloads: top level and nested
	var obj := RefCounted.new()
	_rejects(var_to_bytes_with_objects(obj), "object at top level")
	var nested := cmd.duplicate(true)
	nested["args"] = {"o": obj}
	_rejects(var_to_bytes_with_objects(nested), "object nested in args")
	var nested2 := {"t": CoopProto.PING, "n": obj}
	_rejects(var_to_bytes_with_objects(nested2), "object as a field")
	# truncated packets
	var good := var_to_bytes(cmd)
	for cut in [8, 12, good.size() / 2, good.size() - 1]:
		_rejects(good.slice(0, cut), "truncated at %d" % cut)
	# a chunk whose data is too large
	var chunk := {"t": CoopProto.CHUNK, "xfer": 1, "idx": 0, "total": 1, "raw": 10, "sum": "s", "hash": "h", "data": PackedByteArray()}
	var data := PackedByteArray()
	data.resize(CoopProto.CHUNK_BYTES + 1)
	chunk["data"] = data
	_rejects(var_to_bytes(chunk), "chunk data over the cap")

func _address() -> void:
	var code := CoopAddress.encode("192.168.1.20", 24680)
	_check(code.length() == 14, "code looks like XXXX-XXXX-XXXX (%s)" % code)
	var d := CoopAddress.decode(code)
	_check(d["ok"] and d["ip"] == "192.168.1.20" and d["port"] == 24680, "code round trip")
	_check(CoopAddress.decode(code.to_lower().replace("-", " "))["ok"], "code is forgiving about case and separators")
	for ip in ["10.0.0.1", "255.255.255.255", "0.0.0.0", "127.0.0.1"]:
		var c2 := CoopAddress.encode(ip, 65535)
		var d2 := CoopAddress.decode(c2)
		_check(d2["ok"] and d2["ip"] == ip and d2["port"] == 65535, "round trip " + ip)
	var typo := code.substr(0, 5) + ("A" if code[5] != "A" else "B") + code.substr(6)
	_check(not CoopAddress.decode(typo)["ok"], "a mistyped code is caught by the check byte")
	_check(not CoopAddress.decode("short")["ok"], "short code")
	_check(not CoopAddress.decode("ABCD-EFGH-IJK1")["ok"], "invalid character")
	var p := CoopAddress.parse("192.168.0.9:1234")
	_check(p["ok"] and p["ip"] == "192.168.0.9" and p["port"] == 1234, "ip:port")
	p = CoopAddress.parse("10.1.2.3")
	_check(p["ok"] and p["port"] == CoopProto.DEFAULT_PORT, "ip alone uses the default port")
	p = CoopAddress.parse("localhost:4000")
	_check(p["ok"] and p["ip"] == "127.0.0.1", "localhost")
	_check(not CoopAddress.parse("1.2.3:5")["ok"] and not CoopAddress.parse("1.2.3.4:x")["ok"] and not CoopAddress.parse("")["ok"], "bad addresses give errors")
	p = CoopAddress.parse(code)
	_check(p["ok"] and p["ip"] == "192.168.1.20", "parse accepts a code")
	CoopAddress.resolve_hook = func(t: String) -> Dictionary: return {"ip": "9.9.9.9", "port": 99} if t == "relay-room" else {}
	_check(CoopAddress.parse("relay-room")["ip"] == "9.9.9.9", "resolve hook is asked first")
	_check(CoopAddress.parse("10.1.2.3")["ip"] == "10.1.2.3", "hook returning {} falls through")
	CoopAddress.resolve_hook = Callable()

func _rate() -> void:
	var r := CoopRate.new(10.0, 5.0)
	var ok := 0
	for i in 20:
		if r.allow(0.0):
			ok += 1
	_check(ok == 5, "burst of 5 allowed (%d)" % ok)
	_check(not r.allow(0.05), "still empty after 0.05 s")
	_check(r.allow(1.0), "refills with time")
	_check(r.dropped == 16, "dropped counted (%d)" % r.dropped)
