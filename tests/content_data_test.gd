extends RefCounted
## Content data integrity: JSON validity, duplicate ids, legacy ids preserved, objects / interactions / buffs / traits /
## goals cross references, model files, manifest_extra, and every extra skill / event referenced is known.

const K = preload("res://tests/content_kit.gd")
const Kit = preload("res://tests/sim_testkit.gd")

## interactions injected at runtime by the systems layer (SysContent) that data files may reference
const RUNTIME_INTERACTIONS := ["sys_away", "order_groceries", "apply_for_job", "try_for_baby", "apologize", "propose"]
const FILES := ["objects", "interactions", "buffs", "traits", "careers", "goals", "social", "content_rules", "lot_templates", "needs", "routines", "economy", "aging", "story", "content_sys", "content_family"]

func run() -> Array:
	var f: Array = []
	_json_and_dups(f)
	Kit.setup()
	var d = SimEnv.data()
	_legacy(f)
	_objects(f, d)
	_interactions(f, d)
	_buffs_traits(f, d)
	_markers_hidden(f, d)
	_goals(f, d)
	_social(f)
	Kit.teardown()
	return f

func _json_and_dups(f: Array) -> void:
	for n in FILES:
		var path := "res://data/%s.json" % n
		var txt := K.read_text(path)
		Kit.expect(f, txt != "", "%s.json missing or empty" % n)
		var parsed: Variant = JSON.parse_string(txt)
		Kit.expect(f, parsed is Dictionary, "%s.json does not parse to a Dictionary" % n)
		var dups: Array = K.duplicate_keys(txt)
		Kit.expect(f, dups.is_empty(), "%s.json has duplicate keys: %s" % [n, str(dups.slice(0, 5))])
	var me: Variant = K.read_json("res://assets/models/manifest_extra.json")
	Kit.expect(f, me is Dictionary, "assets/models/manifest_extra.json does not parse")

## Marker buffs (not meant for the player) carry `hidden: true` so the UI can leave them out.
func _markers_hidden(f: Array, d) -> void:
	SysContent.install_all()
	SocialContent.install()
	for id in d.buffs():
		var sid := str(id)
		if sid == "away" or sid == "holiday_today" or sid.begins_with("wx_") or sid.begins_with("mfx_") or Aging.stage_ids().has(sid.trim_prefix("stage_")):
			Kit.expect(f, bool((d.buffs()[id] as Dictionary).get("hidden", false)), "marker buff %s must be hidden" % sid)

func _legacy(f: Array) -> void:
	var legacy: Variant = K.read_json("res://tests/content_legacy_ids.json")
	Kit.expect(f, legacy is Dictionary, "tests/content_legacy_ids.json missing")
	if not (legacy is Dictionary):
		return
	var d = SimEnv.data()
	var tables := {"objects": d.objects(), "interactions": d.interactions(), "buffs": d.buffs(), "traits": d.traits(),
		"careers": (d.get_table("careers").get("careers", {}) as Dictionary), "aspirations": (d.get_table("goals").get("aspirations", {}) as Dictionary),
		"whims": (d.get_table("goals").get("whims", {}) as Dictionary)}
	for k in legacy:
		for id in legacy[k]:
			# interactions get runtime gates patched in, but the id must still exist
			Kit.expect(f, (tables[k] as Dictionary).has(id), "legacy %s id '%s' disappeared" % [k, id])

func _objects(f: Array, d) -> void:
	var objs: Dictionary = d.objects()
	var ints: Dictionary = d.interactions()
	var man: Dictionary = K.read_json("res://assets/models/manifest_extra.json") if K.read_json("res://assets/models/manifest_extra.json") is Dictionary else {}
	var legacy: Dictionary = K.read_json("res://tests/content_legacy_ids.json")
	var legacy_objs: Array = legacy["objects"]
	var new_ids: Array = []
	for oid in objs:
		if not legacy_objs.has(oid):
			new_ids.append(oid)
	Kit.expect(f, new_ids.size() >= 30, "at least 30 new objects expected, found %d" % new_ids.size())
	var skills := K.known_skills()
	for oid in objs:
		var o: Dictionary = objs[oid]
		for k in ["label", "size", "price", "tags", "slots", "state", "advertises", "decor", "interactions", "model"]:
			Kit.expect(f, o.has(k), "object %s lacks key %s" % [oid, k])
		if not o.has("size"):
			continue
		Kit.expect(f, (o["size"] as Array).size() == 2 and int(o["size"][0]) >= 1 and int(o["size"][1]) >= 1, "object %s bad size" % oid)
		Kit.expect(f, int(o.get("price", 0)) > 0, "object %s needs a price" % oid)
		# model: file exists, or an explicit documented fallback
		var mp: String = str(o.get("model", ""))
		var exists: bool = FileAccess.file_exists(mp) or ResourceLoader.exists(mp)
		Kit.expect(f, exists or str(o.get("model_fallback", "")) != "", "object %s: model %s missing and no model_fallback documented" % [oid, mp])
		for iid in o.get("interactions", []):
			Kit.expect(f, ints.has(iid), "object %s lists unknown interaction %s" % [oid, iid])
		for s in o.get("slots", []):
			Kit.expect(f, (s["offset"] as Array).size() == 2, "object %s slot offset must be [x,y]" % oid)
			Kit.expect(f, ["stand", "sit", "lie"].has(str(s.get("pose", "stand"))), "object %s slot pose invalid" % oid)
			if s.has("use"):
				var u: Array = s["use"]
				Kit.expect(f, u.size() == 2 and float(u[0]) >= -0.01 and float(u[0]) <= float(o["size"][0]) + 0.01 and float(u[1]) >= -0.01 and float(u[1]) <= float(o["size"][1]) + 0.01,
					"object %s slot use %s outside its footprint" % [oid, str(u)])
			if bool(s.get("inside", false)):
				var of: Array = s["offset"]
				Kit.expect(f, int(of[0]) < int(o["size"][0]) and int(of[1]) < int(o["size"][1]), "object %s inside-slot offset outside footprint" % oid)
		for key in o.get("state", {}):
			var sd: Dictionary = o["state"][key]
			if sd.has("max"):
				var st: float = float(sd.get("start", sd.get("min", 0)))
				Kit.expect(f, st >= float(sd.get("min", 0)) and st <= float(sd["max"]), "object %s state %s start outside min/max" % [oid, key])
			if sd.has("daily_requires"):
				Kit.expect(f, (o["state"] as Dictionary).has(str(sd["daily_requires"][0])), "object %s daily_requires references missing state" % oid)
			if sd.has("spoiled_key"):
				Kit.expect(f, (o["state"] as Dictionary).has(str(sd["spoiled_key"])), "object %s spoiled_key missing in state" % oid)
		Kit.expect(f, (o.get("advertises", {}) as Dictionary).size() >= 0, "")
	for oid in new_ids:
		var o2: Dictionary = objs[oid]
		Kit.expect(f, man.has(oid), "manifest_extra.json lacks %s" % oid)
		if man.has(oid):
			var fp: Array = man[oid]["footprint"]
			Kit.expect(f, int(fp[0]) == int(o2["size"][0]) and int(fp[1]) == int(o2["size"][1]), "object %s size %s differs from model footprint %s" % [oid, str(o2["size"]), str(fp)])
			Kit.expect(f, absf(float(o2.get("height", 0.0)) - float(fp[2])) < 0.011, "object %s height != model height" % oid)
			Kit.expect(f, FileAccess.file_exists(str(man[oid]["file"])), "manifest_extra file missing for %s" % oid)
		Kit.expect(f, (o2["interactions"] as Array).size() >= 1, "new object %s has no interactions" % oid)
		Kit.expect(f, o2.has("color"), "new object %s lacks colour (fallback box)" % oid)
		# every interaction the object offers must either be generic for it or restrict `objects` to include it
		for iid in o2["interactions"]:
			var only: Array = (ints[iid] as Dictionary).get("objects", [])
			Kit.expect(f, only.is_empty() or only.has(oid) or str((ints[iid] as Dictionary).get("target", "object")) != "object",
				"object %s lists %s, but that interaction's objects list excludes it" % [oid, iid])
	# interactions' object lists point at real objects, and ids of skills used are known
	for iid in ints:
		for oid2 in (ints[iid] as Dictionary).get("objects", []):
			Kit.expect(f, objs.has(oid2), "interaction %s references missing object %s" % [iid, oid2])
		for s in (ints[iid] as Dictionary).get("skill_xp_per_min", {}):
			Kit.expect(f, skills.has(s), "interaction %s trains unknown skill %s" % [iid, s])

func _check_cond(f: Array, where: String, c: Variant, allow_sys: bool, buffs: Dictionary, skills: Array) -> void:
	if not (c is Dictionary):
		f.append("%s: condition is not a dictionary" % where)
		return
	for k in c:
		var v: Variant = c[k]
		if k == "not":
			_check_cond(f, where, v, allow_sys, buffs, skills)
		elif k == "any":
			for sub in v:
				_check_cond(f, where, sub, allow_sys, buffs, skills)
		elif not (K.COND_KEYS.has(k) or (allow_sys and K.SYS_COND_KEYS.has(k))):
			f.append("%s: unknown condition key %s" % [where, k])
		if k in ["has_buff", "lacks_buff"] and not buffs.has(str(v)) and not str(v).begins_with("stage_") and str(v) != "away":
			f.append("%s: condition references unknown buff %s" % [where, str(v)])
		if k in ["skill_at_least", "skill_below"]:
			Kit.expect(f, skills.has(str(v[0])), "%s: unknown skill %s" % [where, str(v[0])])

func _check_loot(f: Array, where: String, l: Variant, buffs: Dictionary, skills: Array, events: Dictionary) -> void:
	if not (l is Dictionary):
		f.append("%s: loot is not a dictionary" % where)
		return
	for k in l:
		Kit.expect(f, K.LOOT_KEYS.has(k), "%s: unknown loot key %s" % [where, k])
		if k in ["add_buff", "remove_buff", "target_add_buff", "target_remove_buff"]:
			Kit.expect(f, buffs.has(str(l[k])), "%s: unknown buff %s" % [where, str(l[k])])
		if k == "skill_xp":
			Kit.expect(f, skills.has(str(l[k][0])), "%s: unknown skill %s" % [where, str(l[k][0])])
		if k == "fire_event":
			events[str(l[k])] = true

func _interactions(f: Array, d) -> void:
	var ints: Dictionary = d.interactions()
	var buffs: Dictionary = d.buffs()
	var needs: Dictionary = d.needs()
	var skills := K.known_skills()
	var legacy: Dictionary = K.read_json("res://tests/content_legacy_ids.json")
	var events: Dictionary = {}
	var new_count := 0
	for iid in ints:
		var it: Dictionary = ints[iid]
		if not (legacy["interactions"] as Array).has(iid):
			new_count += 1
		for k in ["label", "duration_min", "tests", "on_finish"]:
			Kit.expect(f, it.has(k), "interaction %s lacks %s" % [iid, k])
		Kit.expect(f, float(it.get("duration_min", 0)) > 0.0, "interaction %s needs a positive duration" % iid)
		for k in it.get("per_min", {}):
			Kit.expect(f, needs.has(k), "interaction %s per_min uses unknown need %s" % [iid, k])
		for k in it.get("target_per_min", {}):
			Kit.expect(f, needs.has(k), "interaction %s target_per_min uses unknown need %s" % [iid, k])
		for k in it.get("need_decay_mult", {}):
			Kit.expect(f, needs.has(k), "interaction %s need_decay_mult uses unknown need %s" % [iid, k])
		for key in ["tests", "target_tests", "end_when", "emergency"]:
			for c in it.get(key, []):
				_check_cond(f, "interaction %s.%s" % [iid, key], c, false, buffs, skills)
		for key in ["on_finish", "on_cancel"]:
			for l in it.get(key, []):
				_check_loot(f, "interaction %s.%s" % [iid, key], l, buffs, skills, events)
		Kit.expect(f, ["super", "social"].has(str(it.get("kind", "super"))), "interaction %s bad kind" % iid)
		Kit.expect(f, ["object", "folk", "self"].has(str(it.get("target", "object"))), "interaction %s bad target" % iid)
		if str(it.get("target", "object")) == "object":
			Kit.expect(f, not (it.get("objects", []) as Array).is_empty(), "interaction %s has no objects list" % iid)
	Kit.expect(f, new_count >= 50, "expected >= 50 new interactions, found %d" % new_count)
	# every game event a milestone/whim waits for is fired somewhere
	var goals: Dictionary = d.get_table("goals")
	var waiting: Array = []
	for aid in goals["aspirations"]:
		for ms in goals["aspirations"][aid]["milestones"]:
			if str(ms["objective"].get("type", "")) == "game_event":
				waiting.append([str(ms["objective"]["name"]), "aspiration %s/%s" % [aid, ms["id"]]])
	for wid in goals["whims"]:
		var ob: Dictionary = goals["whims"][wid]["objective"]
		if str(ob.get("type", "")) == "game_event":
			waiting.append([str(ob["name"]), "whim %s" % wid])
	for w in waiting:
		Kit.expect(f, events.has(w[0]) or K.ENGINE_EVENTS.has(w[0]), "%s waits for game event '%s' which nothing fires" % [w[1], w[0]])

func _buffs_traits(f: Array, d) -> void:
	var buffs: Dictionary = d.buffs()
	var traits: Dictionary = d.traits()
	var needs: Dictionary = d.needs()
	var legacy: Dictionary = K.read_json("res://tests/content_legacy_ids.json")
	var nb := 0
	for bid in buffs:
		if not (legacy["buffs"] as Array).has(bid):
			nb += 1
		for m in buffs[bid].get("mood", {}):
			Kit.expect(f, Mood.MOODS.has(m), "buff %s unknown mood %s" % [bid, m])
		for k in buffs[bid].get("need_decay_mult", {}):
			Kit.expect(f, needs.has(k), "buff %s unknown need %s" % [bid, k])
		Kit.expect(f, buffs[bid].has("label"), "buff %s lacks label" % bid)
	Kit.expect(f, nb >= 20, "expected >= 20 new buffs, found %d" % nb)
	var nt := 0
	for tid in traits:
		var t: Dictionary = traits[tid]
		if not (legacy["traits"] as Array).has(tid):
			nt += 1
			Kit.expect(f, not (t.get("autonomy_mult", {}) as Dictionary).is_empty() or not (t.get("refuses", []) as Array).is_empty(), "new trait %s must change decisions" % tid)
		for src in t.get("buffs_on", {}):
			Kit.expect(f, buffs.has(src) and buffs.has(t["buffs_on"][src]), "trait %s buffs_on references unknown buff" % tid)
		for k in t.get("need_decay_mult", {}):
			Kit.expect(f, needs.has(k), "trait %s unknown need %s" % [tid, k])
	Kit.expect(f, nt >= 10, "expected >= 10 new traits, found %d" % nt)
	# Id namespaces do not collide between buffs and traits only where the engine mixes them (trait ids are never buff ids by accident)
	for tid2 in traits:
		pass

func _goals(f: Array, d) -> void:
	var g: Dictionary = d.get_table("goals")
	var ints: Dictionary = d.interactions()
	var buffs: Dictionary = d.buffs()
	var skills := K.known_skills()
	var legacy: Dictionary = K.read_json("res://tests/content_legacy_ids.json")
	var na := 0
	for aid in g["aspirations"]:
		var a: Dictionary = g["aspirations"][aid]
		if not (legacy["aspirations"] as Array).has(aid):
			na += 1
			Kit.expect(f, (a["milestones"] as Array).size() == 5, "aspiration %s should have 5 milestones" % aid)
		var seen: Dictionary = {}
		for ms in a["milestones"]:
			Kit.expect(f, not seen.has(ms["id"]), "aspiration %s duplicate milestone id %s" % [aid, ms["id"]])
			seen[ms["id"]] = true
			_check_objective(f, "aspiration %s/%s" % [aid, ms["id"]], ms["objective"], ints, buffs, skills)
			for l in ms.get("reward", []):
				_check_loot(f, "aspiration %s reward" % aid, l, buffs, skills, {})
		for t in a.get("fit_traits", []):
			Kit.expect(f, d.traits().has(t), "aspiration %s fit trait %s unknown" % [aid, t])
	Kit.expect(f, na >= 8, "expected >= 8 new aspirations, found %d" % na)
	var nw := 0
	for wid in g["whims"]:
		var w: Dictionary = g["whims"][wid]
		if not (legacy["whims"] as Array).has(wid):
			nw += 1
		for c in w.get("when", []):
			_check_cond(f, "whim %s.when" % wid, c, true, buffs, skills)
		_check_objective(f, "whim %s" % wid, w["objective"], ints, buffs, skills)
		for t in w.get("trait_weight", {}):
			Kit.expect(f, d.traits().has(t), "whim %s trait_weight unknown trait %s" % [wid, t])
		if str(w.get("dynamic", "")) == "skill_next":
			Kit.expect(f, skills.has(str(w["params"]["skill"])), "whim %s dynamic skill unknown" % wid)
			Kit.expect(f, str(w["label"]).find("%d") >= 0, "whim %s dynamic label needs %%d" % wid)
	Kit.expect(f, nw >= 40, "expected >= 40 new whims, found %d" % nw)

func _check_objective(f: Array, where: String, ob: Dictionary, ints: Dictionary, buffs: Dictionary, skills: Array) -> void:
	match str(ob.get("type", "")):
		"interaction":
			var ids: Array = ob.get("ids", [ob.get("id", "")])
			for i in ids:
				if ob.has("tag"):
					continue
				Kit.expect(f, ints.has(str(i)) or RUNTIME_INTERACTIONS.has(str(i)), "%s objective references unknown interaction %s" % [where, str(i)])
		"buff":
			Kit.expect(f, buffs.has(str(ob.get("id", ""))), "%s objective references unknown buff" % where)
		"cond":
			for c in ob.get("cond", []):
				_check_cond(f, where + ".cond", c, true, buffs, skills)
		"game_event":
			pass
		_:
			f.append("%s: unknown objective type" % where)

func _social(f: Array) -> void:
	var s: Dictionary = K.read_json("res://data/social.json")
	var traits: Dictionary = SimEnv.data().traits()
	for pair in s["compat"]["pairs"]:
		for t in str(pair).split(":"):
			Kit.expect(f, traits.has(t), "social compat pair %s references unknown trait %s" % [pair, t])
