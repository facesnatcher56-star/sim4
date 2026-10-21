class_name RelationshipKnowledge
extends RefCounted
## Getting-to-know knowledge, secrets, gossip, reputation and conversation topic counters.

# ---- knowledge ("getting to know")
static func _know(a: int, b: int) -> Dictionary:
	var p: Dictionary = RelationshipService._pair(a, b)
	var ks: Dictionary = RelationshipRomance._sub(p, "knows", {})
	var key: String = "%d>%d" % [a, b]
	if not ks.has(key):
		ks[key] = {"traits": [], "career": false, "aspiration": false, "interests": []}
	return ks[key]

static func knows_everything(a: int, b: int) -> bool:
	var p: Dictionary = RelationshipService._pair(a, b, false)
	if p.is_empty():
		return false
	var fl: Dictionary = p["flags"]
	for bit in RelationshipService.cfg().get("knowledge", {}).get("full_bits", []):
		if fl.get(str(bit), false):
			return true
	return false

static func knows_trait(a: int, b: int, t: String) -> bool:
	if knows_everything(a, b):
		return true
	return (_know(a, b)["traits"] as Array).has(t)

static func knows_career(a: int, b: int) -> bool:
	return knows_everything(a, b) or bool(_know(a, b)["career"])

static func knows_aspiration(a: int, b: int) -> bool:
	return knows_everything(a, b) or bool(_know(a, b)["aspiration"])

static func knows_interest(a: int, b: int, topic: String) -> bool:
	return knows_everything(a, b) or (_know(a, b)["interests"] as Array).has(topic)

## The interests of `b` that `a` has learned (the topics "Talk about ..." names).
static func known_interests(a: int, b: int) -> Array:
	return (_know(a, b)["interests"] as Array).duplicate()

static func known_traits(a: int, b: int) -> Array:
	var out: Array = []
	for t in RelationshipBits.traits_of(b):
		if knows_trait(a, b, str(t)):
			out.append(str(t))
	return out

static func unknown_trait_count(a: int, b: int) -> int:
	return RelationshipBits.traits_of(b).size() - known_traits(a, b).size()

## `a` learns something about `b`. kind: trait | career | aspiration | interest | all. Returns what was learned ("" = nothing new).
static func reveal(a: int, b: int, kind: String, detail: String = "") -> String:
	if a == b:
		return ""
	var k: Dictionary = _know(a, b)
	var got: String = ""
	match kind:
		"trait":
			var cand: Array = []
			for t in RelationshipBits.traits_of(b):
				if not (k["traits"] as Array).has(str(t)):
					cand.append(str(t))
			if not cand.is_empty():
				var pick: String = str(SysUtil.pick(cand))
				(k["traits"] as Array).append(pick)
				got = "trait:" + pick
		"career":
			if not bool(k["career"]):
				k["career"] = true
				got = "career"
		"aspiration":
			if not bool(k["aspiration"]):
				k["aspiration"] = true
				got = "aspiration"
		"interest":
			var ints: Array = Conversation.interests_of(b)
			var cand2: Array = []
			for t2 in ints:
				if not (k["interests"] as Array).has(str(t2)):
					cand2.append(str(t2))
			if not cand2.is_empty():
				var pick2: String = detail if cand2.has(detail) else str(SysUtil.pick(cand2))
				(k["interests"] as Array).append(pick2)
				got = "interest:" + pick2
		"all":
			for t3 in RelationshipBits.traits_of(b):
				if not (k["traits"] as Array).has(str(t3)):
					(k["traits"] as Array).append(str(t3))
			k["career"] = true
			k["aspiration"] = true
			for t4 in Conversation.interests_of(b):
				if not (k["interests"] as Array).has(str(t4)):
					(k["interests"] as Array).append(str(t4))
			got = "all"
	if got != "":
		SysUtil.game_event("knowledge_revealed", {"folk_id": a, "target_id": b, "what": got})
	return got

## UI summary of what `a` knows about `b`: unknown things are "?".
static func known_summary(a: int, b: int) -> Dictionary:
	var tl: Array = []
	for t in RelationshipBits.traits_of(b):
		var known: bool = knows_trait(a, b, str(t))
		tl.append({"id": str(t), "label": str(SimEnv.data().trait_def(str(t)).get("label", str(t).capitalize())) if known else "?", "known": known})
	var career: String = "?"
	if knows_career(a, b):
		career = Careers.title_of(b) if Careers.has_job(b) else "Unemployed"
		if career == "":
			career = "Unemployed"
	var asp: String = "?"
	if knows_aspiration(a, b):
		asp = Goals.aspiration_label(b)
		if asp == "":
			asp = "None yet"
	var ints: Array = []
	for t2 in Conversation.interests_of(b):
		if knows_interest(a, b, str(t2)):
			ints.append(Conversation.topic_label(str(t2)))
	var total: float = float(tl.size()) + 2.0
	var got: float = 0.0
	for e in tl:
		if bool(e["known"]):
			got += 1.0
	if career != "?":
		got += 1.0
	if asp != "?":
		got += 1.0
	return {"traits": tl, "career": career, "aspiration": asp, "interests": ints, "progress": got / maxf(total, 1.0), "everything": knows_everything(a, b)}

# ---- secrets / gossip / reputation
static func ensure_secrets(owner: int) -> Array:
	if RelationshipService.secrets.has(owner):
		return RelationshipService.secrets[owner]
	var pool: Array = RelationshipService.cfg().get("secrets", [])
	var list: Array = []
	if not pool.is_empty():
		var r := RandomNumberGenerator.new()
		r.seed = owner * 7919 + 13
		var tr: Array = RelationshipBits.traits_of(owner)
		var used: Array = []
		for n in 2:
			var items: Array = []
			var weights: Array = []
			for i in pool.size():
				if used.has(i):
					continue
				var w: float = 1.0
				for t in pool[i].get("traits", []):
					if tr.has(str(t)):
						w += 3.0
				items.append(i)
				weights.append(w)
			var total: float = 0.0
			for w2 in weights:
				total += float(w2)
			var roll: float = r.randf() * total
			var chosen: int = int(items[items.size() - 1])
			for j in items.size():
				roll -= float(weights[j])
				if roll <= 0.0:
					chosen = int(items[j])
					break
			used.append(chosen)
			var sd: Dictionary = pool[chosen]
			list.append({"id": n, "kind": str(sd["kind"]), "text": str(sd["text"]), "severity": float(sd.get("severity", 0.4)), "known_by": []})
	RelationshipService.secrets[owner] = list
	return list

## A secret of `owner` that `to_id` does not know yet ({} if none).
static func secret_for_sharing(owner: int, to_id: int) -> Dictionary:
	for s in ensure_secrets(owner):
		if not (s["known_by"] as Array).has(to_id):
			return s
	return {}

static func knows_secret(learner: int, owner: int, sid: int) -> bool:
	for s in ensure_secrets(owner):
		if int(s["id"]) == sid:
			return (s["known_by"] as Array).has(learner)
	return false

static func secrets_known_by(learner: int) -> Array:
	var out: Array = []
	for owner in RelationshipService.secrets:
		for s in RelationshipService.secrets[owner]:
			if (s["known_by"] as Array).has(learner):
				out.append({"owner": int(owner), "text": str(s["text"]), "kind": str(s["kind"]), "id": int(s["id"])})
	return out

static func learn_secret(learner: int, owner: int, sid: int) -> void:
	for s in ensure_secrets(owner):
		if int(s["id"]) == sid and not (s["known_by"] as Array).has(learner):
			(s["known_by"] as Array).append(learner)
			add_gossip(learner, owner, "%s %s" % [SysUtil.folk_name(owner), str(s["text"])], "secret", sid)
			SysUtil.game_event("secret_learned", {"folk_id": learner, "target_id": owner, "secret": sid})
			return

static func add_gossip(holder: int, about: int, text: String, kind: String, sid: int = -1, other: int = -1) -> void:
	if holder == about:
		return
	var list: Array = RelationshipService.gossip_items.get(holder, [])
	for it in list:
		if int(it["about"]) == about and str(it["text"]) == text:
			return
	list.append({"about": about, "other": other, "text": text, "kind": kind, "sid": sid, "day": SysUtil.day(), "told": []})
	var mx: int = int(RelationshipService.cfg().get("gossip", {}).get("max_items", 6))
	while list.size() > mx:
		list.pop_front()
	RelationshipService.gossip_items[holder] = list

static func gossip_for(holder: int) -> Array:
	return RelationshipService.gossip_items.get(holder, [])

static func reputation(id: int) -> float:
	return float(RelationshipService.reputation_map.get(id, 0.0))

static func add_reputation(id: int, delta: float) -> void:
	var rc: Dictionary = RelationshipService.cfg().get("reputation", {})
	RelationshipService.reputation_map[id] = clampf(reputation(id) + delta, float(rc.get("min", -100)), float(rc.get("max", 100)))

# ---- conversation topic counters
static func topic_count(a: int, b: int, topic: String) -> float:
	var p: Dictionary = RelationshipService._pair(a, b, false)
	if p.is_empty():
		return 0.0
	return float((p.get("topics", {}) as Dictionary).get(topic, 0.0))

static func note_topic(a: int, b: int, topic: String) -> void:
	if topic == "":
		return
	var p: Dictionary = RelationshipService._pair(a, b)
	var tc: Dictionary = RelationshipRomance._sub(p, "topics", {})
	tc[topic] = minf(float(tc.get(topic, 0.0)) + 1.0, float(RelationshipService.cfg().get("topic_rules", {}).get("max_count", 8)))

## Test helper: forget the topic counters of a pair.
static func pair_reset_topics_for_test(a: int, b: int) -> void:
	var p: Dictionary = RelationshipService._pair(a, b, false)
	if not p.is_empty():
		p["topics"] = {}

# ---- shared-history snippets for the UI
static func history_snippets(a: int, b: int, n: int = 3) -> Array:
	var out: Array = []
	var h: Array = RelationshipService.history_for(a, b)
	for i in range(h.size() - 1, maxi(h.size() - 1 - n, -1), -1):
		var ev: Dictionary = h[i]
		var who: String = "You" if int(ev["by"]) == a else SysUtil.folk_name(int(ev["by"]))
		var what: String = str(SimEnv.data().interaction_def(str(ev["kind"])).get("label", str(ev["kind"]).replace("_", " ").capitalize()))
		var lab: String = str(ev.get("label", ""))
		out.append("Day %d: %s - %s%s" % [int(ev["day"]), who, what, (" (" + lab + ")") if lab != "" else ""])
	return out
