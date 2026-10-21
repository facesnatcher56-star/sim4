class_name SocialReaction
extends RefCounted
## Task 52: the world reacts to what the player's person does to someone, when it does not fit what the two have between them (SocialFit.gap). data/reactions.json holds the
## groups of acts and the reactions with their weights. A close fit often works anyway (the usual scored outcome runs); the further out of place, the more likely a real
## reaction: a laugh, a brush-off, a shove, a slap, a scene, a police complaint. The reaction is the consequence: a relationship hit, a buff, onlookers who gossip and think
## less of you, and sometimes a real harassment case through the justice code. Lines never repeat for the same pair twice in a row.
##   SocialReaction.passes(gap)   does the act work as it would have (rolled)?      SocialReaction.react(a, t, iid, d, gap)  -> a resolve() style result, or {} when no group fits

static func cfg() -> Dictionary:
	return SysUtil.table("reactions")

static func min_gap() -> float:
	return float(cfg().get("min_gap", 0.3))

## The chance the act simply works falls smoothly with the gap.
static func passes(gap: float) -> bool:
	if gap < min_gap():
		return true
	return SysUtil.rng.randf() < pow(clampf(1.0 - gap, 0.03, 1.0), float(cfg().get("success_pow", 1.4)))

static func group_of(iid: String) -> String:
	var groups: Dictionary = cfg().get("groups", {})
	for g in groups:
		if ((groups[g] as Dictionary).get("ids", []) as Array).has(iid):
			return str(g)
	return ""

static func _mood(f) -> String:
	return str(f.get_mood().get("mood", "")) if f != null else ""

static func _weight(o: Dictionary, t, gap: float, partner: bool, place: String) -> float:
	if gap < float(o.get("gap_min", 0.0)):
		return 0.0
	var w: float = float(o.get("weight", 0.1))
	w *= (0.4 + gap) if str(o.get("gap_scale", "up")) == "up" else maxf(1.2 - gap, 0.05)
	var tid: int = int(t.id)
	for tr in (o.get("traits", {}) as Dictionary):
		if SocialDynamics.has_t(tid, str(tr)):
			w *= float((o["traits"] as Dictionary)[tr])
	var m: String = _mood(t)
	if (o.get("moods", {}) as Dictionary).has(m):
		w *= float((o["moods"] as Dictionary)[m])
	if (o.get("places", {}) as Dictionary).has(place):
		w *= float((o["places"] as Dictionary)[place])
	if partner and o.has("partner"):
		w *= float(o["partner"])
	return w

static func react(a, t, iid: String, d: Dictionary, gap: float) -> Dictionary:
	var g: String = group_of(iid)
	if g == "" or a == null or t == null:
		return {}
	var outs: Array = ((cfg().get("groups", {}) as Dictionary)[g] as Dictionary).get("outcomes", [])
	var partner: bool = t.has_buff("has_partner")
	var place: String = Venues.type_of_lot(Neighborhood.lot_of(a)) if Neighborhood.lot_of(a) != "" else "street"
	var weights: Array = outs.map(func(o): return _weight(o, t, gap, partner, place))
	var pick = SysUtil.pick_weighted(outs, weights)
	if pick == null:
		return {}
	return _apply(a, t, iid, d, g, pick, gap)

static func _apply(a, t, iid: String, d: Dictionary, group: String, o: Dictionary, gap: float) -> Dictionary:
	var aid: int = int(a.id)
	var tid: int = int(t.id)
	# --- the line: names and the other person's pronouns, never the same twice in a row for this pair
	var lines: Array = o.get("lines", [""])
	var key: String = "react|%s|%s|%s" % [group, str(o["id"]), SysUtil.pair_key(aid, tid)]
	var line: String = str(lines[PlayerPrompt._pick(key, lines.size())])
	line = line.replace("{t}", str(t.name)).replace("{a}", str(a.name))
	line = Sexes.fill(line, tid)
	# --- what it does to the relationship (the other person's view in full, the player's person feels it a little)
	for track in [["fr", "friendship"], ["ro", "romance"], ["tr", "trust"], ["te", "tension"]]:
		var dv: float = float(o.get(track[0], 0.0))
		if dv != 0.0:
			RelationshipService.add_value(tid, aid, str(track[1]), dv)
			RelationshipService.add_value(aid, tid, str(track[1]), dv * 0.4)
	if o.has("abuf"):
		a.add_buff(str(o["abuf"]))
	if o.has("tbuf"):
		t.add_buff(str(o["tbuf"]))
	SimEnv.emit("speech", tid, line, aid)
	if SocialFit.player_controlled(a) or SocialFit.player_controlled(t):
		SysUtil.notify(line, "story")
	LifeLedger.add("reaction", line, [aid, tid], false, 2)
	if float(o.get("witness", 0.0)) > 0.0:
		_witnessed(a, t, line, float(o["witness"]))
	if str(o.get("act", "")) == "report":
		_report(a, t, line)
	var tier: String = str(o.get("tier", "bad"))
	return {"tier": tier, "label": str(o["id"]).capitalize().replace("_", " "), "score": snappedf(1.0 - gap, 0.001), "mode": "full", "topic": "", "cat": str(d.get("category", "")),
		"sentiment": -0.5 if tier == "bad" else (0.4 if tier == "good" else 0.0), "interaction": iid, "actor": aid, "target": tid, "parts": {"gap": gap, "reaction": str(o["id"])},
		"fr": float(o.get("fr", 0.0)), "ro": float(o.get("ro", 0.0)), "tr": float(o.get("tr", 0.0)), "te": float(o.get("te", 0.0)), "reaction": str(o["id"])}

## People who saw it think less of the one who caused a scene, and some of them talk.
static func _witnessed(a, t, line: String, rep: float) -> void:
	var seen: int = 0
	for f in WorldIface.all_folk():
		if int(f.id) == int(a.id) or int(f.id) == int(t.id) or SysUtil.is_away(f):
			continue
		if Vector2(f.tile - a.tile).length() > 9.0:
			continue
		seen += 1
		if SysUtil.rng.randf() < 0.6:
			RelationshipKnowledge.add_gossip(int(f.id), int(a.id), "%s made a scene with %s: %s" % [a.name, t.name, line], "observed", -1, int(t.id))
		if seen >= 4:
			break
	RelationshipKnowledge.add_reputation(int(a.id), -rep * (1.0 + 0.3 * float(seen)))

## The other person goes to the police: a real harassment case through the justice code (a complaint, the scene, the witnesses), not an automatic charge.
static func _report(a, t, line: String) -> void:
	if not JusticeState.enabled:
		return
	var c: Dictionary = CaseStore.create("harassment", int(a.id), int(t.id), CrimePlace.where_now(int(t.id)), {"witnessed": true, "witnesses": [int(t.id)], "witness_clarity": 0.9, "trace": 0.5})
	CaseDiscovery.report(c, int(t.id), "victim")
	CaseStore.note(c, "%s reported %s for unwanted advances." % [t.name, a.name], "harassment", 2)
	if SocialFit.player_controlled(a):
		SysUtil.notify("%s has gone to the police about you." % t.name, "bad")
