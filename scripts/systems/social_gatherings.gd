class_name SocialGatherings
extends RefCounted
## Gatherings, karaoke, social goals/markers and couple upkeep.

# ------------------------------------------------------------------ gatherings
## Host invites friends / family on the lot; they walk over and chat, raising a group score used by Story parties.
static func start_gathering(host_id: int) -> Dictionary:
	var gc: Dictionary = SocialDynamics.cfg().get("gathering", {})
	var host = SysUtil.folk(host_id)
	if host == null or not (gc.get("host_stages", ["adult", "elder"]) as Array).has(str(host.age_stage)):
		return {}                     # only grown-ups host; little ones get their company from a parent (BabyCare)
	var hour: int = (SysUtil.now() % 1440) / 60
	if hour < int(gc.get("earliest_hour", 9)) or hour >= int(gc.get("latest_hour", 22)):
		return {}                     # gatherings are for waking hours
	var cands: Array = []
	for f in WorldIface.all_folk():
		if int(f.id) == host_id or SysUtil.is_away(f) or str(f.age_stage) in ["baby", "toddler"]:
			continue
		var close: float = RelationshipService.value(int(f.id), host_id, "friendship")
		var fam: bool = RelationshipBits.has_flag(host_id, int(f.id), "family") or RelationshipBits.has_flag(host_id, int(f.id), "partner") or RelationshipBits.has_flag(host_id, int(f.id), "spouse")
		if close >= float(gc.get("min_friendship", 12)) or fam:
			cands.append({"f": f, "close": close + (30.0 if fam else 0.0), "fam": fam})
	cands.sort_custom(func(x, y): return float(x["close"]) > float(y["close"]))
	var guests: Array = []
	var fam_n := 0
	for c in cands.slice(0, int(gc.get("max_guests", 5))):
		guests.append(int(c["f"].id))
		if bool(c["fam"]):
			fam_n += 1
	if guests.is_empty():
		SysUtil.notify("%s tried to get everyone together, but nobody could come." % host.name, "info")
		return {}
	var g := {"id": SocialDynamics._next_gathering, "host": host_id, "guests": guests, "start": SysUtil.now(), "end": SysUtil.now() + int(gc.get("duration_min", 90)) + 15,
		"score": 0.0, "kind": "family" if fam_n * 2 >= guests.size() else "friends", "done": false}
	SocialDynamics._next_gathering += 1
	SocialDynamics.gatherings.append(g)
	SocialDynamics._count("gatherings")
	for gid in guests:
		var gf = SysUtil.folk(int(gid))
		var ir := Interaction.create("chat", gf, host_id, false)
		if ir != null:
			gf.enqueue(ir)
	SysUtil.notify("%s is hosting a %s gathering." % [host.name, g["kind"]], "relationship")
	SysUtil.game_event("gathering_started", {"folk_id": host_id, "guests": guests.duplicate(), "kind": g["kind"], "id": g["id"]})
	return g

static func active_gathering(host_id: int) -> Dictionary:
	for g in SocialDynamics.gatherings:
		if int(g["host"]) == host_id and not bool(g["done"]):
			return g
	return {}

static func _tick_gatherings() -> void:
	if SocialDynamics.gatherings.is_empty():
		return
	var gc: Dictionary = SocialDynamics.cfg().get("gathering", {})
	var now := SysUtil.now()
	for g in SocialDynamics.gatherings:
		if bool(g["done"]):
			continue
		var host: int = int(g["host"])
		var present := 0
		for gid in g["guests"]:
			if Conversation.same_circle(host, int(gid)):
				present += 1
		if present >= 1:
			g["score"] = float(g["score"]) + float(gc.get("member_score_per_min", 0.2)) * (present + 1)
		if now >= int(g["end"]):
			_finish_gathering(g)
	var keep: Array = []
	for g2 in SocialDynamics.gatherings:
		if bool(g2["done"]):
			SocialDynamics.recent_gatherings.append(g2)
			if SocialDynamics.recent_gatherings.size() > 8:
				SocialDynamics.recent_gatherings.pop_front()
		else:
			keep.append(g2)
	SocialDynamics.gatherings = keep

static func _finish_gathering(g: Dictionary) -> void:
	var gc: Dictionary = SocialDynamics.cfg().get("gathering", {})
	g["done"] = true
	var host: int = int(g["host"])
	var everyone: Array = [host]
	everyone.append_array(g["guests"])
	var part: Array = []
	for pid in everyone:
		if SysUtil.folk(int(pid)) != null and (int(pid) == host or Conversation.same_circle(host, int(pid)) or float(g["score"]) > 4.0):
			part.append(int(pid))
	if part.size() >= int(gc.get("min_members", 3)):
		for i in part.size():
			var f = SysUtil.folk(int(part[i]))
			if f != null:
				f.add_buff(str(gc.get("buff", "group_warmth")))
			for j in range(i + 1, part.size()):
				RelationshipService.add_both(int(part[i]), int(part[j]), "friendship", float(gc.get("friendship_bond", 2.0)))
	var score: float = float(g["score"])
	g["final_score"] = score
	g["participants"] = part
	for sit in Story.situations:
		if (sit["roles"] as Dictionary).has(str(host)) and str(sit["state"]) in ["mingle", "arrive"]:
			sit["score"] = float(sit["score"]) + score * float(gc.get("story_factor", 0.5))
	SysUtil.notify("The %s gathering wraps up. Group score: %d." % [str(g["kind"]), int(round(score))], "relationship")
	SysUtil.game_event("gathering_done", {"folk_id": host, "score": score, "kind": str(g["kind"]), "participants": part.duplicate(), "id": int(g["id"])})

static func group_score(host_id: int) -> float:
	for i in range(SocialDynamics.gatherings.size() - 1, -1, -1):
		if int(SocialDynamics.gatherings[i]["host"]) == host_id:
			return float(SocialDynamics.gatherings[i].get("final_score", SocialDynamics.gatherings[i]["score"]))
	for j in range(SocialDynamics.recent_gatherings.size() - 1, -1, -1):
		if int(SocialDynamics.recent_gatherings[j]["host"]) == host_id:
			return float(SocialDynamics.recent_gatherings[j].get("final_score", SocialDynamics.recent_gatherings[j]["score"]))
	return Conversation.group_score(host_id)

static func _karaoke(singer_id: int) -> void:
	var s = SysUtil.folk(singer_id)
	if s == null:
		return
	var sc: float = 0.5 + float(s.skill_level("charisma")) * 0.03 + (0.1 if s.has_trait("musical") else 0.0) + (0.1 if str(s.mood_name) == "confident" else 0.0)
	sc += (SysUtil.rng.randf() * 2.0 - 1.0) * 0.2
	var audience := 0
	for f in WorldIface.all_folk():
		if int(f.id) == singer_id or SysUtil.is_away(f) or Vector2(f.tile - s.tile).length() > 6.0:
			continue
		audience += 1
		f.add_to_stat("fun", 6.0 if sc > 0.4 else 2.0)
		if sc > 0.65:
			f.add_buff("party_buzz")
			RelationshipService.add_value(int(f.id), singer_id, "friendship", 1.0)
	if sc > 0.75:
		s.add_buff("proud_performer")
	elif sc < 0.35:
		s.add_buff("embarrassed")
	SysUtil.game_event("karaoke_done", {"folk_id": singer_id, "audience": audience, "score": sc})

# ------------------------------------------------------------------ markers / goals
static func refresh_markers(f) -> void:
	if f == null:
		return
	var fid: int = int(f.id)
	_set_marker(f, "has_partner", not RelationshipRomance.exclusive_partners(fid).is_empty())
	var tellable := false
	for it in RelationshipKnowledge.gossip_for(fid):
		tellable = true
	_set_marker(f, "has_gossip", tellable)

static func _set_marker(f, buff: String, on: bool) -> void:
	if on:
		Emotions.add_hidden(f, buff)
	elif not on and f.has_buff(buff):
		f.remove_buff(buff)

static func update_goals(f) -> void:
	var gc: Dictionary = SocialDynamics.cfg().get("goals", {})
	var fid: int = int(f.id)
	# nobody (not even a loner) goes a whole day without any contact: a strong social urge builds up
	var now := SysUtil.now()
	if not SocialDynamics.last_social.has(fid):
		SocialDynamics.last_social[fid] = now
	if now - int(SocialDynamics.last_social[fid]) >= int(gc.get("contact_hours", 14)) * 60 and not f.has_buff("needs_contact"):
		Emotions.add_hidden(f, "needs_contact")
		_nudge_contact(f)
	var kind := ""
	var target := -1
	var text := ""
	# 1) make peace with someone they are tense with
	var worst := 0.0
	var worst_id := -1
	for o in RelationshipBits.all_known(fid):
		var tv: float = RelationshipRomance.tension(fid, int(o))
		if tv > worst and SysUtil.folk(int(o)) != null:
			worst = tv
			worst_id = int(o)
	var willing: bool = not (f.has_trait("grudgeholder") or f.has_trait("stubborn")) or f.has_buff("guilty_pang")
	_set_marker(f, "wants_reconcile", worst >= float(gc.get("reconcile_tension", 22)) and willing)
	if worst >= float(gc.get("reconcile_tension", 22)) and willing:
		kind = "reconcile"
		target = worst_id
		text = "Wants to make peace with %s" % SysUtil.folk_name(worst_id)
		f.remember("folk:%d" % worst_id, 0.45)
	# 2) friends
	var friends: int = RelationshipBits.count_bit(fid, "friend", true)
	var want_friends: bool = friends < int(gc.get("friend_target", 3))
	_set_marker(f, "wants_friends", want_friends)
	if want_friends and kind == "":
		var best := -1
		var best_s := -999.0
		for g in WorldIface.all_folk():
			if int(g.id) == fid or SysUtil.is_away(g) or str(g.age_stage) in ["baby", "toddler"]:
				continue
			var bit: String = RelationshipBits.bit_for(fid, int(g.id))
			if bit in ["friend", "best_friend", "enemy", "family", "partner", "spouse", "sweetheart", "dating"]:
				continue
			var sc: float = RelationshipBits.compatibility(fid, int(g.id)) + SysUtil.rng.randf() * 0.4 - RelationshipRomance.tension(fid, int(g.id)) * 0.02
			if sc > best_s:
				best_s = sc
				best = int(g.id)
		if best >= 0:
			kind = "make_friend"
			target = best
			text = "Wants to befriend %s" % SysUtil.folk_name(best)
			f.remember("folk:%d" % best, 0.3)
	# 3) company / romance
	_set_marker(f, "wants_company", f.get_stat_value("social") < float(gc.get("company_social_below", 35)))
	var single: bool = not f.has_buff("has_partner")
	var romantic: bool = f.has_trait("romantic") or f.has_trait("charmer")
	_set_marker(f, "wants_romance", romantic and single and str(f.age_stage) in ["adult", "elder", "teen"])
	if kind == "" and f.has_buff("wants_romance"):
		kind = "find_love"
		text = "Looking for love"
	if kind == "":
		SocialDynamics.goals.erase(fid)
	else:
		SocialDynamics.goals[fid] = {"kind": kind, "target": target, "text": text}

## A folk with a long contact drought queues a friendly word with someone (runs after their current activity).
static func _nudge_contact(f) -> bool:
	if not f.queue.is_empty() or (f.current != null and str(f.current.target_kind) == "folk"):
		return false
	var fid: int = int(f.id)
	var best = null
	var best_s := -999.0
	for g in WorldIface.all_folk():
		if int(g.id) == fid or SysUtil.is_away(g) or str(g.age_stage) in ["baby", "toddler"] or str(g.age_stage) != str(f.age_stage) and (str(g.age_stage) in ["child"] or str(f.age_stage) in ["child"]):
			continue
		var sc: float = RelationshipService.value(fid, int(g.id), "friendship") * 0.02 + RelationshipBits.compatibility(fid, int(g.id)) + SysUtil.rng.randf() * 0.3 - RelationshipRomance.tension(fid, int(g.id)) * 0.03
		if sc > best_s:
			best_s = sc
			best = g
	if best == null:
		return false
	var bit: String = RelationshipBits.bit_for(fid, int(best.id))
	var iid := "chat"
	if bit in ["stranger", "acquaintance"]:
		iid = "greet" if SysUtil.rng.randf() < 0.5 else "ask_about_day"
	var ir := Interaction.create(iid, f, int(best.id), false)
	if ir == null or not ir.can_run(f, null, false):
		return false
	f.enqueue(ir)
	return true

static func goal_text(fid: int) -> String:
	return str(SocialDynamics.goals.get(fid, {}).get("text", ""))

## Couples sometimes go on a date or show affection when both are idle (non-player priority, so autonomy-like).
static func couples_upkeep() -> int:
	var gc: Dictionary = SocialDynamics.cfg().get("goals", {})
	var hour: float = SimEnv.hour_f()
	var started := 0
	var seen: Dictionary = {}
	for key in RelationshipService.pairs:
		var p: Dictionary = RelationshipService.pairs[key]
		var fl: Dictionary = p["flags"]
		if not (fl.get("dating", false) or fl.get("sweetheart", false) or fl.get("partner", false) or fl.get("spouse", false)):
			continue
		var a = SysUtil.folk(int(p["lo"]))
		var b = SysUtil.folk(int(p["hi"]))
		if a == null or b == null or SysUtil.is_away(a) or SysUtil.is_away(b) or not a.is_idle() or not b.is_idle():
			continue
		if seen.has(a.id) or seen.has(b.id):
			continue
		var iid := ""
		if hour >= 17.0 and hour <= 22.0 and SysUtil.rng.randf() < float(gc.get("date_chance_per_hour", 0.12)) and not a.on_cooldown("go_on_date"):
			iid = "go_on_date"
		elif SysUtil.rng.randf() < float(gc.get("affection_chance_per_hour", 0.1)):
			var opts: Array = ["hug", "hold_hands", "kiss", "cuddle", "sweet_nothings"]
			iid = str(SysUtil.pick(opts))
		if iid == "":
			continue
		var ir := Interaction.create(iid, a, int(b.id), false)
		if ir != null and ir.can_run(a, null, false) and not a.on_cooldown(iid):
			a.enqueue(ir)
			seen[a.id] = true
			seen[b.id] = true
			started += 1
	return started
