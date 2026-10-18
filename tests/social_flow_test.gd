extends RefCounted
## Social interactions end to end: every new interaction runs, categories, success tiers, topics, getting to know, trust.

const S = preload("res://tests/social_kit.gd")
const LEGACY := ["chat", "tell_joke", "compliment", "flirt", "insult", "serenade", "gift_produce", "tutor"]

func run() -> Array:
	var f: Array = []
	_catalog(f)
	_every_interaction_runs(f)
	_tiers_follow_compatibility(f)
	_topics(f)
	_knowledge(f)
	_trust(f)
	_requires_enforced(f)
	return f

## social.requires is part of can_run, so queued and autonomous paths cannot bypass it.
func _requires_enforced(f: Array) -> void:
	var w := S.setup(31)
	var a := S.folk(w, "Rae", ["friendly"], Vector2i(12, 12))
	var b := S.folk(w, "Sol", ["lazy"], Vector2i(13, 12))
	var ir := Interaction.create("talk_shop", a, b.id)
	S.expect(f, not ir.can_run(a), "talk_shop is refused until you know their job")
	var cand := {"id": "talk_shop", "target_id": b.id, "kind": "folk", "obj": null, "folk": b}
	S.expect(f, Autonomy.evaluate(a, cand)["skipped"], "autonomy skips it too")
	RelationshipKnowledge.reveal(a.id, b.id, "career")
	S.expect(f, ir.can_run(a), "talk_shop runs once the job is known")
	S.teardown()

func _social_ids() -> Array:
	var out: Array = []
	var defs: Dictionary = SimEnv.data().interactions()
	for iid in defs:
		if (defs[iid] as Dictionary).has("social"):
			out.append(str(iid))
	return out

func _catalog(f: Array) -> void:
	S.setup()
	var defs: Dictionary = SimEnv.data().interactions()
	var cats: Dictionary = {}
	var fresh := 0
	for iid in _social_ids():
		var d: Dictionary = defs[iid]
		var c: String = str(d.get("category", ""))
		cats[c] = int(cats.get(c, 0)) + 1
		if not LEGACY.has(iid):
			fresh += 1
		S.expect(f, ["friendly", "funny", "romantic", "mean", "deep", "group"].has(c), "%s has a known category (%s)" % [iid, c])
		var oc: Dictionary = (d["social"] as Dictionary).get("outcomes", {})
		S.expect(f, oc.has("good") or oc.has("great"), "%s defines positive outcomes" % iid)
		S.expect(f, oc.has("bad") or oc.has("meh"), "%s defines a failure outcome" % iid)
	S.expect(f, fresh >= 40, "at least 40 new social interactions (%d)" % fresh)
	for c2 in ["friendly", "funny", "romantic", "mean", "deep", "group"]:
		S.expect(f, int(cats.get(c2, 0)) >= 5, "category %s has >= 5 interactions (%d)" % [c2, int(cats.get(c2, 0))])
	S.expect(f, defs.has("host_gathering") and defs.has("karaoke"), "gathering + karaoke exist")
	S.expect(f, (SimEnv.data().objects()["stereo"]["interactions"] as Array).has("karaoke"), "stereo offers karaoke (runtime injection)")
	S.teardown()

func _every_interaction_runs(f: Array) -> void:
	var w := S.setup(11)
	var ran := 0
	for iid in _social_ids():
		var a := S.folk(w, "A_" + iid, [], Vector2i(12, 12))
		var b := S.folk(w, "B_" + iid, [], Vector2i(12, 12))
		RelationshipService.add_both(a.id, b.id, "friendship", 60.0)
		RelationshipService.add_both(a.id, b.id, "romance", 50.0)
		RelationshipService.add_both(a.id, b.id, "trust", 40.0)
		if iid in ["go_on_date", "make_official", "break_up"]:
			RelationshipBits.set_flag(a.id, b.id, "dating", true, false)
		if iid == "rekindle":
			RelationshipBits.set_flag(a.id, b.id, "ex", true, false)
		if iid in ["toast", "tell_group_story", "group_hug", "party_game", "group_chat"]:
			var c := S.folk(w, "C_" + iid, [], Vector2i(12, 12))
			Conversation.join(c.id, b.id)
			Conversation.join(a.id, b.id)
		var ir := S.run_ok(a, b, iid)
		S.expect(f, ir != null and ir.state == "finished", "%s runs to completion (%s)" % [iid, "" if ir == null else ir.state])
		if not LEGACY.has(iid) and ir != null and ir.state == "finished":
			S.expect(f, S.tier_of(a) != "", "%s resolved an outcome tier" % iid)
		ran += 1
		for x in [a, b]:
			x.current = null
			x.queue.clear()
	S.expect(f, ran >= 40, "ran %d social interactions" % ran)
	S.teardown()

func _tiers_follow_compatibility(f: Array) -> void:
	var w := S.setup(21)
	var good := {"great": 0, "good": 0, "meh": 0, "bad": 0}
	var bad := {"great": 0, "good": 0, "meh": 0, "bad": 0}
	for i in 80:
		var a := S.folk(w, "Ga%d" % i, ["social", "musical"])
		var b := S.folk(w, "Gb%d" % i, ["social", "musical"])
		S.run(a, b, "funny_story")
		good[S.tier_of(a)] += 1
		var c := S.folk(w, "Ba%d" % i, ["neat", "hot_headed"])
		var d := S.folk(w, "Bb%d" % i, ["lazy", "loner"])
		S.run(c, d, "funny_story")
		bad[S.tier_of(c)] += 1
	var gscore: float = float(good["great"]) * 3 + float(good["good"]) * 2 + float(good["meh"])
	var bscore: float = float(bad["great"]) * 3 + float(bad["good"]) * 2 + float(bad["meh"])
	S.expect(f, gscore > bscore, "compatible pairs land funny stories better (%s vs %s)" % [str(good), str(bad)])
	S.expect(f, int(bad["bad"]) > int(good["bad"]), "incompatible pairs flop more often (%d vs %d)" % [int(bad["bad"]), int(good["bad"])])
	S.expect(f, int(good["great"]) + int(good["good"]) > 0 and int(bad["bad"]) > 0, "outcomes are spread over several tiers")
	# charisma matters too
	var tot_lo := 0.0
	var tot_hi := 0.0
	var dd: Dictionary = SimEnv.data().interaction_def("funny_story")
	for j in 30:
		var a2 := S.folk(w, "Lo%d" % j)
		var b2 := S.folk(w, "Lb%d" % j)
		var a3 := S.folk(w, "Hi%d" % j)
		a3.add_skill_xp("charisma", Folk.xp_for_level(8) + 1.0)
		var b3 := S.folk(w, "Hb%d" % j)
		tot_lo += float(SocialScoring.success_score(a2, b2, "funny_story", dd, dd["social"], {}, false)["score"])
		tot_hi += float(SocialScoring.success_score(a3, b3, "funny_story", dd, dd["social"], {}, false)["score"])
	S.expect(f, tot_hi > tot_lo + 5.0, "charisma raises the success score")
	S.teardown()

func _topics(f: Array) -> void:
	var w := S.setup(31)
	var a := S.folk(w, "Fan", ["foodie"])
	var b := S.folk(w, "Chef", ["foodie", "glutton"])
	var c := S.folk(w, "Gamer", ["gamer"])
	S.expect(f, Conversation.interests_of(a.id).has("food"), "foodie is interested in food")
	S.expect(f, Conversation.shared_interests(a.id, b.id).has("food"), "shared interest found")
	S.expect(f, Conversation.shared_interests(a.id, c.id).is_empty(), "no shared interest with the gamer")
	RelationshipService.add_both(a.id, b.id, "friendship", 5.0)
	RelationshipService.add_both(a.id, c.id, "friendship", 5.0)
	var e_shared: Dictionary = Conversation.topic_effect(a.id, b.id, "food")
	var e_none: Dictionary = Conversation.topic_effect(a.id, c.id, "food")
	S.expect(f, float(e_shared["bonus"]) > float(e_none["bonus"]) and bool(e_shared["shared"]), "shared interest raises the success bonus")
	var m0: float = float(e_shared["mult"])
	for i in 4:
		RelationshipKnowledge.note_topic(a.id, b.id, "food")
	var e4: Dictionary = Conversation.topic_effect(a.id, b.id, "food")
	S.expect(f, float(e4["mult"]) < m0 * 0.6, "repeating a topic gives decreasing returns (%.2f -> %.2f)" % [m0, float(e4["mult"])])
	S.expect(f, float(e4["bonus"]) < float(e_shared["bonus"]), "repeat also lowers the success bonus")
	RelationshipKnowledge.pair_reset_topics_for_test(a.id, b.id)
	var food := 0
	for i in 80:
		if Conversation.pick_topic(a.id, b.id) == "food":
			food += 1
	S.expect(f, food > 15, "a fresh shared topic is picked often (%d/80)" % food)
	for i in 8:
		RelationshipKnowledge.note_topic(a.id, b.id, "food")
	var food2 := 0
	for i in 80:
		if Conversation.pick_topic(a.id, b.id) == "food":
			food2 += 1
	S.expect(f, food2 < food, "an exhausted topic is picked less (%d < %d)" % [food2, food])
	var ir := S.run(a, b, "talk_interests")
	S.expect(f, ir.state == "finished", "talk_interests finishes")
	RelationshipKnowledge.note_topic(a.id, b.id, "books")
	var before: float = RelationshipKnowledge.topic_count(a.id, b.id, "books")
	S.set_time(5, 8)
	SocialDynamics.on_day(5)
	S.expect(f, RelationshipKnowledge.topic_count(a.id, b.id, "books") < before, "topics recover over days")
	S.teardown()

func _knowledge(f: Array) -> void:
	var w := S.setup(41)
	var a := S.folk(w, "Ann", ["social"])
	var b := S.folk(w, "Bo", ["foodie", "neat", "romantic"])
	S.expect(f, RelationshipKnowledge.known_traits(a.id, b.id).is_empty(), "strangers know nothing about each other")
	var sm: Dictionary = RelationshipKnowledge.known_summary(a.id, b.id)
	var qs := 0
	for t in sm["traits"]:
		if t["label"] == "?":
			qs += 1
	S.expect(f, qs == 3 and sm["career"] == "?" and sm["aspiration"] == "?", "unknown things show as '?' (%d)" % qs)
	var got: String = RelationshipKnowledge.reveal(a.id, b.id, "trait")
	S.expect(f, got.begins_with("trait:") and RelationshipKnowledge.known_traits(a.id, b.id).size() == 1, "revealing a trait discovers one")
	S.expect(f, RelationshipKnowledge.knows_trait(a.id, b.id, got.substr(6)), "knows_trait agrees")
	S.expect(f, RelationshipKnowledge.reveal(a.id, b.id, "career") == "career" and RelationshipKnowledge.reveal(a.id, b.id, "career") == "", "career revealed once")
	S.expect(f, RelationshipKnowledge.known_summary(a.id, b.id)["career"] == "Unemployed", "unemployed shown once known")
	S.expect(f, RelationshipKnowledge.knows_trait(b.id, a.id, "social") == false, "knowledge is directional")
	# knowledge gates interactions: you cannot talk shop before you know their job
	var q := S.folk(w, "Quincy", ["neat"])
	a.needs["social"].set_value(30.0)
	RelationshipService.add_both(a.id, q.id, "friendship", 40.0)
	S.expect(f, SocialScoring.reason_unavailable(a, q, "talk_shop") == "You don't know their job yet.", "talk_shop is gated on knowing their job: %s" % SocialScoring.reason_unavailable(a, q, "talk_shop"))
	S.expect(f, SocialScoring.reason_unavailable(a, q, "tease_quirk") != "", "tease_quirk needs to know a trait")
	var ir_gate := S.run(a, q, "talk_shop")
	S.expect(f, ir_gate.state == "finished" and str(SocialDynamics.outcome_log.back()["label"]) == "Nothing came of it", "an ungated attempt achieves nothing")
	RelationshipKnowledge.reveal(a.id, q.id, "career")
	RelationshipKnowledge.reveal(a.id, q.id, "trait")
	S.expect(f, SocialScoring.reason_unavailable(a, q, "talk_shop", false) == "" and SocialScoring.reason_unavailable(a, q, "tease_quirk", false) == "", "knowledge unlocks them (%s / %s)" % [SocialScoring.reason_unavailable(a, q, "talk_shop"), SocialScoring.reason_unavailable(a, q, "tease_quirk")])
	var fr_k: float = q.get_rel(a.id, "friendship")
	S.run(a, q, "talk_shop")
	S.expect(f, str(SocialDynamics.outcome_log.back()["label"]) != "Nothing came of it", "knowing their job lets the conversation land")
	RelationshipService.add_both(a.id, b.id, "friendship", 30.0)
	var guard := 0
	while RelationshipKnowledge.unknown_trait_count(a.id, b.id) > 0 and guard < 80:
		S.run(a, b, "get_to_know")
		guard += 1
	S.expect(f, RelationshipKnowledge.unknown_trait_count(a.id, b.id) == 0, "repeated get-to-know chats reveal every trait (%d rounds)" % guard)
	var c := S.folk(w, "Cy")
	var g2 := 0
	while not RelationshipKnowledge.knows_career(a.id, c.id) and g2 < 60:
		S.run(a, c, "ask_about_day")
		g2 += 1
	S.expect(f, RelationshipKnowledge.knows_career(a.id, c.id), "ask_about_day eventually reveals the career")
	var d := S.folk(w, "Di")
	RelationshipService.add_both(a.id, d.id, "friendship", 60.0)
	var g3 := 0
	while not RelationshipKnowledge.knows_aspiration(a.id, d.id) and g3 < 60:
		S.run(a, d, "discuss_dreams")
		g3 += 1
	S.expect(f, RelationshipKnowledge.knows_aspiration(a.id, d.id), "discuss_dreams reveals the aspiration")
	var e := S.folk(w, "Ed", ["lazy", "gamer"])
	RelationshipBits.set_flag(a.id, e.id, "sweetheart", true, false)
	S.expect(f, RelationshipKnowledge.known_summary(a.id, e.id)["everything"] and RelationshipKnowledge.unknown_trait_count(a.id, e.id) == 0, "sweethearts know each other fully")
	var h := S.folk(w, "Hu", ["neat", "social", "creative", "gamer"])
	for i in 40:
		S.run(a, h, "chat")
	S.expect(f, RelationshipKnowledge.known_traits(a.id, h.id).size() >= 1, "chatting reveals traits over time")
	S.teardown()

func _trust(f: Array) -> void:
	var w := S.setup(51)
	var a := S.folk(w, "Ann")
	var b := S.folk(w, "Bo")
	RelationshipService.add_both(a.id, b.id, "friendship", 50.0)
	S.expect(f, RelationshipRomance.trust(b.id, a.id) == 0.0, "trust starts at zero")
	for i in 6:
		S.run(a, b, "offer_help")
	S.expect(f, RelationshipRomance.trust(b.id, a.id) > 3.0, "helping builds trust (%.1f)" % RelationshipRomance.trust(b.id, a.id))
	S.expect(f, a.get_rel(b.id, "trust") == RelationshipRomance.trust(a.id, b.id), "trust lives in Folk.relationships like the other tracks")
	RelationshipService.set_value(b.id, a.id, "trust", 70.0)
	RelationshipService.set_value(b.id, a.id, "friendship", 45.0)
	S.expect(f, RelationshipBits.bit_for(b.id, a.id) == "confidant", "high trust + friendship = confidant, got %s" % RelationshipBits.bit_for(b.id, a.id))
	var t0: float = RelationshipRomance.trust(b.id, a.id)
	for d in range(2, 20):
		S.set_time(d, 8)
		RelationshipService.on_day(d)
	S.expect(f, RelationshipRomance.trust(b.id, a.id) < t0 and RelationshipRomance.trust(b.id, a.id) > t0 - 12.0, "idle trust decays slowly (%.1f -> %.1f)" % [t0, RelationshipRomance.trust(b.id, a.id)])
	S.teardown()
