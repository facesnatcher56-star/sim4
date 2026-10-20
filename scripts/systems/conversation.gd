class_name Conversation
extends RefCounted
## Conversation circles and topics.
##  * Circles: any folk-targeted conversational interaction (chat, funny_story, group_chat, ...) puts its actor into the target's
##    circle (a new pair circle if the target was alone). Members get the hidden `in_conversation` marker buff, and `in_group`
##    when 3+ folk share a circle, which unlocks the group interactions (toast, tell_group_story, group_hug, party_game).
##    A circle lives while at least one member is still *running* a conversational interaction (an "actor"); targets stay until then.
##  * Topics: tied to interests (traits / skills / career), recent events (mood / buffs), shared interests raise success and
##    repeating a topic gives diminishing returns (per-pair counters kept in RelationshipService).
## Group effects are applied once a game minute from SocialDynamics.on_minute -> Conversation.on_minute.

static var circles: Dictionary = {}      # id -> {id, members:Array[int], actors:Array[int], topic, started, turn_at, score, turns}
static var _of: Dictionary = {}          # folk_id -> circle id
static var active_topic: Dictionary = {} # folk_id -> topic the folk is currently talking about
static var _next_id: int = 1

static func reset() -> void:
	circles.clear()
	_of.clear()
	active_topic.clear()
	_next_id = 1

static func cfg() -> Dictionary:
	return SysUtil.table("social").get("group", {})

# ------------------------------------------------------------------ circles
static func circle_id_of(fid: int) -> int:
	return int(_of.get(fid, -1))

static func circle_of(fid: int) -> Dictionary:
	var cid := circle_id_of(fid)
	return circles.get(cid, {})

static func size_of(fid: int) -> int:
	var c := circle_of(fid)
	return (c.get("members", []) as Array).size()

static func same_circle(a: int, b: int) -> bool:
	var ca := circle_id_of(a)
	return ca >= 0 and ca == circle_id_of(b)

static func members_of(fid: int) -> Array:
	return (circle_of(fid).get("members", []) as Array).duplicate()

static func is_group(fid: int) -> bool:
	return size_of(fid) >= int(cfg().get("min_group", 3))

static func all_circles() -> Array:
	return circles.values()

static func _marker(fid: int, on: bool, buff: String) -> void:
	var f = SysUtil.folk(fid)
	if f == null:
		return
	if on:
		Emotions.add_hidden(f, buff)
	elif f.has_buff(buff):
		f.remove_buff(buff)

static func _refresh_markers(c: Dictionary) -> void:
	var grp: bool = (c["members"] as Array).size() >= int(cfg().get("min_group", 3))
	for m in c["members"]:
		_marker(int(m), true, "in_conversation")
		_marker(int(m), grp, "in_group")

static func _new_circle(first: int) -> Dictionary:
	var c := {"id": _next_id, "members": [first], "actors": [], "topic": "", "started": SysUtil.now(), "turn_at": SysUtil.now(), "score": 0.0, "turns": 0}
	circles[_next_id] = c
	_of[first] = _next_id
	_next_id += 1
	return c

## `actor` walks up to `anchor` and joins their circle (creating one when the anchor is alone).
static func join(actor: int, anchor: int) -> int:
	if actor == anchor:
		return -1
	var c: Dictionary = circle_of(anchor)
	if c.is_empty():
		var other: Dictionary = circle_of(actor)
		if not other.is_empty():
			c = other
		else:
			c = _new_circle(anchor)
	var cur := circle_id_of(actor)
	if cur >= 0 and cur != int(c["id"]):
		leave(actor)
	var cap: int = int(cfg().get("max_size", 6))
	for m in [anchor, actor]:
		if not (c["members"] as Array).has(m) and (c["members"] as Array).size() < cap:
			(c["members"] as Array).append(m)
		_of[m] = int(c["id"]) if (c["members"] as Array).has(m) else _of.get(m, -1)
	if not (c["actors"] as Array).has(actor) and (c["members"] as Array).has(actor):
		(c["actors"] as Array).append(actor)
	_refresh_markers(c)
	return int(c["id"])

static func leave(fid: int) -> void:
	var cid := circle_id_of(fid)
	_of.erase(fid)
	active_topic.erase(fid)
	_marker(fid, false, "in_conversation")
	_marker(fid, false, "in_group")
	if cid < 0 or not circles.has(cid):
		return
	var c: Dictionary = circles[cid]
	(c["members"] as Array).erase(fid)
	(c["actors"] as Array).erase(fid)
	if (c["members"] as Array).size() < 2 or (c["actors"] as Array).is_empty():
		_dissolve(cid)
	else:
		_refresh_markers(c)

static func _dissolve(cid: int) -> void:
	if not circles.has(cid):
		return
	var c: Dictionary = circles[cid]
	for m in c["members"]:
		_of.erase(int(m))
		active_topic.erase(int(m))
		_marker(int(m), false, "in_conversation")
		_marker(int(m), false, "in_group")
	circles.erase(cid)

static func _convmode(iid: String) -> String:
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	var sd: Dictionary = d.get("social", {})
	if sd.has("conv"):
		var v: Variant = sd["conv"]
		if v is bool:
			return "pair" if v else "none"
		return str(v)
	if str(d.get("target", "")) != "folk":
		return "none"
	var cat: String = str(d.get("category", ""))
	if cat in ["romantic", "mean"]:
		return "none"
	if (d.get("tags", []) as Array).has("social"):
		return "pair"
	return "none"

## Hooks from RelationshipService.on_interaction_started / _finished.
static func on_started(actor: int, iid: String, target: int) -> void:
	var mode := _convmode(iid)
	if target < 0 or mode == "none":
		return
	if mode == "keep":
		# a group-only action: stays in the circle the actor is already part of
		var c := circle_of(actor)
		if not c.is_empty() and not (c["actors"] as Array).has(actor):
			(c["actors"] as Array).append(actor)
		return
	join(actor, target)
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	if bool((d.get("social", {}) as Dictionary).get("topical", false)):
		var topic := pick_topic(actor, target)
		active_topic[actor] = topic
		var c2 := circle_of(actor)
		if not c2.is_empty():
			c2["topic"] = topic
		ThoughtVoice.chat(actor, target, topic)       # topic lines for both speakers (data/thought_voice.json)

static func on_finished(actor: int, iid: String, _success: bool) -> void:
	var mode := _convmode(iid)
	if mode == "none":
		return
	if mode == "keep":
		var c := circle_of(actor)
		if not c.is_empty():
			(c["actors"] as Array).erase(actor)
			if (c["actors"] as Array).is_empty():
				_dissolve(int(c["id"]))
		return
	leave(actor)

## Per-minute group effects and cleanup. Returns the number of live circles.
static func on_minute() -> int:
	var cc: Dictionary = cfg()
	var now := SysUtil.now()
	# stale markers (e.g. right after loading a save): nobody is in a circle but the buff survived
	for f in WorldIface.all_folk():
		if not _of.has(int(f.id)) or int(_of[int(f.id)]) < 0:
			if f.has_buff("in_conversation"):
				f.remove_buff("in_conversation")
			if f.has_buff("in_group"):
				f.remove_buff("in_group")
	for cid in circles.keys():
		if not circles.has(cid):
			continue
		var c: Dictionary = circles[cid]
		var gone := false
		for m in (c["members"] as Array).duplicate():
			var f = SysUtil.folk(int(m))
			if f == null or SysUtil.is_away(f):
				leave(int(m))
				gone = true
		if gone and not circles.has(cid):
			continue
		var n: int = (c["members"] as Array).size()
		if n < int(cc.get("min_group", 3)):
			continue
		c["score"] = float(c["score"]) + float(cc.get("score_per_min", 0.1)) * n
		for m2 in c["members"]:
			var f2 = SysUtil.folk(int(m2))
			if f2 != null:
				f2.add_to_stat("social", float(cc.get("social_per_min", 0.6)))
		if now - int(c["turn_at"]) >= int(cc.get("turn_min", 10)):
			c["turn_at"] = now
			c["turns"] = int(c["turns"]) + 1
			_group_turn(c)
	return circles.size()

## Everyone in a lively circle warms up a little to everyone else.
static func _group_turn(c: Dictionary) -> void:
	var mem: Array = c["members"]
	var g: float = float(cfg().get("pair_friend_per_turn", 0.3))
	for i in mem.size():
		for j in range(i + 1, mem.size()):
			RelationshipService.add_both(int(mem[i]), int(mem[j]), "friendship", g)
			RelationshipService.touch(int(mem[i]), int(mem[j]))
	SysUtil.game_event("group_turn", {"folk_id": int(mem[0]), "size": mem.size(), "circle": int(c["id"])})

static func group_score(fid: int) -> float:
	return float(circle_of(fid).get("score", 0.0))

# ------------------------------------------------------------------ topics
static func topics() -> Dictionary:
	return SysUtil.table("social").get("topics", {})

static func topic_label(topic: String) -> String:
	return str(topics().get(topic, {}).get("label", topic))

static func rules() -> Dictionary:
	return SysUtil.table("social").get("topic_rules", {})

## Topic ids a folk is personally interested in (traits, trained skills, career).
static func interests_of(fid: int) -> Array:
	var out: Array = []
	var traits: Array = RelationshipBits.traits_of(fid)
	var f = SysUtil.folk(fid)
	var tmin: int = int(SysUtil.table("social").get("knowledge", {}).get("interest_min_skill", 2))
	var tp := topics()
	for tid in tp:
		var t: Dictionary = tp[tid]
		if bool(t.get("boring", false)):
			continue
		var yes := false
		for tr in t.get("traits", []):
			if traits.has(str(tr)):
				yes = true
		if f != null:
			for sk in t.get("skills", []):
				if f.skill_level(str(sk)) >= tmin:
					yes = true
		if bool(t.get("career", false)) and Careers.has_job(fid):
			yes = true
		if yes:
			out.append(str(tid))
	return out

## Topics prompted by what the folk is feeling / recently experienced.
static func recent_topics_of(fid: int) -> Array:
	var out: Array = []
	var f = SysUtil.folk(fid)
	if f == null:
		return out
	var tp := topics()
	for tid in tp:
		var t: Dictionary = tp[tid]
		if (t.get("moods", []) as Array).has(str(f.mood_name)):
			out.append(str(tid))
			continue
		for b in t.get("buffs", []):
			if f.has_buff(str(b)):
				out.append(str(tid))
				break
	return out

static func shared_interests(a: int, b: int) -> Array:
	var ib := interests_of(b)
	var out: Array = []
	for t in interests_of(a):
		if ib.has(t):
			out.append(t)
	return out

static func pick_topic(a: int, b: int) -> String:
	var tp := topics()
	if tp.is_empty():
		return ""
	var r := rules()
	var ia := interests_of(a)
	var ib := interests_of(b)
	var ra := recent_topics_of(a)
	var rb := recent_topics_of(b)
	var items: Array = []
	var weights: Array = []
	for tid in tp:
		var w: float = float(r.get("base_weight", 0.6))
		var ha: bool = ia.has(tid)
		var hb: bool = ib.has(tid)
		if ha and hb:
			w += float(r.get("shared_weight", 3.0))
		elif ha or hb:
			w += float(r.get("one_weight", 1.4))
		if ra.has(tid) or rb.has(tid):
			w += float(r.get("mood_weight", 1.0))
		if bool(tp[tid].get("boring", false)):
			w *= float(r.get("boring_weight", 0.5))
		w /= 1.0 + float(r.get("repeat_decay", 0.6)) * RelationshipKnowledge.topic_count(a, b, str(tid))
		items.append(str(tid))
		weights.append(w)
	return str(SysUtil.pick_weighted(items, weights))

## Success bonus and friendship multiplier for talking about `topic` (a talking to b).
static func topic_effect(a: int, b: int, topic: String) -> Dictionary:
	var out := {"bonus": 0.0, "mult": 1.0, "shared": false, "boring": false, "count": 0, "known": false}
	if topic == "" or not topics().has(topic):
		return out
	var w: Dictionary = SysUtil.table("social").get("outcomes", {}).get("weights", {})
	var r := rules()
	var t: Dictionary = topics()[topic]
	var cnt := RelationshipKnowledge.topic_count(a, b, topic)
	out["count"] = cnt
	var ia := interests_of(a).has(topic)
	var ib := interests_of(b).has(topic)
	out["shared"] = ia and ib
	out["boring"] = bool(t.get("boring", false))
	var bonus := 0.0
	var mult := 1.0
	if ia and ib:
		bonus += float(w.get("topic_shared", 0.1))
		mult *= 1.25
		if RelationshipKnowledge.knows_interest(a, b, topic):
			bonus += float(w.get("topic_known", 0.05))
			out["known"] = true
	elif ib:
		bonus += float(w.get("topic_shared", 0.1)) * 0.5
	if out["boring"]:
		bonus += float(w.get("topic_boring", -0.06))
	bonus -= float(w.get("repeat", 0.05)) * cnt
	mult *= maxf(1.0 / (1.0 + float(r.get("repeat_decay", 0.6)) * cnt), 0.25)
	out["bonus"] = bonus
	out["mult"] = mult
	return out
