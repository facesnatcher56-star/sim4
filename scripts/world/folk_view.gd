class_name FolkView
extends "res://scripts/world/folk_motion.gd"
## Visual for one Folk (see folk_data.gd for the layer chain): per-frame update, pose + clip selection.


# ------------------------------------------------------------------ logic

func _process(delta: float) -> void:
	if folk_id < 0:
		return
	var f = World.get_folk(folk_id)
	if f == null:
		return
	visible = not f.has_meta("away") and not has_meta("occluded") and not has_meta("level_hidden") and not has_meta("in_vehicle")    # away (work, school, party, fast travel), behind a building shell or riding in a vehicle (VehicleView): not drawn
	if not visible:
		_last_tile = Vector2i(-999, -999)      # not animated while hidden: it reappears on its tile
		return
	if has_meta("vehicle_goto"):
		_vehicle_walk(f, delta)          # walking to the door of a vehicle or bus stop (VehicleView)
		return
	_check_tick += 1
	if _check_tick % 20 == 0:
		if stage_of(f) != _stage_now:
			_build_visual()
		elif hash(_appearance_of(f)) + 31 * hash(_stage_now) + 977 * bump_of(f) != _look_sig:
			_apply_appearance(f)
	if not _lead_walk(f):
		_update_waypoints(f)
	_urgent = FolkClipRules.urgent_move(f)
	_resolve_target(f)
	_lead_target(f)
	_move(delta)
	if _res_tick % 3 == 0:
		_update_avoid(f)
	_apply_avoid(delta)
	_apply_pose(f, delta)
	_update_mood_icon(f, delta)


# ------------------------------------------------------------------ vehicles (the view layer VehicleView)

var _veh_goal: Vector2i = Vector2i(-9999, -9999)


## Walk along a real path to the tile in meta "vehicle_goto" (a vehicle door, a bus stop) and stand there; the sim's own walk is ignored meanwhile.
func _vehicle_walk(f, delta: float) -> void:
	var goal: Vector2i = get_meta("vehicle_goto")
	if goal != _veh_goal:
		_veh_goal = goal
		_waypoints.clear()
		var from_t: Vector2i = World.pos_to_tile(position)
		var seg: Array = World.find_path(from_t, goal) if from_t != goal else []
		if seg.size() > 60:
			seg = []
			position = World.tile_to_pos(goal)
		for t in seg:
			_waypoints.append(_wp(t, 0))
	_last_tile = f.tile
	_last_level = f.level
	_level_y = World.walk_y(goal, 0)
	_target = World.tile_to_pos(goal)
	_target_pose = "idle"
	_urgent = false
	_move(delta)
	_apply_pose(f, delta)


## The folk has just been put at a vehicle door: no old walk to catch up on, it walks from here to where the sim has it.
func vehicle_landed() -> void:
	_veh_goal = Vector2i(-9999, -9999)
	_waypoints.clear()
	_last_tile = Vector2i(-999, -999)
	var f = World.get_folk(folk_id)
	if f != null:
		_last_tile = f.tile
		_last_level = f.level
	_ybase = 0.0


# ------------------------------------------------------------------ clip selection

func _pose_key() -> String:
	# key used by interactions[...] dictionaries
	match _target_pose:
		"sit":
			return "sit"
		"lie":
			return "lie"
	return "stand"


func _pick_from(entry: Variant, key: String) -> String:
	if entry is String:
		return entry
	if entry is Dictionary:
		var d: Dictionary = entry
		if d.has(key):
			return str(d[key])
		if d.has("default"):
			return str(d["default"])
	return ""


func _social_clip(entry: Dictionary, role: String) -> String:
	var arr: Array = entry.get(role, [])
	if arr.is_empty():
		return ""
	var seg := maxf(float(entry.get("seg", 4.0)), 0.5)
	var t := (Time.get_ticks_msec() / 1000.0 - _inter_t0) / seg + float(folk_id % 3) * 0.0
	return str(arr[int(t) % arr.size()])


## Somebody is talking to this folk and it has nothing of its own going on (a folk in the shower, at the stove or reading keeps its own clip).
func _social_target(f) -> bool:
	return _partner_role == "target" and not (_is_running(f) and str(f.current.target_kind) != "folk")


func _interaction_entry(f) -> Variant:
	var inter = _partner_inter if _social_target(f) else f.current
	if inter == null:
		return null
	var tags: Array = inter.def.get("tags", []) if inter.def is Dictionary else []
	return FolkClipRules.entry_for(str(inter.def_id), tags)


## A sitting or lying body only ever plays a sitting or lying clip (a standing clip becomes its seated twin, see FolkClipRules.fit_pose).
func _desired_clip(f) -> String:
	var c := _raw_clip(f)
	if _moving or not _waypoints.is_empty():
		return c
	return FolkClipRules.fit_pose(c, _pose_key())


func _raw_clip(f) -> String:
	var m := anim_map()
	var loco: Dictionary = m.get("locomotion", {})
	var key := _pose_key()
	# 1. locomotion
	if _moving or not _waypoints.is_empty():
		if _urgent:
			return str(loco.get("run_clip", "Run"))
		return str(loco.get("walk_clip", "Walk"))
	# 2. one-shot "enter" clip held for its duration
	var now := Time.get_ticks_msec() / 1000.0
	if _hold_clip != "" and now < _hold_until:
		return _hold_clip
	# 3. interaction / partner
	var running := _is_running(f)
	if running or _social_target(f):
		var entry: Variant = _interaction_entry(f)
		if entry is Dictionary and ((entry as Dictionary).has("actor") or (entry as Dictionary).has("target")):
			var role := "actor"
			if _social_target(f):
				role = "target"
			var c := _social_clip(entry, role)
			if c != "":
				return c
		elif entry != null:
			var c2 := _pick_from(entry, key)
			if c2 != "":
				return c2
		if running:
			var post: Dictionary = m.get("posture", {})
			return str(post.get(key, "Use_Stand"))
	# 4. a weapon held out: held low, or raised at someone (task 57b)
	if _target_pose != "sit" and _target_pose != "lie":
		var wc := WeaponShop.clip_of(folk_id)
		if wc != "":
			return wc
	# 5. idle by posture / mood
	var idle: Dictionary = m.get("idle", {})
	if _target_pose == "sit":
		return str(idle.get("sit", "Sit_Idle"))
	if _target_pose == "lie":
		return str(idle.get("lie", "Sleep"))
	var mood := str(f.mood_name) if "mood_name" in f else "neutral"
	var moods: Dictionary = idle.get("mood", {})
	if moods.has(mood):
		var md: Dictionary = moods[mood]
		if int(f.mood_intensity) >= int(md.get("min_intensity", 1)):
			return str(md.get("clip", "Idle"))
	return str(idle.get("default", "Idle"))


func _apply_pose(f, delta: float) -> void:
	var want := _target_pose
	if _moving or not _waypoints.is_empty():
		want = "walk"
	if want != pose:
		pose = want
		pose_changed.emit(folk_id, pose)
	rotation.y = facing_yaw
	# interaction change bookkeeping (enter clips, social timers)
	var cur: Variant = f.current if _is_running(f) else null
	if cur != _cur_ref:
		_cur_ref = cur
		_inter_t0 = Time.get_ticks_msec() / 1000.0
		_hold_clip = ""
		_social_dir = Vector2.ZERO
		_social_len = 0.0
		if cur != null:
			var entry: Variant = _interaction_entry(f)
			if entry is Dictionary and (entry as Dictionary).has("enter"):
				var ec := _resolve_clip(str(entry["enter"]))
				if _anim != null and _anim.has_animation(ec):
					_hold_clip = str(entry["enter"])
					_hold_until = _inter_t0 + clampf(_anim.get_animation(ec).length, 1.0, 4.0)
	var wanted := _desired_clip(f)
	if _anim != null:
		var played := _resolve_clip(wanted)
		_play_clip_name(played)
		var shown: Variant = (_partner_inter if _social_target(f) else f.current) if (_is_running(f) or _social_target(f)) else null
		FolkProps.update(self, shown, played)
		FolkFx.update(self, shown, played)
		_anim.speed_scale = _anim_speed(wanted)
		position.y = _ybase + (_elev + _sit_lift() if pose in ["sit", "lie"] else 0.0)
		return
	if _rig == null:
		return
	_placeholder_pose(delta)


func _sit_lift() -> float:
	# Smaller bodies sit lower on the same seat; lift them so the pelvis meets the cushion.
	if pose != "sit":
		return 0.0
	return (1.0 - _body_scale) * 0.45
