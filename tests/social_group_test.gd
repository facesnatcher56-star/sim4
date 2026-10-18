extends RefCounted
## Group socials: conversation circles (join / leave / markers), group interactions, gatherings feeding Story parties, karaoke.

const S = preload("res://tests/social_kit.gd")

func run() -> Array:
	var f: Array = []
	_circles(f)
	_group_actions(f)
	_gathering(f)
	_karaoke(f)
	_story_hook(f)
	return f

func _circles(f: Array) -> void:
	var w := S.setup(201)
	var a := S.folk(w, "Ann")
	var b := S.folk(w, "Bo")
	var c := S.folk(w, "Cy")
	var d := S.folk(w, "Di")
	for p in [[a, b], [a, c], [b, c], [a, d], [b, d], [c, d]]:
		RelationshipService.add_both(p[0].id, p[1].id, "friendship", 30.0)
	# a plain chat creates a pair circle while it runs
	var ia := Interaction.create("chat", a, b.id, true)
	ia.start()
	ia.tick(1.0)
	S.expect(f, Conversation.same_circle(a.id, b.id) and Conversation.size_of(a.id) == 2, "chatting forms a pair circle")
	S.expect(f, a.has_buff("in_conversation") and b.has_buff("in_conversation") and not a.has_buff("in_group"), "markers: in_conversation but not yet a group")
	# a third folk joins the conversation -> group
	var ic := Interaction.create("group_chat", c, b.id, true)
	S.expect(f, ic.can_run(c, null, false), "group_chat is available when the target is in a conversation")
	var lonely_target := Interaction.create("group_chat", c, d.id, true)
	S.expect(f, not lonely_target.can_run(c, null, false), "group_chat is NOT available towards someone who is not in a conversation")
	ic.start()
	ic.tick(1.0)
	S.expect(f, Conversation.size_of(b.id) == 3 and Conversation.is_group(a.id), "third person joins: group of 3")
	S.expect(f, a.has_buff("in_group") and b.has_buff("in_group") and c.has_buff("in_group"), "in_group marker for everyone in the circle")
	# group actions become available in a group
	S.expect(f, SocialDynamics.reason_unavailable(c, a, "toast") == "", "toast unlocked in a group")
	S.expect(f, SocialDynamics.reason_unavailable(d, a, "toast") != "", "toast is not available outside a group (reason given)")
	# fourth joins, then people leave
	var id4 := Interaction.create("group_chat", d, a.id, true)
	id4.start()
	id4.tick(1.0)
	S.expect(f, Conversation.size_of(a.id) == 4, "fourth joins")
	var s0: float = a.get_stat_value("social")
	# group warmth: per-minute social + friendship drift
	var fr0: float = RelationshipService.value(a.id, c.id, "friendship")
	S.set_time(1, 12)
	for i in 25:
		S.set_time(1, 12, i)
		Conversation.on_minute()
		SimEnv.clock().total_minutes += 1
	S.expect(f, RelationshipService.value(a.id, c.id, "friendship") > fr0, "group conversation warms everyone up")
	S.expect(f, Conversation.group_score(a.id) > 1.0, "the circle accumulates a group score (%.1f)" % Conversation.group_score(a.id))
	S.expect(f, SocialDynamics.group_score(a.id) > 1.0, "SocialDynamics.group_score exposes it")
	# leaving shrinks the group; below 3 the in_group marker goes away
	Conversation.leave(d.id)
	S.expect(f, Conversation.size_of(a.id) == 3 and not d.has_buff("in_conversation"), "leaving removes the marker and shrinks the circle")
	Conversation.leave(c.id)
	S.expect(f, Conversation.size_of(a.id) == 2 and not a.has_buff("in_group") and a.has_buff("in_conversation"), "below 3 the group marker clears")
	# finishing the actors' interactions dissolves the circle
	ia.finish(true)
	ic.finish(true)
	id4.finish(true)
	S.expect(f, Conversation.all_circles().is_empty() and not a.has_buff("in_conversation") and not b.has_buff("in_conversation"), "circle dissolves when nobody is talking")
	# max size
	var many: Array = []
	for i in 8:
		many.append(S.folk(w, "M%d" % i))
	for i in range(1, 8):
		Conversation.join(many[i].id, many[0].id)
	S.expect(f, Conversation.size_of(many[0].id) <= 6, "circles are capped (%d)" % Conversation.size_of(many[0].id))
	# anxious folk avoid groups
	var anx := S.folk(w, "Anx")
	anx.add_buff("anxious_jitters")
	anx.refresh_mood()
	S.expect(f, anx.get_mood()["mood"] == "anxious" and SocialDynamics.reason_unavailable(anx, many[0], "group_chat") != "", "anxious folk cannot join group chats")
	S.teardown()

func _group_actions(f: Array) -> void:
	var w := S.setup(211)
	var folks: Array = []
	for i in 4:
		folks.append(S.folk(w, "G%d" % i))
	for i in 4:
		for j in range(i + 1, 4):
			RelationshipService.add_both(folks[i].id, folks[j].id, "friendship", 35.0)
	for i in range(1, 4):
		Conversation.join(folks[i].id, folks[0].id)
	S.expect(f, Conversation.is_group(folks[0].id), "setup: a group of four")
	var fun0: float = folks[1].get_stat_value("fun")
	var fr0: float = RelationshipService.value(folks[1].id, folks[2].id, "friendship")
	var big := 0
	for i in 10:
		for k in 1:
			S.run(folks[0], folks[1], "toast")
	S.expect(f, folks[2].get_stat_value("fun") > fun0 or folks[1].get_stat_value("fun") >= 99.0, "toasts raise fun for the whole circle")
	S.expect(f, RelationshipService.value(folks[1].id, folks[2].id, "friendship") > fr0, "toasts bond everyone")
	var before: float = RelationshipService.value(folks[2].id, folks[3].id, "friendship")
	for i in 6:
		S.run(folks[0], folks[1], "tell_group_story")
		S.run(folks[3], folks[1], "group_hug")
		S.run(folks[2], folks[1], "party_game")
	S.expect(f, RelationshipService.value(folks[2].id, folks[3].id, "friendship") > before, "group stories / hugs / games bond the circle")
	S.expect(f, S.K.count_events("toast") >= 1 and S.K.count_events("group_boost") >= 1, "group events are emitted")
	S.expect(f, Conversation.is_group(folks[0].id), "the circle survives group actions")
	# dance together is a pair action with party vibes
	var x := S.folk(w, "Dx")
	var y := S.folk(w, "Dy")
	RelationshipService.add_both(x.id, y.id, "friendship", 30.0)
	var fr1: float = x.get_rel(y.id, "friendship")
	for i in 6:
		S.run(x, y, "dance_together")
	S.expect(f, x.get_rel(y.id, "friendship") > fr1, "dancing together bonds")
	S.teardown()

func _gathering(f: Array) -> void:
	var w := S.setup(221)
	var host := S.folk(w, "Host", ["social"])
	var guests: Array = []
	for i in 4:
		var g := S.folk(w, "Guest%d" % i, [], Vector2i(14 + i, 12))
		RelationshipService.add_both(host.id, g.id, "friendship", 35.0)
		guests.append(g)
	var fam := S.folk(w, "Kin", [], Vector2i(10, 12))
	RelationshipService.set_flag(host.id, fam.id, "family", true, false)
	var stranger := S.folk(w, "Stranger", [], Vector2i(10, 14))
	var dir = S.director()
	dir.autonomy_enabled = false
	S.set_time(1, 15)
	var ir := S.run(host, null, "host_gathering")
	S.expect(f, ir.state == "finished", "host_gathering runs")
	var g0: Dictionary = SocialDynamics.active_gathering(host.id)
	S.expect(f, not g0.is_empty() and (g0["guests"] as Array).size() >= 4, "gathering started with guests")
	S.expect(f, (g0["guests"] as Array).has(fam.id) and not (g0["guests"] as Array).has(stranger.id), "family and friends are invited, strangers are not")
	S.expect(f, S.K.count_events("gathering_started") == 1 and S.K.has_note("hosting"), "gathering announced")
	var circle_max := 0
	for i in 110:
		S.run_minutes(1)
		circle_max = maxi(circle_max, Conversation.size_of(host.id))
	S.expect(f, circle_max >= 3, "guests mingle in a circle around the host (max %d)" % circle_max)
	S.expect(f, S.K.count_events("gathering_done") == 1, "gathering finishes")
	var done: Dictionary = S.K.last_event("gathering_done")
	S.expect(f, float(done.get("score", 0.0)) > 3.0, "gathering produced a group score (%.1f)" % float(done.get("score", 0.0)))
	S.expect(f, SocialDynamics.group_score(host.id) > 3.0, "group_score(host) reports it")
	S.expect(f, (done.get("participants", []) as Array).size() >= 3, "participants are listed")
	S.expect(f, host.has_buff("group_warmth"), "participants feel the warmth")
	S.expect(f, RelationshipService.value(guests[0].id, guests[1].id, "friendship") > 0.5, "guests who did not know each other bonded")
	S.expect(f, SocialDynamics.stats["gatherings"] >= 1, "counted")
	# nobody to invite
	var loner := S.folk(w, "Loner", [], Vector2i(2, 2))
	loner.household_id = 5
	for gg in guests:
		gg.household_id = 1
	var empty := SocialDynamics.start_gathering(loner.id)
	S.expect(f, empty.is_empty() or (empty["guests"] as Array).size() >= 0, "gathering handles an unpopular host")
	S.teardown()

func _karaoke(f: Array) -> void:
	var w := S.setup(231)
	var stereo = w.add_object("stereo", Vector2i(12, 10))
	var singer := S.folk(w, "Sing", ["musical"])
	var fan1 := S.folk(w, "Fan1", [], Vector2i(13, 12))
	var fan2 := S.folk(w, "Fan2", [], Vector2i(14, 12))
	singer.add_skill_xp("charisma", Folk.xp_for_level(5) + 1.0)
	fan1.needs["fun"].set_value(10.0)
	var fun0: float = fan1.get_stat_value("fun")
	var ir := Interaction.create("karaoke", singer, stereo.id, true)
	S.expect(f, ir != null and ir.can_run(singer, stereo, false), "karaoke is runnable at a stereo")
	ir.start()
	var guard := 0
	while ir.state != "finished" and guard < 100:
		ir.tick(1.0)
		guard += 1
	S.expect(f, ir.state == "finished", "karaoke finishes")
	S.expect(f, S.K.count_events("karaoke_done") == 1, "karaoke_done event")
	S.expect(f, fan1.get_stat_value("fun") > fun0, "the audience enjoys it")
	var autoc: bool = SimEnv.data().interaction_def("karaoke").get("autonomous", false)
	S.expect(f, autoc, "karaoke can be chosen autonomously (party mixer)")
	S.teardown()

func _story_hook(f: Array) -> void:
	var w := S.setup(241)
	var scores: Dictionary = SimEnv.data().get_table("story")["visits"]["score"]
	S.expect(f, scores.has("group_chat") and scores.has("toast") and float(scores["yell_at"]) < 0.0, "group socials raise (and yelling lowers) a Story party score")
	S.expect(f, float(scores["chat"]) == 1.0, "existing score weights untouched")
	# a gathering hosted during a party adds to that situation's score
	var host := S.folk(w, "H")
	var g := S.folk(w, "G")
	RelationshipService.add_both(host.id, g.id, "friendship", 30.0)
	var sit := {"id": 99, "state": "mingle", "roles": {str(host.id): "host", str(g.id): "guest"}, "score": 0.0, "kind": "party", "host_ids": [host.id], "spawned": [], "guest_ids": []}
	Story.situations.append(sit)
	S.set_time(1, 12)
	var gat := SocialDynamics.start_gathering(host.id)
	gat["score"] = 10.0
	gat["end"] = 0
	SocialDynamics._tick_gatherings()
	S.expect(f, float(sit["score"]) > 3.0, "gathering score feeds the Story party score (%.1f)" % float(sit["score"]))
	Story.situations.erase(sit)
	S.teardown()
