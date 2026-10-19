class_name CoopReassembler
extends RefCounted
## Collects the chunks of ONE snapshot transfer at a time (higher transfer ids replace lower ones). Chunks may arrive in any
## order and more than once; a header that disagrees with the first chunk, a bad index or an oversized transfer is rejected.
## No sockets here, so it is unit-testable.

var xfer: int = -1
var total: int = 0
var raw: int = 0
var sum: String = ""
var state_hash: String = ""
var parts: Dictionary = {}       # idx -> PackedByteArray
var got_bytes: int = 0
var done_xfers: int = 0

## Returns "" when the chunk was stored, "dup" for a repeat (harmless), "stale" for an older transfer, else the rejection reason.
func add(p_xfer: int, idx: int, p_total: int, p_raw: int, p_sum: String, p_hash: String, data: PackedByteArray) -> String:
	if p_xfer < xfer:
		return "stale"
	if p_total < 1 or p_raw < 1 or p_raw > CoopProto.MAX_SNAPSHOT_RAW:
		return "bad header"
	if p_total > CoopProto.MAX_SNAPSHOT_RAW / 64 + 2:
		return "bad header"
	if idx < 0 or idx >= p_total:
		return "bad index"
	if p_xfer > xfer:
		_reset(p_xfer, p_total, p_raw, p_sum, p_hash)
	elif p_total != total or p_raw != raw or p_sum != sum or p_hash != state_hash:
		return "inconsistent header"
	if parts.has(idx):
		return "dup"
	if got_bytes + data.size() > CoopProto.MAX_SNAPSHOT_RAW:
		return "too big"
	if idx < total - 1 and data.size() != CoopProto.CHUNK_BYTES:
		return "short chunk"
	parts[idx] = data
	got_bytes += data.size()
	return ""

func _reset(p_xfer: int, p_total: int, p_raw: int, p_sum: String, p_hash: String) -> void:
	xfer = p_xfer
	total = p_total
	raw = p_raw
	sum = p_sum
	state_hash = p_hash
	parts = {}
	got_bytes = 0

func progress() -> float:
	return 0.0 if total <= 0 else float(parts.size()) / float(total)

func complete() -> bool:
	return total > 0 and parts.size() == total

## {"ok": true, "data": compressed bytes} once complete and the checksum matches; else {"ok": false, "err": ...}.
func assemble() -> Dictionary:
	if not complete():
		return {"ok": false, "err": "incomplete"}
	var all := PackedByteArray()
	for i in total:
		all.append_array(parts[i])
	if CoopSnapshot.sum_of(all) != sum:
		return {"ok": false, "err": "checksum mismatch"}
	done_xfers += 1
	return {"ok": true, "data": all}

func clear() -> void:
	xfer = -1
	total = 0
	parts = {}
	got_bytes = 0
