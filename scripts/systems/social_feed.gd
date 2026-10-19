class_name SocialFeed
extends RefCounted
## The social media app (task 14). Residents post a photo, a thought, share the town news, or pass on gossip; townies post by themselves.
##   reach  = 3 + 1.5 per friend + 0.4 per point of fame      likes = reach x (0.25 + 0.05 x charisma) x (0.7 .. 1.3)
##   a post is social and fun for the poster and grows FAME (LifeFame); a post with 20+ likes goes round town (a chronicle line)
##   gossip: posting it tells up to `spread` friends AT ONCE (SocialActions' own gossip rules: the subject loses reputation, and it can backfire),
##           so rumours spread faster than in conversation; the poster's own standing drops a little
##   news:   shares today's top headline of the TownNews store
## One post of each kind per person per day. Townies: `townie_post_chance` a day, a line in the feed (the 30 newest are kept).
## Data: data/life/50_media.json config.social_feed. Tier: events for residents, one dice per alive townie a day.

static var posts: Array = []             # [{day, who, text}] oldest first
static var last_post: Dictionary = {}    # "folk|kind" -> day

static func reset() -> void:
	posts.clear()
	last_post.clear()

static func cfg() -> Dictionary:
	return LifeDefs.cfg("social_feed")

static func kinds() -> Dictionary:
	return cfg().get("kinds", {})

static func feed(n: int = 8) -> Array:
	return posts.slice(maxi(posts.size() - n, 0))

static func _add(who: String, text: String) -> void:
	posts.append({"day": SysUtil.day(), "who": who, "text": text})
	while posts.size() > int(cfg().get("feed_cap", 30)):
		posts.pop_front()

static func reach(fid: int) -> float:
	var c: Dictionary = cfg()
	return float(c.get("reach_base", 3.0)) + float(c.get("reach_per_friend", 1.5)) * float(RelationshipBits.count_bit(fid, "friend", true)) + float(c.get("reach_per_fame", 0.4)) * LifeFame.value(fid)

static func why_not(fid: int, kind: String) -> String:
	var f = SysUtil.folk(fid)
	var k: Dictionary = kinds().get(kind, {})
	if f == null or k.is_empty():
		return "That is not possible."
	if str(f.age_stage) in ["baby", "toddler", "child"]:
		return "Too young for that."
	if str(f.age_stage) == "teen" and bool(k.get("adult_only", false)):
		return "Only for adults."
	if int(last_post.get("%d|%s" % [fid, kind], -1)) == SysUtil.day():
		return "Already posted that today."
	if kind == "news" and TownNews.bulletin().is_empty():
		return "There is no news to share."
	if kind == "gossip" and RelationshipKnowledge.gossip_for(fid).is_empty():
		return "%s has no gossip to share." % f.name
	return ""

static func post(fid: int, kind: String) -> Dictionary:
	var why: String = why_not(fid, kind)
	if why != "":
		return {"ok": false, "reason": why}
	var f = SysUtil.folk(fid)
	var c: Dictionary = cfg()
	var k: Dictionary = kinds()[kind]
	last_post["%d|%s" % [fid, kind]] = SysUtil.day()
	var likes: int = int(reach(fid) * (0.25 + 0.05 * float(f.skill_level("charisma"))) * PhoneState.rng.randf_range(0.7, 1.3))
	f.add_to_stat("social", minf(float(k.get("social", 4.0)) + float(likes) * 0.3, float(c.get("social_cap", 14.0))))
	f.add_to_stat("fun", float(k.get("fun", 2.0)))
	LifeFame.add(fid, minf(float(likes) / 25.0, 1.5) + float(k.get("fame", 0.0)))
	var text: String = ""
	var spread := 0
	match kind:
		"photo":
			var where: String = Neighborhood.label_of(Neighborhood.lot_of(f)) if Places.on_map(Neighborhood.lot_of(f)) else "home"
			text = "%s shared a photo from %s." % [f.name, where]
		"thought":
			var pool: Array = c.get("thoughts", ["Good day."])
			text = "%s posted: \"%s\"" % [f.name, str(pool[PhoneState.rng.randi_range(0, pool.size() - 1)])]
		"news":
			var b: Array = TownNews.bulletin()
			text = "%s shared the news: %s" % [f.name, str(b[0]["text"])]
		"gossip":
			spread = _spread_gossip(fid, int(c.get("gossip_spread", 4)))
			text = "%s passed some gossip on to %d friend%s." % [f.name, spread, "" if spread == 1 else "s"]
			RelationshipKnowledge.add_reputation(fid, -float(c.get("gossip_poster_reputation", 0.5)))
	_add(str(f.name), text)
	SysUtil.notify("%s (%d likes)" % [text, likes] if kind != "gossip" else text, "info")
	if likes >= int(c.get("viral_likes", 20)):
		LifeNote.say("viral_post", "A post by %s went round the whole town." % f.name, [fid], 0, false)
	SysUtil.game_event("social_post", {"folk_id": fid, "kind": kind, "likes": likes})
	return {"ok": true, "reason": "", "likes": likes, "spread": spread, "text": text}

## Tell the gossip to friends at once; returns how many friends heard something new.
static func _spread_gossip(fid: int, n: int) -> int:
	var heard := 0
	for ct in PhoneCmd.contacts(fid, 20):
		if heard >= n:
			break
		if float(ct["friendship"]) < 10.0 or str(ct["reason"]) != "":
			continue
		var before: int = _told_count(fid)
		SocialActions._gossip(fid, int(ct["id"]), "good", false, 1.0)
		if _told_count(fid) > before:
			heard += 1
	return heard

static func _told_count(fid: int) -> int:
	var n := 0
	for it in RelationshipKnowledge.gossip_for(fid):
		n += (it["told"] as Array).size()
	return n

## Townies post by themselves.
static func on_day(day: int) -> void:
	var c: Dictionary = cfg()
	var lines: Array = c.get("townie_posts", [])
	if lines.is_empty():
		return
	for t in Story.alive_townies():
		if SysUtil.folk(int(t["id"])) != null and SysUtil.is_resident(SysUtil.folk(int(t["id"]))):
			continue
		if PhoneState.rng.randf() >= float(c.get("townie_post_chance", 0.25)):
			continue
		var line: String = str(lines[PhoneState.rng.randi_range(0, lines.size() - 1)])
		var place_ids: Array = Places.all().keys()
		place_ids.sort()
		var pl: String = Places.label(str(place_ids[PhoneState.rng.randi_range(0, place_ids.size() - 1)]))
		_add(str(t["name"]), line.replace("{name}", str(t["name"])).replace("{place}", pl))
		if PhoneState.rng.randf() < float(c.get("townie_viral_chance", 0.01)):
			LifeNote.say("viral_post", "%s's post about %s got shared all over town." % [t["name"], pl], [int(t["id"])], 0, false)
			LifeFame.add(int(t["id"]), 3.0)

static func to_dict() -> Dictionary:
	return {"posts": posts.duplicate(true), "last": last_post.duplicate()}

static func from_dict(d: Dictionary) -> void:
	reset()
	posts = (d.get("posts", []) as Array).duplicate(true)
	for p in posts:
		p["day"] = int(p["day"])
	for k in (d.get("last", {}) as Dictionary):
		last_post[str(k)] = int(d["last"][k])
