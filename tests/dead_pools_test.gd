extends RefCounted
## The dead leave the gossip / toast / social pools: after death nothing names them as an actor or subject.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := K.setup(77)
	var a := K.make_folk(w, "Alma Wren")
	var b := K.make_folk(w, "Bruno Hale", [], 1, Vector2i(14, 12))
	Story.generate_townies(12)
	var tid: int = int(Story.alive_townies()[3]["id"])
	RelationshipService.add_both(a.id, b.id, "friendship", 40.0)
	RelationshipService.add_both(a.id, tid, "friendship", 40.0)
	RelationshipKnowledge.add_gossip(a.id, b.id, "Bruno is rude", "rumor", -1, tid)
	RelationshipKnowledge.add_gossip(a.id, tid, "Townie is odd", "rumor", -1, b.id)
	RelationshipKnowledge.add_gossip(b.id, a.id, "Alma sings", "rumor", -1, -1)
	var bid: int = int(b.id)
	Aging.kill(bid, "old age")
	Aging.kill(tid, "old age")
	K.expect(f, DeadPools.is_dead(bid) and DeadPools.is_dead(tid) and not DeadPools.is_dead(int(a.id)), "dead folk and dead townie are recognised")
	K.expect(f, RelationshipKnowledge.gossip_for(a.id).is_empty(), "gossip about the dead is gone (%s)" % str(RelationshipKnowledge.gossip_for(a.id)))
	K.expect(f, not RelationshipService.gossip_items.has(bid), "the dead hold no gossip")
	var first: int = K.events.size()
	var notes0: int = K.notes.size()
	SocialActions.gossip_backfire(tid, a.id, bid)
	SocialActions.gossip_backfire(a.id, a.id, bid)
	SocialActions._gossip(bid, a.id, "good", false, 1.0)
	RelNotify.say([a.id, bid], "Alma and Bruno made up.", "relationship")
	RelationshipToasts.announce(bid, a.id, "friend")
	for d in range(3, 40):
		K.set_time(d, 0)
		Story.on_day(d)
	var named: int = 0
	for i in range(first, K.events.size()):
		var e: Array = K.events[i]
		var p: Dictionary = e[1]
		if int(p.get("folk_id", -1)) == bid or int(p.get("folk_id", -1)) == tid or int(p.get("actor_id", -2)) == bid:
			named += 1
			print("  dead named as actor: ", e[0], " ", p)
	K.expect(f, named == 0, "no events name the dead as the actor (%d)" % named)
	var talk: int = 0
	for i in range(notes0, K.notes.size()):
		var txt: String = str(K.notes[i][0])
		if txt.find("Bruno") >= 0 and txt.find("gossip") >= 0 or txt.find("now sees") >= 0 and txt.find("Bruno") >= 0:
			talk += 1
	K.expect(f, talk == 0, "no toasts about the dead socialising (%d)" % talk)
	K.teardown()
	return f
