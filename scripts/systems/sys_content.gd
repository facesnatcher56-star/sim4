class_name SysContent
extends RefCounted
## Runtime content injected into the shared Data tables by the systems layer (idempotent):
## interactions (sys_away, order_groceries, apply_for_job, try_for_baby, apologize, propose), buffs (away,
## pregnant, grieving, stage_* markers, perk buffs) and age-stage gates patched into existing interaction defs.

const GATE_MARK := "_sys_gate"

static func install() -> void:
	var data = SimEnv.data()
	var inter: Dictionary = data.interactions()
	var buffs: Dictionary = data.buffs()
	if inter.is_empty() or inter.has("sys_away"):
		_ensure_world_defs()
		return
	_add_interactions(inter)
	_add_buffs(buffs)
	_patch_targets(inter)
	_patch_stage_gates(inter)
	_ensure_world_defs()

static func _add_interactions(inter: Dictionary) -> void:
	inter["sys_away"] = {
		"label": "Away", "kind": "super", "target": "self", "duration_min": 60, "posture": "stand",
		"tests": [], "per_min": {"hunger": 0.035, "bladder": 0.06, "social": 0.02}, "on_finish": [], "on_cancel": [],
		"autonomous": false, "priority": "high", "interruptible": true, "tags": ["away"],
	}
	inter["order_groceries"] = {
		"label": "Order Groceries", "kind": "super", "target": "object", "objects": ["fridge"], "duration_min": 6,
		"posture": "stand", "tests": [{"coins_at_least": 20}, {"object_state_below": ["stock", 4]}],
		"on_finish": [{"fire_event": "order_groceries"}], "autonomous": true, "priority": "low", "cooldown_min": 240,
		"tags": ["food", "chore", "shop"], "advertises": {"hunger": 0.6}, "thought": "We're running low on food.",
	}
	inter["apply_for_job"] = {
		"label": "Look for Jobs", "kind": "super", "target": "object", "objects": ["computer"], "duration_min": 20,
		"posture": "sit", "tests": [{"has_job": false}], "on_finish": [{"fire_event": "job_search"}],
		"autonomous": false, "priority": "normal", "tags": ["skill", "career"],
	}
	inter["try_for_baby"] = {
		"label": "Try for Baby", "kind": "social", "target": "folk", "duration_min": 40, "posture": "stand",
		"tests": [{"relationship_above": ["romance", 44]}, {"any": [{"has_buff": "stage_adult"}, {"has_buff": "stage_elder"}]}],
		"target_tests": [{"any": [{"has_buff": "stage_adult"}, {"has_buff": "stage_elder"}]}],
		"on_finish": [{"relationship_add": ["romance", 2]}, {"fire_event": "try_for_baby"}], "autonomous": false,
		"priority": "normal", "tags": ["social", "flirt", "baby"],
	}
	inter["apologize"] = {
		"label": "Apologize", "kind": "social", "target": "folk", "duration_min": 5, "posture": "stand",
		"tests": [], "on_finish": [{"relationship_add": ["friendship", 2]}, {"fire_event": "apologize"}],
		"autonomous": false, "priority": "normal", "tags": ["social"],
	}
	inter["propose"] = {
		"label": "Propose", "kind": "social", "target": "folk", "duration_min": 10, "posture": "stand",
		"tests": [{"relationship_above": ["romance", 44]}], "on_finish": [{"fire_event": "propose"}],
		"autonomous": false, "priority": "normal", "tags": ["social", "flirt"],
	}

static func _add_buffs(buffs: Dictionary) -> void:
	buffs["away"] = {"label": "Away", "mood": {}, "duration_min": 0}
	buffs["pregnant"] = {"label": "Expecting", "mood": {"happy": 1, "uncomfortable": 1}, "duration_min": 0,
		"need_decay_mult": {"hunger": 1.2, "bladder": 1.2}, "thought": "A little one is on the way."}
	buffs["grieving"] = {"label": "Grieving", "mood": {"sad": 3}, "duration_min": 4320, "need_decay_mult": {"fun": 1.2},
		"thought": "I miss them so much."}
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

## Make the fridge advertise grocery ordering and the computer the job hunt (also in the World's def copy).
static func _ensure_world_defs() -> void:
	var odefs: Dictionary = SimEnv.data().objects()
	_add_obj_interaction(odefs, "fridge", "order_groceries")
	_add_obj_interaction(odefs, "computer", "apply_for_job")
	var w = WorldIface.world()
	if w != null and "defs" in w and w.defs is Dictionary:
		_add_obj_interaction(w.defs, "fridge", "order_groceries")
		_add_obj_interaction(w.defs, "computer", "apply_for_job")

static func _add_obj_interaction(defs: Dictionary, obj_id: String, iid: String) -> void:
	if not defs.has(obj_id):
		return
	var od: Dictionary = defs[obj_id]
	var list: Array = od.get("interactions", [])
	if not list.has(iid):
		list.append(iid)
		od["interactions"] = list
