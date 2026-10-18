class_name FamilyContent
extends RefCounted
## Runtime content injected into the shared Data tables by the family layer (idempotent, like SysContent):
##  * interactions: feed_baby, change_diaper, rock_to_sleep, play_with_baby, hold_baby, teach_walking/talking/potty,
##    have_wedding, divorce, ask_to_move_in, adopt_child, sleep_crib
##  * buffs: pregnant_t1..t3, crying, baby_crying, engaged, married, newlywed, divorced, widowed, bereaved, new_parent,
##    proud_parent; need decay multipliers on the hidden stage_baby / stage_toddler markers
##  * object: `crib` (model res://assets/models/crib.glb - the view falls back to a box when it is missing). Skipped
##    if data/objects.json ever defines its own `crib`.
##  * patches: babies cannot use beds / sofas (`sleep` tagged interactions) and cannot clean themselves after accidents.
## Call FamilyContent.install() after SysContent.install(); SystemsManager and SaveLoad do.

const MARK := "_fam_patch"
const ADULT := {"any": [{"has_buff": "stage_adult"}, {"has_buff": "stage_elder"}]}
const SMALL := {"any": [{"has_buff": "stage_baby"}, {"has_buff": "stage_toddler"}]}

static func install() -> void:
	var data = SimEnv.data()
	var inter: Dictionary = data.interactions()
	if inter.is_empty():
		return
	if not data.buffs().has("stage_baby"):
		SysContent.install()      # the stage_* marker buffs are created there
	if not inter.has("feed_baby"):
		_add_interactions(inter)
		_add_buffs(data.buffs())
		_patch_existing(inter)
	_ensure_crib(data.objects())
	var w = WorldIface.world()
	if w != null and "defs" in w and w.defs is Dictionary:
		_ensure_crib(w.defs)

static func _care(label: String, minutes: float, target_tests: Array, target_per_min: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {
		"label": label, "kind": "social", "target": "folk", "duration_min": minutes, "posture": "stand", "_sys_gate": true,
		"tests": [ADULT.duplicate(true)], "target_tests": target_tests + [{"lacks_buff": "away"}],
		"target_per_min": target_per_min, "on_finish": [{"relationship_add": ["friendship", 1.5]}],
		"autonomous": false, "priority": "high", "interruptible": true, "tags": ["baby_care", "family"],
	}
	for k in extra:
		d[k] = extra[k]
	return d

static func _add_interactions(inter: Dictionary) -> void:
	inter["feed_baby"] = _care("Feed Baby", 10.0, [{"has_buff": "stage_baby"}, {"stat_below": ["hunger", 85]}], {"hunger": 9.0},
		{"per_min": {"social": 0.3}, "thought": "Time for a bottle."})
	inter["change_diaper"] = _care("Change Diaper", 4.0, [{"has_buff": "stage_baby"}, {"any": [{"stat_below": ["bladder", 70]}, {"stat_below": ["hygiene", 70]}]}],
		{"bladder": 30.0, "hygiene": 20.0}, {"per_min": {"hygiene": -0.5}, "thought": "Diaper time."})
	inter["rock_to_sleep"] = _care("Rock to Sleep", 25.0, [{"has_buff": "stage_baby"}, {"stat_below": ["energy", 75]}], {"energy": 6.0, "comfort": 1.0},
		{"on_finish": [{"relationship_add": ["friendship", 1.5]}, {"target_add_buff": "nap_refreshed"}], "thought": "Shh, shh..."})
	inter["play_with_baby"] = _care("Play with Little One", 20.0, [SMALL.duplicate(true)], {"fun": 4.0, "social": 3.0},
		{"per_min": {"fun": 1.5, "social": 1.0}, "thought": "Peek-a-boo!"})
	inter["hold_baby"] = _care("Cuddle Little One", 12.0, [SMALL.duplicate(true)], {"social": 6.0, "comfort": 3.0},
		{"per_min": {"social": 1.5}})
	for sk in ["walking", "talking", "potty"]:
		var lbl: Dictionary = {"walking": "Teach to Walk", "talking": "Teach to Talk", "potty": "Potty Train"}
		inter["teach_" + sk] = _care(str(lbl[sk]), 25.0, [{"has_buff": "stage_toddler"}], {"fun": 1.0},
			{"per_min": {"social": 0.5}, "on_finish": [{"relationship_add": ["friendship", 1.0]}, {"fire_event": "teach_" + sk}]})
	inter["have_wedding"] = {
		"label": "Hold Wedding", "kind": "social", "target": "folk", "duration_min": 45, "posture": "stand", "_sys_gate": true,
		"tests": [{"has_buff": "engaged"}], "target_tests": [{"has_buff": "engaged"}, {"lacks_buff": "away"}],
		"per_min": {"fun": 0.5, "social": 0.5}, "on_finish": [{"fire_event": "wedding"}],
		"autonomous": false, "priority": "normal", "tags": ["social", "romance", "wedding"], "thought": "I do!",
	}
	inter["divorce"] = {
		"label": "Divorce", "kind": "social", "target": "folk", "duration_min": 15, "posture": "stand", "_sys_gate": true,
		"tests": [{"has_buff": "married"}], "target_tests": [{"has_buff": "married"}, {"lacks_buff": "away"}],
		"on_finish": [{"fire_event": "divorce"}], "autonomous": false, "priority": "normal", "tags": ["social", "conflict"],
	}
	inter["ask_to_move_in"] = {
		"label": "Ask to Move In", "kind": "social", "target": "folk", "duration_min": 15, "posture": "stand", "_sys_gate": true,
		"tests": [ADULT.duplicate(true), {"relationship_above": ["friendship", 10]}],
		"target_tests": [ADULT.duplicate(true), {"lacks_buff": "away"}],
		"on_finish": [{"fire_event": "move_in_request"}], "autonomous": false, "priority": "normal", "tags": ["social", "family"],
	}
	inter["adopt_child"] = {
		"label": "Adopt a Child", "kind": "super", "target": "self", "duration_min": 30, "posture": "stand", "_sys_gate": true,
		"tests": [ADULT.duplicate(true)], "on_finish": [{"fire_event": "adopt_child"}], "autonomous": false, "priority": "normal",
		"tags": ["family"], "thought": "Maybe it's time to grow our family.",
	}
	inter["sleep_crib"] = {
		"label": "Sleep in Crib", "kind": "super", "target": "object", "objects": ["crib"], "tags": ["sleep", "rest"], "_sys_gate": true,
		"duration_min": 480, "posture": "lie", "tests": [SMALL.duplicate(true), {"stat_below": ["energy", 55]}],
		"per_min": {"energy": 0.2, "comfort": 0.1},
		"need_decay_mult": {"hunger": 0.6, "bladder": 0.7, "social": 0.4, "fun": 0.3, "hygiene": 0.6, "energy": 0.3},
		"end_when": [{"stat_above": ["energy", 92]}], "on_finish": [{"add_buff": "well_rested"}],
		"autonomous": true, "priority": "normal", "advertises": {"energy": 5.0, "comfort": 1.0}, "thought": "Sleepy baby...",
	}

static func _add_buffs(b: Dictionary) -> void:
	b["pregnant_t1"] = {"label": "First Trimester", "mood": {"uncomfortable": 2}, "duration_min": 0,
		"need_decay_mult": {"hunger": 1.3, "energy": 1.3}, "thought": "I feel a bit queasy..."}
	b["pregnant_t2"] = {"label": "Second Trimester", "mood": {"happy": 2}, "duration_min": 0,
		"need_decay_mult": {"hunger": 1.4, "bladder": 1.2}, "thought": "I'm glowing."}
	b["pregnant_t3"] = {"label": "Third Trimester", "mood": {"uncomfortable": 2, "tense": 1}, "duration_min": 0,
		"need_decay_mult": {"bladder": 1.8, "energy": 1.5, "hunger": 1.4, "comfort": 1.6}, "thought": "Any day now..."}
	b["crying"] = {"label": "Crying", "mood": {"sad": 3, "uncomfortable": 1}, "duration_min": 0, "thought": "Waaaaah!"}
	b["baby_crying"] = {"label": "Baby Crying", "mood": {"tense": 2}, "duration_min": 90, "need_decay_mult": {"fun": 1.1},
		"thought": "That crying is wearing me down."}
	b["engaged"] = {"label": "Engaged", "mood": {"happy": 1}, "duration_min": 0, "thought": "We're getting married!"}
	b["married"] = {"label": "Married", "mood": {}, "duration_min": 0, "hidden": true}
	b["newlywed"] = {"label": "Newlywed", "mood": {"happy": 3}, "duration_min": 2880, "thought": "Married life!"}
	b["divorced"] = {"label": "Divorced", "mood": {"sad": 3}, "duration_min": 4320, "thought": "It's really over."}
	b["widowed"] = {"label": "Widowed", "mood": {"sad": 4}, "duration_min": 8640, "need_decay_mult": {"fun": 1.2},
		"thought": "I miss them so much."}
	b["bereaved"] = {"label": "Bereaved", "mood": {"sad": 3}, "duration_min": 5760, "thought": "I can't believe they're gone."}
	b["new_parent"] = {"label": "New Parent", "mood": {"happy": 1, "uncomfortable": 1}, "duration_min": 2880,
		"need_decay_mult": {"energy": 1.2}, "thought": "A whole new little person."}
	b["proud_parent"] = {"label": "Proud Parent", "mood": {"happy": 3}, "duration_min": 1440, "thought": "Look how much they've learned!"}
	if b.has("stage_baby"):
		b["stage_baby"]["need_decay_mult"] = {"hunger": 1.6, "bladder": 1.8, "hygiene": 1.5, "energy": 0.9, "fun": 1.3, "social": 1.3}
	if b.has("stage_toddler"):
		b["stage_toddler"]["need_decay_mult"] = {"hunger": 1.2, "bladder": 1.3, "fun": 1.2}

## Babies need adults for everything except sleeping in the crib.
static func _patch_existing(inter: Dictionary) -> void:
	for iid in inter:
		var d: Dictionary = inter[iid]
		if bool(d.get(MARK, false)) or str(iid) == "sleep_crib":
			continue
		d[MARK] = true
		var tags: Array = d.get("tags", [])
		if tags.has("sleep") and not tags.has("emergency"):
			var tests: Array = d.get("tests", [])
			tests.append({"lacks_buff": "stage_baby"})
			d["tests"] = tests
		if d.has("emergency") and str(iid) == "have_accident":
			var em: Array = d["emergency"]
			em.append({"lacks_buff": "stage_baby"})
			d["emergency"] = em

static func _ensure_crib(odefs: Dictionary) -> void:
	if odefs.is_empty():
		return
	if not odefs.has("crib"):
		odefs["crib"] = {
			"label": "Crib", "size": [1, 2], "price": 250, "tags": ["bedroom", "baby", "furniture"],
			"model": "res://assets/models/crib.glb", "color": "#c9a37a", "height": 0.9,
			"slots": [{"offset": [1, 0], "use": [0.5, 0.5], "pose": "lie", "y": 0.4}],
			"state": {}, "advertises": {"energy": 4.0}, "decor": 1.0, "interactions": ["sleep_crib"],
		}
	else:
		var list: Array = odefs["crib"].get("interactions", [])
		if not list.has("sleep_crib"):
			list.append("sleep_crib")
			odefs["crib"]["interactions"] = list
