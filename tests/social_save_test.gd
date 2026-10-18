extends RefCounted
## Save / load of the social state: knowledge, trust, tension, romance flags, secrets, gossip, reputation, affairs, emotional memory,
## gatherings, plus the whole-game SaveLoad round trip keeps it.

const S = preload("res://tests/social_kit.gd")
const SLOT := 93

func run() -> Array:
	var f: Array = []
	_roundtrip(f)
	_through_saveload(f)
	_old_save(f)
	return f

func _populate(w: StubWorld) -> Array:
	var a := S.folk(w, "Ann", ["social", "romantic"])
	var b := S.folk(w, "Bo", ["foodie", "jealous"])
	var c := S.folk(w, "Cy", ["gossip"])
	RelationshipService.add_both(a.id, b.id, "friendship", 55.0)
	RelationshipService.add_both(a.id, b.id, "romance", 50.0)
	RelationshipService.add_both(a.id, c.id, "friendship", 40.0)
	RelationshipService.add_value(b.id, a.id, "trust", 33.0)
	RelationshipKnowledge.reveal(a.id, b.id, "trait")
	RelationshipKnowledge.reveal(a.id, b.id, "career")
	RelationshipKnowledge.reveal(a.id, b.id, "interest")
	RelationshipRomance.start_dating(a.id, b.id, false)
	RelationshipKnowledge.note_topic(a.id, b.id, "food")
	SocialConflict.escalate(a.id, c.id, 30.0)
	var sec: Dictionary = RelationshipKnowledge.secret_for_sharing(b.id, c.id)
	RelationshipKnowledge.learn_secret(c.id, b.id, int(sec["id"]))
	RelationshipKnowledge.add_gossip(a.id, c.id, "Cy was seen sneaking around", "observed", -1, b.id)
	RelationshipKnowledge.add_reputation(c.id, -12.0)
	RelationshipService.affairs.append({"cheater": a.id, "other": c.id, "victim": b.id, "day": 1})
	Emotions.imprint(a, "folk:%d" % b.id, 0.5, "first_kiss", "", "your first kiss")
	S.set_time(2, 10)
	Emotions.record_minute(a)
	SocialDynamics.last_social[a.id] = 123
	return [a, b, c]

func _roundtrip(f: Array) -> void:
	var w := S.setup(501)
	var p := _populate(w)
	var a: Folk = p[0]
	var b: Folk = p[1]
	var c: Folk = p[2]
	var d1: Dictionary = RelationshipService.to_dict()
	S.expect(f, d1.has("social") and (d1["social"] as Dictionary).has("secrets") and (d1["social"] as Dictionary).has("emotions"), "to_dict carries the social block")
	var parsed: Variant = JSON.parse_string(JSON.stringify(d1))
	RelationshipService.reset()
	S.expect(f, RelationshipKnowledge.knows_trait(a.id, b.id, "anything") == false and RelationshipKnowledge.reputation(c.id) == 0.0, "reset wipes the social state")
	RelationshipService.from_dict(parsed)
	var diffs: Array = []
	S.expect(f, S.K.deep_eq(d1, RelationshipService.to_dict(), "rel", diffs), "social roundtrip is lossless: %s" % str(diffs.slice(0, 6)))
	S.expect(f, RelationshipKnowledge.known_traits(a.id, b.id).size() == 1, "revealed traits survive (%s)" % str(RelationshipKnowledge.known_traits(a.id, b.id)))
	S.expect(f, RelationshipKnowledge.knows_career(a.id, b.id) and RelationshipBits.has_flag(a.id, b.id, "dating"), "career knowledge + dating flag survive")
	S.expect(f, RelationshipBits.bit_for(a.id, b.id) == "dating" and a.get_rel(b.id, "bond") == 1.0, "dating bit + bond track survive")
	S.expect(f, RelationshipRomance.trust(b.id, a.id) == 33.0, "trust survives")
	S.expect(f, RelationshipRomance.tension(c.id, a.id) > 10.0, "tension survives (%.0f)" % RelationshipRomance.tension(c.id, a.id))
	S.expect(f, RelationshipKnowledge.knows_secret(c.id, b.id, 0) or RelationshipKnowledge.knows_secret(c.id, b.id, 1), "secret knowledge survives")
	S.expect(f, RelationshipKnowledge.gossip_for(a.id).size() == 1 and int(RelationshipKnowledge.gossip_for(a.id)[0]["about"]) == c.id, "gossip items survive with int ids")
	S.expect(f, is_equal_approx(RelationshipKnowledge.reputation(c.id), -12.0), "reputation survives")
	S.expect(f, RelationshipService.affairs.size() == 1 and int(RelationshipService.affairs[0]["victim"]) == b.id, "pending affairs survive")
	S.expect(f, Emotions.moments_of(a.id).size() == 1 and Emotions.moments_of(a.id)[0]["key"] == "folk:%d" % b.id, "emotional memories survive")
	S.expect(f, RelationshipKnowledge.topic_count(a.id, b.id, "food") == 1.0, "topic counters survive")
	S.expect(f, RelationshipRomance.romance_stage(a.id, b.id) == "dating", "romance stage derives from restored state")
	S.expect(f, RelationshipRomance.exclusive_partners(a.id) == [b.id], "partners restored")
	S.teardown()

func _through_saveload(f: Array) -> void:
	var w := S.setup(511)
	var p := _populate(w)
	var a: Folk = p[0]
	var b: Folk = p[1]
	var c: Folk = p[2]
	# a gathering mid-way
	for i in 3:
		var g := S.folk(w, "G%d" % i)
		RelationshipService.add_both(a.id, g.id, "friendship", 30.0)
	S.set_time(1, 15)
	var gat := SocialGatherings.start_gathering(a.id)
	S.expect(f, not gat.is_empty(), "precondition: gathering running")
	var snap_before: Dictionary = SaveLoad.snapshot("social")
	S.expect(f, SaveLoad.save(SLOT, "Social state"), "save works: %s" % SaveLoad.last_error)
	var rep_before: float = RelationshipKnowledge.reputation(c.id)
	RelationshipService.reset()
	SystemsManager.reset_all()
	for fk in w.all_folk().duplicate():
		fk.current = null
		fk.queue.clear()
		SysUtil.world_remove_folk(fk.id)
	S.expect(f, SaveLoad.load(SLOT), "load works: %s" % SaveLoad.last_error)
	S.expect(f, RelationshipBits.has_flag(a.id, b.id, "dating"), "romance flag after SaveLoad")
	S.expect(f, is_equal_approx(RelationshipKnowledge.reputation(c.id), rep_before), "reputation after SaveLoad")
	S.expect(f, RelationshipKnowledge.knows_career(a.id, b.id), "knowledge after SaveLoad")
	S.expect(f, not SocialGatherings.active_gathering(a.id).is_empty(), "the running gathering is restored")
	S.expect(f, Emotions.moments_of(a.id).size() == 1, "emotional memory after SaveLoad")
	var a2 = w.get_folk(a.id)
	S.expect(f, a2 != null and a2.get_rel(b.id, "trust") == a.get_rel(b.id, "trust"), "trust track on the loaded folk")
	# the restored game continues: mood effect buffs and markers are consistent
	var hidden := 0
	for bf in a2.buffs:
		if SimEnv.data().buff_def(str(bf["id"])).get("hidden", false):
			hidden += 1
	S.expect(f, hidden >= 1, "hidden marker buffs are saved with the folk (%d)" % hidden)
	SaveLoad.delete_slot(SLOT)
	S.teardown()

func _old_save(f: Array) -> void:
	var w := S.setup(521)
	var a := S.folk(w, "Ann")
	var b := S.folk(w, "Bo")
	RelationshipService.add_both(a.id, b.id, "friendship", 20.0)
	var d: Dictionary = RelationshipService.to_dict()
	d.erase("social")
	for key in d["pairs"]:
		(d["pairs"][key] as Dictionary).erase("knows")
		(d["pairs"][key] as Dictionary).erase("topics")
	RelationshipService.from_dict(JSON.parse_string(JSON.stringify(d)))
	S.expect(f, RelationshipBits.bit_for(a.id, b.id) == "acquaintance" or RelationshipBits.bit_for(a.id, b.id) == "friend", "a save from before the social update still loads")
	S.expect(f, RelationshipKnowledge.known_traits(a.id, b.id).is_empty() and RelationshipKnowledge.gossip_for(a.id).is_empty(), "...with empty new state")
	S.teardown()
