class_name VehicleFeed
extends RefCounted
## One-way message board from the sim to the vehicle layer (task 12b). The sim POSTS what the layer needs to draw (an emergency unit sent out);
## the layer READS it. Nothing here is saved, hashed or read back by the sim, and nothing draws from a sim rng, so a game with no view behaves
## the same as one with a view. Entries are plain Dictionaries with a `seq`; the list is capped.
##   VehicleFeed.post(kind, data)      VehicleFeed.since(seq) -> [entries newer than seq]      VehicleFeed.last_seq()      VehicleFeed.reset()

const CAP := 48

static var entries: Array = []
static var _seq: int = 0


static func reset() -> void:
	entries.clear()


static func post(kind: String, data: Dictionary = {}) -> void:
	_seq += 1
	var e: Dictionary = data.duplicate()
	e["kind"] = kind
	e["seq"] = _seq
	e["now"] = SysUtil.now()
	entries.append(e)
	if entries.size() > CAP:
		entries.pop_front()


static func last_seq() -> int:
	return _seq


static func since(seq: int) -> Array:
	var out: Array = []
	for e in entries:
		if int(e["seq"]) > seq:
			out.append(e)
	return out
