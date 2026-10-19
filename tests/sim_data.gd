extends RefCounted
## Data-file integrity: schemas, cross references, and agreement with data/objects.json (world agent).

const Kit = preload("res://tests/sim_testkit.gd")
const COND_KEYS := ["circadian", "pair_flag_absent", "stat_below", "stat_above", "has_trait", "lacks_trait", "has_buff", "lacks_buff", "mood_is", "skill_at_least",
	"object_state_eq", "object_state_above", "object_state_below", "time_between", "coins_at_least", "relationship_above",
	"has_job", "posture_is", "posture_not", "not", "any"]
const LOOT_KEYS := ["add_buff", "remove_buff", "target_add_buff", "target_remove_buff", "stat_add", "target_stat_add", "skill_xp",
	"object_state_add", "object_state_set", "object_state_toggle", "coins_add", "relationship_add", "fire_event", "notify", "consume_item", "chance"]

func run() -> Array:
	var f: Array = []
	Kit.setup()
	var d = SimEnv.data()
	var needs: Dictionary = d.needs()
	var buffs: Dictionary = d.buffs()
	var traits: Dictionary = d.traits()
	var ints: Dictionary = d.interactions()
	var objs: Dictionary = d.objects()
	Kit.expect(f, needs.size() >= 6, "data: >= 6 needs (%d)" % needs.size())
	Kit.expect(f, buffs.size() >= 20, "data: >= 20 buffs (%d)" % buffs.size())
	Kit.expect(f, traits.size() >= 10, "data: >= 10 traits (%d)" % traits.size())
	Kit.expect(f, ints.size() >= 25, "data: >= 25 interactions (%d)" % ints.size())
	for n in ["hunger", "energy", "bladder", "hygiene", "social", "fun"]:
		Kit.expect(f, needs.has(n), "data: need %s defined" % n)
	for nid in needs:
		for t in needs[nid].get("thresholds", []):
			Kit.expect(f, buffs.has(t["buff"]), "data: need %s threshold buff '%s' undefined" % [nid, t["buff"]])
	for bid in buffs:
		for m in buffs[bid].get("mood", {}):
			Kit.expect(f, Mood.MOODS.has(m), "data: buff %s uses unknown mood %s" % [bid, m])
		for k in buffs[bid].get("need_decay_mult", {}):
			Kit.expect(f, needs.has(k), "data: buff %s decays unknown need %s" % [bid, k])
	for tid in traits:
		for k in traits[tid].get("need_decay_mult", {}):
			Kit.expect(f, needs.has(k), "data: trait %s decays unknown need %s" % [tid, k])
		for src in traits[tid].get("buffs_on", {}):
			Kit.expect(f, buffs.has(src) and buffs.has(traits[tid]["buffs_on"][src]), "data: trait %s buffs_on references unknown buff" % tid)
		Kit.expect(f, traits[tid].has("autonomy_mult") or traits[tid].has("refuses"), "data: trait %s has decision weights" % tid)
	var covered: Dictionary = {}
	for iid in ints:
		var it: Dictionary = ints[iid]
		for k in ["label", "duration_min", "tests", "on_finish"]:
			Kit.expect(f, it.has(k), "data: interaction %s missing '%s'" % [iid, k])
		for k in it.get("per_min", {}):
			Kit.expect(f, needs.has(k), "data: interaction %s per_min unknown need %s" % [iid, k])
			covered[k] = true
		for k in it.get("advertises", {}):
			covered[k] = true
		for c in it.get("tests", []) + it.get("target_tests", []) + it.get("end_when", []) + it.get("emergency", []):
			_check_cond(f, iid, c)
		for lst in ["on_finish", "on_cancel"]:
			for l in it.get(lst, []):
				for k in l:
					Kit.expect(f, LOOT_KEYS.has(k), "data: interaction %s %s uses unknown loot key %s" % [iid, lst, k])
					if k in ["add_buff", "remove_buff", "target_add_buff"]:
						Kit.expect(f, buffs.has(l[k]), "data: interaction %s references unknown buff %s" % [iid, l[k]])
		for o in it.get("objects", []):
			if not objs.is_empty():
				Kit.expect(f, objs.has(o), "data: interaction %s references object '%s' missing from objects.json" % [iid, o])
	for n in ["hunger", "energy", "bladder", "hygiene", "social", "fun"]:
		Kit.expect(f, covered.has(n), "data: some interaction serves need %s" % n)
	# Agreement with the world agent's object definitions.
	if objs.is_empty():
		print("  (objects.json not present; cross-check skipped)")
	for oid in objs:
		for iid in objs[oid].get("interactions", []):
			Kit.expect(f, ints.has(iid), "data: object %s lists interaction '%s' which data/interactions.json does not define" % [oid, iid])
	for oid in ["fridge", "stove", "table", "bed", "toilet", "shower", "sofa", "tv", "bookshelf", "easel", "treadmill", "computer", "bathtub", "sink", "counter", "plant", "lamp"]:
		if not objs.is_empty():
			Kit.expect(f, objs.has(oid), "data: contract object '%s' missing from objects.json" % oid)
	# Each autonomous object interaction is reachable from some object definition.
	var reachable: Dictionary = {}
	for iid in ints:
		var it2: Dictionary = ints[iid]
		if str(it2.get("target", "object")) != "object":
			reachable[iid] = true
	for iid in ints:
		if str(ints[iid].get("target", "object")) == "object" and not objs.is_empty():
			var ok := false
			for oid in ints[iid].get("objects", []):
				ok = ok or objs.has(oid)
			Kit.expect(f, ok, "data: interaction %s is unreachable (no matching object def)" % iid)
	Kit.teardown()
	return f

func _check_cond(f: Array, iid: String, c: Variant) -> void:
	if not (c is Dictionary):
		f.append("data: interaction %s has a non-dictionary condition" % iid)
		return
	for k in c:
		if not COND_KEYS.has(k):
			f.append("data: interaction %s uses unknown condition key %s" % [iid, k])
		elif k == "not":
			_check_cond(f, iid, c[k])
		elif k == "any":
			for sub in c[k]:
				_check_cond(f, iid, sub)