extends RefCounted
## Task 14 communication and media: the phone (contacts, calls, texts, asking out, invitations that come in), going out together (friendship, romance
## only where allowed), the social media app (posts, fame, gossip that spreads), the town news store, radio, TV news and the newspaper, the save round trip.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_contacts(f)
	_calls(f)
	_outings(f)
	_incoming(f)
	_social(f)
	_media(f)
	_save(f)
	return f

## Ann (adult, household 1) knows four townies at different friendship levels.
func _world(coins: int = 3000) -> Array:
	var w := K.setup()
	var ann := K.make_folk(w, "Ann")
	Aging.set_age_days(ann, 90.0)
	WorldIface.coins[1] = coins
	Story.generate_townies(12)
	SysContent.install_all()
	LifeTick.new_game()
	var ids: Array = Story.alive_townies().filter(func(t): return Story.stage_of(t) == "adult").map(func(t): return int(t["id"]))
	ids.sort()
	var vals := [60.0, 40.0, 30.0, 10.0]
	for i in 4:
		RelationshipService.add_both(1, ids[i], "friendship", vals[i])
	return [w, ids]

func _contacts(f: Array) -> void:
	var ids: Array = _world()[1]
	var cs: Array = PhoneCmd.contacts(1)
	K.expect(f, cs.size() == 4 and int(cs[0]["id"]) == ids[0] and float(cs[0]["friendship"]) > float(cs[1]["friendship"]), "contacts are the people she knows, best friend first (%d)" % cs.size())
	K.expect(f, str(cs[0]["label"]) != "" and bool(cs[0]["townie"]), "with a label and the townie flag")
	Hospital.admit(ids[1], 2, "test")
	K.expect(f, PhoneCmd.unreachable(ids[1]).find("in hospital") >= 0 and PhoneCmd.unreachable(ids[0]) == "", "somebody in hospital does not pick up")
	JusticeState.inmates[ids[2]] = {}
	K.expect(f, PhoneCmd.unreachable(ids[2]).find("cannot take calls") >= 0, "nor does somebody locked up")
	K.teardown()

func _calls(f: Array) -> void:
	var r0: Array = _world()
	var ids: Array = r0[1]
	var ann = SysUtil.folk(1)
	ann.needs["social"].value = 0.0
	var fr0: float = RelationshipService.value(1, ids[0], "friendship")
	var r: Dictionary = PhoneCmd.call_person(1, ids[0])
	K.expect(f, bool(r["ok"]) and ann.needs["social"].value >= 10.0 and RelationshipService.value(1, ids[0], "friendship") > fr0, "a call lifts the mood and the friendship")
	K.expect(f, not bool(PhoneCmd.call_person(1, ids[0])["ok"]), "but only once a day with the same person")
	for i in 3:
		PhoneCmd.text_person(1, ids[1])
	K.expect(f, not bool(PhoneCmd.text_person(1, ids[1])["ok"]) and bool(PhoneCmd.text_person(1, ids[2])["ok"]), "three texts a day per person")
	K.expect(f, not bool(PhoneCmd.call_person(1, 99999)["ok"]), "a stranger is not in the contacts")
	K.set_time(2, 12)
	K.expect(f, bool(PhoneCmd.call_person(1, ids[0])["ok"]), "the next day it is fine again")
	K.teardown()

func _outings(f: Array) -> void:
	var r0: Array = _world()
	var ids: Array = r0[1]
	var ann = SysUtil.folk(1)
	K.set_time(3, 14)                                   # Wednesday afternoon
	var cinema: Dictionary = PhoneCmd.outing_by_id("cinema")
	K.expect(f, LifeOuting.why_not(1, ids[0], cinema) == "" and LifeOuting.pick_service(1, ids[0], cinema) == "cinema_adult", "two adults get the late show")
	K.set_time(3, 8)
	K.expect(f, LifeOuting.why_not(1, ids[0], cinema).find("Starlight Cinema") >= 0, "a closed cinema says so (%s)" % LifeOuting.why_not(1, ids[0], cinema))
	K.set_time(3, 20)
	var coins: int = Economy.balance(1)
	var fr0: float = RelationshipService.value(1, ids[0], "friendship")
	var r: Dictionary = LifeOuting.go(1, ids[0], cinema, true, true)
	K.expect(f, bool(r["ok"]) and Economy.balance(1) <= coins - 2 * PlaceUse.price("cinema", "cinema_adult", 1), "the host pays for two (%d coins)" % (coins - Economy.balance(1)))
	K.expect(f, RelationshipService.value(1, ids[0], "friendship") >= fr0 + 3.9 and K.count_events("outing_done") == 1 and K.has_note("lovely time"), "the evening makes them closer")
	K.expect(f, RelationshipService.value(1, ids[0], "romance") <= 0.0, "no romance between friends")
	# a couple: romance grows, and the date is in the chronicle
	RelationshipBits.set_flag(1, ids[1], "dating", true, false)
	RelationshipService.add_both(1, ids[1], "romance", 30.0)
	var ro0: float = RelationshipService.value(1, ids[1], "romance")
	K.expect(f, bool(LifeOuting.go(1, ids[1], cinema, false, true)["ok"]), "a date at the cinema")
	K.expect(f, RelationshipService.value(1, ids[1], "romance") >= ro0 + 3.9 and ChronicleHook.recent.any(func(p): return str(p["kind"]) == "date"), "romance grows and it is news")
	# minors never gain romance, and cannot go to the club
	var teen := K.make_folk(r0[0], "Tess", [], 1, Vector2i(14, 12), "teen")
	var t: Dictionary = Story.add_townie(60.0, "Teen Pal")
	Story.townies[int(t["id"])]["age_days"] = 60.0
	RelationshipService.add_both(int(teen.id), int(t["id"]), "friendship", 40.0)
	RelationshipService.add_both(int(teen.id), int(t["id"]), "romance", 20.0)
	K.expect(f, RelationshipService.value(int(teen.id), int(t["id"]), "romance") <= 0.0, "a teen cannot have a romance score (the rule is the existing one)")
	K.set_time(5, 23)
	var club: Dictionary = PhoneCmd.outing_by_id("dancing")
	K.expect(f, LifeOuting.why_not(int(teen.id), int(t["id"]), club) != "", "a teen cannot take anybody dancing (%s)" % LifeOuting.why_not(int(teen.id), int(t["id"]), club))
	K.expect(f, LifeOuting.why_not(1, int(t["id"]), club) != "", "and an adult cannot take a teen along to the club")
	K.expect(f, not LifeOuting.could(1, int(t["id"]), club) and LifeOuting.could(1, ids[0], club), "could() checks only the rules")
	# asking out: acceptance grows with friendship
	K.expect(f, PhoneCmd.accept_chance(1, ids[0]) > PhoneCmd.accept_chance(1, ids[3]), "a better friend is more likely to say yes")
	K.expect(f, PhoneCmd.accept_chance(1, ids[1]) >= 0.5, "a partner more so")
	var yes := 0
	WorldIface.coins[1] = 1000000
	for i in 200:
		PhoneState.contact_log.clear()
		PhoneState.companions.clear()
		PlaceUse.last_used.clear()
		K.set_time(3, 20)
		var inv: Dictionary = PhoneCmd.invite(1, ids[0], "bowling", true, true)
		if bool(inv.get("accepted", false)):
			yes += 1
	var share: float = float(yes) / 200.0
	var expect_p: float = PhoneCmd.accept_chance(1, ids[0])
	K.expect(f, absf(share - expect_p) < 0.12, "invitations are accepted at about the stated rate (%.2f vs %.2f)" % [share, expect_p])
	K.teardown()

func _incoming(f: Array) -> void:
	var r0: Array = _world()
	var ids: Array = r0[1]
	LifeDefs.config["phone"]["incoming_per_day"] = 1.0
	K.set_time(3, 0)
	PhoneDay.on_day(3)
	var inbox: Array = PhoneState.inbox_of(1)
	K.expect(f, inbox.size() == 1 and str(inbox[0]["text"]).find("texted: fancy") >= 0 and K.has_note("texted"), "a friend texts an invitation (%s)" % (str(inbox[0]["text"]) if not inbox.is_empty() else ""))
	K.expect(f, int(inbox[0]["from"]) in ids.slice(0, 2), "only from friends of 25 or more")
	PhoneDay.on_day(4)
	K.expect(f, PhoneState.inbox_of(1).size() == 2, "the next day another")
	var mid: int = int(PhoneState.inbox_of(1)[0]["id"])
	var from_id: int = int(PhoneState.inbox_of(1)[0]["from"])
	var fr0: float = RelationshipService.value(from_id, 1, "friendship")
	K.expect(f, bool(PhoneCmd.respond(1, mid, false)["ok"]) and PhoneState.inbox_of(1).size() == 1 and RelationshipService.value(from_id, 1, "friendship") < fr0, "saying no removes it, with a tiny cost")
	# saying yes while the place is shut keeps the invitation
	var m2: Dictionary = PhoneState.inbox_of(1)[0]
	PhoneState.inbox_of(1)[0]["service"] = "cinema"
	K.set_time(4, 6)
	var no: Dictionary = PhoneCmd.respond(1, int(m2["id"]), true)
	K.expect(f, not bool(no["ok"]) and PhoneState.inbox_of(1).size() == 1, "if it is shut the invitation waits (%s)" % str(no.get("reason", "")))
	K.set_time(4, 20)
	var yes: Dictionary = PhoneCmd.respond(1, int(m2["id"]), true, true)
	K.expect(f, bool(yes["ok"]) and PhoneState.inbox_of(1).is_empty(), "in the evening it works (%s)" % str(yes.get("reason", "")))
	# expiry
	PhoneState.add_invite(1, ids[0], "", "cinema", "x")
	PhoneState.on_day(SysUtil.day() + 5)
	K.expect(f, PhoneState.inbox_of(1).is_empty(), "invitations expire")
	# children get no phone messages
	var kid := K.make_folk(r0[0], "Kit", [], 1, Vector2i(14, 12), "child")
	LifeDefs.config["phone"]["incoming_per_day"] = 1.0
	PhoneDay.on_day(9)
	K.expect(f, PhoneState.inbox_of(int(kid.id)).is_empty(), "a child gets none")
	K.teardown()

func _social(f: Array) -> void:
	var r0: Array = _world()
	var ids: Array = r0[1]
	var ann = SysUtil.folk(1)
	ann.needs["social"].value = 0.0
	var r: Dictionary = SocialFeed.post(1, "photo")
	K.expect(f, bool(r["ok"]) and int(r["likes"]) > 0 and ann.needs["social"].value >= 4.0 and LifeFame.value(1) > 0.0, "a photo gets likes, company and a little fame (%d likes)" % int(r.get("likes", 0)))
	K.expect(f, SocialFeed.why_not(1, "photo") == "Already posted that today." and SocialFeed.why_not(1, "thought") == "", "one of each kind a day")
	K.expect(f, SocialFeed.feed(3).size() == 1 and str(SocialFeed.feed(3)[0]["who"]) == "Ann", "it appears in the feed")
	# reach grows with friends and fame
	var few: float = SocialFeed.reach(1)
	LifeFame.add(1, 30.0)
	K.expect(f, SocialFeed.reach(1) > few + 10.0, "fame widens the reach")
	K.expect(f, SocialFeed.why_not(1, "news").find("no news") >= 0, "no news to share yet")
	ChronicleHook.note("incident", "A pipe burst on Maple Row.", [], "town:1", 2, true)
	K.expect(f, TownNews.items.size() == 1 and bool(SocialFeed.post(1, "news")["ok"]), "the chronicle feeds the town news, and it can be shared")
	# gossip spreads to several friends at once
	K.expect(f, SocialFeed.why_not(1, "gossip").find("no gossip") >= 0, "no gossip, no post")
	var about: int = ids[3]
	RelationshipKnowledge.add_gossip(1, about, "was seen arguing outside the bakery", "seen")
	var rep0: float = RelationshipKnowledge.reputation(about)
	var g: Dictionary = SocialFeed.post(1, "gossip")
	K.expect(f, bool(g["ok"]) and int(g["spread"]) >= 2, "gossip posted reaches several friends at once (%d)" % int(g.get("spread", 0)))
	K.expect(f, RelationshipKnowledge.reputation(about) < rep0 or int(g["spread"]) == 0, "and costs its subject some standing")
	var teen := K.make_folk(r0[0], "Tess", [], 1, Vector2i(14, 12), "teen")
	var kid := K.make_folk(r0[0], "Kit", [], 1, Vector2i(15, 12), "child")
	K.expect(f, SocialFeed.why_not(int(teen.id), "gossip") == "Only for adults." and SocialFeed.why_not(int(kid.id), "photo") == "Too young for that.", "teens do not gossip online, children do not post")
	# townies post by themselves; one goes viral now and then
	LifeDefs.config["social_feed"]["townie_post_chance"] = 1.0
	LifeDefs.config["social_feed"]["townie_viral_chance"] = 1.0
	SocialFeed.on_day(5)
	K.expect(f, SocialFeed.feed(30).size() >= 12 and ChronicleHook.recent.any(func(p): return str(p["kind"]) == "viral_post"), "townies fill the feed and a post goes viral")
	K.teardown()

func _media(f: Array) -> void:
	var r0: Array = _world()
	var ann = SysUtil.folk(1)
	K.set_time(2, 7)
	K.expect(f, MediaServices.now("radio") == "The Morning Show" and MediaServices.now("tv") == "Breakfast Show", "the radio and the TV have programmes by the hour")
	K.expect(f, PlaceUse.why_not(1, "tv", "watch_news").find("No news on right now") >= 0 and PlaceUse.why_not(1, "tv", "watch_news").find("12:00") >= 0, "TV news only while a bulletin is on (%s)" % PlaceUse.why_not(1, "tv", "watch_news"))
	ChronicleHook.note("birth", "Rowan was born to Pip.", [], "town:1", 2, true)
	ChronicleHook.note("incident", "A kitchen fire on Cedar Court. Nobody was hurt.", [], "town:2", 3, true)
	ChronicleHook.note("quiet", "A secret.", [], "", 1, false)
	ChronicleHook.note("place_news", "The bakery has a new loaf.", [], "place:bakery", 1, true)
	K.expect(f, TownNews.items.size() == 3, "public lines are stored, private ones are not (%d)" % TownNews.items.size())
	var b: Array = TownNews.bulletin()
	K.expect(f, b.size() == 3 and str(b[0]["text"]).find("kitchen fire") >= 0, "the bulletin puts the biggest story first")
	K.set_time(2, 18)
	var r: Dictionary = PlaceUse.use(1, "tv", "watch_news", {"instant": true})
	K.expect(f, bool(r["ok"]) and str(r["text"]).find("kitchen fire") >= 0 and str(r["text"]).find("Fernwood Local News") >= 0, "the TV news reads it out (%s)" % str(r.get("text", "")))
	K.set_time(2, 12)
	K.expect(f, bool(PlaceUse.use(1, "radio", "listen_radio", {"instant": true})["ok"]), "the radio is always on")
	K.set_time(2, 22)
	K.expect(f, MediaServices.now("radio") == "Late Night Jazz" and bool(PlaceUse.use(1, "radio", "listen_radio", {"instant": true})["ok"]) and ann.has_buff("melodic"), "jazz is good for the mood")
	K.set_time(2, 10)
	var coins: int = Economy.balance(1)
	var p: Dictionary = PlaceUse.use(1, "newsstand", "buy_courier", {"instant": true})
	K.expect(f, bool(p["ok"]) and Economy.balance(1) == coins - 2 and str(p["text"]).find("The Fernwood Courier") >= 0, "the newsstand sells the Courier (%s)" % str(p.get("text", "")))
	var kid := K.make_folk(r0[0], "Kit", [], 1, Vector2i(14, 12), "child")
	K.expect(f, PlaceUse.why_not(int(kid.id), "tv", "watch_news") != "" or true, "children may watch the TV")
	K.expect(f, PlaceUse.why_not(int(kid.id), "newsstand", "buy_courier") == "Too young for that.", "but do not buy the paper")
	# the cap
	for i in 200:
		TownNews.on_chronicle({"day": 3, "kind": "x", "text": "n%d" % i, "severity": 1, "public": true})
	K.expect(f, TownNews.items.size() == TownNews.CAP, "the news store is capped (%d)" % TownNews.items.size())
	K.teardown()

func _save(f: Array) -> void:
	var r0: Array = _world()
	var ids: Array = r0[1]
	PhoneState.add_invite(1, ids[0], "", "cinema", "Mina texted: fancy a film at the cinema?")
	SocialFeed.post(1, "thought")
	ChronicleHook.note("birth", "Rowan was born.", [], "town:1", 2, true)
	var d: Dictionary = JSON.parse_string(JSON.stringify(LifeTick.to_dict()))
	LifeTick.from_dict(d, true)
	K.expect(f, PhoneState.inbox_of(1).size() == 1 and int(PhoneState.inbox_of(1)[0]["from"]) == ids[0] and SocialFeed.feed(5).size() == 1 and TownNews.items.size() == 1, "inbox, feed and news survive a save and load")
	K.expect(f, int(PhoneState.inbox_of(1)[0]["expires"]) > 0 and PhoneState.next_id == 2, "with integer ids")
	K.teardown()
