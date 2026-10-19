extends RefCounted
## Shared helpers for content_* tests (no run(), so the runner skips it).

const Kit = preload("res://tests/sim_testkit.gd")

const COND_KEYS := ["circadian", "no_free_bed", "pair_flag_absent", "stat_below", "stat_above", "has_trait", "lacks_trait", "has_buff", "lacks_buff", "mood_is", "skill_at_least",
	"object_state_eq", "object_state_above", "object_state_below", "time_between", "coins_at_least", "relationship_above",
	"has_job", "posture_is", "posture_not", "not", "any", "age_stage_is", "homemaker", "fridge_clean"]
const SYS_COND_KEYS := ["friends_at_least", "bit_count", "career_is", "career_level_at_least", "age_stage_is", "skill_below", "in_school", "pregnant"]
const LOOT_KEYS := ["add_buff", "remove_buff", "target_add_buff", "target_remove_buff", "stat_add", "target_stat_add", "skill_xp",
	"object_state_add", "object_state_set", "object_state_toggle", "coins_add", "relationship_add", "fire_event", "notify", "consume_item", "chance"]
## game events emitted by the engine / other systems that goals may listen to
const ENGINE_EVENTS := ["promoted", "visit_started", "baby_born", "birthday", "daily_task_done", "relationship_bit_changed", "milestone_completed",
	"aspiration_completed", "branch_chosen", "hired", "fired", "retired", "job_offer", "food_spoiled"]

static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)

static func known_skills() -> Array:
	var out: Array = []
	for s in Folk.SKILLS:
		out.append(s)
	var rules: Variant = read_json("res://data/content_rules.json")
	if rules is Dictionary:
		for s2 in (rules as Dictionary).get("skills", {}):
			out.append(s2)
	return out

## Returns the list of duplicate object keys found in raw JSON text ("path.key").
static func duplicate_keys(text: String) -> Array:
	var dups: Array = []
	var stack: Array = []        # each: {"keys": Dictionary, "is_obj": bool}
	var path: Array = []
	var i := 0
	var n := text.length()
	var expect_key: Array = []   # parallel to stack: true while the next string at that level is a key
	while i < n:
		var ch := text[i]
		if ch == "\"":
			var j := i + 1
			var s := ""
			while j < n and text[j] != "\"":
				if text[j] == "\\":
					s += text[j + 1]
					j += 2
					continue
				s += text[j]
				j += 1
			i = j + 1
			if not stack.is_empty() and stack[-1]["is_obj"] and expect_key[-1]:
				if (stack[-1]["keys"] as Dictionary).has(s):
					dups.append("/".join(path) + "/" + s)
				stack[-1]["keys"][s] = true
				expect_key[-1] = false
				path.append(s)
				stack[-1]["pending"] = true
			continue
		if ch == "{":
			stack.append({"keys": {}, "is_obj": true, "pending": false})
			expect_key.append(true)
		elif ch == "[":
			stack.append({"keys": {}, "is_obj": false, "pending": false})
			expect_key.append(false)
		elif ch == "}" or ch == "]":
			stack.pop_back()
			expect_key.pop_back()
			if not stack.is_empty() and stack[-1]["is_obj"] and stack[-1]["pending"]:
				stack[-1]["pending"] = false
				if not path.is_empty():
					path.pop_back()
		elif ch == ",":
			if not stack.is_empty() and stack[-1]["is_obj"]:
				expect_key[-1] = true
				if stack[-1]["pending"]:
					stack[-1]["pending"] = false
					if not path.is_empty():
						path.pop_back()
		i += 1
	return dups

# ------------------------------------------------------------------ preparing a folk/object so an interaction's tests pass
static func satisfy(f: Folk, obj, conds: Array, other: Folk = null) -> void:
	# stat_above first, then stat_below (so "above -40" and "below 50" coexist)
	for c in conds:
		if c is Dictionary and (c as Dictionary).has("stat_above"):
			var v: Array = c["stat_above"]
			if f.needs.has(str(v[0])) and f.get_stat_value(str(v[0])) <= float(v[1]):
				(f.needs[str(v[0])] as Stat).set_value(float(v[1]) + 10.0)
	for c in conds:
		if not (c is Dictionary):
			continue
		for key in c:
			var v2: Variant = c[key]
			match str(key):
				"circadian":
					if str(v2) == "sleep_ok":
						(f.needs["energy"] as Stat).set_value(5.0)
				"stat_below":
					if f.needs.has(str(v2[0])) and f.get_stat_value(str(v2[0])) >= float(v2[1]):
						(f.needs[str(v2[0])] as Stat).set_value(float(v2[1]) - 15.0)
				"has_trait":
					if not f.traits.has(str(v2)):
						f.traits.append(str(v2))
				"lacks_trait":
					f.traits.erase(str(v2))
				"has_buff":
					f.add_buff(str(v2))
				"lacks_buff":
					f.remove_buff(str(v2))
				"skill_at_least":
					f.add_skill_xp(str(v2[0]), Folk.xp_for_level(int(v2[1])) + 1.0)
				"object_state_eq":
					if obj != null:
						WorldIface.state_set(obj, str(v2[0]), v2[1])
				"object_state_above":
					if obj != null:
						WorldIface.state_set(obj, str(v2[0]), float(v2[1]) + 2.0)
				"object_state_below":
					if obj != null:
						WorldIface.state_set(obj, str(v2[0]), maxf(float(v2[1]) - 1.0, 0.0))
				"time_between":
					Kit.set_time(2, int(float(v2[0])), 30)
				"coins_at_least":
					WorldIface.coins[int(f.household_id)] = int(v2) + 100
				"relationship_above":
					if other != null:
						f.add_rel(other.id, str(v2[0]), float(v2[1]) + 5.0)
						other.add_rel(f.id, str(v2[0]), float(v2[1]) + 5.0)
				"any":
					if not (v2 as Array).is_empty():
						satisfy(f, obj, [(v2 as Array)[0]], other)

## Make the social `requires` of a folk-to-folk interaction true (the engine refuses to run it otherwise).
static func satisfy_requires(f: Folk, other: Folk, req: Array) -> void:
	for r in req:
		match str(r):
			"bonded":
				RelationshipBits.set_flag(f.id, other.id, "dating", true, false)
			"not_bonded", "not_married":
				pass
			"knows_career":
				RelationshipKnowledge.reveal(f.id, other.id, "career")
			"knows_aspiration":
				RelationshipKnowledge.reveal(f.id, other.id, "aspiration")
			"knows_trait":
				if other.traits.is_empty():
					other.traits.append("friendly")
				RelationshipKnowledge.reveal(f.id, other.id, "trait")

## Run one interaction to its end (no director). Returns {"ok": bool, "why": String, "ir": Interaction}.
static func run_interaction(w: StubWorld, iid: String, obj_def: String, f: Folk, other: Folk = null) -> Dictionary:
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	var obj = null
	var target_id := -1
	var kind := str(d.get("target", "object"))
	if kind == "object":
		obj = w.add_object(obj_def, Vector2i(12, 10))
		target_id = obj.id
	elif kind == "folk":
		target_id = other.id
	satisfy(f, obj, d.get("tests", []), other)
	if other != null:
		satisfy(other, null, d.get("target_tests", []), f)
		satisfy_requires(f, other, (d.get("social", {}) as Dictionary).get("requires", []))
	var ir := Interaction.create(iid, f, target_id, true)
	if ir == null:
		return {"ok": false, "why": "create returned null", "ir": null}
	if not ir.can_run(f, obj if obj != null else null):
		return {"ok": false, "why": "can_run false after satisfying tests %s" % str(d.get("tests", [])), "ir": ir}
	if not ir.start():
		return {"ok": false, "why": "start() failed", "ir": ir}
	var guard := 0
	while ir.state != "finished" and ir.state != "cancelled" and guard < 2000:
		ir.tick(1.0)
		guard += 1
	if ir.state != "finished":
		return {"ok": false, "why": "did not finish (state %s, elapsed %.1f)" % [ir.state, ir.elapsed_min], "ir": ir}
	return {"ok": true, "why": "", "ir": ir, "obj": obj}

static func new_folk(w: StubWorld, fname: String, traits: Array = [], tile: Vector2i = Vector2i(12, 12)) -> Folk:
	var f := Folk.create(fname, traits)
	f.household_id = 1
	w.add_folk(f, tile)
	return f