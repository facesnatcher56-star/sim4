extends RefCounted
## Late nights: parties and invites end around midnight (children and elders earlier, night owls a little later), nobody is sent out to a
## party in the small hours, and guests are sent home from half past midnight.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := K.setup(31)
	var adult := K.make_folk(w, "Adele", [])
	var owl := K.make_folk(w, "Owen", ["night_owl"], 1, Vector2i(14, 12))
	var kid := K.make_folk(w, "Kit", [], 1, Vector2i(16, 12), "child")
	var eld := K.make_folk(w, "Elda", [], 1, Vector2i(18, 12), "elder")
	K.set_time(5, 22, 30)
	K.expect(f, Circadian.party_minutes_left(adult) == 120, "adult at 22:30 has 2 hours (%d)" % Circadian.party_minutes_left(adult))
	K.expect(f, Circadian.party_minutes_left(kid) == 0, "a child is not sent to a night party")
	K.expect(f, Circadian.party_minutes_left(eld) == 0, "an elder is home by 22:30")
	K.set_time(5, 21, 30)
	K.expect(f, Circadian.party_minutes_left(eld) == 60, "an elder at 21:30 has one hour (%d)" % Circadian.party_minutes_left(eld))
	K.set_time(6, 3, 0)
	K.expect(f, Circadian.party_minutes_left(adult) == 0 and Circadian.party_minutes_left(owl) == 0, "nobody goes out at 03:00")
	K.set_time(6, 0, 30)
	K.expect(f, Circadian.party_minutes_left(owl) == 90 and Circadian.party_minutes_left(adult) == 0, "a night owl may stay out later (%d)" % Circadian.party_minutes_left(owl))
	K.expect(f, Circadian.guests_curfew(), "guests are sent home from 00:30")
	K.set_time(5, 23, 0)
	K.expect(f, not Circadian.guests_curfew(), "but not at 23:00")
	# an invite accepted at 22:30 is cut to the time left; one at 23:50 is not accepted
	Story.generate_townies()
	Story.auto_accept_invites = false
	var tid: int = int(Story.alive_townies()[4]["id"])
	RelationshipService.add_both(adult.id, tid, "friendship", 40.0)
	K.set_time(5, 22, 30)
	var inv: Dictionary = StoryVisits.send_invite(tid, adult.id)
	StoryVisits.respond_invite(int(inv["id"]), true)
	var pend: Dictionary = Away.pending.get(adult.id, {})
	K.expect(f, not pend.is_empty() and float(pend["minutes"]) <= 120.0, "the party is cut to end by 00:30 (%s)" % str(pend.get("minutes", "none")))
	K.set_time(5, 23, 50)
	var inv2: Dictionary = StoryVisits.send_invite(tid, eld.id)
	K.expect(f, not StoryVisits.respond_invite(int(inv2["id"]), true) and str(inv2["state"]) == "expired", "no party is joined at 23:50 by an elder")
	# midnight invites wait for the daytime
	Story.auto_accept_invites = true
	K.set_time(6, 0, 0)
	var inv3: Dictionary = StoryVisits.send_invite(tid, kid.id)
	K.set_time(6, 0, 45)
	StoryVisits.on_minute()
	K.expect(f, str(inv3["state"]) == "open", "an invite that arrives at midnight waits")
	K.set_time(6, 10, 30)
	StoryVisits.on_minute()
	K.teardown()
	return f
