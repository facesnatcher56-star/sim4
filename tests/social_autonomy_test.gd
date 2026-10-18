extends RefCounted
## Autonomous social life over a 3-day run: every folk socializes a sensible amount (not zero, not constant), the mix of socials is varied,
## loneliness drives initiative, relationship goals (reconcile / make friends) steer targets, and spam is rate limited.

const S = preload("res://tests/social_kit.gd")

var report: Array = []

func run() -> Array:
	var f: Array = []
	_three_day_balance(f)
	_goals_and_loneliness(f)
	for line in report:
		print("  " + str(line))
	return f

func _social_def(iid: String) -> bool:
	return str(SimEnv.data().interaction_def(iid).get("target", "")) == "folk"

func _three_day_balance(f: Array) -> void:
	var w := S.setup(401)
	S.K.mgr.autosave_enabled = false
	S.K.mgr.enabled = true
	S.furnish_for_test(w)
	var names := [["Alice", ["neat", "social"]], ["Bob", ["lazy", "gamer"]], ["Cara", ["creative", "active", "romantic"]], ["Dev", ["hot_headed", "loner"]]]
	var folks: Array = []
	for i in names.size():
		var fk := S.folk(w, names[i][0], names[i][1], Vector2i(11 + i, 12))
		folks.append(fk)
		Goals.ensure_profile(fk)
	var dir = S.director()
	S.set_time(1, 7)
	var counts: Dictionary = {}
	var kinds: Dictionary = {}
	var per_hour: Dictionary = {}
	var seen_interaction: Dictionary = {}
	var total_min := 3 * 1440
	for m in total_min:
		SimEnv.clock().advance_minutes(1)
		dir.tick_minute(1)
		# The loner's social need drains so slowly (and the others keep chatting to him) that he is rarely lonely enough to start a
		# talk himself, so a count of 0..1 says nothing about autonomy. Make him lonely every evening (17:00) and check he then picks socials.
		if m % 1440 == 600:
			var dev = folks[3]
			dev.add_to_stat("social", -50.0 - dev.get_stat_value("social"))
		for fk2 in folks:
			var cur = fk2.current
			if cur != null and cur.state == "running" and cur.target_kind == "folk" and not seen_interaction.has(cur):
				seen_interaction[cur] = true
				counts[fk2.id] = int(counts.get(fk2.id, 0)) + 1
				kinds[cur.def_id] = int(kinds.get(cur.def_id, 0)) + 1
				var hr: int = int(m / 60)
				per_hour[hr] = int(per_hour.get(hr, 0)) + 1
	var line := "autonomous socials started in 3 days: "
	var total := 0
	for fk3 in folks:
		line += "%s=%d " % [fk3.name, int(counts.get(fk3.id, 0))]
		total += int(counts.get(fk3.id, 0))
	report.append(line)
	var ks: Array = []
	for k in kinds:
		ks.append("%s x%d" % [k, kinds[k]])
	ks.sort()
	report.append("mix: " + ", ".join(ks))
	var mood_line := "final moods: "
	for fk4 in folks:
		mood_line += "%s=%s(%d) " % [fk4.name, fk4.mood_name, fk4.mood_intensity]
	report.append(mood_line)
	report.append("tiers: " + str(SocialDynamics.stats["tiers"]) + " arguments=" + str(SocialDynamics.stats["arguments"]) + " gossip=" + str(SocialDynamics.stats["gossip"]))
	for fk5 in folks:
		var n := int(counts.get(fk5.id, 0))
		S.expect(f, n >= (2 if fk5.has_trait("loner") else 4), "%s socializes at least a little (%d)" % [fk5.name, n])
		S.expect(f, n <= 160, "%s does not socialize constantly (%d in 3 days)" % [fk5.name, n])
	S.expect(f, kinds.size() >= 5, "a varied mix of socials (%d kinds)" % kinds.size())
	var top := 0
	for k2 in kinds:
		top = maxi(top, int(kinds[k2]))
	S.expect(f, float(top) <= 0.55 * float(maxi(total, 1)), "no single social dominates (%d of %d)" % [top, total])
	# the social need stays healthy on average thanks to autonomy
	var worst := 100.0
	for fk6 in folks:
		worst = minf(worst, fk6.get_stat_value("social"))
	S.expect(f, worst > -80.0, "nobody ends up with a rock-bottom social need (%.0f)" % worst)
	# loner socializes less than the social butterfly
	S.expect(f, int(counts.get(folks[0].id, 0)) > int(counts.get(folks[3].id, 0)), "social butterfly out-socializes the loner (%d vs %d)" % [int(counts.get(folks[0].id, 0)), int(counts.get(folks[3].id, 0))])
	# spread through the day: socials happen in many different hours, not in one burst
	S.expect(f, per_hour.size() >= 12, "socials are spread over the 3 days (%d distinct hours)" % per_hour.size())
	for fk7 in folks:
		fk7.current = null
		fk7.queue.clear()
	S.teardown()

func _goals_and_loneliness(f: Array) -> void:
	var w := S.setup(411)
	var a := S.folk(w, "Ann")
	var b := S.folk(w, "Bo")
	var c := S.folk(w, "Cy")
	# reconcile goal: tension -> wants_reconcile and a positive pull towards that person
	RelationshipService.add_both(a.id, b.id, "friendship", 30.0)
	SocialConflict.escalate(a.id, b.id, 40.0)
	SocialGatherings.update_goals(a)
	S.expect(f, a.has_buff("wants_reconcile") and SocialDynamics.goals[a.id]["kind"] == "reconcile", "tension creates a reconcile goal")
	S.expect(f, SocialGatherings.goal_text(a.id).find("Bo") >= 0, "goal text names the person: %s" % SocialGatherings.goal_text(a.id))
	S.expect(f, a.memory_bias("folk:%d" % b.id) > 0.0, "reconcile goal pulls Ann towards Bo despite the avoidance memory")
	# the reconcile interactions are boosted by the goal buff
	var cand := {"id": "make_up", "target_id": b.id, "kind": "folk", "obj": null, "folk": b}
	var with_goal: float = float(Autonomy.evaluate(a, cand)["sub"]["buff_mult"])
	a.remove_buff("wants_reconcile")
	var without: float = float(Autonomy.evaluate(a, cand)["sub"]["buff_mult"])
	S.expect(f, with_goal > without * 2.0, "wants_reconcile boosts make_up (x%.1f vs x%.1f)" % [with_goal, without])
	# grudgeholders do not set the goal
	var g := S.folk(w, "Grudge", ["grudgeholder"])
	RelationshipService.add_both(g.id, c.id, "friendship", 30.0)
	SocialConflict.escalate(g.id, c.id, 40.0)
	SocialGatherings.update_goals(g)
	S.expect(f, not g.has_buff("wants_reconcile"), "grudge-holders do not want to make peace")
	# make friends goal for people with few friends
	var d := S.folk(w, "Dee")
	SocialGatherings.update_goals(d)
	S.expect(f, d.has_buff("wants_friends") and SocialDynamics.goals.has(d.id), "folk with few friends want friends")
	var kind: String = str(SocialDynamics.goals[d.id]["kind"])
	S.expect(f, kind == "make_friend" and int(SocialDynamics.goals[d.id]["target"]) >= 0, "make_friend goal has a target")
	# loneliness raises the appetite for socials
	var lonely := S.folk(w, "Lonely")
	lonely.needs["social"].set_value(-70.0)
	var happy := S.folk(w, "Happy")
	happy.needs["social"].set_value(60.0)
	var cand_c := {"id": "chat", "target_id": b.id, "kind": "folk", "obj": null, "folk": b}
	var s_lonely: float = float(Autonomy.evaluate(lonely, cand_c).get("score", 0.0))
	var s_happy: float = float(Autonomy.evaluate(happy, cand_c).get("score", 0.0))
	S.expect(f, s_lonely > s_happy * 2.0, "a lonely folk scores a chat much higher (%.1f vs %.1f)" % [s_lonely, s_happy])
	# after socializing, the pace buff lowers further urge
	lonely.add_buff("socialized_recently")
	var s_after: float = float(Autonomy.evaluate(lonely, cand_c).get("score", 0.0))
	S.expect(f, s_after < s_lonely, "recent socializing cools the urge (%.1f < %.1f)" % [s_after, s_lonely])
	# couples get dates / affection when idle in the evening
	var p1 := S.folk(w, "P1")
	var p2 := S.folk(w, "P2")
	RelationshipService.add_both(p1.id, p2.id, "friendship", 60.0)
	RelationshipService.add_both(p1.id, p2.id, "romance", 60.0)
	RelationshipBits.set_flag(p1.id, p2.id, "partner", true, false)
	S.set_time(2, 19)
	var started := 0
	for i in 60:
		p1.queue.clear()
		p1.current = null
		p2.queue.clear()
		p2.current = null
		started += SocialGatherings.couples_upkeep()
	S.expect(f, started > 0, "couples are nudged to go on dates / show affection (%d)" % started)
	S.teardown()
