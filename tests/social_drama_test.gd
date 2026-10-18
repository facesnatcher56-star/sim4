extends RefCounted
## Social drama: secrets & gossip (and backfire), arguments -> reconciliation, grudges, the romance arc, cheating / jealousy,
## and personality (opposite traits argue more, compatible ones bond more).

const S = preload("res://tests/social_kit.gd")

func run() -> Array:
	var f: Array = []
	_secrets_and_gossip(f)
	_gossip_backfire(f)
	_arguments(f)
	_traits_drive_arguments_and_bonding(f)
	_romance_arc(f)
	_cheating_and_jealousy(f)
	_trait_decisions(f)
	return f

# ------------------------------------------------------------------ secrets / gossip
func _secrets_and_gossip(f: Array) -> void:
	var w := S.setup(101)
	var a := S.folk(w, "Ann", ["gossip"])
	var b := S.folk(w, "Bo", ["social"])
	var c := S.folk(w, "Cy", ["shy"])
	RelationshipService.add_both(a.id, b.id, "friendship", 60.0)
	RelationshipService.add_both(a.id, b.id, "trust", 40.0)
	RelationshipService.add_both(b.id, c.id, "friendship", 40.0)
	RelationshipService.add_both(a.id, c.id, "friendship", 40.0)
	S.expect(f, RelationshipKnowledge.ensure_secrets(c.id).size() == 2, "every folk has secrets")
	var sec: Dictionary = RelationshipKnowledge.secret_for_sharing(c.id, a.id)
	S.expect(f, not sec.is_empty(), "there is a secret to share")
	# Cy confides in Ann: trust up, Ann now knows the secret and holds gossip about Cy
	RelationshipService.add_both(c.id, a.id, "trust", 30.0)
	var t0: float = RelationshipRomance.trust(a.id, c.id)
	var shared := false
	for i in 12:
		var ir := S.run(c, a, "share_secret")
		if RelationshipKnowledge.knows_secret(a.id, c.id, int(sec["id"])):
			shared = true
			break
	S.expect(f, shared, "sharing a secret lets the listener learn it")
	S.expect(f, RelationshipRomance.trust(a.id, c.id) > t0, "confiding raised trust (%.1f -> %.1f)" % [t0, RelationshipRomance.trust(a.id, c.id)])
	S.expect(f, RelationshipKnowledge.gossip_for(a.id).size() >= 1, "listener now holds gossip about Cy")
	SocialGatherings.refresh_markers(a)
	S.expect(f, a.has_buff("has_gossip"), "has_gossip marker unlocks the gossip interaction")
	# Ann gossips to Bo: Bo learns it, Bo's view of Cy and Cy's reputation drop
	var fr_before: float = b.get_rel(c.id, "friendship")
	var rep_before: float = RelationshipKnowledge.reputation(c.id)
	var gossiped := false
	for i in 12:
		var ir2 := S.run(a, b, "gossip")
		if RelationshipKnowledge.knows_secret(b.id, c.id, int(sec["id"])):
			gossiped = true
			break
	S.expect(f, gossiped, "gossip spreads the secret to a third party")
	S.expect(f, b.get_rel(c.id, "friendship") < fr_before, "gossip lowers the listener's opinion of the subject")
	S.expect(f, RelationshipKnowledge.reputation(c.id) < rep_before, "the subject's reputation drops (%.1f -> %.1f)" % [rep_before, RelationshipKnowledge.reputation(c.id)])
	S.expect(f, SocialDynamics.stats["gossip"] >= 1, "gossip is counted")
	# the gossip chain goes on: Bo can pass it to someone else
	S.expect(f, RelationshipKnowledge.gossip_for(b.id).size() >= 1, "the listener can pass it on")
	# witnessed romance becomes gossip
	var d := S.folk(w, "Di", [], Vector2i(13, 12))
	var e := S.folk(w, "Ed", [], Vector2i(12, 12))
	var g := S.folk(w, "Gus", [], Vector2i(12, 13))
	RelationshipService.add_both(d.id, e.id, "friendship", 40.0)
	RelationshipService.add_both(d.id, e.id, "romance", 50.0)
	var seen := false
	for i in 20:
		S.run(d, e, "kiss")
		if RelationshipKnowledge.gossip_for(g.id).size() > 0:
			seen = true
			break
	S.expect(f, seen, "bystanders pick up gossip about what they witness")
	S.teardown()

func _gossip_backfire(f: Array) -> void:
	var w := S.setup(111)
	var backfires := 0
	var trust_losses := 0
	for i in 40:
		var a := S.folk(w, "Gs%d" % i, ["gossip"])
		var b := S.folk(w, "Li%d" % i, ["honest"])
		var c := S.folk(w, "Su%d" % i)
		RelationshipService.add_both(a.id, b.id, "friendship", 60.0)
		RelationshipService.add_both(b.id, c.id, "friendship", 60.0)
		RelationshipService.add_both(a.id, c.id, "trust", 30.0)
		RelationshipKnowledge.add_gossip(a.id, c.id, "Su is hiding something", "observed")
		var tr0: float = RelationshipRomance.trust(c.id, a.id)
		var n0: int = int(SocialDynamics.stats["backfires"])
		SocialActions._gossip(a.id, b.id, "good", false, 1.0)
		if int(SocialDynamics.stats["backfires"]) > n0:
			backfires += 1
			if RelationshipRomance.trust(c.id, a.id) < tr0 - 20.0 and RelationshipRomance.tension(c.id, a.id) > 15.0 and RelationshipKnowledge.reputation(a.id) < 0.0:
				trust_losses += 1
			S.expect(f, a.has_buff("guilty_pang"), "a caught gossip feels guilty")
	S.expect(f, backfires > 3 and backfires < 38, "gossip can backfire, but not always (%d/40)" % backfires)
	S.expect(f, trust_losses == backfires, "a backfire costs the gossiper trust, causes tension and hurts their reputation (%d/%d)" % [trust_losses, backfires])
	# honest listeners disapprove: trust in the gossiper drops
	var a2 := S.folk(w, "G2", ["gossip"])
	var b2 := S.folk(w, "H2", ["honest"])
	var c2 := S.folk(w, "S2")
	RelationshipKnowledge.add_gossip(a2.id, c2.id, "S2 did something", "observed")
	RelationshipService.add_value(b2.id, a2.id, "trust", 20.0)
	var t_before: float = RelationshipRomance.trust(b2.id, a2.id)
	SocialActions._gossip(a2.id, b2.id, "good", false, 1.0)
	S.expect(f, RelationshipRomance.trust(b2.id, a2.id) < t_before, "honest listeners trust gossipers less")
	# honest folk refuse to gossip / rumor-monger on their own
	var autonomy_blocked: bool = Autonomy.refuses(b2, "gossip", SimEnv.data().interaction_def("gossip"), null)
	S.expect(f, autonomy_blocked, "honest folk refuse gossip (trait decision)")
	S.teardown()

# ------------------------------------------------------------------ arguments
func _arguments(f: Array) -> void:
	var w := S.setup(121)
	var a := S.folk(w, "Ann", ["hot_headed"])
	var b := S.folk(w, "Bo", [])
	RelationshipService.add_both(a.id, b.id, "friendship", 40.0)
	RelationshipService.add_both(a.id, b.id, "trust", 30.0)
	S.set_time(1, 12)
	var fr0: float = b.get_rel(a.id, "friendship")
	S.run(a, b, "argue")
	S.expect(f, RelationshipRomance.tension(b.id, a.id) > 10.0 and RelationshipRomance.tension(a.id, b.id) > 5.0, "arguments create tension on both sides")
	S.expect(f, b.get_rel(a.id, "friendship") < fr0, "arguments cost friendship")
	S.expect(f, SocialDynamics.stats["arguments"] >= 1, "argument counted")
	# escalation: arguing again inside the window escalates
	var lvl1: int = SocialConflict.arg_level(a.id, b.id)
	S.run(a, b, "argue")
	var lvl2: int = SocialConflict.arg_level(a.id, b.id)
	S.expect(f, lvl2 > lvl1, "a second argument escalates (%d -> %d)" % [lvl1, lvl2])
	S.run(a, b, "argue")
	S.expect(f, S.K.count_events("argument") >= 3, "argument events are emitted")
	S.expect(f, a.has_buff("furious") or a.has_buff("fuming"), "a screaming match leaves anger behind")
	S.expect(f, S.K.has_note("screaming"), "the screaming match is announced")
	# avoidance: tension makes the other less likely to seek them (memory bias)
	S.expect(f, b.memory_bias("folk:%d" % a.id) < 0.0, "tension feeds avoidance via Folk.memory_bias")
	# the angry mood unlocks yelling and storming off
	a.add_buff("furious")
	a.refresh_mood()
	S.expect(f, a.get_mood()["mood"] == "angry", "furious folk are angry")
	var reason_y: String = SocialScoring.reason_unavailable(a, b, "yell_at")
	S.expect(f, reason_y == "", "angry folk may yell (%s)" % reason_y)
	var calm := S.folk(w, "Cal", [])
	S.expect(f, SocialScoring.reason_unavailable(calm, b, "yell_at") != "", "calm folk cannot yell")
	# grudges last days: tension fades gradually
	var t0: float = RelationshipRomance.tension(b.id, a.id)
	S.expect(f, t0 > 25.0, "big fight leaves a lot of tension (%.0f)" % t0)
	S.set_time(2, 8)
	RelationshipService.on_day(2)
	var t1: float = RelationshipRomance.tension(b.id, a.id)
	S.expect(f, t1 < t0 and t1 > t0 - 12.0, "tension fades by days, not instantly (%.0f -> %.0f)" % [t0, t1])
	# reconcile: make_up + apologize + hug bring it back down, resolving the argument
	var resolved_before: int = S.K.count_events("argument_resolved")
	b.remove_buff("furious")
	var guard := 0
	while RelationshipRomance.tension(b.id, a.id) > 10.0 and guard < 30:
		S.run(a, b, "make_up")
		guard += 1
	S.expect(f, RelationshipRomance.tension(b.id, a.id) <= 10.0 and RelationshipRomance.tension(a.id, b.id) <= 10.0, "make_up eventually clears the tension (%d tries)" % guard)
	S.expect(f, S.K.count_events("argument_resolved") > resolved_before, "resolution is announced as an event")
	S.expect(f, S.K.has_note("made up"), "'made up' toast")
	S.expect(f, RelationshipRomance.trust(b.id, a.id) > 0.0, "making up restores some trust")
	# apology path
	var c := S.folk(w, "Cy")
	var d := S.folk(w, "Di")
	RelationshipService.add_both(c.id, d.id, "friendship", 30.0)
	SocialConflict.escalate(c.id, d.id, 30.0)
	S.expect(f, RelationshipRomance.tension(d.id, c.id) > 15.0, "an argument between Cy and Di")
	var tries := 0
	while RelationshipRomance.tension(d.id, c.id) > 10.0 and tries < 20:
		S.run(c, d, "heartfelt_apology")
		tries += 1
	S.expect(f, RelationshipRomance.tension(d.id, c.id) <= 10.0, "heartfelt apologies work too (%d tries)" % tries)
	# hugging soothes
	SocialConflict.escalate(c.id, d.id, 25.0)
	var th0: float = RelationshipRomance.tension(d.id, c.id)
	for i in 6:
		S.run(c, d, "hug")
	S.expect(f, RelationshipRomance.tension(d.id, c.id) < th0, "hugs soothe tension (%.0f -> %.0f)" % [th0, RelationshipRomance.tension(d.id, c.id)])
	# the sys apologize event also helps
	SocialConflict.escalate(c.id, d.id, 25.0)
	var ta: float = RelationshipRomance.tension(d.id, c.id)
	SysUtil.game_event("apologize", {"folk_id": c.id, "target_id": d.id})
	S.expect(f, RelationshipRomance.tension(d.id, c.id) < ta, "the classic apologize event reduces tension")
	S.teardown()

func _traits_drive_arguments_and_bonding(f: Array) -> void:
	var w := S.setup(131)
	var opposite := 0
	var matched := 0
	var gain_opp := 0.0
	var gain_match := 0.0
	var n := 120
	for i in n:
		var a := S.folk(w, "Oa%d" % i, ["neat", "jealous"])
		var b := S.folk(w, "Ob%d" % i, ["lazy", "charmer"])
		var c := S.folk(w, "Ma%d" % i, ["social", "optimist"])
		var d := S.folk(w, "Mb%d" % i, ["social", "easygoing"])
		var o0: int = int(SocialDynamics.stats["arguments"])
		var fo0: float = b.get_rel(a.id, "friendship")
		for round in 3:
			S.run(a, b, "chat")
			S.run(a, b, "funny_story")
			S.run(a, b, "get_to_know")
		opposite += int(SocialDynamics.stats["arguments"]) - o0
		gain_opp += b.get_rel(a.id, "friendship") - fo0
		var m0: int = int(SocialDynamics.stats["arguments"])
		var fm0: float = d.get_rel(c.id, "friendship")
		for round in 3:
			S.run(c, d, "chat")
			S.run(c, d, "funny_story")
			S.run(c, d, "get_to_know")
		matched += int(SocialDynamics.stats["arguments"]) - m0
		gain_match += d.get_rel(c.id, "friendship") - fm0
	S.expect(f, RelationshipBits.compatibility(S.folk(w, "x1", ["neat", "jealous"]).id, S.folk(w, "x2", ["lazy", "charmer"]).id) < -0.5, "opposite traits are incompatible")
	S.expect(f, opposite > matched * 2 + 3, "opposite traits cause far more arguments (%d vs %d over %d pairs)" % [opposite, matched, n])
	S.expect(f, gain_match > gain_opp * 1.4, "compatible pairs bond more (friendship %.0f vs %.0f)" % [gain_match, gain_opp])
	S.teardown()

# ------------------------------------------------------------------ romance
func _romance_arc(f: Array) -> void:
	var w := S.setup(141)
	var a := S.folk(w, "Rae", ["romantic", "charmer"])
	var b := S.folk(w, "Sol", ["romantic"])
	S.expect(f, RelationshipRomance.romance_stage(a.id, b.id) == "none", "stage: none")
	RelationshipService.add_both(a.id, b.id, "friendship", 35.0)
	a.add_rel(b.id, "romance", 25.0)
	S.expect(f, RelationshipRomance.romance_stage(a.id, b.id) == "crush", "stage: crush (one-sided or early)")
	# spark is stable, in range, and compatibility-driven
	var sp: float = RelationshipRomance.spark(a.id, b.id)
	S.expect(f, sp >= 0.0 and sp <= 1.0 and is_equal_approx(sp, RelationshipRomance.spark(b.id, a.id)), "spark is symmetric and in 0..1 (%.2f)" % sp)
	var sp_bad: float = RelationshipRomance.spark(S.folk(w, "x", ["hot_headed", "loner"]).id, S.folk(w, "y", ["lazy", "charmer"]).id)
	var good_sum := 0.0
	var bad_sum := 0.0
	for i in 30:
		good_sum += RelationshipRomance.spark(S.folk(w, "g1_%d" % i, ["romantic"]).id, S.folk(w, "g2_%d" % i, ["romantic", "charmer"]).id)
		bad_sum += RelationshipRomance.spark(S.folk(w, "b1_%d" % i, ["hot_headed", "loner"]).id, S.folk(w, "b2_%d" % i, ["lazy", "social"]).id)
	S.expect(f, good_sum > bad_sum, "compatible pairs have more spark on average (%.1f vs %.1f)" % [good_sum / 30.0, bad_sum / 30.0])
	# flirt until both feel it
	var guard := 0
	while RelationshipRomance.romance_stage(a.id, b.id) == "crush" and guard < 40:
		S.run(a, b, "wink")
		S.run(a, b, "flirt")
		S.run(b, a, "flirt")
		guard += 1
	S.expect(f, RelationshipRomance.romance_stage(a.id, b.id) in ["flirting", "dating", "sweethearts"], "stage: flirting once both are into it (%s)" % RelationshipRomance.romance_stage(a.id, b.id))
	# ask on a date
	RelationshipService.add_both(a.id, b.id, "friendship", 15.0)
	RelationshipService.add_both(a.id, b.id, "romance", 12.0)
	guard = 0
	while not RelationshipBits.has_flag(a.id, b.id, "dating") and RelationshipRomance.romance_stage(a.id, b.id) != "sweethearts" and guard < 40:
		S.run(a, b, "ask_out")
		guard += 1
	S.expect(f, RelationshipBits.has_flag(a.id, b.id, "dating") or RelationshipRomance.romance_stage(a.id, b.id) == "sweethearts", "ask_out can start dating (%d tries)" % guard)
	S.expect(f, S.K.has_note("dating") or RelationshipRomance.romance_stage(a.id, b.id) == "sweethearts", "dating is announced")
	if RelationshipBits.has_flag(a.id, b.id, "dating"):
		S.expect(f, a.get_rel(b.id, "bond") == 1.0 and b.get_rel(a.id, "bond") == 1.0 and RelationshipBits.bit_for(a.id, b.id) == "dating", "dating sets the bond track + bit")
		S.expect(f, a.has_buff("has_partner"), "dating marks both as attached")
	# go on dates (then official)
	var dates0: int = RelationshipRomance.dates_count(a.id, b.id)
	for i in 3:
		S.run(a, b, "go_on_date")
	S.expect(f, RelationshipRomance.dates_count(a.id, b.id) > dates0, "dates are counted (%d)" % RelationshipRomance.dates_count(a.id, b.id))
	RelationshipService.add_both(a.id, b.id, "romance", 30.0)
	RelationshipService.add_both(a.id, b.id, "friendship", 20.0)
	guard = 0
	while RelationshipRomance.romance_stage(a.id, b.id) == "dating" and guard < 30:
		S.run(a, b, "make_official")
		guard += 1
	S.expect(f, RelationshipRomance.romance_stage(a.id, b.id) in ["sweethearts", "partners"], "make_official -> sweethearts/partners (%s)" % RelationshipRomance.romance_stage(a.id, b.id))
	S.expect(f, a.get_rel(b.id, "bond") >= 2.0, "bond track reflects the official status")
	# first kiss is an emotional memory
	guard = 0
	while not bool(RelationshipService._pair(a.id, b.id).get("first_kiss", false)) and guard < 30:
		S.run(a, b, "kiss")
		guard += 1
	S.expect(f, bool(RelationshipService._pair(a.id, b.id).get("first_kiss", false)), "first kiss happens")
	S.expect(f, Emotions.moments_of(a.id).size() > 0, "the first kiss is remembered as a moment")
	# breakup -> ex
	var broke := false
	for i in 10:
		S.run(a, b, "break_up")
		if RelationshipRomance.romance_stage(a.id, b.id) == "ex":
			broke = true
			break
	S.expect(f, broke, "break_up ends the relationship -> stage ex")
	S.expect(f, RelationshipBits.bit_for(a.id, b.id) == "ex" or RelationshipBits.has_flag(a.id, b.id, "ex"), "ex flag set")
	S.expect(f, a.get_rel(b.id, "romance") <= 5.0 and b.get_rel(a.id, "romance") <= 5.0, "romance collapses after a breakup")
	S.expect(f, a.get_rel(b.id, "ex") == 1.0, "ex track set")
	S.expect(f, not a.has_buff("has_partner") or not RelationshipRomance.exclusive_partners(a.id).has(b.id), "no longer attached")
	S.expect(f, S.K.has_note("broke up") and S.K.count_events("breakup") >= 1, "the breakup is announced")
	S.expect(f, b.has_buff("heartbroken") or a.has_buff("heartbroken") or a.has_buff("guilty_pang") or b.has_buff("guilty_pang"), "someone is hurting afterwards")
	# rekindle
	var back := false
	RelationshipService.add_both(a.id, b.id, "friendship", 40.0)
	for i in 30:
		S.run(a, b, "rekindle")
		if RelationshipBits.has_flag(a.id, b.id, "dating"):
			back = true
			break
	S.expect(f, back, "exes can rekindle (dating again)")
	# an ex fades after enough days
	RelationshipRomance.breakup(a.id, b.id, "breakup", 0.5)
	for d in range(2, 30):
		S.set_time(d, 8)
		SocialDynamics.on_day(d)
	S.expect(f, not RelationshipBits.has_flag(a.id, b.id, "ex"), "the ex status fades after weeks")
	S.teardown()

func _cheating_and_jealousy(f: Array) -> void:
	var w := S.setup(151)
	var a := S.folk(w, "Kit", ["romantic"], Vector2i(12, 12))
	var b := S.folk(w, "Lou", ["jealous"], Vector2i(13, 12))
	var c := S.folk(w, "Max", [], Vector2i(30, 30))      # far from the victim
	for p in [[a, b], [a, c]]:
		RelationshipService.add_both(p[0].id, p[1].id, "friendship", 50.0)
		RelationshipService.add_both(p[0].id, p[1].id, "romance", 55.0)
	RelationshipBits.set_flag(a.id, b.id, "partner", true, false)
	S.expect(f, RelationshipRomance.exclusive_partners(a.id) == [b.id], "Kit is partnered with Lou")
	# secret affair far away: undiscovered, but recorded
	a.tile = Vector2i(2, 2)
	var guard := 0
	while RelationshipService.affairs.is_empty() and guard < 20:
		S.run(a, c, "sneak_kiss")
		guard += 1
	S.expect(f, not RelationshipService.affairs.is_empty() or S.K.count_events("cheating_discovered") > 0, "a secret kiss with someone else is cheating (affair recorded)")
	S.expect(f, SocialDynamics.stats["cheats"] >= 1, "cheat counted")
	# it comes out eventually
	var found := S.K.count_events("cheating_discovered") > 0
	var rec_before: float = b.get_rel(a.id, "trust")
	for d in range(2, 80):
		if found:
			break
		S.set_time(d, 8)
		SocialDynamics.on_day(d)
		found = S.K.count_events("cheating_discovered") > 0
	S.expect(f, found, "affairs are discovered over time")
	S.expect(f, b.get_rel(a.id, "trust") < rec_before or b.get_rel(a.id, "trust") < 10.0, "the victim loses trust")
	S.expect(f, b.has_buff("cheated_on") or RelationshipRomance.romance_stage(a.id, b.id) == "ex", "betrayal or breakup follows")
	S.expect(f, a.has_buff("guilty_pang"), "the cheater feels guilty")
	S.expect(f, RelationshipKnowledge.reputation(a.id) < 0.0, "cheating hurts reputation")
	S.expect(f, S.K.has_note("cheating"), "cheating discovery toast")
	# witnessed cheating is immediate, and a jealous partner is more likely to leave
	S.teardown()
	var w2 := S.setup(152)
	var leaves := 0
	var stays := 0
	for i in 40:
		var v := S.folk(w2, "V%d" % i, ["jealous"], Vector2i(5, 5))
		var x := S.folk(w2, "X%d" % i, [], Vector2i(6, 5))
		var y := S.folk(w2, "Y%d" % i, [], Vector2i(7, 5))
		RelationshipService.add_both(v.id, x.id, "friendship", 60.0)
		RelationshipService.add_both(v.id, x.id, "romance", 70.0)
		RelationshipBits.set_flag(v.id, x.id, "partner", true, false)
		RelationshipService.add_both(x.id, y.id, "friendship", 40.0)
		RelationshipService.add_both(x.id, y.id, "romance", 40.0)
		SocialConflict.cheat_check(x.id, y.id)
		if RelationshipBits.has_flag(v.id, x.id, "ex"):
			leaves += 1
		else:
			stays += 1
		S.expect(f, v.has_buff("cheated_on"), "witnessed cheating is discovered at once")
		S.expect(f, v.has_buff("jealous_pang"), "jealous partners feel jealous")
	S.expect(f, leaves > 10 and stays > 3, "some jealous partners leave, some stay (%d/%d)" % [leaves, stays])
	# jealous trait amplifies the existing flirt-jealousy
	var p1 := S.folk(w2, "Pj", ["jealous"], Vector2i(5, 8))
	var p2 := S.folk(w2, "Pn", [], Vector2i(5, 9))
	var fl := S.folk(w2, "Fl", [], Vector2i(6, 8))
	var tg := S.folk(w2, "Tg", [], Vector2i(7, 8))
	for pr in [[p1, fl], [p2, fl]]:
		RelationshipService.add_both(pr[0].id, pr[1].id, "friendship", 60.0)
		RelationshipService.add_both(pr[0].id, pr[1].id, "romance", 60.0)
	RelationshipBits.set_flag(p1.id, fl.id, "partner", true, false)
	RelationshipService.add_both(fl.id, tg.id, "friendship", 40.0)
	var r_before: float = p1.get_rel(fl.id, "romance")
	S.run(fl, tg, "wink")
	var drop_jealous: float = r_before - p1.get_rel(fl.id, "romance")
	S.expect(f, drop_jealous >= 10.0, "even a wink makes a jealous partner lose romance (%.1f)" % drop_jealous)
	S.teardown()

# ------------------------------------------------------------------ personality
func _trait_decisions(f: Array) -> void:
	var w := S.setup(161)
	var shy := S.folk(w, "Shy", ["shy"])
	var gos := S.folk(w, "Gos", ["gossip"])
	var char := S.folk(w, "Chr", ["charmer"])
	var nrm := S.folk(w, "Nrm", [])
	var peace := S.folk(w, "Peace", ["forgiving"])
	var grudge := S.folk(w, "Grudge", ["grudgeholder"])
	var d_gossip: Dictionary = SimEnv.data().interaction_def("gossip")
	var d_flirt: Dictionary = SimEnv.data().interaction_def("wink")
	var d_group: Dictionary = SimEnv.data().interaction_def("group_chat")
	var base_g: float = _mult(nrm, "gossip", d_gossip)
	S.expect(f, _mult(gos, "gossip", d_gossip) > base_g * 2.0, "gossip trait loves gossiping")
	S.expect(f, _mult(char, "wink", d_flirt) > _mult(nrm, "wink", d_flirt) * 1.4, "charmers flirt more")
	S.expect(f, _mult(shy, "group_chat", d_group) < _mult(nrm, "group_chat", d_group) * 0.7, "shy folk avoid groups")
	var d_mu: Dictionary = SimEnv.data().interaction_def("make_up")
	S.expect(f, _mult(peace, "make_up", d_mu) > _mult(grudge, "make_up", d_mu) * 3.0, "forgiving folk reconcile far more than grudge-holders")
	# insults land harder on grudge-holders, softer on forgiving folk
	var x1 := S.folk(w, "X1")
	var x2 := S.folk(w, "X2")
	var x3 := S.folk(w, "X3")
	for tgt in [x1]:
		pass
	RelationshipService.add_both(x1.id, grudge.id, "friendship", 30.0)
	RelationshipService.add_both(x1.id, peace.id, "friendship", 30.0)
	var g0: float = grudge.get_rel(x1.id, "friendship")
	var p0: float = peace.get_rel(x1.id, "friendship")
	SocialDynamics._rel(x1.id, grudge.id, "friendship", -10.0)
	SocialDynamics._rel(x1.id, peace.id, "friendship", -10.0)
	S.expect(f, (g0 - grudge.get_rel(x1.id, "friendship")) > (p0 - peace.get_rel(x1.id, "friendship")) * 1.8, "grudge-holders take insults harder than forgiving folk")
	# grudges last: tension fades slower for grudge-holders
	SocialConflict.escalate(x1.id, grudge.id, 40.0)
	SocialConflict.escalate(x1.id, peace.id, 40.0)
	S.set_time(2, 8)
	SocialDynamics.on_day(2)
	S.expect(f, RelationshipRomance.tension(peace.id, x1.id) < RelationshipRomance.tension(grudge.id, x1.id) - 5.0, "forgiving folk let go faster")
	# traits have conflicts / affinities in data
	var td: Dictionary = SimEnv.data().traits()
	S.expect(f, (td["forgiving"]["conflicts"] as Array).has("grudgeholder") and (td["empath"]["affinities"] as Array).has("forgiving"), "trait conflicts/affinities are data")
	S.expect(f, RelationshipBits.compatibility(peace.id, S.folk(w, "Emp", ["empath"]).id) > 0.2, "affinities raise compatibility")
	S.expect(f, RelationshipBits.compatibility(peace.id, grudge.id) < -0.2, "conflicts lower compatibility")
	S.teardown()

## autonomy multiplier a folk would apply to `iid` (traits x buffs), via Autonomy.evaluate's sub-scores.
func _mult(fk: Folk, iid: String, d: Dictionary) -> float:
	var other: Folk = null
	for o in WorldIface.all_folk():
		if o.id != fk.id:
			other = o
			break
	var m := 1.0
	var tags := Autonomy.tags_of(d, null)
	var adv: Array = (d.get("advertises", {}) as Dictionary).keys()
	for td in fk.trait_defs():
		var tm: Dictionary = td.get("autonomy_mult", {})
		for key in tm:
			if Autonomy.token_matches(str(key), iid, tags, null, adv):
				m *= float(tm[key])
	return m
