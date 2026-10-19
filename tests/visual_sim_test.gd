extends RefCounted
## VISUAL agent (task 27, sim and generator side): folk get up onto a walkable exit tile, meet a seated folk beside them, a go-here onto furniture lands
## beside it, crowd spawns are free walkable tiles, the shower/bath of a bathroom is private, generated homes have no overlapping objects, every yard
## piece has usable use tiles, and every desk, computer and terminal comes with a chair.
const Kit = preload("res://tests/house_kit.gd")

var fails: Array = []
var W: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _folk(name: String, tile: Vector2i) -> Folk:
	var f := Folk.create(name)
	f.age_stage = "adult"
	W.add_folk(f, tile)
	return f


func run() -> Array:
	fails = []
	var root: Window = Engine.get_main_loop().root
	W = root.get_node_or_null("World")
	if W == null:
		return ["World autoload missing"]
	W.reset()
	_exit_after_seat()
	_meet_beside_seated()
	_go_here_onto_furniture()
	_spawn_tiles()
	_generated_homes()
	_bathroom_privacy()
	W.reset()
	return fails


func _run_to_end(ir: Interaction) -> void:
	_check(ir.start(), "%s did not start" % ir.def_id)
	for i in 80:
		if ir.state == "finished" or ir.state == "cancelled":
			break
		ir.tick(1.0)


## Item 2: getting up from an armchair (the slot is the chair's own tile) steps to a walkable tile, never idles inside the cushion.
func _exit_after_seat() -> void:
	W.reset()
	var oid: int = W.place_object("armchair", Vector2i(8, 8), 0)
	var o = W.get_object(oid)
	_check(not W.is_walkable(Vector2i(8, 8)), "armchair tile should be blocked")
	var f := _folk("Reader", Vector2i(8, 10))
	var ir := Interaction.create("read_armchair", f, oid)
	_run_to_end(ir)
	_check(ir.state == "finished", "read_armchair ended as %s" % ir.state)
	_check(W.is_walkable(f.tile), "after reading, the folk stands on blocked tile %s" % str(f.tile))
	_check(f.tile != Vector2i(8, 8), "the folk stayed in the armchair tile")
	_check(maxi(absi(f.tile.x - 8), absi(f.tile.y - 8)) == 1, "exit tile %s is not next to the chair" % str(f.tile))
	_check(W.exit_tile(o, 0) == f.tile, "exit_tile disagrees with where the folk went")
	# a walkable slot (a counter, a fridge) leaves the folk where it was
	var fid: int = W.place_object("fridge", Vector2i(14, 8), 0)
	var f2 := _folk("Cook", Vector2i(14, 12))
	var ir2 := Interaction.create("grab_snack", f2, fid)
	_run_to_end(ir2)
	_check(f2.tile == W.slot_tile(fid, 0), "standing slot: folk moved from %s to %s" % [str(W.slot_tile(fid, 0)), str(f2.tile)])
	W.remove_folk(f.id)
	W.remove_folk(f2.id)


## Item 3: a chat with somebody sitting in a chair is held beside the chair.
func _meet_beside_seated() -> void:
	W.reset()
	var cid: int = W.place_object("armchair", Vector2i(8, 8), 0)
	var sitter := _folk("Sitter", Vector2i(8, 8))
	_check(W.reserve(cid, 0, sitter.id), "could not seat the sitter")
	var visitor := _folk("Visitor", Vector2i(8, 14))
	var ir := Interaction.create("chat", visitor, sitter.id)
	_check(ir != null and ir.start(), "chat did not start")
	_check(W.is_walkable(ir.path.back() if not ir.path.is_empty() else visitor.tile), "the visitor's route ends on a blocked tile")
	for i in 60:
		if ir.state == "running":
			break
		ir.tick(1.0)
	_check(ir.state == "running", "chat state %s" % ir.state)
	_check(W.is_walkable(visitor.tile) and visitor.tile != sitter.tile, "the visitor stands at %s (sitter at %s)" % [str(visitor.tile), str(sitter.tile)])
	ir.cancel("test")
	W.release(cid, 0, sitter.id)
	W.remove_folk(visitor.id)
	W.remove_folk(sitter.id)


## Item 4: a go-here onto a table lands next to it.
func _go_here_onto_furniture() -> void:
	W.reset()
	var tid: int = W.place_object("coffee_table", Vector2i(10, 10), 0)
	var f := _folk("Walker", Vector2i(10, 16))
	var ir := Interaction.create_goto(f, Vector2i(10, 10), false)
	_check(ir.start(), "go_here onto a table did not start")
	for i in 60:
		if ir.state != "walking":
			break
		ir.tick(1.0)
	_check(W.is_walkable(f.tile), "go_here ended on blocked tile %s" % str(f.tile))
	_check(W.object_at(f.tile) != W.get_object(tid), "go_here ended inside the coffee table")
	for t in ir.path:
		_check(W.is_walkable(t), "the go_here route passes blocked tile %s" % str(t))
	W.remove_folk(f.id)


## Item 3 / 8: crowd and guest spawns are walkable tiles with nobody on them.
func _spawn_tiles() -> void:
	W.reset()
	var did: int = W.place_object("dining_chair", Vector2i(5, 5), 0)
	var blocked := Vector2i(5, 5)
	var taken := Vector2i(6, 5)
	var free := Vector2i(7, 5)
	var other := _folk("Standing", taken)
	var entries: Array = [blocked, taken, free]
	for si in 3:
		var t: Vector2i = Crowd._free_spawn(entries, si)
		_check(W.is_walkable(t) and t != taken, "spawn index %d gave %s (blocked chair or occupied)" % [si, str(t)])
	_check(Crowd.free_near(taken) != taken and W.is_walkable(Crowd.free_near(taken)), "free_near of an occupied tile gave %s" % str(Crowd.free_near(taken)))
	_check(Crowd.free_near(free) == free, "free_near moved an unoccupied tile")
	W.remove_folk(other.id)
	W.remove_object(did)


## Items 5 and 7: the generator's audit is clean on every shipped lot, it catches what it should, and every desk-like object has a chair.
func _generated_homes() -> void:
	var lots: Dictionary = HouseGenerator.lots()
	var desks := 0
	var with_chair := 0
	for id in lots:
		var t: Dictionary = lots[id]
		var bad: Array = HouseAudit.audit(t)
		_check(bad.is_empty(), "%s: %s" % [id, str(bad.slice(0, 2))])
		var sid := str(id)
		if not (sid.begins_with("small_") or sid.begins_with("medium_") or sid.begins_with("large_") or sid.begins_with("classic_") or sid.begins_with("townie_")):
			continue
		var objs: Array = t["objects"]
		var chair_tiles: Dictionary = {}
		for o in objs:
			if str(o["def"]) in ["chair", "dining_chair", "armchair"]:
				chair_tiles[Vector2i(int(o["tile"][0]), int(o["tile"][1]))] = true
		for o in objs:
			if not (str(o["def"]) in HouseDesks.TYPES):
				continue
			desks += 1
			var d := HousePlan.def_of(str(o["def"]))
			for s in HousePlan.slot_tiles(d, Vector2i(int(o["tile"][0]), int(o["tile"][1])), int(o.get("rot", 0))):
				if chair_tiles.has(s):
					with_chair += 1
					break
	_check(desks > 5, "only %d desks in the generated homes" % desks)
	_check(with_chair == desks, "%d of %d desks, computers and terminals have a chair on their use tile" % [with_chair, desks])
	# the audit catches the reviewer's cases: two objects on one tile, and a planter whose use tile is under the mailbox
	var t2 := {"floors": [], "walls": [{"a": [2, 2], "b": [10, 2], "type": "wall"}, {"a": [10, 2], "b": [10, 8], "type": "wall"}, {"a": [2, 8], "b": [10, 8], "type": "wall"}, {"a": [2, 2], "b": [2, 8], "type": "wall"}],
		"objects": [{"def": "garden_plot", "tile": [14, 12], "rot": 0}, {"def": "mailbox", "tile": [14, 13], "rot": 0}, {"def": "mailbox", "tile": [14, 13], "rot": 0}]}
	var found: Array = HouseAudit.audit(t2)
	var s_overlap := false
	var s_slot := false
	for m in found:
		s_overlap = s_overlap or "overlaps" in str(m)
		s_slot = s_slot or "use slot" in str(m)
	_check(s_overlap and s_slot, "audit missed an overlap or a blocked planter slot: %s" % str(found))


## Item 6: while one folk showers (or is on the way), nobody else uses the shower or bath of that bathroom; a chat with the showering folk is
## refused; other rooms and the user itself are unaffected.
func _bathroom_privacy() -> void:
	var t: Dictionary = {}
	for id in HouseGenerator.pool("medium"):
		var tt: Dictionary = HouseGenerator.template(id)
		var has := false
		for o in tt["objects"]:
			if str(o["def"]) == "shower":
				has = true
		if has:
			t = tt
			break
	_check(not t.is_empty(), "no generated medium home with a shower")
	if t.is_empty():
		return
	Kit.apply(t, W)
	var shower = W.objects_of_def("shower")[0]
	var rid: int = W.room_id(shower.tile)
	var same_room: Array = []
	var other_room: Array = []
	for o in W.all_objects():
		if o.has_tag("bathroom") and o != shower:
			if W.room_id(o.tile) == rid:
				same_room.append(o)
			else:
				other_room.append(o)
	_check(not same_room.is_empty(), "the shower's bathroom has no other bathroom object")
	var a := _folk("Showerer", Vector2i(1, 1))
	var b := _folk("Waiter", Vector2i(2, 1))
	_check(W.reserve(shower.id, 0, a.id), "could not reserve the shower")
	for o in same_room:
		_check(W.bathroom_locked(o, b.id), "%s in the bathroom of an occupied shower is not locked" % o.def_id)
		_check(not W.bathroom_locked(o, a.id), "the showering folk is locked out of its own bathroom")
	var idef: Dictionary = SimEnv.data().interaction_def("take_shower")
	_check(not Interaction.def_runnable(idef, b, shower, null), "a second folk may use an occupied shower")
	for o in other_room:
		_check(not W.bathroom_locked(o, b.id), "%s in another bathroom is locked" % o.def_id)
	a.current = Interaction.create("take_shower", a, shower.id)
	a.current.state = "running"
	var chat: Dictionary = SimEnv.data().interaction_def("chat")
	_check(WorldIface.private_use(a), "a showering folk is not private")
	_check(not Interaction.def_runnable(chat, b, null, a), "a chat with somebody in the shower is allowed")
	W.release(shower.id, 0, a.id)
	a.current = null
	for o in same_room:
		_check(not W.bathroom_locked(o, b.id), "%s still locked after the shower is free" % o.def_id)
	W.remove_folk(a.id)
	W.remove_folk(b.id)
