extends RefCounted
## VISUAL agent (task 27, view side; none of it changes sim state): folk sit on the chair at a desk / computer / table, a showering folk keeps the
## Shower clip when somebody talks to them, idle folk standing on one spot spread out, and folk never glide in a straight line through furniture.

var fails: Array = []
var W: Node
var _holder: Node3D


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _mk(name: String, tile: Vector2i) -> Array:
	var f := Folk.create(name)
	f.age_stage = "adult"
	W.add_folk(f, tile)
	var fv := FolkView.new()
	fv.name = "folk_%d" % f.id
	_holder.add_child(fv)
	fv.setup(f.id)
	return [f, fv]


func _step(fv: FolkView, n: int, dt: float = 0.033) -> void:
	for i in n:
		fv._process(dt)


func run() -> Array:
	fails = []
	var root: Window = Engine.get_main_loop().root
	W = root.get_node_or_null("World")
	if W == null:
		return ["World autoload missing"]
	FolkView.reload_map()
	W.reset()
	_holder = Node3D.new()
	root.add_child(_holder)
	_sit_at_desk()
	_shower_keeps_its_clip()
	_idle_spacing()
	_no_straight_line_through_furniture()
	_holder.free()
	W.reset()
	return fails


## A chair on the use tile of a desk: typing is seated, facing the desk, on the chair. No chair: standing as before.
func _sit_at_desk() -> void:
	W.reset()
	var did: int = W.place_object("desk", Vector2i(8, 8), 0)
	var cid: int = W.place_object("chair", Vector2i(8, 9), 2)
	var pr := _mk("Writer", Vector2i(8, 9))
	var f: Folk = pr[0]
	var fv: FolkView = pr[1]
	_check(W.reserve(did, 0, f.id), "could not reserve the desk")
	f.current = Interaction.create("write_story", f, did)
	f.current.state = "running"
	_step(fv, 40)
	_check(fv.pose == "sit", "at a desk with a chair the pose is %s" % fv.pose)
	_check(fv.clip == "Sit_Type", "writing at a desk plays '%s'" % fv.clip)
	var chair_pos: Vector2 = W.get_object(cid).slot_use_pos(0)
	_check(Vector2(fv.position.x, fv.position.z).distance_to(chair_pos) < 0.1, "the writer is not on the chair: %s vs %s" % [str(fv.position), str(chair_pos)])
	W.remove_object(cid)
	W.release(did, 0, f.id)
	f.current = null
	fv.free()
	W.remove_folk(f.id)
	# without a chair the folk stands at the desk and does not play Paint
	var pr2 := _mk("Standing", Vector2i(8, 9))
	var f2: Folk = pr2[0]
	var fv2: FolkView = pr2[1]
	_check(W.reserve(did, 0, f2.id), "could not reserve the desk (2)")
	f2.current = Interaction.create("write_story", f2, did)
	f2.current.state = "running"
	_step(fv2, 40)
	_check(fv2.pose != "sit" and fv2.clip == "Type", "no chair: pose %s clip %s" % [fv2.pose, fv2.clip])
	W.release(did, 0, f2.id)
	f2.current = null
	fv2.free()
	W.remove_folk(f2.id)


## Item 6: somebody talks to the folk in the shower: it keeps washing (Shower), it does not laugh along; the talker does not get a free clip either.
func _shower_keeps_its_clip() -> void:
	W.reset()
	var sid: int = W.place_object("shower", Vector2i(8, 8), 0)
	var pr := _mk("Showerer", Vector2i(8, 8))
	var f: Folk = pr[0]
	var fv: FolkView = pr[1]
	_check(W.reserve(sid, 0, f.id), "could not reserve the shower")
	f.current = Interaction.create("take_shower", f, sid)
	f.current.state = "running"
	var pr2 := _mk("Talker", Vector2i(8, 10))
	var g: Folk = pr2[0]
	var gv: FolkView = pr2[1]
	g.current = Interaction.create("chat", g, f.id)
	g.current.state = "running"
	_step(fv, 40)
	_step(gv, 40)
	_check(fv._partner_role == "target", "the showering folk was not found as the chat target (%s)" % fv._partner_role)
	_check(fv.clip == "Shower", "a showering folk spoken to plays '%s', want Shower" % fv.clip)
	W.release(sid, 0, f.id)
	f.current = null
	g.current = null
	fv.free()
	gv.free()
	W.remove_folk(f.id)
	W.remove_folk(g.id)


## Item 8: idle folk on one spot keep their distance, and nothing the view does touches sim state (tile, rng).
func _idle_spacing() -> void:
	W.reset()
	var pairs: Array = []
	for i in 2:
		pairs.append(_mk("Idler%d" % i, Vector2i(12, 12)))
	var tiles: Array = []
	for p in pairs:
		tiles.append((p[0] as Folk).tile)
	var rng_before: int = SysUtil.rng.state
	for k in 60:
		for p in pairs:
			(p[1] as FolkView)._process(0.033)
	var closest := 99.0
	for i in pairs.size():
		for j in range(i + 1, pairs.size()):
			var a: FolkView = pairs[i][1]
			var b: FolkView = pairs[j][1]
			closest = minf(closest, Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length())
	_check(closest >= 0.4, "two idle folk on one tile stand %.2f m apart" % closest)
	for i in pairs.size():
		_check((pairs[i][0] as Folk).tile == tiles[i], "the view moved a folk's sim tile")
		_check(W.is_walkable(W.pos_to_tile((pairs[i][1] as FolkView).position)), "an idler was pushed onto a blocked tile")
	_check(SysUtil.rng.state == rng_before, "the view touched the sim rng")
	for p in pairs:
		(p[1] as FolkView).free()
		W.remove_folk((p[0] as Folk).id)


## Item 4: a folk whose view is far from its sim tile with a table in between walks around it.
func _no_straight_line_through_furniture() -> void:
	W.reset()
	for x in range(8, 13):
		W.place_object("coffee_table", Vector2i(x, 10), 0)       # a wall of tables, 5 wide
	var pr := _mk("Detour", Vector2i(10, 6))
	var f: Folk = pr[0]
	var fv: FolkView = pr[1]
	_step(fv, 3)
	f.tile = Vector2i(10, 14)                                    # the sim moved the folk to the other side
	fv._last_tile = Vector2i(10, 14)                             # (no route known to the view: the far-goal fallback)
	var through := 0
	for i in 400:
		fv._process(0.033)
		var t: Vector2i = W.pos_to_tile(fv.position)
		if not W.is_walkable(t):
			through += 1
	_check(through == 0, "the view crossed blocked tiles in %d frames" % through)
	_check(Vector2(fv.position.x, fv.position.z).distance_to(Vector2(10.5, 14.5)) < 0.3, "the view never arrived: %s" % str(fv.position))
	fv.free()
	W.remove_folk(f.id)
