class_name StorytellerRipple
extends RefCounted
## How a city event reaches the player's households, second-hand. A card's `ripple` block has up to four parts:
##   near    households in the same district (data ripple.near_zones): a toast (sirens, smoke, a detour), a worried moodlet, the day counts as notable for them
##   know    households with someone who knows the person it happened to: a toast, a little friendship, maybe a thank-you visit later (`thanks`), a follow-up card
##           (a friend's house burnt down: they ask for a bed), a job opening (`job_open`)
##   detour  road works in the district for a while (the traffic system routes round it)
##   town    news for everybody: a Story news line and the Storyteller log, and the Chronicle at severity 2+
## Perception: full detail only near the household or among people it knows; the rest is a short news line, so nothing is lost and nothing floods the screen.
## The household's ripple counters (Storyteller.ripple_count) are what the tests measure.

static func rcfg() -> Dictionary:
	return Storyteller.cfg().get("ripple", {})

static func _count(hid: int, part: String) -> void:
	var r: Dictionary = Storyteller.ripples.get(hid, {"near": 0, "know": 0, "town": 0})
	r[part] = int(r.get(part, 0)) + 1
	Storyteller.ripples[hid] = r

static func knows_who(hid: int, who: int) -> Array:
	var out: Array = []
	if who < 0:
		return out
	for r in StorytellerPlay.residents_of(hid):
		if RelationshipService.knows(int(r.id), who):
			out.append(r)
	return out

static func spread(cid: String, c: Dictionary, ctx: Dictionary, extra: Dictionary) -> void:
	var rp: Dictionary = c.get("ripple", {})
	var zone: String = str(ctx.get("zone", ""))
	var who: int = int(ctx.get("who", -1))
	var rc: Dictionary = rcfg()
	for hid in CityState.full_households():
		var hz: String = CityState.zone_of_household(int(hid))
		var touched: bool = false
		if rp.has("near") and StorytellerDistrict.distance(hz, zone) <= int(rc.get("near_zones", 0)):
			touched = _near(int(hid), rp["near"], ctx) or touched
		if rp.has("know") and who >= 0:
			touched = _know(int(hid), rp["know"], ctx, who) or touched
		if touched:
			var e: Dictionary = StorytellerBudget.entry("h%d" % int(hid))
			e["last_notable"] = SysUtil.day()
	if rp.has("detour"):
		TransportTraffic.add_works(zone, "accident", float((rp["detour"] as Dictionary).get("days", 0.3)))
	if rp.has("town"):
		_town(cid, rp["town"], ctx)

static func _near(hid: int, p: Dictionary, ctx: Dictionary) -> bool:
	var text: String = StorytellerFx.fill(str(p.get("text", "")), ctx)
	var buff: String = str(p.get("buff", ""))
	var res: Array = StorytellerPlay.residents_of(hid)
	if res.is_empty():
		return false
	if buff != "" and not SimEnv.data().buff_def(buff).is_empty():
		for f in res:
			if Storyteller.rng.randf() < float(rcfg().get("near_buff_chance", 0.7)):
				f.add_buff(buff)
	StorytellerLog.toast(hid, text)
	StorytellerLog.add("ripple", text, "", "h%d" % hid, [hid], "home", "")
	_count(hid, "near")
	return true

static func _know(hid: int, p: Dictionary, ctx: Dictionary, who: int) -> bool:
	var friends: Array = knows_who(hid, who)
	if friends.is_empty() or Storyteller.rng.randf() >= float(rcfg().get("know_chance", 0.9)):
		return false
	var host = friends[0]
	var text: String = StorytellerFx.fill(str(p.get("text", "")), ctx)
	StorytellerLog.toast(hid, text)
	StorytellerLog.add("ripple", text, "", "h%d" % hid, [hid], "home", "")
	if p.has("friend"):
		RelationshipService.add_both(int(host.id), who, "friendship", float(p["friend"]))
	var later: Array = rcfg().get("later_days", [1, 4])
	if bool(p.get("thanks", false)):
		StorytellerQueue.add({"kind": "thanks", "due": SysUtil.day() + Storyteller.rng.randi_range(2, 4), "hid": hid, "folk_id": int(host.id), "other": who})
	if p.has("home_card") and Storyteller.rng.randf() < float(p.get("chance", 0.5)):
		var d: Array = p.get("delay", later)
		StorytellerQueue.add({"kind": "home_card", "card": str(p["home_card"]), "due": SysUtil.day() + Storyteller.rng.randi_range(int(d[0]), int(d[1])), "hid": hid, "folk_id": int(host.id), "other": who})
	if bool(p.get("job_open", false)):
		for r in StorytellerPlay.residents_of(hid):
			if str(r.age_stage) in ["adult", "elder"] and not Careers.has_job(int(r.id)) and not Careers.offers.has(int(r.id)):
				Careers.make_offer(r)
				break
	_count(hid, "know")
	return true

static func _town(cid: String, p: Dictionary, ctx: Dictionary) -> void:
	var text: String = StorytellerFx.fill(str(p.get("news", "")), ctx)
	if text == "":
		return
	Story._log(text)
	StorytellerLog.add("news", text, "", str(ctx.get("key", "")), [], "town", cid)
	for hid in CityState.full_households():
		_count(int(hid), "town")
	var sev: int = int(p.get("sev", 1))
	if sev >= 2:
		ChronicleHook.note(cid, text, [], "town:0", sev, true)
