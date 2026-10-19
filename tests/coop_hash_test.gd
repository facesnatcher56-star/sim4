extends RefCounted
## CoopHash: deterministic, sensitive to what matters, and identical on a client that loaded the host's snapshot
## (through JSON, like the wire does). Also: the snapshot load touches no save slot.

const HoodKit := preload("res://tests/hood_kit.gd")
const Kit := preload("res://tests/coop_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = HoodKit.new_game("classic")
	HoodKit.set_time(2, 9)
	HoodKit.run(90)
	var h0 := CoopHash.of_world()
	var c0 := CoopHash.canonical()
	_check(h0.length() == 16 and h0 == CoopHash.of_world(), "hash is stable when nothing changes (%s)" % h0)
	var pk := CoopSnapshot.pack_world()
	_check(pk["hash"] == h0, "pack_world carries the hash of the same instant")
	var text := CoopSnapshot.unpack(pk["data"], pk["raw"])
	_check(text != "", "snapshot unpacks")
	var slots_before := _slot_stamp()
	# two fresh loads of the same snapshot: same hash, and the same as the host's
	var hashes: Array = []
	for round in 2:
		HoodKit.new_game("large" if round == 0 else "small")      # a different game in between
		_check(CoopHash.of_world() != h0, "a different game has a different hash")
		var err := CoopSnapshot.load_text(text)
		_check(err == "", "load_text ok (%s)" % err)
		hashes.append(CoopHash.of_world())
	_check(hashes[0] == hashes[1], "two fresh loads agree (%s vs %s)" % [hashes[0], hashes[1]])
	_check(hashes[0] == h0, "client hash equals host hash (%s vs %s) HOST %s CLIENT %s" % [hashes[0], h0, c0.left(600), CoopHash.canonical().left(600)])
	_check(_slot_stamp() == slots_before, "loading a co-op snapshot did not touch the save slots")
	# sensitivity
	var f: Folk = WorldIface.all_folk()[0]
	var base := CoopHash.of_world()
	f.tile += Vector2i(1, 0)
	_check(CoopHash.of_world() != base, "a moved folk changes the hash")
	f.tile -= Vector2i(1, 0)
	_check(CoopHash.of_world() == base, "and moving back restores it")
	var st: Stat = f.needs["hunger"]
	st.value += 5.0
	_check(CoopHash.of_world() != base, "a need changes the hash")
	st.value -= 5.0
	st.value = roundf(st.value)
	base = CoopHash.of_world()
	st.value += 0.2
	_check(CoopHash.of_world() == base, "needs are rounded (tiny drift ignored)")
	st.value -= 0.2
	Economy.deposit(1, 100, "test")
	_check(CoopHash.of_world() != base, "coins change the hash")
	var m := CoopHash.of_world()
	HoodKit.run(1)
	_check(CoopHash.of_world() != m, "a game minute changes the hash")
	# mid-activity: a folk with an order, 20 minutes on; the snapshot -> JSON -> restore round trip keeps the hash
	var cmd := Kit.find_command()
	if not cmd.is_empty():
		CoopCommands.apply({"player_id": 2, "folk_id": cmd["folk"].id, "action": "interact", "args": {"interaction_id": cmd["iid"], "target_id": cmd["tid"]}, "game_minute": 0, "seq": 1})
		for step in 4:
			HoodKit.run(7)
			var host_h := CoopHash.of_world()
			var pk2 := CoopSnapshot.pack_world()
			_check(CoopSnapshot.load_text(CoopSnapshot.unpack(pk2["data"], pk2["raw"])) == "", "mid-activity load ok")
			_check(CoopHash.of_world() == host_h, "mid-activity round trip keeps the hash (step %d)" % step)
	HoodKit.teardown()
	return fails

func _slot_stamp() -> String:
	var parts: PackedStringArray = []
	for i in range(0, 8):
		var p := SaveLoad.path(i)
		parts.append("%d:%d" % [i, FileAccess.get_modified_time(p) if FileAccess.file_exists(p) else 0])
	return ",".join(parts)
