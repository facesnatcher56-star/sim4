extends Node
## Task 60: the object test bench (not a test). For every object kind the running game knows (objects.json plus the content packs):
##   place: at each rotation in the open and with its back to a wall on the player's lot (and on an upper floor when the town has one); measure
##          the drawn model against its footprint (overhang, under-fill, sitting on the floor); sell it again.
##   use:   the player's character runs every action the object offers (walk-to spot, facing, clip, held prop, object state, needs / skills / coins).
##   look:  a close shot by day with the character beside it, a night shot and a mid-zoom shot.
## One JSON line per kind ("BENCH {...}") and shots to <out>/<def>_*.png.
##   powershell -File tools/quiet_godot.ps1 --script res://tools/sweep.gd -- run=res://tools/object_bench_run.gd <out dir> [only=a,b] [skip=n]
var _out := "user://bench/"
var _only: Array = []
var _skip := 0
var m
var hud
var lv
var f
var clk
var _home := ""
var _rect := Rect2i()
var _upper := -1          # the player's building after stairs and a first floor were added (the upstairs test), -1 when that failed


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a.begins_with("skip="):
			_skip = int(a.substr(5))
		elif not a.begins_with("--") and not a.begins_with("run="):
			_out = a.trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(_out)
	TestFixture.isolate_user_files()
	get_window().unfocusable = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	m = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(m)
	_go.call_deferred()


func _w(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(n: String) -> void:
	await _w(4)
	get_tree().root.get_texture().get_image().save_png(_out + n.validate_filename() + ".png")


func _go() -> void:
	await _w(5)
	m.title.visible = false
	m.start_picker.open()
	m.start_picker.select("solo")
	m.start_picker._emit_chosen()
	await _w(60)
	hud = m.hud
	lv = m.find_child("LotView", true, false)
	clk = get_tree().root.get_node("Clock")
	f = hud._resolve(hud.selected_folk_id)
	hud.tips.visible = false
	hud.tracker.visible = false
	_home = Neighborhood.lot_of(f)
	_rect = NeighborhoodLots.rect_of(_home)
	Economy.deposit(f.household_id, 900000, "bench")
	_clear_home()
	hud.toasts.visible = false          # shots of the object, not of the news
	var kinds: Array = World.defs.keys()
	kinds.sort()
	print("BENCH_KINDS %d" % kinds.size())
	for i in kinds.size():
		var d := str(kinds[i])
		if i < _skip or (not _only.is_empty() and not _only.has(d)):
			continue
		print("BENCH_KIND %d/%d %s" % [i, kinds.size(), d])
		await _bench(d)
	# the upstairs pass last: building a first floor moves the camera to it, which would spoil the shots above
	_upper = await _make_upper_floor()
	print("BENCH_UPPER %s" % str(_upper))
	for d2 in kinds:
		if _only.is_empty() or _only.has(str(d2)):
			print("BENCH_UP %s %s" % [str(d2), _upstairs(str(d2))])
	print("BENCH_END")
	get_tree().quit(0)


## Everything movable goes from the player's lot, so each kind is tried on bare floor (doors, windows and the mailbox stay).
func _clear_home() -> void:
	for o in World.all_objects():
		if NeighborhoodLots.lot_at(o.tile) == _home and not o.is_wall_mounted() and not (str(o.def_id) in ["mailbox", "stairs"]):
			World.remove_object(o.id)


func _bench(d: String) -> void:
	var def: Dictionary = World.get_def(d)
	var rep := {"def": d, "label": str(def.get("label", d)), "size": def.get("size", [1, 1]), "slots": (def.get("slots", []) as Array).size(),
		"tags": def.get("tags", []), "wall_mount": str(def.get("mount", "")) == "wall", "private": bool(def.get("private", false)), "place": [], "wall": [], "use": []}
	# ---- place in the open and against a wall, at each rotation
	var keep_id := -1
	for rot in 4:
		var t := _spot(d, rot, false)
		var r := {"rot": rot}
		if t.x < 0:
			r["err"] = "no spot: " + World.last_error
		else:
			r.merge(await _place_check(d, t, rot, false))
			if keep_id < 0 and rot == 0 and r.has("id"):
				keep_id = int(r["id"])
		if r.has("id") and int(r["id"]) != keep_id:
			r["sold"] = World.sell_object(int(r["id"]), f.household_id)
		r.erase("id")
		(rep["place"] as Array).append(r)
	if not bool(rep["wall_mount"]):
		for rot in 4:
			var t2 := _spot(d, rot, true)
			var r2 := {"rot": rot}
			if t2.x < 0:
				r2["err"] = "no wall spot: " + World.last_error
			else:
				r2.merge(await _place_check(d, t2, rot, true))
				if r2.has("id"):
					World.sell_object(int(r2["id"]), f.household_id)
			r2.erase("id")
			(rep["wall"] as Array).append(r2)
	# ---- use it, and look at it
	if keep_id >= 0:
		var o = World.get_object(keep_id)
		await _look(o, d)
		await _use_all(o, d, rep)
		if World.get_object(keep_id) != null:
			World.sell_object(keep_id, f.household_id)
	print("BENCH " + JSON.stringify(rep))


## A tile on the player's lot where the kind fits at `rot`: in the open (nothing within a tile), or with its back to a wall.
func _spot(d: String, rot: int, wall: bool) -> Vector2i:
	var def: Dictionary = World.get_def(d)
	var back: Vector2 = -WorldObject.rotate_vec(Vector2(0, 1), rot)
	var bk := Vector2i(roundi(back.x), roundi(back.y))
	for y in range(_rect.position.y + 1, _rect.end.y - 1):
		for x in range(_rect.position.x + 1, _rect.end.x - 1):
			var t := Vector2i(x, y)
			if not World.can_place(d, t, rot):
				continue
			if str(def.get("mount", "")) == "wall":
				return t
			var fp: Array = WorldObject.footprint_of(def, t, rot)
			var touches := false
			for c in fp:
				var nb: Vector2i = c + bk
				if not fp.has(nb) and not World.edge_open(c, nb):
					touches = true
			if wall and touches:
				return t
			if not wall and not touches and _clear_around(fp):
				return t
	return Vector2i(-1, -1)


func _clear_around(fp: Array) -> bool:
	for c in fp:
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var n: Vector2i = c + Vector2i(dx, dy)
				if fp.has(n):
					continue
				if World.object_at(n) != null:
					return false
				if not World.edge_open(c, n) and absi(dx) + absi(dy) == 1:
					return false
	return true


## Place, then measure the drawn model against the footprint and the floor.
func _place_check(d: String, t: Vector2i, rot: int, wall: bool) -> Dictionary:
	var id: int = World.buy_place(d, t, rot, f.household_id)
	if id < 0:
		return {"err": "buy_place: " + World.last_error, "tile": [t.x, t.y]}
	await _w(3)
	var o = World.get_object(id)
	var out := {"id": id, "tile": [t.x, t.y]}
	var node = (lv.get("_obj_nodes") as Dictionary).get(id, null)
	if node == null:
		out["note"] = "no node (wall-mounted or upper floor)"
		return out
	var bb := _aabb(node)
	if bb.size == Vector3.ZERO:
		out["note"] = "no mesh"
		return out
	var fp: Array = o.footprint() if o.has_method("footprint") else WorldObject.footprint_of(World.get_def(d), t, rot)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for c in fp:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.y))
		hi = Vector2(maxf(hi.x, c.x + 1), maxf(hi.y, c.y + 1))
	out["over"] = [snappedf(lo.x - bb.position.x, 0.01), snappedf(bb.end.x - hi.x, 0.01), snappedf(lo.y - bb.position.z, 0.01), snappedf(bb.end.z - hi.y, 0.01)]          # -x, +x, -z, +z: model past the footprint (m)
	out["fill"] = snappedf((bb.size.x * bb.size.z) / maxf((hi.x - lo.x) * (hi.y - lo.y), 0.01), 0.01)
	out["y"] = [snappedf(bb.position.y, 0.01), snappedf(bb.end.y, 0.01)]
	if wall:
		var back: Vector2 = -WorldObject.rotate_vec(Vector2(0, 1), rot)
		var past := 0.0          # how far the model goes through the wall behind it
		if back.x < -0.5:
			past = lo.x - bb.position.x
		elif back.x > 0.5:
			past = bb.end.x - hi.x
		elif back.y < -0.5:
			past = lo.y - bb.position.z
		else:
			past = bb.end.z - hi.y
		out["through_wall"] = snappedf(past - 0.05, 0.01)          # the wall itself is about 0.1 thick: half of it is free
	return out


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree() or (mi as MeshInstance3D).mesh == null:
			continue
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## The upstairs test needs a first floor: stairs in the player's flat, then a floor above, the way a player builds one.
func _make_upper_floor() -> int:
	var inside := Vector2i(-1, -1)
	for y in range(_rect.position.y, _rect.end.y):
		for x in range(_rect.position.x, _rect.end.x):
			var t := Vector2i(x, y)
			if World.get_floor(t) != "" and not World.rooms.is_outdoor(t, 0):
				inside = t
	if inside.x < 0:
		return -1
	var bid: int = World.lbuild.ensure_building(inside)
	if bid < 0:
		return -1
	var stairs := -1
	for rot in 4:
		for y in range(_rect.position.y, _rect.end.y):
			for x in range(_rect.position.x, _rect.end.x):
				if stairs < 0 and not World.rooms.is_outdoor(Vector2i(x, y), 0) and World.can_place("stairs", Vector2i(x, y), rot):
					stairs = World.buy_place("stairs", Vector2i(x, y), rot, f.household_id)
	if stairs < 0:
		print("BENCH_UPPER_FAIL stairs: " + World.last_error)
		return -1
	if World.lbuild.add_level(bid, true, f.household_id) <= 0:
		print("BENCH_UPPER_FAIL floor: " + World.last_error)
		return -1
	await _w(5)
	return bid


## Upper floor: can it go on the first floor the bench built?
func _upstairs(d: String) -> String:
	if _upper < 0:
		return "not tested (no upper floor)"
	for b in [World.levels.building(_upper)]:
		var rc: Rect2i = b["rect"]
		for y in range(rc.position.y, rc.end.y):
			for x in range(rc.position.x, rc.end.x):
				if World.can_place(d, Vector2i(x, y), 0, 1):
					return "ok"
	return "no: " + World.last_error


func _look(o, d: String) -> void:
	_fresh()
	f.tile = _free_near(o.tile)
	f.level = 0
	Neighborhood.refresh_view(f.id)
	clk.set_speed(0)
	clk.total_minutes = (clk.day() - 1) * 1440 + 12 * 60
	lv.focus_tile(o.tile)
	lv.set_zoom(7.0)
	await _w(40)
	await _shot(d + "_day")
	lv.set_zoom(18.0)
	await _w(20)
	await _shot(d + "_mid")
	clk.total_minutes = (clk.day() - 1) * 1440 + 23 * 60
	lv.set_zoom(7.0)
	await _w(60)
	await _shot(d + "_night")
	clk.total_minutes = (clk.day() - 1) * 1440 + 12 * 60


func _fresh() -> void:
	for n in f.needs:
		(f.needs[n] as Stat).set_value(45.0)          # mid: actions gated on a need being low or high are both on offer
	f.clear_queue()
	if f.current != null:
		f.cancel_current("bench")
	for dlg in hud.dialogs():          # a window an action opened (Plan a Holiday) would cover every later shot
		if dlg != null and dlg.visible:
			dlg.visible = false
	hud.pie.close()


func _free_near(t: Vector2i) -> Vector2i:
	for r in range(1, 5):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var c := t + Vector2i(dx, dy)
				if World.is_walkable(c) and NeighborhoodLots.lot_at(c) == _home:
					return c
	return t


func _use_all(o, d: String, rep: Dictionary) -> void:
	_fresh()
	var entries: Array = InteractionQuery.entries_for(f, "object", int(o.id))
	rep["offered"] = entries.filter(func(e): return bool(e["enabled"])).map(func(e): return str(e["label"]))
	rep["greyed"] = entries.filter(func(e): return not bool(e["enabled"])).map(func(e): return "%s: %s" % [e["label"], e["reason"]])

	for e in entries:
		if not bool(e["enabled"]) or e.has("action"):
			continue
		if World.get_object(o.id) == null:
			break
		_fresh()
		var now: Array = InteractionQuery.entries_for(f, "object", int(o.id)).filter(func(x): return str(x["id"]) == str(e["id"]))
		if not now.is_empty() and not bool(now[0]["enabled"]):          # an earlier action changed things (a meal is ready, the plot is watered)
			rep["use"].append({"id": str(e["id"]), "label": str(e["label"]), "skipped": str(now[0]["reason"])})
			continue

		rep["use"].append(await _use(o, d, e))


func _use(o, d: String, e: Dictionary) -> Dictionary:
	_fresh()
	f.tile = _free_near(o.tile)
	Neighborhood.refresh_view(f.id)
	await _w(4)
	var id := str(e["id"])
	var needs0 := {}
	for k in f.needs:
		needs0[k] = f.get_stat_value(k)
	var skills0: Dictionary = f.skills.duplicate(true)
	var state0: Dictionary = (o.state as Dictionary).duplicate(true)
	var coins0: int = Economy.balance(f.household_id)
	var ev := {}          # lambdas copy locals: the start / finish flags live in a dictionary they share
	var cs := func(fid, iid, _t): if fid == f.id and iid == id: ev["started"] = true
	var cf := func(fid, iid, ok): if fid == f.id and iid == id: ev["ok"] = ok
	Events.interaction_started.connect(cs)
	Events.interaction_finished.connect(cf)
	UIU.enqueue(f, id, int(o.id))
	clk.set_speed(3)
	var clips := {}
	var props := {}
	var face := -1.0
	var dist := -1.0
	var state_mid := {}
	var shot := false
	var fv = lv.get_folk_view(f.id)
	var ms0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - ms0 < 25000:
		await get_tree().process_frame
		if ev.has("ok"):
			break
		if f.current != null and str(f.current.def_id) == id and str(f.current.state) == "running":
			var clip: String = fv._desired_clip(f)
			clips[clip] = true
			for p in FolkProps.props_for(id, f.current.def.get("tags", []), clip):
				props[str(p)] = true
			if not shot and f.current.progress() >= 0.4:
				clk.set_speed(1)
				lv.focus_tile(f.tile)
				lv.set_zoom(6.5)
				await _w(8)
				var to: Vector2 = o.center2d() - Vector2(fv.position.x, fv.position.z)
				var fwd := Vector2(-sin(fv.facing_yaw), -cos(fv.facing_yaw))
				face = snappedf(rad_to_deg(fwd.angle_to(to)), 1.0)
				dist = snappedf(to.length(), 0.01)
				state_mid = (o.state as Dictionary).duplicate(true)
				await _shot("%s_use_%s" % [d, id])
				shot = true
				clk.set_speed(3)
		elif ev.has("started") and f.current == null:
			break
	Events.interaction_started.disconnect(cs)
	Events.interaction_finished.disconnect(cf)
	clk.set_speed(0)
	var dn := {}
	for k in f.needs:
		var dv: float = f.get_stat_value(k) - float(needs0[k])
		if absf(dv) >= 1.0:
			dn[k] = snappedf(dv, 1.0)
	var dsk := {}
	for k in f.skills:
		var x0: float = float((skills0.get(k, {"xp": 0.0}) as Dictionary).get("xp", 0.0))
		var x1: float = float((f.skills[k] as Dictionary).get("xp", 0.0))
		if x1 - x0 > 0.01:
			dsk[k] = snappedf(x1 - x0, 0.1)
	var after: Dictionary = (o.state as Dictionary) if World.get_object(o.id) != null else {}
	for k in after:          # an instant action (a lamp switch) changes the state without a running phase
		if not state_mid.has(k):
			state_mid[k] = after[k]
	var changed := {}
	for k in state_mid:
		if str(state_mid[k]) != str(state0.get(k, null)):
			changed[k] = [state0.get(k, null), state_mid[k]]
	return {"id": id, "label": str(e["label"]), "started": ev.has("started"), "ok": ev.get("ok", null), "clips": clips.keys(), "props": props.keys(), "face_deg": face, "dist": dist,
		"state_mid": changed, "needs": dn, "skills": dsk, "coins": Economy.balance(f.household_id) - coins0}
