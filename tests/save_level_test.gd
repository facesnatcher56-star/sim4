extends RefCounted
## A folk on an upper floor keeps its floor through a save round trip and a co-op snapshot (World.add_folk used to reset the level to 0).

const HoodKit := preload("res://tests/hood_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = HoodKit.new_game("small")
	var f: Folk = folk[0]
	var office: Rect2i = MapBuilder.lot_rect("office")
	# the tower of the office has floors; put the folk on level 2 (any tile of the lot: the level is data on the folk)
	f.tile = office.position + Vector2i(15, 12)
	f.level = 2
	var fid: int = int(f.id)
	var snap: Variant = JSON.parse_string(JSON.stringify(SaveLoad.snapshot("lvl")))
	HoodKit.new_game("small")
	_check(SaveLoad.restore(snap), "restore")
	_check(WorldIface.get_folk(fid) != null and WorldIface.get_folk(fid).level == 2, "the folk is still on level 2 after a save round trip")
	var pk := CoopSnapshot.pack_world()
	var text := CoopSnapshot.unpack(pk["data"], pk["raw"])
	HoodKit.new_game("large")
	_check(CoopSnapshot.load_text(text) == "", "snapshot loads")
	_check(WorldIface.get_folk(fid) != null and WorldIface.get_folk(fid).level == 2, "and after a co-op snapshot")
	HoodKit.teardown()
	return fails
