extends RefCounted
## Story progression: townie roster, off-lot daily advance, visitors (state machine, party score), invites, burglar.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_roster(f)
	_advance(f)
	_visit(f)
	_party_score(f)
	_invite(f)
	_burglar(f)
	_roundtrip(f)
	return f

func _roster(f: Array) -> void:
	K.setup()
	Story.generate_townies()
	K.expect(f, Story.alive_townies().size() == 12, "12 townies generated, got %d" % Story.alive_townies().size())
	var names: Dictionary = {}
	var ids: Dictionary = {}
	for t in Story.alive_townies():
		names[t["name"]] = true
		ids[t["id"]] = true
		K.expect(f, (t["traits"] as Array).size() == 2 and int(t["id"]) >= 1000, "townie has traits and a 1000+ id")
	K.expect(f, names.size() == 12 and ids.size() == 12, "unique names and ids")
	var stages: Dictionary = {}
	for t2 in Story.alive_townies():
		stages[Story.stage_of(t2)] = true
	K.expect(f, stages.has("adult") and stages.has("teen") and stages.has("elder"), "a mix of ages: %s" % str(stages.keys()))
	var careers: int = 0
	for t3 in Story.alive_townies():
		if str(t3["career"]) != "":
			careers += 1
	K.expect(f, careers >= 5, "most adult townies have jobs (%d)" % careers)
	K.expect(f, RelationshipService.pairs.size() >= 3, "the townie web has relationships")
	K.teardown()

func _advance(f: Array) -> void:
	var w := K.setup()
	K.make_folk(w, "Ann")
	Story.generate_townies()
	var c0: Dictionary = {}
	for t in Story.alive_townies():
		c0[t["id"]] = [t["age_days"], t["career"], t["level"]]
	var babies_seen: bool = false
	for d in range(2, 61):
		K.set_time(d, 0)
		Story.on_day(d)
		SimEnv.clock().total_minutes += 0
	var changed: int = 0
	for t2 in Story.alive_townies():
		if c0.has(t2["id"]) and (c0[t2["id"]][0] != t2["age_days"] or c0[t2["id"]][1] != t2["career"] or c0[t2["id"]][2] != t2["level"]):
			changed += 1
	K.expect(f, changed >= 4, "townies age and change jobs (%d changed)" % changed)
	K.expect(f, Story.news.size() >= 3, "story log records events: %d" % Story.news.size())
	K.expect(f, Story.alive_townies().size() >= 6 and Story.alive_townies().size() <= 24, "population stays sane: %d" % Story.alive_townies().size())
	var spouse_or_partner: int = 0
	for key in RelationshipService.pairs:
		var fl: Dictionary = RelationshipService.pairs[key]["flags"]
		if fl.get("partner", false) or fl.get("spouse", false):
			spouse_or_partner += 1
		if fl.get("family", false):
			babies_seen = true
	K.expect(f, spouse_or_partner >= 1, "at least one couple exists after 60 days")
	K.expect(f, Story.townies.size() > 12 or babies_seen, "arrivals or births happened")
	K.teardown()

func _visit(f: Array) -> void:
	var w := K.setup()
	var host := K.make_folk(w, "Ann")
	var dir = K.director()
	Story.generate_townies()
	var guest_id: int = int(Story.alive_townies()[3]["id"])
	var gname: String = Story.name_of(guest_id)
	K.set_time(2, 12)
	Story.spawn_tile = Vector2i(2, 2)
	var sit: Dictionary = StoryVisits.invite_over(guest_id, host.id, 120)
	K.expect(f, str(sit["state"]) == "scheduled", "visit scheduled")
	K.expect(f, w.get_folk(guest_id) == null, "guest not on the lot yet")
	K.run(dir, 20)
	var g = w.get_folk(guest_id)
	K.expect(f, g != null and g.name == gname and g.has_meta("visitor") and g.household_id == -1, "guest arrives as a full Folk")
	K.expect(f, str(sit["state"]) in ["arrive", "mingle"], "state machine moved on: %s" % sit["state"])
	K.expect(f, K.count_events("visit_started") == 1 and K.has_note("arrived"), "arrival announced")
	K.expect(f, sit["roles"][str(host.id)] == "host" and sit["roles"][str(guest_id)] == "guest", "roles assigned")
	K.expect(f, RelationshipBits.bit_for(host.id, guest_id) != "stranger", "host and guest are acquainted after the visit starts")
	K.expect(f, not SysUtil.is_resident(g) and not Aging.records.has(guest_id), "visitors are not residents")
	K.run(dir, 30)
	K.expect(f, str(sit["state"]) == "mingle", "mingling")
	K.run(dir, 100)
	K.expect(f, str(sit["state"]) == "done" and w.get_folk(guest_id) == null, "guest left at the end (state %s)" % sit["state"])
	K.expect(f, K.count_events("visit_finished") == 1, "visit_finished event")
	K.expect(f, RelationshipService.knows(host.id, guest_id), "the relationship persists after the guest left")
	K.expect(f, RelationshipBits.bit_for(host.id, guest_id) in ["acquaintance", "friend", "best_friend"], "acquaintance made: %s" % RelationshipBits.bit_for(host.id, guest_id))
	K.expect(f, Story.townies[guest_id]["last_visit_day"] == 2, "townie remembers the visit")
	K.teardown()

func _party_score(f: Array) -> void:
	var w := K.setup()
	var host := K.make_folk(w, "Ann", ["social"])
	var dir = K.director()
	dir.autonomy_enabled = false
	Story.generate_townies()
	var gs: Array = []
	for t in Story.alive_townies().slice(2, 5):
		gs.append(int(t["id"]))
	K.set_time(2, 12)
	var sit: Dictionary = StoryVisits.start_party(host.id, gs, 120)
	WorldIface.coins[1] = 0
	K.run(dir, 45)
	K.expect(f, (sit["spawned"] as Array).size() == 3, "three guests arrived")
	var score0: float = float(sit["score"])
	# simulate friendly socializing between participants through the real event path
	for g in gs:
		var gf = w.get_folk(g)
		SimEnv.events().emit_signal("interaction_started", host.id, "chat", g)
		SimEnv.events().emit_signal("interaction_finished", host.id, "chat", true)
		SimEnv.events().emit_signal("interaction_started", g, "tell_joke", host.id)
		SimEnv.events().emit_signal("interaction_finished", g, "tell_joke", true)
		K.expect(f, gf != null, "guest on the lot")
	for i in 3:
		for g2 in gs:
			SimEnv.events().emit_signal("interaction_started", host.id, "compliment", g2)
			SimEnv.events().emit_signal("interaction_finished", host.id, "compliment", true)
	K.expect(f, float(sit["score"]) > score0 + 10.0, "social interactions raise the party score: %.1f" % float(sit["score"]))
	K.run(dir, 130)
	var ev: Dictionary = K.last_event("visit_finished")
	K.expect(f, bool(ev.get("success", false)) and int(ev.get("reward", 0)) > 0, "a lively party is a success with a reward: %s" % str(ev))
	K.expect(f, WorldIface.get_coins(1) > 0 and host.has_buff("social_glow"), "party reward: gifts and social glow")
	K.expect(f, w.all_folk().size() == 1, "all guests went home")
	# a dull visit gets no reward
	var guest: int = int(Story.alive_townies()[8]["id"])
	var dull: Dictionary = StoryVisits.invite_over(guest, host.id, 60)
	K.run(dir, 120)
	K.expect(f, str(dull["state"]) == "done" and int(K.last_event("visit_finished")["reward"]) == 0, "a silent visit earns nothing")
	K.teardown()

func _invite(f: Array) -> void:
	var w := K.setup()
	var ann := K.make_folk(w, "Ann")
	var dir = K.director()
	Story.generate_townies()
	var tid: int = int(Story.alive_townies()[4]["id"])
	RelationshipService.add_both(ann.id, tid, "friendship", 40.0)
	Story.auto_accept_invites = false
	K.set_time(3, 10)
	var inv: Dictionary = StoryVisits.send_invite(tid, ann.id)
	K.expect(f, K.has_note("invites") and K.count_events("party_invite") == 1, "invite notification")
	K.expect(f, StoryVisits.open_invites(ann.id).size() == 1, "open invite listed")
	var social0: float = (ann.needs["social"] as Stat).value
	K.expect(f, StoryVisits.respond_invite(int(inv["id"]), true), "accepting works")
	K.run(dir, 5)
	K.expect(f, SysUtil.is_away(ann) and ann.get_meta("away") == "party", "the folk leaves for the party")
	K.run(dir, 190)
	K.expect(f, not SysUtil.is_away(ann), "back from the party")
	K.expect(f, (ann.needs["social"] as Stat).value > social0 + 20.0 and ann.has_buff("social_glow"), "party boosts social need")
	K.expect(f, K.count_events("party_attended") == 1, "party_attended event")
	K.expect(f, RelationshipService.value(ann.id, tid, "friendship") > 40.0, "friendship with the host grew")
	# auto accept after a delay, decline path, expiry
	Story.auto_accept_invites = true
	var inv2: Dictionary = StoryVisits.send_invite(tid, ann.id)
	K.run(dir, 40)
	K.expect(f, str(inv2["state"]) == "accepted", "auto-accept answers invites: %s" % inv2["state"])
	K.run(dir, 200)
	Story.auto_accept_invites = false
	var inv3: Dictionary = StoryVisits.send_invite(tid, ann.id)
	StoryVisits.respond_invite(int(inv3["id"]), false)
	K.expect(f, str(inv3["state"]) == "declined", "declining")
	K.teardown()

func _burglar(f: Array) -> void:
	var w := K.setup()
	var ann := K.make_folk(w, "Ann")
	var bo := K.make_folk(w, "Bo")
	var bed = w.add_object("bed", Vector2i(5, 5))
	var lamp = w.add_object("lamp", Vector2i(7, 5))
	WorldIface.coins[1] = 2000
	K.set_time(3, 3)
	K.expect(f, Story.try_burglary(true) == 0, "awake folk: no burglary")
	for fk in [ann, bo]:
		var ir := Interaction.create("sleep_bed", fk, bed.id, false)
		fk.current = ir
		ir.state = "running"
		fk.posture = "lie"
	lamp.state["on"] = true
	K.expect(f, Story.try_burglary(true) == 0 and WorldIface.get_coins(1) == 2000, "a lamp left on scares burglars off")
	lamp.state["on"] = false
	var stolen: int = Story.try_burglary(true)
	K.expect(f, stolen >= 20 and stolen <= 300 and WorldIface.get_coins(1) == 2000 - stolen, "everyone asleep, no lamp: coins stolen (%d)" % stolen)
	K.expect(f, K.has_note("burglar") and K.count_events("burglary") == 1, "burglary announced")
	# hour gating through the clock: outside 1-5 never happens
	var before: int = Story.burglaries
	for h in range(6, 24):
		Story.on_hour(h)
	K.expect(f, Story.burglaries == before, "burglars only strike in the small hours")
	for fk2 in [ann, bo]:
		fk2.current = null
	K.teardown()

func _roundtrip(f: Array) -> void:
	var w := K.setup()
	var host := K.make_folk(w, "Ann")
	Story.generate_townies()
	StoryVisits.invite_over(int(Story.alive_townies()[2]["id"]), host.id)
	StoryVisits.send_invite(int(Story.alive_townies()[3]["id"]), host.id)
	Story.on_day(2)
	var d1: Dictionary = Story.to_dict()
	var parsed: Variant = JSON.parse_string(JSON.stringify(d1))
	Story.from_dict(parsed)
	var diffs: Array = []
	K.expect(f, K.deep_eq(d1, Story.to_dict(), "story", diffs), "story roundtrip: %s" % str(diffs.slice(0, 5)))
	K.teardown()
