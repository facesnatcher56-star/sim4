class_name SysContent
extends RefCounted
## Runtime content for the systems layer (idempotent). The literal interactions / buffs live in data/content_sys.json
## (merged by ContentMerge); this adds the derived buffs (stage_* markers, perk buffs) and patches existing interaction
## defs: nobody socialises with someone who is away, and age stages gate interactions by tag.

const GATE_MARK := "_sys_gate"

static func install() -> void:
	var data = SimEnv.data()
	var inter: Dictionary = data.interactions()
	if inter.is_empty() or inter.has("sys_away"):
		_ensure_world_defs()
		return
	var cfg: Dictionary = data.get_table("content_sys")
	ContentMerge.install(cfg)
	_add_marker_buffs(data.buffs())
	_patch_targets(inter)
	_patch_stage_gates(inter)
	_ensure_world_defs()

## Everything the systems layer needs in one call (SysContent, then the family and weather layers built on it).
static func install_all() -> void:
	install()
	FamilyContent.install()
	WeatherContent.install()

## Buffs derived from other tables: the hidden stage_<id> markers (data/aging.json) and the goals' perk buffs.
static func _add_marker_buffs(buffs: Dictionary) -> void:
	for st in Aging.stage_ids():
		buffs["stage_" + str(st)] = {"label": str(st).capitalize(), "mood": {}, "duration_min": 0, "hidden": true}
	var perks: Dictionary = SysUtil.table("goals").get("perk_buffs", {})
	for pid in perks:
		buffs[pid] = (perks[pid] as Dictionary).duplicate(true)

## Nobody can chat with / flirt with / insult someone who is away from the lot.
static func _patch_targets(inter: Dictionary) -> void:
	for iid in inter:
		var d: Dictionary = inter[iid]
		if str(d.get("target", "object")) == "folk":
			var tt: Array = d.get("target_tests", [])
			tt.append({"lacks_buff": "away"})
			d["target_tests"] = tt

## Age-stage gating: add `lacks_buff stage_<x>` tests to interactions whose tags a stage forbids/does not allow.
static func _patch_stage_gates(inter: Dictionary) -> void:
	var stages: Array = Aging.stage_table()
	for iid in inter:
		var d: Dictionary = inter[iid]
		if bool(d.get(GATE_MARK, false)) or str(iid).begins_with("sys_"):
			continue
		d[GATE_MARK] = true
		var tags: Array = d.get("tags", [])
		for s in stages:
			var sid: String = str(s["id"])
			var blocked: bool = false
			if (s.get("forbid_tags", []) as Array).size() > 0:
				for t in s["forbid_tags"]:
					if tags.has(t):
						blocked = true
			if (s.get("allow_tags", []) as Array).size() > 0:
				blocked = true
				for t in s["allow_tags"]:
					if tags.has(t):
						blocked = false
			if blocked:
				var cond: Dictionary = {"lacks_buff": "stage_" + sid}
				var tests: Array = d.get("tests", [])
				tests.append(cond)
				d["tests"] = tests
				if str(d.get("target", "object")) == "folk":
					var tt: Array = d.get("target_tests", [])
					tt.append(cond)
					d["target_tests"] = tt

## Make the fridge / computer offer the interactions of data/content_sys.json (also in the World's def copy).
static func _ensure_world_defs() -> void:
	var extra: Dictionary = (SimEnv.data().get_table("content_sys") as Dictionary).get("object_interactions", {})
	var worlds: Array = [SimEnv.data().objects()]
	var w = WorldIface.world()
	if w != null and "defs" in w and w.defs is Dictionary:
		worlds.append(w.defs)
	for defs in worlds:
		for oid in extra:
			for iid in extra[oid]:
				ContentMerge.add_object_interaction(defs, str(oid), str(iid))
