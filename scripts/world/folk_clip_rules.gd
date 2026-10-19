class_name FolkClipRules
extends RefCounted
## Data-driven clip policy for FolkView (view only, never touches sim state): which moves are urgent enough to play Run, which clips are
## sitting / lying clips, and what a stand clip becomes while the folk sits or lies. All lists live in data/animation_map.json.


static func _loco() -> Dictionary:
	return FolkView.anim_map().get("locomotion", {})


## Run is for urgent moves only: an interaction of urgent priority, one with an emergency/fire/chase/exercise tag or id, or a walk that
## was flagged `hurry` (late for work or school). Everything else, however far behind the view is, walks.
static func urgent_move(f) -> bool:
	if f == null or f.current == null:
		return false
	var rw: Dictionary = _loco().get("run_when", {})
	var ir = f.current
	if bool(ir.params.get("hurry", false)):
		return true
	if str(ir.def.get("priority", "normal")) in (rw.get("priorities", []) as Array):
		return true
	if str(ir.def_id) in (rw.get("ids", []) as Array):
		return true
	for t in ir.def.get("tags", []):
		if str(t) in (rw.get("tags", []) as Array):
			return true
	return false


## Chores on a bed, a toilet or another seat or bunk (making the bed, cleaning the toilet): the folk stands beside the object on its use tile, it
## never lies or sits down on it. Data: animation_map `stand_at_slot` (interaction ids).
static func stands_at_slot(f) -> bool:
	return f != null and f.current != null and str(f.current.def_id) in (FolkView.anim_map().get("stand_at_slot", []) as Array)


static func is_sit_clip(c: String) -> bool:
	return c in (FolkView.anim_map().get("sit_clips", []) as Array)


static func is_lie_clip(c: String) -> bool:
	return c in (FolkView.anim_map().get("lie_clips", []) as Array)


## `c` made valid for the body pose: a stand clip while sitting becomes its sitting twin (Read -> Sit_Read), else the sit idle; lying -> Sleep.
static func fit_pose(c: String, pose_key: String) -> String:
	var m := FolkView.anim_map()
	if pose_key == "sit" and not is_sit_clip(c):
		var sub: Dictionary = m.get("sit_substitute", {})
		return str(sub.get(c, sub.get("*", "Sit_Idle")))
	if pose_key == "lie" and not is_lie_clip(c):
		return str((m.get("idle", {}) as Dictionary).get("lie", "Sleep"))
	return c


## The data entry of an interaction (own id first, then tags in tag_order, then any tag).
static func entry_for(id: String, tags: Array) -> Variant:
	var m := FolkView.anim_map()
	var ints: Dictionary = m.get("interactions", {})
	if ints.has(id):
		return ints[id]
	var tmap: Dictionary = m.get("tags", {})
	for t in m.get("tag_order", []):
		if str(t) in tags and tmap.has(str(t)):
			return tmap[str(t)]
	for t in tags:
		if tmap.has(str(t)):
			return tmap[str(t)]
	return null


static func pick_from(entry: Variant, key: String) -> String:
	if entry is String:
		return entry
	if entry is Dictionary:
		var d: Dictionary = entry
		if d.has(key):
			return str(d[key])
		if d.has("default"):
			return str(d["default"])
		var arr: Array = d.get("actor", [])
		if not arr.is_empty():
			return str(arr[0])
	return ""


## The clip a lone interaction plays in `pose_key` (stand|sit|lie), pose-fitted. "" when the map has nothing for it.
static func clip_for(id: String, tags: Array, pose_key: String) -> String:
	var c := pick_from(entry_for(id, tags), pose_key)
	if c == "":
		c = str((FolkView.anim_map().get("posture", {}) as Dictionary).get(pose_key, "Use_Stand"))
	return fit_pose(c, pose_key)
