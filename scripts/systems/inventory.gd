class_name Inventory
extends RefCounted
## What a person has on them (task 55 / 57): glasses, cigarettes, ammunition boxes, weapons... One list per person of
## {id, n, shown (held out), ammo, serial, registered_to (household id, -1 = none), dirty_case (an old case the item is tied to, -1)}.
## Items that are only counted (a box of rounds) stack in `n`. Saved with the market block (MarketTick).
##   Inventory.add(pid, id, opts)  Inventory.take(pid, id)  Inventory.has(pid, id)  Inventory.items(pid)  Inventory.count(pid, id)

static var held: Dictionary = {}          # pid -> Array of entries
static var _serial: int = 1000

static func reset() -> void:
	held = {}
	_serial = 1000

static func items(pid: int) -> Array:
	return held.get(pid, [])

static func has(pid: int, id: String) -> bool:
	return items(pid).any(func(e): return str(e["id"]) == id)

static func count(pid: int, id: String) -> int:
	var n: int = 0
	for e in items(pid):
		if str(e["id"]) == id:
			n += int(e.get("n", 1))
	return n

static func add(pid: int, id: String, opts: Dictionary = {}) -> Dictionary:
	var list: Array = items(pid).duplicate()
	if bool(opts.get("stack", false)):
		for e in list:
			if str(e["id"]) == id:
				e["n"] = int(e.get("n", 1)) + int(opts.get("n", 1))
				held[pid] = list
				return e
	_serial += 1
	var e2: Dictionary = {"id": id, "n": int(opts.get("n", 1)), "shown": bool(opts.get("shown", false)), "ammo": int(opts.get("ammo", 0)), "serial": _serial,
		"registered_to": int(opts.get("registered_to", -1)), "dirty_case": int(opts.get("dirty_case", -1))}
	list.append(e2)
	held[pid] = list
	return e2

## Take one (or `n` from a stack). Returns the entry taken, {} if there was none.
static func take(pid: int, id: String, n: int = 1) -> Dictionary:
	var list: Array = items(pid).duplicate()
	for i in list.size():
		if str(list[i]["id"]) != id:
			continue
		var e: Dictionary = list[i]
		if int(e.get("n", 1)) > n:
			e["n"] = int(e["n"]) - n
		else:
			list.remove_at(i)
		if list.is_empty():
			held.erase(pid)
		else:
			held[pid] = list
		return e
	return {}

static func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for k in held:
		out[str(k)] = held[k]
	return {"held": out, "serial": _serial}

static func from_dict(d: Dictionary) -> void:
	reset()
	_serial = int(d.get("serial", 1000))
	for k in (d.get("held", {}) as Dictionary):
		held[int(k)] = d["held"][k]
