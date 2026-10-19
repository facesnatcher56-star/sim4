class_name CoopProto
extends RefCounted
## Co-op wire protocol (task 24C stage 1). Every packet is ONE Dictionary made with var_to_bytes: {"t": type, ...fields}.
## Decoding is strict: bytes_to_var (never the with_objects variant), top-level must be a Dictionary, the type must be in
## SCHEMAS, every field must be present with exactly the declared kind and within its size cap, no extra fields, floats
## must be finite, nested values may only be plain data (no Objects). Anything else is rejected with a reason string.

const VERSION := 1                 # bump on ANY change of a message layout or meaning
const DEFAULT_PORT := 24680
const MAX_PEERS := 4               # host + 3 clients
const CHUNK_BYTES := 32768
const MAX_PACKET := 40000          # absolute cap for any packet (a chunk is the biggest message)
const MAX_SNAPSHOT_RAW := 96 * 1024 * 1024
const CH_CONTROL := 0              # reliable, ordered
const CH_SNAPSHOT := 1             # reliable, ordered (chunks only, so a big transfer never delays heartbeats)

# client -> host
const HELLO := 1
const PING := 2
const CMD := 3
const SNAP_REQ := 4
const HASH := 5
const BYE := 6
const READY := 7
# host -> client
const WELCOME := 10
const REFUSE := 11
const PONG := 12
const LOBBY := 13
const KICK := 14
const CHUNK := 15
const ACK := 16
const EVENT := 17
const SYNC := 18

## kind codes: i = int, s = String, b = bool, y = PackedByteArray, d = plain Dictionary, a = plain Array.
## Each field is [kind, cap]: cap = max characters / bytes / entries for s, y, d, a.
const SCHEMAS := {
	HELLO: {"proto": ["i", 0], "build": ["s", 64], "name": ["s", 24], "token": ["s", 40]},
	PING: {"n": ["i", 0]},
	CMD: {"player_id": ["i", 0], "folk_id": ["i", 0], "action": ["s", 32], "args": ["d", 16], "game_minute": ["i", 0], "seq": ["i", 0]},
	SNAP_REQ: {"why": ["s", 32]},
	HASH: {"xfer": ["i", 0], "hash": ["s", 64], "minute": ["i", 0]},
	BYE: {},
	READY: {"ready": ["b", 0]},
	WELCOME: {"proto": ["i", 0], "build": ["s", 64], "player_id": ["i", 0], "token": ["s", 40], "resumed": ["b", 0], "host": ["s", 24]},
	REFUSE: {"code": ["s", 24], "reason": ["s", 200]},
	PONG: {"n": ["i", 0]},
	LOBBY: {"host": ["s", 24], "max": ["i", 0], "peers": ["a", 8]},
	KICK: {"code": ["s", 24], "reason": ["s", 200]},
	CHUNK: {"xfer": ["i", 0], "idx": ["i", 0], "total": ["i", 0], "raw": ["i", 0], "sum": ["s", 64], "hash": ["s", 64], "data": ["y", CHUNK_BYTES]},
	ACK: {"seq": ["i", 0], "ok": ["b", 0], "msg": ["s", 160], "minute": ["i", 0]},
	EVENT: {"kind": ["s", 32], "text": ["s", 200], "data": ["d", 16]},
	SYNC: {"xfer": ["i", 0], "ok": ["b", 0], "host_hash": ["s", 64]},
}
const MAX_DEPTH := 3
const MAX_NODES := 200
const MAX_STR := 200
const MAX_INT := 9007199254740991

## Set by tests to simulate another game build.
static var build_override: String = ""

static func build_id() -> String:
	if build_override != "":
		return build_override
	return "%s/save%d" % [str(ProjectSettings.get_setting("application/config/version", "dev")), SaveLoad.VERSION]

## Encode a message; returns an empty array when the fields do not satisfy the schema (a programming error).
static func encode(type: int, fields: Dictionary = {}) -> PackedByteArray:
	var d: Dictionary = fields.duplicate()
	d["t"] = type
	var why := validate(d)
	if why != "":
		push_warning("CoopProto.encode: invalid message type %d: %s" % [type, why])
		return PackedByteArray()
	return var_to_bytes(d)

## Returns {"ok": true, "t": type, "m": fields} or {"ok": false, "err": reason}.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 8 or bytes.size() > MAX_PACKET:
		return {"ok": false, "err": "bad size %d" % bytes.size()}
	if (bytes.decode_u32(0) & 0xFFFF) != TYPE_DICTIONARY:      # also refuses object-encoded packets (type 24)
		return {"ok": false, "err": "not a dictionary"}
	var v: Variant = bytes_to_var(bytes)                       # NEVER bytes_to_var_with_objects
	if not (v is Dictionary):
		return {"ok": false, "err": "undecodable"}
	var d: Dictionary = v
	var why := validate(d)
	if why != "":
		return {"ok": false, "err": why}
	return {"ok": true, "t": int(d["t"]), "m": d}

static func validate(d: Dictionary) -> String:
	if not d.has("t") or typeof(d["t"]) != TYPE_INT:
		return "no type"
	var t: int = d["t"]
	if not SCHEMAS.has(t):
		return "unknown type %d" % t
	var schema: Dictionary = SCHEMAS[t]
	if d.size() != schema.size() + 1:
		return "wrong field count for type %d" % t
	for k in schema:
		if not d.has(k):
			return "missing field %s" % k
		var why := _check(d[k], str(schema[k][0]), int(schema[k][1]))
		if why != "":
			return "field %s: %s" % [k, why]
	return ""

static func _check(v: Variant, kind: String, cap: int) -> String:
	match kind:
		"i":
			if typeof(v) != TYPE_INT or absi(v) > MAX_INT:
				return "not an int"
		"b":
			if typeof(v) != TYPE_BOOL:
				return "not a bool"
		"s":
			if typeof(v) != TYPE_STRING or (v as String).length() > cap:
				return "bad string"
		"y":
			if typeof(v) != TYPE_PACKED_BYTE_ARRAY or (v as PackedByteArray).size() > cap:
				return "bad bytes"
		"d":
			if typeof(v) != TYPE_DICTIONARY or (v as Dictionary).size() > cap:
				return "bad dictionary"
			return _plain(v, 0, [0])
		"a":
			if typeof(v) != TYPE_ARRAY or (v as Array).size() > cap:
				return "bad array"
			return _plain(v, 0, [0])
	return ""

static func _finite_number(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return absi(v) <= MAX_INT
	if typeof(v) == TYPE_FLOAT:
		return not is_nan(v) and not is_inf(v)
	return false

## Plain data only: int / finite float / bool / short String / Dictionary with String keys / Array, bounded depth and size.
static func _plain(v: Variant, depth: int, count: Array) -> String:
	count[0] += 1
	if count[0] > MAX_NODES or depth > MAX_DEPTH:
		return "too large or too deep"
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return "" if _finite_number(v) else "bad number"
		TYPE_BOOL:
			return ""
		TYPE_STRING:
			return "" if (v as String).length() <= MAX_STR else "string too long"
		TYPE_DICTIONARY:
			for k in v:
				if typeof(k) != TYPE_STRING or (k as String).length() > 40:
					return "bad key"
				var w := _plain(v[k], depth + 1, count)
				if w != "":
					return w
			return ""
		TYPE_ARRAY:
			for x in v:
				var w2 := _plain(x, depth + 1, count)
				if w2 != "":
					return w2
			return ""
	return "forbidden value type %d" % typeof(v)
