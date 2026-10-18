extends RefCounted
## Death causes through Aging.kill: text, grief tiers / lengths, children mourn, memory, graves (stub world and the real big map),
## townie deaths, chronicle fields, save round trip of graves.

const K = preload("res://tests/systems_kit.gd")
const HK = preload("res://tests/hood_kit.gd")

var _thoughts: Array = []

func run() -> Array:
	var f: Array = []
	_causes(f)
	_grief(f)
	_townie(f)
	_grave_interactions(f)
	_save(f)
	_real_world(f)
	return f

func _near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func _remaining(folk, buff: String) -> float:
	for b in folk.buffs:
		if str(b["id"]) == buff:
			return float(b["remaining"])
	return -2.0

func _causes(f: Array) -> void:
	for cause in DeathCauses.ids():
		var w := K.setup()
		Incidents.reset()
		var a := K.make_folk(w, "Tobin Rowe", [], 1, Vector2i(12, 12), "adult")
		Aging.set_age_days(a, 80.0)
		var cdef: Dictionary = DeathCauses.def(cause)
		K.notes.clear()
		K.events.clear()
		var lg: Dictionary = Aging.kill(a.id, cause)
		K.expect(f, w.get_folk(a.id) == null, "%s: the deceased leaves the world" % cause)
		K.expect(f, K.has_note("Tobin Rowe"), "%s: toast names them" % cause)
		K.expect(f, str(K.last_event("died").get("cause", "")) == cause, "%s: died event carries the cause id" % cause)
		K.expect(f, str(lg["cause"]) == str(cdef["label"]) and str(lg["cause_id"]) == cause, "%s: legacy has label + id" % cause)
		if str(cdef.get("legacy_text", "")) != "":
			K.expect(f, str(lg["summary"]).find(str(cdef["legacy_text"])) >= 0, "%s: legacy sentence" % cause)
		var gr: Array = Graves.list()
		K.expect(f, gr.size() == 1 and gr[0]["name"] == "Tobin Rowe" and gr[0]["cause"] == cdef["label"] and int(gr[0]["died"]) == SysUtil.day(), "%s: grave record {name, born, died, cause}" % cause)
		var want_def: String = "urn" if str(cdef["grave_style"]) == "urn" else "grave"
		var found := false
		for o in w.objects.values():
			if o.def_id == want_def:
				found = true
		K.expect(f, found, "%s: a %s object stands in the world" % [cause, want_def])
		var cr: Array = K.events.filter(func(e): return e[0] == "chronicle" and e[1]["kind"] == "death")
		K.expect(f, cr.size() == 1 and cr[0][1]["subjects"] == [a.id] and cr[0][1]["public"] == true and int(cr[0][1]["severity"]) >= 1, "%s: one chronicle death entry with the shared fields" % cause)
		K.teardown()

func _grief(f: Array) -> void:
	var results: Dictionary = {}
	for cause in ["old_age", "heart_attack", "test_urn"]:
		var w := K.setup()
		Incidents.reset()
		var dead := K.make_folk(w, "Dad", [], 1, Vector2i(12, 12), "adult")
		var wife := K.make_folk(w, "Mum", [], 1, Vector2i(13, 12), "adult")
		var kid := K.make_folk(w, "Kid", [], 1, Vector2i(14, 12), "child")
		var baby := K.make_folk(w, "Baby", [], 1, Vector2i(15, 12), "baby")
		var pal := K.make_folk(w, "Pal", [], 2, Vector2i(16, 12), "adult")
		var stranger := K.make_folk(w, "Stranger", [], 3, Vector2i(17, 12), "adult")
		for o in [wife, kid, baby]:
			RelationshipBits.set_flag(dead.id, o.id, "family")
			RelationshipBits.set_flag(o.id, dead.id, "family")
		RelationshipService.add_both(pal.id, dead.id, "friendship", 52.0)
		_thoughts.clear()
		var cb := func(fid, text): _thoughts.append([fid, text])
		SimEnv.events().thought.connect(cb)
		Aging.kill(dead.id, cause)
		SimEnv.events().thought.disconnect(cb)
		var tier: String = DeathCauses.grief_buff(float(DeathCauses.def(cause)["grief"]["strength"]))
		K.expect(f, wife.has_buff(tier) and kid.has_buff(tier) and pal.has_buff(tier), "%s: family, child and friend grieve with %s" % [cause, tier])
		K.expect(f, not baby.has_buff(tier) and not stranger.has_buff(tier), "%s: babies and strangers do not" % cause)
		var days: float = float(DeathCauses.def(cause)["grief"]["days"])
		K.expect(f, _near(_remaining(wife, tier), days * 1440.0, 1.0), "%s: family grieves %.0f days (%.0f min)" % [cause, days, _remaining(wife, tier)])
		K.expect(f, _near(_remaining(pal, tier), days * 1440.0 * 0.6, 1.0), "%s: a friend grieves 60%% as long" % cause)
		var kid_thoughts: Array = _thoughts.filter(func(t): return t[0] == kid.id)
		K.expect(f, kid_thoughts.size() >= 1 and str(kid_thoughts[kid_thoughts.size() - 1][1]) == str(DeathCauses.def(cause)["child_text"]), "%s: child gets age-appropriate wording" % cause)
		K.expect(f, wife.memory.size() >= 1 and Emotions.moments_of(wife.id).size() >= 1, "%s: emotional memory imprinted on the mourner" % cause)
		K.expect(f, wife.get_stat_value("fun") < 60.0, "%s: grief costs fun" % cause)
		results[cause] = _remaining(wife, tier)
		K.teardown()
	K.expect(f, results["heart_attack"] > results["old_age"] and results["test_urn"] > results["heart_attack"], "violent / sudden deaths are mourned longer than old age: %s" % str(results))

func _townie(f: Array) -> void:
	var w := K.setup()
	Incidents.reset()
	var a := K.make_folk(w, "Ada", [], 1)
	Story.generate_townies()
	var ids: Array = Story.townies.keys()
	ids.sort()
	var friend: int = int(ids[0])
	var stranger: int = int(ids[1])
	RelationshipService.add_both(a.id, friend, "friendship", 60.0)
	K.notes.clear()
	K.events.clear()
	var lg: Dictionary = Aging.kill(stranger, "heart_attack")
	K.expect(f, not bool(Story.townies[stranger]["alive"]) and str(Story.townies[stranger]["cause"]) == "heart_attack", "Aging.kill kills a far townie")
	K.expect(f, K.notes.is_empty() and not a.has_buff("grieving_heavy"), "a stranger's death is chronicle-only (no toast, no grief)")
	K.expect(f, K.count_events("chronicle") == 1, "chronicle entry for the townie death")
	lg = Aging.kill(friend, "heart_attack")
	K.expect(f, bool(lg.get("townie", false)) and a.has_buff("grieving_heavy") and K.has_note("collapsed suddenly"), "a friend's death: grief + toast")
	var graves: Array = Graves.list().filter(func(g): return g["folk_id"] == friend)
	K.expect(f, graves.size() == 1 and bool(graves[0]["park"]), "townie grave is a park grave")
	K.expect(f, Aging.kill(friend, "old age").is_empty(), "cannot die twice")
	# old-age townie death through Story keeps working
	Story.townies[int(ids[2])]["age_days"] = 400.0
	Story.on_day(3)
	K.expect(f, not bool(Story.townies[int(ids[2])]["alive"]), "Story's natural townie death goes through Aging.kill")
	K.teardown()

func _grave_interactions(f: Array) -> void:
	var w := K.setup()
	Incidents.reset()
	var dead := K.make_folk(w, "Old Ben", [], 1, Vector2i(12, 12), "adult")
	var son := K.make_folk(w, "Sam", [], 1, Vector2i(14, 14), "adult")
	RelationshipBits.set_flag(dead.id, son.id, "family")
	RelationshipBits.set_flag(son.id, dead.id, "family")
	Aging.kill(dead.id, "heart_attack")
	var gobj = null
	for o in w.objects.values():
		if o.def_id == "grave":
			gobj = o
	K.expect(f, gobj != null, "grave object placed")
	if gobj == null:
		K.teardown()
		return
	K.expect(f, Graves.hover_text(gobj).find("Old Ben") >= 0 and Graves.hover_text(gobj).find("Heart attack") >= 0, "tooltip: name, dates, cause: %s" % Graves.hover_text(gobj).replace("\n", " / "))
	var dd: Dictionary = SimEnv.data().object_def("grave")
	K.expect(f, not bool(dd.get("blocks", true)) and (dd["interactions"] as Array).has("remember_grave") and (dd["interactions"] as Array).has("mourn_grave"), "grave never blocks and offers Remember / Mourn")
	var ir = Interaction.create("mourn_grave", son, gobj.id, true)
	K.expect(f, ir != null and ir.can_run(son), "Mourn can be started on the grave")
	Graves.on_game_event("grave_remembered", {"folk_id": son.id, "object_id": gobj.id})
	K.expect(f, int(Graves.record_for_object(gobj.id)["visits"]) == 1, "visits counted")
	var mem_before: int = Emotions.moments_of(son.id).size()
	Graves.on_game_event("grave_mourned", {"folk_id": son.id, "object_id": gobj.id})
	K.expect(f, son.has_buff("at_peace") and not son.has_buff("grieving_heavy"), "Mourn: grief eases into peace")
	K.expect(f, Emotions.moments_of(son.id).size() > mem_before, "Mourn leaves a small memory")
	K.teardown()

func _save(f: Array) -> void:
	var w := K.setup()
	Incidents.reset()
	var a := K.make_folk(w, "Ada Rowe", [], 1)
	K.make_folk(w, "Bo", [], 1, Vector2i(5, 5))
	Aging.kill(a.id, "test_urn")
	var before: Dictionary = Graves.to_dict()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(before))
	Graves.reset()
	Graves.from_dict(parsed)
	var diffs: Array = []
	K.expect(f, K.deep_eq(before, Graves.to_dict(), "graves", diffs), "grave records survive JSON: %s" % str(diffs))
	K.expect(f, SaveLoad.save(95, "death save"), "save with a grave")
	Graves.reset()
	K.expect(f, SaveLoad.load_slot(95) and Graves.list().size() == 1 and Graves.list()[0]["name"] == "Ada Rowe" and Graves.list()[0]["style"] == "urn", "grave persists through save + load")
	SaveLoad.delete_slot(95)
	K.teardown()

func _real_world(f: Array) -> void:
	var folk: Array = HK.new_game()
	var W: Node = HK.world()
	if not ("regions" in W) or not W.regions.has_regions():
		f.append("real big map has regions")
		HK.teardown()
		return
	var who = folk[1]
	var tile: Vector2i = who.tile
	Aging.kill(who.id, "heart_attack")
	var graves: Array = W.objects_of_def("grave")
	K.expect(f, graves.size() == 1, "a grave stands on the big map (%d)" % graves.size())
	if not graves.is_empty():
		var g = graves[0]
		K.expect(f, W.regions.region_at(g.tile) == W.regions.home_id, "the grave is on the home lot")
		K.expect(f, W.is_outdoor(g.tile) and W.is_walkable(g.tile), "in the yard, walkable (never blocks): tile %s" % str(g.tile))
		K.expect(f, W.is_walkable(g.tile + Vector2i(0, 1)), "the tile in front is free for visitors")
		K.expect(f, W.has_path(folk[0].tile, folk[2].tile), "household paths still work")
	# a townie's grave goes to the park
	var tid: int = int(Story.alive_townies()[0]["id"])
	Aging.kill(tid, "heart_attack")
	var park_graves: Array = Graves.list().filter(func(r): return bool(r["park"]) and int(r["object_id"]) >= 0)
	K.expect(f, park_graves.size() == 1, "townie grave placed at the park")
	if not park_graves.is_empty():
		var go = W.get_object(int(park_graves[0]["object_id"]))
		K.expect(f, go != null and W.regions.kind_at(go.tile) == "park", "and it really is inside the park region")
	HK.teardown()
	var _unused: Vector2i = tile
