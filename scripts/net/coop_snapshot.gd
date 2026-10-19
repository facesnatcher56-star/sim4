class_name CoopSnapshot
extends RefCounted
## Snapshot transfer helpers. Host: pack() = SaveLoad.snapshot() as JSON text -> zstd -> chunks. Client: unpack() the
## reassembled bytes and load_text() them through SaveLoad.restore, which works purely in memory: NO save slot is read or
## written, so a co-op join never touches the player's own saves.

static func sum_of(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()

## {"data": compressed, "raw": uncompressed size, "sum": checksum, "hash": CoopHash.of_world() of the same instant}.
static func pack(snapshot: Dictionary, state_hash: String) -> Dictionary:
	var raw := JSON.stringify(snapshot).to_utf8_buffer()
	var comp := raw.compress(FileAccess.COMPRESSION_ZSTD)
	return {"data": comp, "raw": raw.size(), "sum": sum_of(comp), "hash": state_hash}

## Host side: the whole current world.
static func pack_world() -> Dictionary:
	return pack(SaveLoad.snapshot("coop"), CoopHash.of_world())

## Split compressed data into CHUNK_BYTES pieces.
static func split(data: PackedByteArray) -> Array:
	var out: Array = []
	var n := maxi(1, ceili(float(data.size()) / float(CoopProto.CHUNK_BYTES)))
	for i in n:
		out.append(data.slice(i * CoopProto.CHUNK_BYTES, mini(data.size(), (i + 1) * CoopProto.CHUNK_BYTES)))
	return out

## Decompressed JSON text, or "" when the data is corrupt / the size lies.
static func unpack(data: PackedByteArray, raw_size: int) -> String:
	if raw_size < 1 or raw_size > CoopProto.MAX_SNAPSHOT_RAW:
		return ""
	var raw := data.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		return ""
	return raw.get_string_from_utf8()

## Parse and restore into the running game (in memory). Returns "" on success or a plain-language reason.
static func load_text(text: String) -> String:
	var js := JSON.new()
	if js.parse(text) != OK or not (js.data is Dictionary):
		return "The world data from the host was damaged."
	var d: Dictionary = js.data
	if str(d.get("format", "")) != SaveLoad.FORMAT:
		return "The host sent something that is not a game world."
	if not SaveLoad.restore(d):
		return SaveLoad.last_error if SaveLoad.last_error != "" else "The world from the host could not be loaded."
	return ""
