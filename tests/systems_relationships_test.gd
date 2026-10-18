extends RefCounted
## Relationships: bits, history, grudges / warmth, compatibility, decay, jealousy, status upgrades, persistence.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_bits(f)
	_history_and_grudge(f)
	_compat_and_describe(f)
	_decay(f)
	_status_and_proposal(f)
	_jealousy(f)
	_offlot_persistence(f)
	_roundtrip(f)
	return f

func _bits(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann")
	var b := K.make_folk(w, "Bo")
	K.expect(f, RelationshipBits.bit_for(a.id, b.id) == "stranger", "strangers by default")
	a.add_rel(b.id, "friendship", 8.0)
	K.expect(f, RelationshipBits.bit_for(a.id, b.id) == "acquaintance", "friendship 8 -> acquaintance")
	a.add_rel(b.id, "friendship", 25.0)
	K.expect(f, RelationshipBits.bit_for(a.id, b.id) == "friend", "friendship 33 -> friend")
	K.expect(f, RelationshipBits.bit_for(b.id, a.id) == "acquaintance", "directional: Bo only knows Ann (acquaintance)")
	a.add_rel(b.id, "friendship", 40.0)
	K.expect(f, RelationshipBits.bit_for(a.id, b.id) == "best_friend", "73 -> best friend")
	K.expect(f, K.count_events("relationship_bit_changed") >= 3, "bit changes emit game events")
	a.add_rel(b.id, "friendship", -120.0)
	K.expect(f, RelationshipBits.bit_for(a.id, b.id) == "enemy", "-47 -> enemy")
	a.add_rel(b.id, "friendship", 50.0)
	a.add_rel(b.id, "romance", 30.0)
	K.expect(f, RelationshipBits.bit_for(a.id, b.id) == "crush", "romance 30 -> crush")
	RelationshipBits.set_flag(a.id, b.id, "family")
	K.expect(f, RelationshipBits.bit_for(a.id, b.id) == "family", "family flag wins")
	K.expect(f, RelationshipBits.count_bit(a.id, "family") == 1, "count_bit family")
	K.expect(f, SysCond.check([{"bit_count": ["family", 1]}], a), "SysCond bit_count")
	K.expect(f, not SysCond.check([{"friends_at_least": 1}], b), "Bo has no friends")
	K.teardown()

func _history_and_grudge(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann", ["hot_headed"])
	var b := K.make_folk(w, "Bo")
	var c := K.make_folk(w, "Cy")
	var d := K.make_folk(w, "Di")
	# Ann insults Bo through the real Loot / event pipeline
	_social(a, b, "insult")
	_social(a, b, "insult")
	var h: Array = RelationshipService.history_for(a.id, b.id)
	K.expect(f, h.size() == 2 and h[0]["kind"] == "insult" and float(h[0]["sentiment"]) < 0.0, "insults are logged with negative sentiment")
	K.expect(f, int(h[0]["day"]) == 1, "history entries carry the day")
	var grudge: float = RelationshipService.grudge(b.id, a.id)
	K.expect(f, grudge > 0.4, "Bo holds a grudge against Ann (%.2f)" % grudge)
	K.expect(f, b.memory_bias("folk:%d" % a.id) < 0.0, "grudge feeds autonomy memory (negative bias)")
	K.expect(f, K.count_events("social_done") == 2, "social_done events emitted")
	# the same friendly chat lands worse when there is a grudge
	var base_gain: float = _gain(c, d, "chat")
	var grudge_gain: float = _gain(b, a, "chat")
	K.expect(f, grudge_gain < base_gain, "chat with a grudge gains less (%.2f < %.2f)" % [grudge_gain, base_gain])
	# warmth: helping builds goodwill
	var e := K.make_folk(w, "Ed")
	var g := K.make_folk(w, "Gi")
	for i in 4:
		_social(e, g, "compliment")
	K.expect(f, RelationshipService.warmth(g.id, e.id) > 0.3, "compliments build warmth")
	var warm_gain: float = _gain(e, g, "chat")
	K.expect(f, warm_gain > base_gain, "chat after warmth gains more (%.2f > %.2f)" % [warm_gain, base_gain])
	# apologizing relieves the grudge
	var before: float = RelationshipService.grudge(b.id, a.id)
	RelationshipService.on_apologize(a.id, b.id)
	K.expect(f, RelationshipService.grudge(b.id, a.id) < before, "apology softens the grudge")
	K.expect(f, RelationshipService.history_for(a.id, b.id).back()["kind"] == "apologize", "apology is in the history")
	# history is capped at 30 and old events fade
	for i in 40:
		RelationshipService.add_history(a.id, b.id, "chat", 0.3)
	K.expect(f, RelationshipService.history_for(a.id, b.id).size() == 30, "history keeps the last 30 events")
	K.set_time(120, 8)
	K.expect(f, RelationshipService.warmth(a.id, b.id) < 0.05, "old events fade away")
	K.teardown()

## Run one social interaction through the real event pipeline: start event, loot, finish event.
func _social(actor: Folk, target: Folk, iid: String) -> void:
	var ev = SimEnv.events()
	ev.emit_signal("interaction_started", actor.id, iid, target.id)
	var d: Dictionary = SimEnv.data().interaction_def(iid)
	Loot.apply(d.get("on_finish", []), {"folk": actor, "object": null, "target": target})
	ev.emit_signal("interaction_finished", actor.id, iid, true)

func _gain(actor: Folk, target: Folk, iid: String) -> float:
	var before: float = target.get_rel(actor.id, "friendship")
	_social(actor, target, iid)
	return target.get_rel(actor.id, "friendship") - before

func _compat_and_describe(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann", ["social", "romantic"])
	var b := K.make_folk(w, "Bo", ["social", "romantic"])
	var c := K.make_folk(w, "Cy", ["loner", "lazy"])
	K.expect(f, RelationshipBits.compatibility(a.id, b.id) > 0.5, "similar social romantics click (%.2f)" % RelationshipBits.compatibility(a.id, b.id))
	K.expect(f, RelationshipBits.compatibility(a.id, c.id) < 0.0, "social vs loner clash (%.2f)" % RelationshipBits.compatibility(a.id, c.id))
	K.expect(f, abs(RelationshipBits.compatibility(a.id, c.id) - RelationshipBits.compatibility(c.id, a.id)) < 0.001, "compatibility is symmetric")
	# compatible pairs get more out of the same chat
	var g_good: float = _gain(a, b, "chat")
	var g_bad: float = _gain(a, c, "chat")
	K.expect(f, g_good > g_bad, "compatible pair gains more from chat (%.2f vs %.2f)" % [g_good, g_bad])
	var txt: String = RelationshipBits.describe(a.id, b.id)
	K.expect(f, txt.find("Ann") >= 0 and txt.find("Bo") >= 0 and txt.find("chat") >= 0, "describe mentions names and history: %s" % txt)
	K.expect(f, RelationshipBits.bit_label("best_friend") == "Best Friend", "bit labels come from data")
	K.teardown()

func _decay(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann")
	var b := K.make_folk(w, "Bo")
	var c := K.make_folk(w, "Cy")
	a.add_rel(b.id, "friendship", 50.0)
	b.add_rel(a.id, "friendship", 50.0)
	a.add_rel(c.id, "friendship", 50.0)
	c.add_rel(a.id, "friendship", 50.0)
	RelationshipBits.set_flag(a.id, c.id, "family")
	for d in range(2, 12):
		K.set_time(d, 8)
		RelationshipService.on_day(d)
	var v: float = a.get_rel(b.id, "friendship")
	K.expect(f, v < 50.0 and v > 30.0, "unused friendships fade slowly (%.1f)" % v)
	K.expect(f, a.get_rel(c.id, "friendship") > v, "family fades slower (%.1f > %.1f)" % [a.get_rel(c.id, "friendship"), v])
	# contact resets the idle timer
	RelationshipService.touch(a.id, b.id)
	var v2: float = a.get_rel(b.id, "friendship")
	RelationshipService.on_day(12)
	K.expect(f, a.get_rel(b.id, "friendship") == v2, "recent contact stops decay")
	K.teardown()

func _status_and_proposal(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann")
	var b := K.make_folk(w, "Bo")
	for dir in [[a, b], [b, a]]:
		(dir[0] as Folk).add_rel((dir[1] as Folk).id, "friendship", 40.0)
		(dir[0] as Folk).add_rel((dir[1] as Folk).id, "romance", 50.0)
	_social(a, b, "chat")
	K.expect(f, RelationshipBits.bit_for(a.id, b.id) == "sweetheart", "mutual romance upgrades to sweethearts, got %s" % RelationshipBits.bit_for(a.id, b.id))
	K.expect(f, K.has_note("sweethearts"), "announcement for the new couple")
	for dir in [[a, b], [b, a]]:
		(dir[0] as Folk).add_rel((dir[1] as Folk).id, "friendship", 30.0)
		(dir[0] as Folk).add_rel((dir[1] as Folk).id, "romance", 30.0)
	K.set_time(8, 8)
	RelationshipService.on_day(8)
	K.expect(f, RelationshipBits.bit_for(a.id, b.id) == "partner", "long-time sweethearts become partners, got %s" % RelationshipBits.bit_for(a.id, b.id))
	for dir in [[a, b], [b, a]]:
		(dir[0] as Folk).add_rel((dir[1] as Folk).id, "friendship", 30.0)
		(dir[0] as Folk).add_rel((dir[1] as Folk).id, "romance", 30.0)
	K.expect(f, RelationshipBits.propose(a.id, b.id) == "accepted" and RelationshipBits.bit_for(a.id, b.id) == "spouse", "proposal to a partner with high romance -> spouse")
	var c := K.make_folk(w, "Cy")
	K.expect(f, RelationshipBits.propose(a.id, c.id) == "no_bond", "proposing to a stranger fails")
	K.teardown()

func _jealousy(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann", ["romantic"], 1, Vector2i(12, 12))
	var b := K.make_folk(w, "Bo", ["hot_headed"], 1, Vector2i(13, 12))
	var c := K.make_folk(w, "Cy", [], 1, Vector2i(14, 12))
	a.add_rel(c.id, "friendship", 40.0)
	RelationshipService.add_both(a.id, b.id, "friendship", 60.0)
	RelationshipService.add_both(a.id, b.id, "romance", 60.0)
	RelationshipBits.set_flag(a.id, b.id, "partner")
	var rom_before: float = b.get_rel(a.id, "romance")
	_social(a, c, "flirt")
	K.expect(f, b.get_rel(a.id, "romance") < rom_before, "partner loses romance towards the flirt")
	K.expect(f, b.has_buff("furious"), "hot-headed partner is furious")
	K.expect(f, K.count_events("jealousy") == 1 and K.has_note("jealous"), "jealousy announced")
	var kinds: Array = []
	for ev in RelationshipService.history_for(a.id, b.id):
		kinds.append(ev["kind"])
	K.expect(f, kinds.has("jealous"), "jealousy enters the shared history")
	# flirting with the partner is fine
	var count: int = K.count_events("jealousy")
	_social(a, b, "flirt")
	K.expect(f, K.count_events("jealousy") == count, "flirting with your own partner is not jealousy")
	K.teardown()

func _offlot_persistence(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann")
	var v := Folk.create("Vee", ["social"], 1500)
	v.household_id = -1
	w.add_folk(v, Vector2i(5, 5))
	RelationshipService.add_both(a.id, v.id, "friendship", 35.0)
	K.expect(f, RelationshipBits.bit_for(a.id, v.id) == "friend", "Ann and the visitor became friends")
	RelationshipService.sync_folk(v)
	SysUtil.world_remove_folk(v.id)
	K.expect(f, w.get_folk(1500) == null, "visitor left the world")
	K.expect(f, RelationshipService.value(v.id, a.id, "friendship") == 35.0, "the store remembers an off-lot folk's feelings")
	K.expect(f, RelationshipBits.bit_for(v.id, a.id) == "friend", "bit_for works for off-lot folk")
	RelationshipService.add_value(v.id, a.id, "friendship", 10.0)
	var v2 := Folk.create("Vee", ["social"], 1500)
	w.add_folk(v2, Vector2i(5, 5))
	RelationshipService.restore_folk(v2)
	K.expect(f, v2.get_rel(a.id, "friendship") == 45.0, "restored folk gets its relationships back (%.1f)" % v2.get_rel(a.id, "friendship"))
	K.teardown()

func _roundtrip(f: Array) -> void:
	var w := K.setup()
	var a := K.make_folk(w, "Ann")
	var b := K.make_folk(w, "Bo")
	_social(a, b, "insult")
	_social(a, b, "chat")
	RelationshipBits.set_flag(a.id, b.id, "family")
	var d1: Dictionary = RelationshipService.to_dict()
	var parsed: Variant = JSON.parse_string(JSON.stringify(d1))
	RelationshipService.from_dict(parsed)
	var diffs: Array = []
	K.expect(f, K.deep_eq(d1, RelationshipService.to_dict(), "rel", diffs), "relationship roundtrip: %s" % str(diffs.slice(0, 5)))
	K.expect(f, RelationshipBits.bit_for(a.id, b.id) == "family", "flags survive a roundtrip")
	K.expect(f, RelationshipService.history_for(a.id, b.id).size() == 2, "history survives a roundtrip")
	K.teardown()
