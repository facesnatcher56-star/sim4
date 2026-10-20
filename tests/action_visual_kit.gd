extends RefCounted
## Shared helpers for the task-33 action-visual audit (no run(), so the runner skips it): which clip every interaction resolves to and
## whether that clip is a generic one (the owner's "same default model animation and nothing changes"). View data only.

const Kit = preload("res://tests/sim_testkit.gd")
## clips that say nothing about what the folk is doing
const GENERIC := ["Use_Stand", "Idle", "Talk", "Sit_Idle"]


## Installs all content on a stub world (call Kit.teardown() when done) and returns {id: row} for every interaction:
## {tags, target, objects:[def ids], poses:[pose per object], clips:[distinct resolved clips], generic:bool, group:String}.
static func rows() -> Dictionary:
	Kit.setup()
	SysContent.install_all()
	SocialContent.install()
	NeighborhoodService.install()       # venues, works, buildings (order_coffee, work_line, ...)
	CrimeFlow.install()
	var d = SimEnv.data()
	FolkView.reload_map()
	var objs: Dictionary = d.objects()
	var by_int: Dictionary = {}
	for oid in objs:
		var o: Dictionary = objs[oid]
		var pose := "stand"
		for s in o.get("slots", []):
			pose = str((s as Dictionary).get("pose", "stand"))
			break
		for iid in o.get("interactions", []):
			if not by_int.has(iid):
				by_int[iid] = {"objects": [], "poses": []}
			(by_int[iid]["objects"] as Array).append(str(oid))
			(by_int[iid]["poses"] as Array).append(pose)
	var out: Dictionary = {}
	var ints: Dictionary = d.interactions()
	for id in ints:
		var idef: Dictionary = ints[id]
		var tags: Array = idef.get("tags", [])
		var objs_l: Array = by_int.get(id, {}).get("objects", [])
		var poses: Array = by_int.get(id, {}).get("poses", [])
		var clips: Array = []
		var ps: Array = poses if not poses.is_empty() else ["stand"]
		if FolkClipRules.stands_at_slot_id(str(id)):
			ps = ["stand"]
		for p in ps:
			for c in clips_for(str(id), tags, str(p)):
				if not clips.has(c):
					clips.append(c)
		var generic := true
		for c in clips:
			if not (c in GENERIC):
				generic = false
		var raw_generic := generic                          # on a generic clip, allow-list or not
		if str(id) in (FolkView.anim_map().get("generic_ok", []) as Array):
			generic = false
		var group := "(" + ", ".join(tags.slice(0, 2)) + ")" if objs_l.is_empty() else str(objs_l[0])
		if objs_l.is_empty() and tags.is_empty():
			group = "(no tag)"
		out[str(id)] = {"tags": tags, "target": str(idef.get("target", "object")), "objects": objs_l, "poses": poses, "clips": clips,
			"generic": generic, "raw_generic": raw_generic, "group": group, "idef": idef}
	return out


## Every clip the interaction can show in that pose (social entries cycle several).
static func clips_for(id: String, tags: Array, pose: String) -> Array:
	var e: Variant = FolkClipRules.entry_for(id, tags)
	if e is Dictionary and ((e as Dictionary).has("actor") or (e as Dictionary).has("target")):
		var l: Array = []
		for k in ["actor", "target"]:
			for c in (e as Dictionary).get(k, []):
				if not l.has(str(c)):
					l.append(str(c))
		return l
	return [FolkClipRules.clip_for(id, tags, pose)]


## Share of interactions on a generic clip, the allow-list counted as generic (the strict number).
static func share(rows_d: Dictionary) -> float:
	var g := 0
	for id in rows_d:
		if bool(rows_d[id]["raw_generic"]):
			g += 1
	return float(g) / maxf(1.0, float(rows_d.size()))


const SEED := 4242
static var _counts: Dictionary = {}


static func _on_started(_fid, iid, _tid) -> void:
	_counts[str(iid)] = int(_counts.get(str(iid), 0)) + 1


## How often each interaction starts in a `days`-day run of the real game (classic start, fixed seed, the hash-baseline setup): {id: count}.
## View-independent: nothing here is saved or compared with the coop hash.
static func freq(days: int = 3) -> Dictionary:
	var HoodKit = load("res://tests/hood_kit.gd")
	HoodKit.teardown()
	SimSeed.apply(SEED)
	HoodKit.new_game("classic", SEED, SEED)
	HoodKit.set_time(1, 7)
	_counts = {}
	var ev = SimEnv.events()
	ev.interaction_started.connect(_on_started)
	HoodKit.run(days * 1440)
	ev.interaction_started.disconnect(_on_started)
	HoodKit.teardown()
	return _counts.duplicate()
