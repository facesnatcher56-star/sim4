extends RefCounted
## ANIMATION agent: every clip referenced by data/animation_map.json exists in every folk body variant, the rig/material/hair
## contract holds, and the cyclic clips loop cleanly. Convention: run() -> Array of failure strings.

const REQUIRED := ["Idle", "Walk", "Run", "Sit_Idle", "Sit_Eat", "Sit_Watch", "Sleep", "Use_Stand", "Cook", "Wash", "Read",
	"Exercise_Treadmill", "Paint", "Type", "Dance", "Talk", "Laugh", "Wave", "Cry", "Angry", "Sad_Idle", "Hug", "Kiss", "Carry",
	"Faint", "Fall", "Shower", "ToiletSit", "Swim_idle", "Baby_Idle", "Baby_Crawl"]
const BONES := ["hips", "spine", "chest", "neck", "head", "shoulder_L", "upper_arm_L", "forearm_L", "hand_L", "shoulder_R",
	"upper_arm_R", "forearm_R", "hand_R", "thigh_L", "shin_L", "foot_L", "thigh_R", "shin_R", "foot_R"]
const MATS := ["skin", "hair", "eyes", "shirt", "pants", "shoes"]

var fails: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


## All clip-name-looking strings (capitalised) inside the clip-bearing sections of the map.
static func map_clips(m: Dictionary) -> Array:
	var out: Array = []
	for sec in ["interactions", "tags", "posture", "idle", "locomotion", "variants", "fallbacks"]:
		_collect(m.get(sec, {}), out)
	return out


static func _collect(v: Variant, out: Array) -> void:
	if v is String:
		var s := str(v)
		if s != "" and s[0] == s[0].to_upper() and s != "*" and not out.has(s):
			out.append(s)
	elif v is Dictionary:
		for k in v:
			if str(k) in ["seg", "min_intensity"]:
				continue
			_collect(v[k], out)
	elif v is Array:
		for x in v:
			_collect(x, out)


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func run() -> Array:
	fails = []
	FolkView.reload_map()
	var m: Dictionary = FolkView.anim_map()
	_check(m.has("interactions") and m.has("variant_files"), "animation_map.json missing or incomplete")
	var needed: Array = REQUIRED.duplicate()
	for c in map_clips(m):
		if not needed.has(c):
			needed.append(c)
	_check(needed.size() >= 31, "expected at least the 31 standard clips, got %d" % needed.size())
	var files: Dictionary = m.get("variant_files", {})
	for stage in ["adult", "teen", "child", "elder", "toddler", "baby", "fallback"]:
		_check(files.has(stage), "variant_files lacks " + stage)
		var path := str(files.get(stage, ""))
		_check(ResourceLoader.exists(path), "model missing: " + path)
		if not ResourceLoader.exists(path):
			continue
		var ps = load(path)
		_check(ps is PackedScene, "not a PackedScene: " + path)
		if not (ps is PackedScene):
			continue
		var inst: Node = ps.instantiate()
		var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
		_check(ap != null, "%s: no AnimationPlayer" % stage)
		if ap != null:
			for c in needed:
				_check(ap.has_animation(c), "%s: clip '%s' missing" % [stage, c])
			# loop safety: first and last keys of every rotation track of cyclic clips match
			for c in ["Idle", "Walk", "Run", "Sit_Idle", "Dance", "Talk", "Baby_Crawl", "Carry"]:
				if not ap.has_animation(c):
					continue
				var a: Animation = ap.get_animation(c)
				var worst := 0.0
				for t in a.get_track_count():
					if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
						continue
					var n := a.track_get_key_count(t)
					var q0: Quaternion = a.track_get_key_value(t, 0)
					var q1: Quaternion = a.track_get_key_value(t, n - 1)
					worst = maxf(worst, 1.0 - absf(q0.dot(q1)))
				_check(worst < 1e-3, "%s/%s: not loop-safe (first/last key differ by %f)" % [stage, c, worst])
			FolkView.prepare_player(ap)
			for c in ["Idle", "Walk"]:
				_check(ap.get_animation(c).loop_mode == Animation.LOOP_LINEAR, "%s/%s should loop" % [stage, c])
			_check(ap.get_animation("Faint").loop_mode == Animation.LOOP_NONE, "%s/Faint should not loop" % stage)
		var sk := _find(inst, "Skeleton3D") as Skeleton3D
		_check(sk != null, "%s: no Skeleton3D" % stage)
		if sk != null:
			for b in BONES:
				_check(sk.find_bone(b) >= 0, "%s: bone %s missing" % [stage, b])
		for i in 6:
			_check(inst.find_child("hair_%d" % i, true, false) != null, "%s: hair_%d missing" % [stage, i])
		var seen := {}
		_collect_mats(inst, seen)
		for mn in MATS:
			_check(seen.has(mn), "%s: material '%s' missing" % [stage, mn])
		inst.free()
	for v in (m.get("variants", {}) as Dictionary):
		_check(v in FolkView.STAGES, "variants: unknown stage " + str(v))
	return fails


func _collect_mats(n: Node, seen: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat != null:
				seen[str(mat.resource_name)] = true
	for c in n.get_children():
		_collect_mats(c, seen)
