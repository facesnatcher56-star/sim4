extends SceneTree
## Reviewer tool (not a test; the runner skips it): windowed check of task 56. Orders the pawn on a long walk across town at a given
## game speed and measures the drawn model's movement per frame. A "jump" is more than JUMP_M metres in one frame.
##   godot --path . --script res://tests/speed_walk_probe.gd -- <speed 1|2|3> [seed]
const JUMP_M := 2.5
var _main: Node = null
var _frames := 0
var _f = null
var _view: Node3D = null
var _last := Vector3.INF
var _max := 0.0
var _jumps: Array = []
var _covered := 0.0
var _start_frame := 0
var _speed := 3
var _seed := 77
var _arrived_frame := -1
var _sim_ms := 0
var _t0 := 0

func _find_view(n: Node, id: int) -> Node3D:
	if n is Node3D and n.get("folk_id") != null and int(n.get("folk_id")) == id:
		return n
	for c in n.get_children():
		var r = _find_view(c, id)
		if r != null:
			return r
	return null

func _process(_d: float) -> bool:
	if _main == null:
		var a := OS.get_cmdline_user_args()
		if a.size() > 0:
			_speed = int(a[0])
		if a.size() > 1:
			_seed = int(a[1])
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5:
		var r := RandomNumberGenerator.new()
		r.seed = _seed
		var h := HouseholdSetup.make_household("solo", r)
		_main.start_new_game(h, str(Scenario.def("solo").get("start_id", "small")), {"scenario": "solo", "difficulty": "normal", "world_seed": _seed, "funds": Scenario.funds_for("solo", "normal")})
		return false
	if _frames == 20:
		_f = SysUtil.residents()[0]
		_view = _find_view(root, int(_f.id))
		var W = root.get_node("World")
		var best := Vector2i(-1, -1)
		var bd := 0.0
		for y in W.height:
			for x in W.width:
				var t := Vector2i(x, y)
				if W.get_floor(t) in ["sidewalk", "pavement", "concrete"] and W.is_walkable(t):
					var d: float = t.distance_to(_f.tile)
					if d > bd and d < 90:
						bd = d
						best = t
		print("SPEED56 speed %d pawn %s target %s (%.0f tiles) view %s" % [_speed, str(_f.tile), str(best), bd, str(_view != null)])
		_f.enqueue(Interaction.create_goto(_f, best, true, 0))
		root.get_node("Clock").set_speed(_speed)
		_start_frame = _frames
		_t0 = Time.get_ticks_msec()
		return false
	if _frames > 20 and _view != null:
		var p: Vector3 = _view.global_position
		if _last != Vector3.INF:
			var dd := Vector2(p.x - _last.x, p.z - _last.z).length()
			_covered += dd
			_max = maxf(_max, dd)
			if dd > JUMP_M:
				_jumps.append("f%d %.1fm" % [_frames - _start_frame, dd])
		_last = p
		var idle: bool = _f.current == null and _f.queue.is_empty()
		var goal: Vector3 = root.get_node("World").tile_to_pos(_f.tile)
		var off: float = Vector2(p.x - goal.x, p.z - goal.z).length()
		if idle and _arrived_frame < 0:
			_arrived_frame = _frames
			_sim_ms = Time.get_ticks_msec() - _t0
			print("SPEED56 at sim arrival: clock speed %d real_rate %.1f skip %s" % [root.get_node("Clock").speed, root.get_node("Clock").real_rate(), str(TimeSkip.active)])
		if (idle and (off < 1.0 or _frames - _arrived_frame > 600)) or _frames - _start_frame > 4000:
			print("SPEED56 sim arrived at frame %d (%.1f s real); view arrived %d frames later, off %.1f m; covered %.0f m, max per frame %.2f m, jumps %d %s, fps %.0f" % [_arrived_frame - _start_frame, _sim_ms / 1000.0, _frames - _arrived_frame, off, _covered, _max, _jumps.size(), str(_jumps.slice(0, 10)), Engine.get_frames_per_second()])
			print("SPEED56 at end: clock speed %d real_rate %.1f" % [root.get_node("Clock").speed, root.get_node("Clock").real_rate()])
			quit(0)
	return false
