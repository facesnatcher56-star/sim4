class_name CoopLive
extends RefCounted
## Host side of the LIVE UPDATES (co-op stage 2): a compact state delta per client, built from the real world and sent as CoopProto.DELTA.
## The client does not simulate; CoopView applies the delta to its local copy of the world (positions, activities, needs, mood, away flag,
## coins, toasts). Per peer only what CHANGED since that peer's last delta is sent. Bounded: <= MAX_ROWS folk rows and MAX_TOASTS toasts per
## delta, one delta per `min_gap_s` real seconds and per game minute at most, zstd'd JSON <= CoopProto.MAX_DELTA_BYTES (else the peer is told to
## re-sync with a snapshot instead). Every `hash_every_min` game minutes the delta carries the host's state hash; the client answers with HASH.
## Safety nets: the client asks for a snapshot when a folk / object count differs, the host re-sends a full snapshot every `full_every_min`.

const MAX_ROWS := 64
const MAX_TOASTS := 8
const NEED_DECIMALS := 0.01

var min_gap_s: float = 0.5
var hash_every_min: int = 10
var full_every_min: int = 60
var toasts: Array = []                  # ring of {i, text, kind}
var hash_log: Dictionary = {}           # game minute -> host hash (for the minutes where a check was due), last 8
var deltas_sent: int = 0
var bytes_sent: int = 0
var _toast_n: int = 0
var _connected := false
var _hash_minute: int = -1
var _hash_val: String = ""

func connect_events() -> void:
	if not _connected:
		SimEnv.events().notification.connect(_on_note)
		_connected = true

func disconnect_events() -> void:
	if _connected:
		SimEnv.events().notification.disconnect(_on_note)
		_connected = false

func _on_note(text: String, kind: String) -> void:
	_toast_n += 1
	toasts.append({"i": _toast_n, "text": text.left(160), "kind": kind.left(16)})
	while toasts.size() > 40:
		toasts.pop_front()

## New per-peer record (stored by CoopHost in the peer's record under "live").
func new_peer() -> Dictionary:
	return {"rows": {}, "coins": {}, "toast": _toast_n, "sent_s": -100.0, "sent_min": -1, "full_min": SimEnv.now_min(), "need_snap": ""}

## Called after a snapshot went to the peer: the next delta carries everything again.
func reset_peer(st: Dictionary) -> void:
	st["rows"] = {}
	st["coins"] = {}
	st["toast"] = _toast_n
	st["sent_min"] = -1
	st["full_min"] = SimEnv.now_min()
	st["need_snap"] = ""

func _row(f) -> Dictionary:
	var needs := {}
	for nid in f.needs:
		needs[nid] = snappedf((f.needs[nid] as Stat).value, NEED_DECIMALS)
	var cur = f.current
	return {"i": int(f.id), "x": f.tile.x, "y": f.tile.y, "l": int(f.level), "a": str(cur.def_id) if cur != null else "",
		"t": int(cur.target_id) if cur != null else -1, "po": str(f.posture), "aw": str(f.get_meta("away", "")) if f.has_meta("away") else "",
		"md": str(f.mood_name), "mi": int(f.mood_intensity), "n": needs}

## The delta for one peer, or {} when nothing changed / it is too soon. `st` is the peer's record from new_peer(); `player_id` its player.
func build(st: Dictionary, player_id: int, now_s: float) -> Dictionary:
	var now_min := SimEnv.now_min()
	if now_s - float(st["sent_s"]) < min_gap_s or now_min == int(st["sent_min"]):
		return {}
	var rows: Array = []
	var count := 0
	var seen: Dictionary = st["rows"]
	for f in WorldIface.all_folk():
		if int(f.household_id) <= 0 or f.has_meta("visitor") or not CoopVisibility.visible_to(player_id, f):
			continue
		count += 1
		var r := _row(f)
		var key := JSON.stringify(r)
		if seen.get(int(f.id), "") != key and rows.size() < MAX_ROWS:
			seen[int(f.id)] = key
			rows.append(r)
	var coins := {}
	for hid in Economy.household_ids():
		var b := Economy.balance(int(hid))
		if int((st["coins"] as Dictionary).get(int(hid), -999999)) != b:
			(st["coins"] as Dictionary)[int(hid)] = b
			coins[str(hid)] = b
	var tl: Array = []
	for t in toasts:
		if int(t["i"]) > int(st["toast"]) and tl.size() < MAX_TOASTS:
			st["toast"] = int(t["i"])
			if CoopVisibility.toast_for(player_id, str(t["text"])):
				tl.append([t["text"], t["kind"]])
	var w = WorldIface.world()
	var d := {"m": now_min, "f": rows, "c": coins, "t": tl, "nf": count, "no": (w.objects as Dictionary).size() if w != null and "objects" in w else 0}
	st["sent_s"] = now_s
	st["sent_min"] = now_min
	if now_min - int(st["full_min"]) >= full_every_min:
		st["full_min"] = now_min
		st["need_snap"] = "periodic"
	return d

## True when this minute is a hash-check minute; the hash is computed once per minute for all peers.
func hash_due(now_min: int) -> String:
	if now_min % hash_every_min != 0:
		return ""
	if _hash_minute != now_min:
		_hash_minute = now_min
		_hash_val = CoopHash.of_world()
		hash_log[now_min] = _hash_val
		while hash_log.size() > 8:
			hash_log.erase(hash_log.keys()[0])
	return _hash_val

func encode(d: Dictionary) -> PackedByteArray:
	return JSON.stringify(d).to_utf8_buffer().compress(FileAccess.COMPRESSION_ZSTD)

static func decode(bytes: PackedByteArray) -> Dictionary:
	var raw := bytes.decompress_dynamic(CoopProto.MAX_DELTA_BYTES * 16, FileAccess.COMPRESSION_ZSTD)
	if raw.is_empty():
		return {}
	var v: Variant = JSON.parse_string(raw.get_string_from_utf8())
	return v if v is Dictionary else {}
