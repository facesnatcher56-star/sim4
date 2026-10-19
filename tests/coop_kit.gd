extends RefCounted
## Helpers for the coop_* tests (no run(), so the runner skips it).
## FakeNet wires a CoopHost to CoopClients in memory (no sockets); packets are queued and delivered by pump().

class FakeNet:
	var host: CoopHost
	var clients: Dictionary = {}          # peer id -> CoopClient
	var to_host: Array = []               # [peer id, bytes]
	var to_client: Dictionary = {}        # peer id -> Array of bytes
	var dropped: Array = []
	var now: float = 0.0
	var reorder: bool = false
	var duplicate: bool = false
	var snapshot_bytes: int = 100000

	func _init() -> void:
		host = CoopHost.new()
		host.snapshot_fn = _snap
		host.send_fn = func(id: int, b: PackedByteArray, _ch: int):
			if not to_client.has(id):
				to_client[id] = []
			to_client[id].append(b)
			if duplicate:
				to_client[id].append(b)
		host.drop_fn = func(id: int): dropped.append(id)

	var snap_hash := "h-1"
	func _snap() -> Dictionary:
		var raw := PackedByteArray()
		raw.resize(snapshot_bytes)
		for i in raw.size():
			raw[i] = 32 + ((i * 7 + (i >> 3) + (i * i >> 5)) % 90)       # printable ASCII, so it is valid text
		var comp := raw.compress(FileAccess.COMPRESSION_ZSTD)
		return {"data": comp, "raw": raw.size(), "sum": CoopSnapshot.sum_of(comp), "hash": snap_hash}

	func add_client(id: int, name: String, token: String = "") -> CoopClient:
		var c := CoopClient.new()
		c.player_name = name
		c.token = token
		c.send_fn = func(b: PackedByteArray, _ch: int): to_host.append([id, b])
		c.load_fn = func(_text: String) -> String: return ""
		c.hash_fn = func() -> String: return snap_hash
		clients[id] = c
		to_client[id] = []
		host.peer_connected(id, now)
		c.hello(now)
		return c

	func pump(rounds: int = 20) -> void:
		for _r in rounds:
			var q := to_host.duplicate()
			to_host.clear()
			for e in q:
				host.on_packet(e[0], e[1], now)
			for id in to_client.keys():
				var list: Array = to_client[id]
				to_client[id] = []
				if reorder:
					list.reverse()
				if clients.has(id):
					for b in list:
						(clients[id] as CoopClient).on_packet(b, now)
			if to_host.is_empty() and to_client.values().all(func(a): return a.is_empty()):
				break

	func advance(seconds: float, step: float = 1.0) -> void:
		var t := 0.0
		while t < seconds:
			now += step
			t += step
			host.tick(now)
			for id in clients:
				(clients[id] as CoopClient).tick(now)
			pump()

## Drain a packet list from FakeNet.to_client[id] into decoded messages.
static func decode_all(list: Array) -> Array:
	var out: Array = []
	for b in list:
		var r := CoopProto.decode(b)
		if r["ok"]:
			out.append(r)
	return out

## A command the real sim accepts right now: {"folk": Folk, "iid": String, "tid": int} (empty if none is found).
## Looks at the objects around a household folk and tries each of their interactions without queueing anything.
static func find_command() -> Dictionary:
	var defs: Dictionary = SimEnv.data().interactions()
	var tbl: Dictionary = SimEnv.data().get_table("objects")
	for f in WorldIface.all_folk():
		if int(f.household_id) != 1:
			continue
		for o in WorldIface.objects_near(f.tile, 40):
			var offered: Array = (tbl.get(o.def_id, {}) as Dictionary).get("interactions", [])
			for iid in offered:
				if not defs.has(iid):
					continue
				var ir := Interaction.create(str(iid), f, int(o.id), true)
				if ir != null and ir.can_run(f, null, false):
					return {"folk": f, "iid": str(iid), "tid": int(o.id)}
	return {}
