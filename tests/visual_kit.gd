extends RefCounted
## Shared helper (no run(), so the runner skips it): the visual audit (tests/visual_audit.gd) without a window. Starts the real new-game path,
## gives every folk a FolkView, steps clock + views with a fixed frame time, and measures what the player would see: Run frames while
## walking, sitting poses without a seat or with a standing clip, standing in a blocked tile outside a slot, folk on top of each other.

const K = preload("res://tests/start_kit.gd")
const SIT_HOLD := 40           # frames in the sit pose before it counts (a folk may still be settling)
const OVERLAP_M := 0.3

static func run_audit(speed: int, game_minutes: int, seed_v: int = 101, scenario: String = "family", dt: float = 1.0 / 60.0) -> Dictionary:
	var root: Window = Engine.get_main_loop().root
	var W = root.get_node("World")
	var clk = root.get_node("Clock")
	FolkView.reload_map()
	K.new_game(scenario, "normal", {}, -1, {"world_seed": seed_v})
	var holder := Node3D.new()
	root.add_child(holder)
	var views: Dictionary = {}
	clk.set_speed(speed)
	var m := {"frames": 0, "folk_frames": 0, "move": 0, "run": 0, "run_urgent": 0, "sit": 0, "sit_no_seat": 0, "sit_stand_clip": 0, "blocked_still": 0, "blocked_move": 0, "overlap": 0, "anoms": {}}
	var sit_hold: Dictionary = {}
	var end: int = clk.total_minutes + game_minutes
	while clk.total_minutes < end:
		clk._process(dt)
		for f in W.all_folk():
			if not views.has(f.id):
				var fv := FolkView.new()
				fv.name = "folk_%d" % f.id
				holder.add_child(fv)
				fv.setup(f.id)
				views[f.id] = fv
		for id in views.keys():
			if W.get_folk(id) == null:
				views[id].free()
				views.erase(id)
		var vis: Array = []
		for id in views:
			var fv: FolkView = views[id]
			fv._process(dt)
			if fv.visible:
				vis.append(fv)
		m["frames"] += 1
		_measure(W, vis, m, sit_hold)
	holder.free()
	K.teardown()
	return m

static func _note(m: Dictionary, key: String) -> void:
	var a: Dictionary = m["anoms"]
	a[key] = int(a.get(key, 0)) + 1

static func _measure(W, vis: Array, m: Dictionary, sit_hold: Dictionary) -> void:
	for fv in vis:
		var f = W.get_folk(fv.folk_id)
		m["folk_frames"] += 1
		var clip: String = str(fv.clip)
		if fv._moving or not fv._waypoints.is_empty():
			m["move"] += 1
			if clip == "Run":
				if FolkClipRules.urgent_move(f):
					m["run_urgent"] += 1
				else:
					m["run"] += 1
					_note(m, "run %s" % [str(f.current.def_id) if f.current != null else "-"])
		var tile: Vector2i = W.pos_to_tile(fv.position)
		if str(fv.pose) == "sit":
			sit_hold[fv.folk_id] = int(sit_hold.get(fv.folk_id, 0)) + 1
			if int(sit_hold[fv.folk_id]) > SIT_HOLD:
				m["sit"] += 1
				if W.reservation_of(fv.folk_id) == null:
					m["sit_no_seat"] += 1
					_note(m, "sit_no_seat %s" % [str(f.current.def_id) if f.current != null else "-"])
				elif not FolkClipRules.is_sit_clip(clip):
					m["sit_stand_clip"] += 1
					_note(m, "sit_stand_clip %s %s" % [clip, str(f.current.def_id) if f.current != null else "-"])
		else:
			sit_hold.erase(fv.folk_id)
		var using_here := false
		var rs = W.reservation_of(fv.folk_id)
		if rs is Array:
			var ro = W.get_object(rs[0])
			if ro != null and ro.slot_tile(int(rs[1])) == tile:
				using_here = true
		if str(fv.pose) in ["idle", "walk", "use", "stand"] and not using_here and not W.is_walkable(tile, int(f.level)):
			var o = W.object_at(tile, int(f.level))
			if o != null and str(o.def_id).begins_with("elevator"):
				continue                     # a lift cabin is walkable for the lift ride
			m["blocked_move" if (fv._moving or not fv._waypoints.is_empty()) else "blocked_still"] += 1
			_note(m, "blocked %s %s moving=%s role=%s pose=%s state=%s res=%s" % [str(o.def_id) if o != null else "wall", str(f.current.def_id) if f.current != null else "-", str(fv._moving), fv._partner_role, fv.pose, str(f.current.state) if f.current != null else "-", str(rs)])
	for i in vis.size():
		var a = vis[i]
		if str(a.pose) in ["sit", "lie"]:
			continue
		var fa = W.get_folk(a.folk_id)
		for j in range(i + 1, vis.size()):
			var b = vis[j]
			if str(b.pose) in ["sit", "lie"] or int(W.get_folk(b.folk_id).level) != int(fa.level):
				continue
			if Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length() < OVERLAP_M:
				m["overlap"] += 1
				_note(m, "overlap %s(%s) & %s(%s) pose %s/%s roles %s/%s pair=%s %s %s" % [str(fa.current.def_id) if fa.current != null else "-", str(a._moving), str(W.get_folk(b.folk_id).current.def_id) if W.get_folk(b.folk_id).current != null else "-", str(b._moving), a.pose, b.pose, a._partner_role, b._partner_role, str(a._partner_id == b.folk_id or b._partner_id == a.folk_id), "%s>%d" % [fa.name, a._partner_id], "%s>%d" % [W.get_folk(b.folk_id).name, b._partner_id]])
