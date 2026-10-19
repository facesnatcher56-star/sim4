extends RefCounted
## Snapshot chunk reassembly without sockets: reordering, duplicates, stale / inconsistent / truncated transfers, corruption,
## and the pack -> split -> reassemble -> unpack round trip (zstd).

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _snapshot_like() -> Dictionary:
	var rows: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 6000:
		rows.append({"id": i, "name": "folk%d" % i, "tile": [i % 160, i % 120], "needs": {"hunger": rng.randf() * 100.0, "energy": rng.randf()}, "z": rng.randf()})
	return {"format": "sim4", "version": 4, "folk": rows}

func run() -> Array:
	fails = []
	var snap := _snapshot_like()
	var pk := CoopSnapshot.pack(snap, "hash-1")
	var data: PackedByteArray = pk["data"]
	var chunks := CoopSnapshot.split(data)
	_check(chunks.size() >= 3, "test data needs several chunks (%d, %d bytes)" % [chunks.size(), data.size()])
	_check(int(pk["raw"]) > data.size(), "compression shrank it (%d -> %d)" % [pk["raw"], data.size()])
	var total: int = chunks.size()
	# reversed order + every chunk twice
	var ra := CoopReassembler.new()
	var order: Array = range(total)
	order.reverse()
	for i in order:
		_check(ra.add(1, i, total, pk["raw"], pk["sum"], "hash-1", chunks[i]) == "", "chunk %d accepted" % i)
		if i == total - 1 or i == 0:
			continue
	for i in order:
		var why := ra.add(1, i, total, pk["raw"], pk["sum"], "hash-1", chunks[i])
		_check(why == "dup", "repeat of chunk %d is a harmless dup (%s)" % [i, why])
	_check(ra.complete(), "complete after all chunks")
	var a := ra.assemble()
	_check(a["ok"], "assemble ok (%s)" % str(a.get("err", "")))
	var text := CoopSnapshot.unpack(a["data"], ra.raw)
	_check(text != "" and (JSON.parse_string(text) as Dictionary)["folk"].size() == 6000, "round trip equals the source")
	# shuffled with duplicates interleaved
	var rb := CoopReassembler.new()
	var shuffled: Array = range(total)
	shuffled.shuffle()
	for i in shuffled:
		rb.add(7, i, total, pk["raw"], pk["sum"], "h", chunks[i])
		rb.add(7, i, total, pk["raw"], pk["sum"], "h", chunks[i])
	_check(rb.assemble()["ok"], "shuffled + duplicated assembles")
	# missing chunk never completes
	var rc := CoopReassembler.new()
	for i in total - 1:
		rc.add(2, i, total, pk["raw"], pk["sum"], "h", chunks[i])
	_check(not rc.complete() and not rc.assemble()["ok"], "a missing chunk is not complete")
	_check(rc.progress() > 0.0 and rc.progress() < 1.0, "progress is partial")
	# stale / newer transfers
	var rd := CoopReassembler.new()
	rd.add(5, 0, total, pk["raw"], pk["sum"], "h", chunks[0])
	_check(rd.add(4, 1, total, pk["raw"], pk["sum"], "h", chunks[1]) == "stale", "older transfer ignored")
	_check(rd.add(6, 0, total, pk["raw"], pk["sum"], "h", chunks[0]) == "" and rd.xfer == 6 and rd.parts.size() == 1, "newer transfer replaces the old")
	# inconsistent header / bad index / bad totals / short chunk
	_check(rd.add(6, 1, total + 1, pk["raw"], pk["sum"], "h", chunks[1]) != "", "changed total rejected")
	_check(rd.add(6, total, total, pk["raw"], pk["sum"], "h", chunks[1]) == "bad index", "index past the end")
	_check(rd.add(6, -1, total, pk["raw"], pk["sum"], "h", chunks[1]) == "bad index", "negative index")
	_check(rd.add(9, 0, 0, pk["raw"], pk["sum"], "h", chunks[0]) == "bad header", "zero total")
	_check(rd.add(9, 0, 5, CoopProto.MAX_SNAPSHOT_RAW + 1, pk["sum"], "h", chunks[0]) == "bad header", "raw size over the cap")
	_check(rd.add(6, 1, total, pk["raw"], pk["sum"], "h", chunks[1].slice(0, 100)) == "short chunk", "a truncated middle chunk")
	# corrupted payload: checksum catches it
	var re := CoopReassembler.new()
	for i in total:
		var d: PackedByteArray = chunks[i].duplicate()
		if i == 1:
			d[10] = d[10] ^ 0xFF
		re.add(3, i, total, pk["raw"], pk["sum"], "h", d)
	_check(re.complete() and not re.assemble()["ok"], "a flipped byte fails the checksum")
	# unpack refuses lying sizes and garbage
	_check(CoopSnapshot.unpack(data, 5) == "", "wrong raw size")
	_check(CoopSnapshot.unpack(data, CoopProto.MAX_SNAPSHOT_RAW + 1) == "", "raw size over the cap")
	_check(CoopSnapshot.unpack(PackedByteArray([1, 2, 3, 4]), 100) == "", "garbage data")
	_check(CoopSnapshot.load_text("not json") != "" and CoopSnapshot.load_text("[1,2]") != "" and CoopSnapshot.load_text("{\"format\":\"x\"}") != "", "load_text refuses non-snapshots")
	return fails
