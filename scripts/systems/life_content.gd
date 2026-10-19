class_name LifeContent
extends RefCounted
## Runtime content of task 14 (idempotent): data/content_life.json merged by ContentMerge. SysContent.install_all() calls it.

static func install() -> void:
	ContentMerge.install(SimEnv.data().get_table("content_life"))
	_patch_counselling()

## "Talk to a Counsellor" (task 18) is also offered for burnout, shock and trauma (the buffs a counsellor helps with).
static func _patch_counselling() -> void:
	var d: Dictionary = SimEnv.data().interaction_def("seek_counselling")
	if d.is_empty():
		return
	for t in d.get("tests", []):
		if t is Dictionary and (t as Dictionary).has("any"):
			for b in Counselling.cfg().get("other", []):
				var row := {"has_buff": str(b)}
				if not (t["any"] as Array).has(row):
					(t["any"] as Array).append(row)
