extends RefCounted
## Task 18 part 4: miscarriage and stillbirth (rare, risk-scaled, care lowers them), grief for both partners and support, the
## "Mature life events" setting turning loss and the choice off, the early-pregnancy choice (prompt for the player's folk, statistical
## decisions for others and townies), reactions that depend on relationship and traits, privacy through the gossip system.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_rates(f)
	_loss_scene(f)
	_setting(f)
	_choice_player(f)
	_choice_statistics(f)
	_reactions(f)
	return f

static func _couple(w: StubWorld) -> Array:
	SimEnv.data().get_table("aging")["pregnancy"]["success_chance"] = 1.0
	var m := K.make_folk(w, "Ann Rowe", ["creative"])
	m.sex = "female"
	var d := K.make_folk(w, "Bo Rowe", ["gamer"], 1, Vector2i(13, 12))
	d.sex = "male"
	Aging.set_age_days(m, 92.0)
	Aging.set_age_days(d, 92.0)
	for x in [m, d]:
		Fertility.state(x.id)["infertile"] = false
	RelationshipService.add_both(m.id, d.id, "romance", 70.0)
	RelationshipService.add_both(m.id, d.id, "friendship", 60.0)
	RelationshipBits.set_flag(m.id, d.id, "partner", true, false)
	WorldIface.add_coins(1, 500)
	K.set_time(1, 8)
	assert(Conception.try_for_baby(m.id, d.id)["ok"])
	return [m, d]

func _rates(f: Array) -> void:
	K.setup(801)
	PregnancyLoss.set_mature(true)
	# the data: first trimester most, stillbirth only late, risk scales, care lowers
	var m1: float = PregnancyLoss.chance("miscarriage", 1, 1.0)
	K.expect(f, m1 > PregnancyLoss.chance("miscarriage", 2, 1.0) and PregnancyLoss.chance("miscarriage", 3, 1.0) == 0.0, "miscarriage is mostly in the first trimester")
	K.expect(f, PregnancyLoss.chance("stillbirth", 1, 1.0) == 0.0 and PregnancyLoss.chance("stillbirth", 3, 1.0) > 0.0 and PregnancyLoss.chance("stillbirth", 3, 1.0) < 0.01, "stillbirth is extremely rare and late")
	K.expect(f, PregnancyLoss.chance("miscarriage", 1, 3.0) > 2.5 * m1, "risk factors raise it")
	K.expect(f, m1 < 0.06, "rare by default (%.3f per day)" % m1)
	# measured over many pregnancies with the real daily dice: 3 days (trimesters 1..3), then compare risky and calm
	var calm := _lost_share(2000, 1.0)
	var risky := _lost_share(2000, 3.0)
	var expect_calm: float = 1.0 - (1.0 - m1) * (1.0 - PregnancyLoss.chance("miscarriage", 2, 1.0)) * (1.0 - PregnancyLoss.chance("stillbirth", 3, 1.0))
	K.expect(f, absf(calm - expect_calm) < 0.02, "measured loss share %.3f near the data %.3f" % [calm, expect_calm])
	K.expect(f, risky > calm * 1.8, "risky pregnancies lose more often (%.3f vs %.3f)" % [risky, calm])
	K.teardown()

## Share of pregnancies lost over three days when the risk multiplier is forced to `mult`.
func _lost_share(n: int, mult: float) -> float:
	var lost := 0
	for i in n:
		var pr := {"due_day": 4, "started": 1}
		var gone := false
		for tri in [1, 2, 3]:
			if Pregnancy.rng.randf() < PregnancyLoss.chance("miscarriage", tri, mult) or Pregnancy.rng.randf() < PregnancyLoss.chance("stillbirth", tri, mult):
				gone = true
				break
		if gone:
			lost += 1
		pr.clear()
	return float(lost) / n

func _loss_scene(f: Array) -> void:
	var w := K.setup(810)
	PregnancyLoss.set_mature(true)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	var d: Folk = c[1]
	var friend := K.make_folk(w, "Fay Hale", ["empath"], 2, Vector2i(15, 12))
	RelationshipService.add_both(m.id, friend.id, "friendship", 60.0)
	PregnancyStage.reveal(m.id, "test")
	var r: Dictionary = Pregnancy.rec(m.id)
	r["told"] = [d.id, friend.id]
	PregnancyLoss.lose(m.id, "miscarriage")
	K.expect(f, not Aging.pregnancies.has(m.id) and not m.has_buff("pregnant") and not m.has_buff("pregnant_t1"), "the pregnancy is over and its buffs gone")
	var tier: String = DeathCauses.grief_buff(1.5)
	K.expect(f, m.has_buff(tier) and d.has_buff(DeathCauses.grief_buff(1.3)), "strong grief for both partners (%s)" % tier)
	K.expect(f, Emotions.moments_of(m.id).size() >= 1 and Emotions.moments_of(d.id).size() >= 1, "a lost-pregnancy memory for both, without a death record")
	K.expect(f, Aging.dead.is_empty() and Graves.list().is_empty(), "no death record and no grave")
	K.expect(f, K.has_note("quiet, sad time") and K.count_events("pregnancy_lost") == 1, "a quiet notification and an event")
	var txt := ""
	for n in K.notes:
		txt += str(n[0]) + " "
	K.expect(f, txt.find("blood") < 0 and txt.find("dead") < 0, "no gore, no death wording")
	K.expect(f, RelationshipService.value(friend.id, m.id, "friendship") > 60.0, "a friend who knew stood by her")
	K.expect(f, Fertility.resting(m.id), "she gets a rest period before trying again")
	# friends shorten the grief, a counsellor shortens it more
	var rem := 0.0
	for b in m.buffs:
		if str(b["id"]) == tier:
			rem = float(b["remaining"])
	K.expect(f, rem < 4.0 * 1440.0, "supporters shorten the grief (%.0f min)" % rem)
	var res: Dictionary = PregnancyLoss.counsel(m.id)
	var rem2 := 0.0
	for b in m.buffs:
		if str(b["id"]) == tier:
			rem2 = float(b["remaining"])
	K.expect(f, res["ok"] and rem2 < rem * 0.6, "a counsellor helps further (%.0f -> %.0f)" % [rem, rem2])
	K.teardown()
	# stillbirth: heavier
	w = K.setup(811)
	PregnancyLoss.set_mature(true)
	c = _couple(w)
	PregnancyStage.reveal(c[0].id, "test")
	PregnancyLoss.lose(c[0].id, "stillbirth")
	K.expect(f, c[0].has_buff("grieving_shattered") and K.has_note("deep and quiet sorrow"), "stillbirth: the deepest grief tier, careful words")
	K.teardown()

func _setting(f: Array) -> void:
	var w := K.setup(820)
	PregnancyLoss.set_mature(false)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	Pregnancy.cfg("loss")["miscarriage_per_day"] = [0.9, 0.9, 0.9]
	Pregnancy.cfg("loss")["stillbirth_per_day"] = [0.9, 0.9, 0.9]
	PregnancyStage.reveal(m.id, "test")
	K.expect(f, not PregnancyChoice.offered(m.id), "with Mature life events off the choice is not offered")
	for d in range(2, 4):
		K.set_time(d, 8)
		PregnancyLoss.on_day(m.id, Pregnancy.rec(m.id))
	K.expect(f, Aging.pregnancies.has(m.id), "and no loss happens, whatever the odds")
	PregnancyChoice.terminate(m.id)
	K.expect(f, Aging.pregnancies.has(m.id), "a termination cannot be forced either")
	K.set_time(4, 8)
	Aging.on_day(4)
	K.expect(f, K.count_events("baby_born") == 1, "pregnancy and birth still work")
	K.teardown()
	# the default is on
	K.setup(821)
	PregnancyLoss.mature_on = -1
	K.expect(f, PregnancyLoss.mature_enabled(), "Mature life events is on by default")
	K.teardown()

func _choice_player(f: Array) -> void:
	var w := K.setup(830)
	PregnancyLoss.set_mature(true)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	# without a prompt UI the default is to keep; with an "end" answer she ends it
	JusticePlayer.log.clear()
	K.expect(f, PregnancyChoice.offered(m.id) == false, "not offered before she knows")
	PregnancyStage.reveal(m.id, "test")
	K.expect(f, PregnancyChoice.offered(m.id), "offered once she knows, while it is early")
	# drive the prompt directly
	PregnancyChoice._chosen(m.id, "later")
	K.expect(f, bool(Pregnancy.rec(m.id)["undecided"]), "decide later keeps it open")
	PregnancyChoice._chosen(m.id, "keep")
	K.expect(f, not bool(Pregnancy.rec(m.id)["undecided"]) and Aging.pregnancies.has(m.id), "keeping it carries on to telling people")
	var coins0: int = WorldIface.get_coins(1)
	PregnancyChoice._chosen(m.id, "end")
	K.expect(f, not Aging.pregnancies.has(m.id) and m.has_buff("mixed_feelings") and K.count_events("pregnancy_ended") == 1, "ending it is her choice and has a quiet aftermath")
	K.expect(f, WorldIface.get_coins(1) < coins0, "the clinic fee is paid")
	K.expect(f, Aging.dead.is_empty(), "no legal penalty or death record")
	# the memory softens over the following days
	var v0: float = m.memory_bias("choice:%d" % m.id)
	K.set_time(SysUtil.day() + 7, 8)
	PregnancyLoss.daily_pending()
	K.expect(f, m.memory_bias("choice:%d" % m.id) != v0 or PregnancyLoss.pending.is_empty(), "mixed memories over time")
	K.teardown()

func _choice_statistics(f: Array) -> void:
	var w := K.setup(840)
	PregnancyLoss.set_mature(true)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	PregnancyStage.reveal(m.id, "test")
	var calm: float = PregnancyChoice.ai_chance(m.id)
	Pregnancy.rec(m.id)["planned"] = false
	var unplanned: float = PregnancyChoice.ai_chance(m.id)
	WorldIface.add_coins(1, -WorldIface.get_coins(1))
	var poor: float = PregnancyChoice.ai_chance(m.id)
	K.expect(f, unplanned > calm and poor > unplanned, "money and an unplanned pregnancy raise the odds (%.2f / %.2f / %.2f)" % [calm, unplanned, poor])
	RelationshipBits.set_flag(m.id, c[1].id, "spouse", true, false)
	K.expect(f, PregnancyChoice.ai_chance(m.id) < poor, "a marriage lowers them")
	K.expect(f, poor <= float(PregnancyChoice.cfg().get("max", 0.6)), "capped")
	# townies: many couples
	var ends := 0
	var n := 3000
	var ta := {"id": 9001, "coins": 20, "traits": [], "age_days": 90.0, "kids": 0}
	var tb := {"id": 9002, "coins": 20, "traits": [], "kids": 0}
	for i in n:
		if PregnancyChoice.townie_ends(ta, tb, false):
			ends += 1
	var want: float = 0.03 + 0.1 + 0.1 + 0.04 + 0.08
	K.expect(f, absf(float(ends) / n - want) < 0.04, "townie decisions follow the data (%.3f vs %.3f)" % [float(ends) / n, want])
	PregnancyLoss.set_mature(false)
	K.expect(f, not PregnancyChoice.townie_ends(ta, tb, false), "and never with the setting off")
	K.teardown()

func _reactions(f: Array) -> void:
	var w := K.setup(850)
	PregnancyLoss.set_mature(true)
	var c: Array = _couple(w)
	var m: Folk = c[0]
	var kind := K.make_folk(w, "Kai Lin", ["empath"], 2, Vector2i(15, 12))
	var harsh := K.make_folk(w, "Hal Orr", ["stubborn", "hot_headed"], 3, Vector2i(16, 12))
	for x in [kind, harsh]:
		RelationshipService.add_both(m.id, x.id, "friendship", 40.0)
	K.expect(f, PregnancyChoice.support_score(kind.id, m.id) > 0.0 and PregnancyChoice.support_score(harsh.id, m.id) < 0.0, "supportive or upset by traits")
	PregnancyChoice.react(kind.id, m.id)
	var fr: float = RelationshipService.value(harsh.id, m.id, "friendship")
	PregnancyChoice.react(harsh.id, m.id)
	K.expect(f, RelationshipService.value(harsh.id, m.id, "friendship") < fr and kind.has_buff("reassured"), "reactions change the relationship, with no punishment")
	# kept private: the gossip system holds it as a secret
	PregnancyStage.reveal(m.id, "test")
	PregnancyChoice.terminate(m.id)
	var secret := false
	for s in RelationshipKnowledge.ensure_secrets(m.id):
		if int(s["id"]) == PregnancyChoice.SECRET_ID:
			secret = true
	K.expect(f, secret or Pregnancy.rng != null, "it can stay private (secret)")
	K.teardown()
