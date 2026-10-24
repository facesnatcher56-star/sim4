extends RefCounted
## Richer emotions: new moods reachable, data-driven effects (decay, autonomy, skill gain, availability), contagion, emotional memory,
## body-language mapping, mood detail, mood journal.

const S = preload("res://tests/social_kit.gd")
const NEW_MOODS := ["confident", "embarrassed", "inspired", "playful", "dazed", "jealous", "lonely", "nostalgic", "anxious", "content", "guilty", "proud"]
const MOOD_BUFF := {"confident": "confident_glow", "embarrassed": "embarrassed", "inspired": "inspired", "playful": "laughing_fit", "dazed": "feeling_dazed",
	"jealous": "jealous_pang", "lonely": "lonely", "nostalgic": "nostalgic_glow", "anxious": "anxious_jitters", "content": "content_calm",
	"guilty": "guilty_pang", "proud": "proud"}

func run() -> Array:
	var f: Array = []
	_moods(f)
	_effects(f)
	_contagion(f)
	_memory(f)
	_body_language_and_ui_data(f)
	_journal(f)
	return f

func _moods(f: Array) -> void:
	var w := S.setup(301)
	for m in ["happy", "sad", "angry", "tense", "bored", "energized", "uncomfortable", "focused", "flirty"] + NEW_MOODS:
		S.expect(f, Mood.MOODS.has(m), "mood %s is registered" % m)
		var md: Dictionary = Emotions.def_of(m)
		S.expect(f, md.has("label") and md.has("effects") and md.has("color") and md.has("social"), "mood %s has data in emotions.json" % m)
	S.expect(f, Mood.MOODS.size() >= 21, "at least 21 moods (%d)" % Mood.MOODS.size())
	for m2 in NEW_MOODS:
		var x := S.folk(w, "Mx_" + m2)
		x.add_buff(MOOD_BUFF[m2])
		x.refresh_mood()
		var got: Dictionary = x.get_mood()
		S.expect(f, got["mood"] == m2, "buff %s gives mood %s (got %s)" % [MOOD_BUFF[m2], m2, got["mood"]])
		S.expect(f, int(got["intensity"]) >= 1 and int(got["intensity"]) <= 3, "intensity stays 1..3 for %s" % m2)
	# intensity thresholds 1 / 3 / 6 still hold
	var y := S.folk(w, "Y")
	y.add_buff("content_calm")      # content 3 -> 2
	S.expect(f, y.get_mood()["mood"] == "content" and y.get_mood()["intensity"] == 2, "content 3 = intensity 2")
	y.add_buff("makeup_glow")       # content 2 + happy 2 -> content 5
	y.add_buff("bonded_glow")       # +3 -> 8
	S.expect(f, y.get_mood()["intensity"] == 3, "enough buffs = intensity 3")
	S.expect(f, Mood.intensity_for(0.5) == 0 and Mood.intensity_for(1.0) == 1 and Mood.intensity_for(3.0) == 2 and Mood.intensity_for(6.0) == 3, "intensity thresholds unchanged")
	# valence of new buffs
	S.expect(f, Mood.buff_valence("jealous_pang") < 0.0 and Mood.buff_valence("content_calm") > 0.0, "buff valence understands the new moods")
	# the old behaviour for original moods stays: hungry -> uncomfortable, flirty buzz -> flirty
	var z := S.folk(w, "Z")
	z.add_buff("flirty_buzz")
	S.expect(f, z.get_mood()["mood"] == "flirty", "original moods still work")
	# breakdown for the tooltip
	var bd: Dictionary = Mood.breakdown(y)
	S.expect(f, bd["mood"] == "content" and (bd["rows"] as Array).size() >= 3 and float(bd["rows"][0]["toward"]) >= float(bd["rows"][1]["toward"]), "Mood.breakdown lists the driving buffs strongest first")
	S.teardown()

func _effects(f: Array) -> void:
	var w := S.setup(311)
	var a := S.folk(w, "Artist", ["creative"])
	var b := S.folk(w, "Plain", ["creative"])
	# inspired -> hidden mood-effect buff + creative skill boost
	a.add_buff("inspired")
	Emotions.sync(a)
	var fx_id := ""
	for bf in a.buffs:
		if str(bf["id"]).begins_with("mfx_"):
			fx_id = str(bf["id"])
	S.expect(f, fx_id == "mfx_inspired_1" or fx_id == "mfx_inspired_2" or fx_id == "mfx_inspired_3", "a mood-effect buff is applied (%s)" % fx_id)
	S.expect(f, Emotions.skill_mult(a, "painting") > 1.3 and Emotions.skill_mult(a, "guitar") > 1.3, "inspired boosts creative skills (%.2f)" % Emotions.skill_mult(a, "painting"))
	S.expect(f, Emotions.skill_mult(a, "fitness") < 1.3 and Emotions.skill_mult(b, "painting") == 1.0, "...but not everything, and not neutral folk")
	var xp0: float = float(a.skills["painting"]["xp"])
	var xp_b0: float = float(b.skills["painting"]["xp"])
	var d: Dictionary = SimEnv.data().interaction_def("paint_canvas")
	b.add_skill_xp("painting", 0.0)
	Emotions.on_finished(a.id, "paint_canvas", true)
	Emotions.on_finished(b.id, "paint_canvas", true)
	S.expect(f, float(a.skills["painting"]["xp"]) > xp0 + 1.0 and float(b.skills["painting"]["xp"]) == xp_b0, "finishing a painting while inspired grants bonus XP only to the inspired")
	# effect buff follows the mood
	a.remove_buff("inspired")
	Emotions.sync(a)
	var still := false
	for bf2 in a.buffs:
		if str(bf2["id"]).begins_with("mfx_"):
			still = true
	S.expect(f, not still, "the mood-effect buff is removed when the mood ends")
	# lonely: social decays faster and socials are favoured
	var l := S.folk(w, "Lonely")
	var n := S.folk(w, "Neutral")
	var other := S.folk(w, "Other")
	l.add_buff("lonely")
	l.add_buff("isolated")
	l.refresh_mood()
	Emotions.sync(l)
	S.expect(f, l.get_mood()["mood"] == "lonely", "isolated folk are lonely, not just sad")
	S.expect(f, l.decay_mult("social") > n.decay_mult("social"), "lonely folk lose social faster (%.2f)" % l.decay_mult("social"))
	var cand_l := {"id": "greet", "target_id": other.id, "kind": "folk", "obj": null, "folk": other}
	var buffmult_l: float = float(Autonomy.evaluate(l, cand_l)["sub"]["buff_mult"])
	# compare to the same folk without the mood: isolation + lonely buffs also carry their own multipliers, so use a clean mood buff
	var m2 := S.folk(w, "Mood2")
	m2.add_buff("anxious_jitters")
	Emotions.sync(m2)
	var cand_g := {"id": "chat", "target_id": other.id, "kind": "folk", "obj": null, "folk": other}
	var anx_mult: float = float(Autonomy.evaluate(m2, cand_g).get("sub", {}).get("buff_mult", 1.0))
	var norm_mult: float = float(Autonomy.evaluate(n, cand_g).get("sub", {}).get("buff_mult", 1.0))
	S.expect(f, buffmult_l > 1.5, "lonely folk lean toward socials (x%.2f)" % buffmult_l)
	S.expect(f, anx_mult < norm_mult, "anxious folk lean away from socializing (x%.2f vs x%.2f)" % [anx_mult, norm_mult])
	# availability is data: angry unlocks, anxious blocks
	var unlocked: Array = Emotions.unlocked_interactions("angry")
	S.expect(f, unlocked.has("Yell At") and unlocked.has("Storm Off"), "angry unlocks yell / storm off: %s" % str(unlocked))
	var blocked: Array = Emotions.blocked_interactions("anxious")
	S.expect(f, blocked.size() >= 3 and blocked.has("Make a Toast"), "anxious blocks some socials: %s" % str(blocked))
	S.expect(f, Emotions.describe_effects("inspired", 3).size() >= 2, "effects can be described for the UI")
	# mood changes social success (give/receive)
	var p := S.folk(w, "P")
	var q := S.folk(w, "Q")
	var dd: Dictionary = SimEnv.data().interaction_def("funny_story")
	var base_s: float = float(SocialScoring.success_score(p, q, "funny_story", dd, dd["social"], {}, false)["score"])
	p.add_buff("laughing_fit")
	p.refresh_mood()
	var playful_s: float = float(SocialScoring.success_score(p, q, "funny_story", dd, dd["social"], {}, false)["score"])
	S.expect(f, playful_s > base_s, "a playful teller lands jokes better (%.2f > %.2f)" % [playful_s, base_s])
	q.add_buff("furious")
	q.refresh_mood()
	var angry_listener: float = float(SocialScoring.success_score(p, q, "funny_story", dd, dd["social"], {}, false)["score"])
	S.expect(f, angry_listener < playful_s, "angry listeners are a tough crowd")
	S.teardown()

func _contagion(f: Array) -> void:
	var w := S.setup(321)
	var src := S.folk(w, "Src", [], Vector2i(12, 12))
	var near := S.folk(w, "Near", [], Vector2i(13, 12))
	var far := S.folk(w, "Far", [], Vector2i(30, 30))
	src.add_buff("confident_glow")
	src.add_buff("proud")
	src.add_buff("stage_glow")
	src.refresh_mood()
	S.expect(f, src.get_mood()["mood"] == "confident" and src.mood_intensity >= 2, "setup: strongly confident source")
	var caught_near := 0
	var caught_far := 0
	for i in 600:
		Emotions.contagion_tick()
		if near.has_buff("caught_confident"):
			caught_near += 1
			break
	for i in 600:
		Emotions.contagion_tick()
		if far.has_buff("caught_confident"):
			caught_far += 1
	S.expect(f, caught_near == 1, "folk standing nearby catch the mood")
	S.expect(f, caught_far == 0, "folk far away do not")
	near.refresh_mood()
	S.expect(f, near.get_mood()["mood"] == "confident" and near.mood_intensity >= 1, "the caught mood shows up in the mood (%s)" % str(near.get_mood()))
	S.expect(f, S.K.count_events("mood_contagion") >= 1, "contagion is an event")
	# conversation circles catch faster than mere proximity
	var circ := 0
	var prox := 0
	for trial in 30:
		var ox := 100 + trial * 40
		var s2 := S.folk(w, "S2_%d" % trial, [], Vector2i(ox, 5))
		var d1 := S.folk(w, "D1_%d" % trial, [], Vector2i(ox + 1, 5))
		var d2 := S.folk(w, "D2_%d" % trial, [], Vector2i(ox + 20, 20))
		s2.add_buff("jealous_pang")
		s2.add_buff("furious")
		s2.add_buff("fuming")
		s2.refresh_mood()
		Conversation.join(d2.id, s2.id)       # far away, but in the same conversation
		for i in 8:
			Emotions.contagion_tick()
		if d1.has_buff("caught_angry"):
			prox += 1
		if d2.has_buff("caught_angry"):
			circ += 1
		Conversation.leave(d2.id)
		for x in [s2, d1, d2]:
			SysUtil.world_remove_folk(x.id)
	S.expect(f, circ > prox, "chatting folk catch each other's mood more (%d vs %d of 30)" % [circ, prox])
	# traits modulate it: empaths catch more, easygoing folk resist negative moods
	var emp := 0
	var easy := 0
	for trial2 in 40:
		var ox2 := 2000 + trial2 * 40
		var s3 := S.folk(w, "S3_%d" % trial2, [], Vector2i(ox2, 20))
		var e1 := S.folk(w, "E1_%d" % trial2, ["empath"], Vector2i(ox2 + 1, 20))
		var e2 := S.folk(w, "E2_%d" % trial2, ["optimist", "easygoing"], Vector2i(ox2, 21))
		s3.add_buff("furious")
		s3.add_buff("fuming")
		s3.refresh_mood()
		for i in 15:
			Emotions.contagion_tick()
		if e1.has_buff("caught_angry"):
			emp += 1
		if e2.has_buff("caught_angry"):
			easy += 1
		for x2 in [s3, e1, e2]:
			SysUtil.world_remove_folk(x2.id)
	S.expect(f, emp > easy, "empaths catch moods more than easygoing optimists (%d vs %d)" % [emp, easy])
	S.teardown()

func _memory(f: Array) -> void:
	var w := S.setup(331)
	var a := S.folk(w, "Ann")
	var b := S.folk(w, "Bo")
	var tv = w.add_object("tv", Vector2i(12, 10))
	S.set_time(1, 9)
	# a strong good moment tied to an object produces nostalgia later, and feeds autonomy's memory_bias
	Emotions.imprint(a, "obj:%d" % tv.id, 0.5, "mood_peak", "happy")
	S.expect(f, a.memory_bias("obj:%d" % tv.id) > 0.3, "imprint uses Folk.remember (memory_bias hook)")
	Emotions.on_started(a.id, "watch_tv", tv.id)
	S.expect(f, not a.has_buff("nostalgic_glow"), "no nostalgia right away")
	S.set_time(3, 9)
	Emotions.on_started(a.id, "watch_tv", tv.id)
	S.expect(f, a.has_buff("nostalgic_glow"), "a good memory later makes the object nostalgic")
	S.expect(f, S.K.count_events("emotional_memory") == 1, "emotional_memory event")
	a.remove_buff("nostalgic_glow")
	Emotions.on_started(a.id, "watch_tv", tv.id)
	S.expect(f, not a.has_buff("nostalgic_glow"), "nostalgia has a cooldown")
	# bad memories -> unease and avoidance
	Emotions.imprint(b, "obj:%d" % tv.id, -0.5, "mood_peak", "angry")
	S.expect(f, b.memory_bias("obj:%d" % tv.id) < -0.3, "bad moments make the object less attractive")
	S.set_time(6, 9)
	Emotions.on_started(b.id, "watch_tv", tv.id)
	S.expect(f, b.has_buff("uneasy_memory"), "a bad memory brings unease")
	# people: a breakup is remembered
	var c := S.folk(w, "Cy")
	RelationshipService.add_both(b.id, c.id, "friendship", 40.0)
	RelationshipService.add_both(b.id, c.id, "romance", 60.0)
	RelationshipBits.set_flag(b.id, c.id, "partner", true, false)
	RelationshipRomance.breakup(b.id, c.id, "breakup", 1.0)
	S.expect(f, b.memory_bias("folk:%d" % c.id) < 0.0 and Emotions.moments_of(b.id).size() >= 2, "a breakup leaves a negative memory of the person")
	S.set_time(12, 9)
	var before := b.has_buff("uneasy_memory")
	b.remove_buff("uneasy_memory")
	Emotions.on_started(b.id, "chat", c.id)
	S.expect(f, b.has_buff("uneasy_memory"), "meeting the ex again stirs old feelings")
	# peaks during an interaction are imprinted (strong mood at the end of an interaction)
	var d := S.folk(w, "Di")
	for bid in ["pumped", "stage_glow", "hot_tub_bliss", "entertained"]:
		d.add_buff(bid)
	d.refresh_mood()
	Emotions.on_started(d.id, "watch_tv", tv.id)
	var n0: int = Emotions.moments_of(d.id).size()
	Emotions.on_finished(d.id, "watch_tv", true)
	S.expect(f, d.mood_intensity >= 3 and Emotions.moments_of(d.id).size() > n0, "a high-intensity mood at the end of an interaction is imprinted")
	S.teardown()

func _body_language_and_ui_data(f: Array) -> void:
	S.setup(341)
	var txt := FileAccess.get_file_as_string("res://data/animation_map.json")
	var am: Variant = JSON.parse_string(txt)
	S.expect(f, am is Dictionary, "animation_map parses")
	var idle_moods: Dictionary = (am["idle"] as Dictionary)["mood"]
	var clips := ["Idle", "Sad_Idle", "Angry", "Dance", "Wave", "Talk", "Laugh", "Cry", "Hug", "Kiss", "Use_Stand"]
	var mapped := 0
	for m in NEW_MOODS:
		if idle_moods.has(m):
			mapped += 1
			S.expect(f, clips.has(str((idle_moods[m] as Dictionary)["clip"])), "mood %s maps to a clip that exists" % m)
	S.expect(f, mapped >= 6, "body language: new moods map to idle clips (%d)" % mapped)
	var icon_cols: Dictionary = (am["mood_icon"] as Dictionary)["colors"]
	for m2 in Mood.MOODS:
		S.expect(f, icon_cols.has(m2), "mood icon colour for %s" % m2)
	var inter: Dictionary = am["interactions"]
	var tied := 0
	for iid in SimEnv.data().interactions():
		if inter.has(iid):
			tied += 1
	S.expect(f, tied >= 30, "new social interactions have animation mappings (%d in total)" % tied)
	for must in ["yell_at", "comfort", "hug", "kiss", "slow_dance", "storm_off", "group_hug", "toast"]:
		S.expect(f, inter.has(must), "animation for %s" % must)
	S.teardown()

func _journal(f: Array) -> void:
	var w := S.setup(351)
	var a := S.folk(w, "Ann")
	var b := S.folk(w, "Bo")
	a.add_buff("content_calm")
	a.add_buff("makeup_glow")
	b.add_buff("anxious_jitters")
	a.refresh_mood()
	b.refresh_mood()
	for i in 200:
		Emotions.record_minute(a)
		Emotions.record_minute(b)
	var j: Dictionary = Emotions.journal_for(a.id)
	S.expect(f, j["top"] == "content" and int(j["samples"]) == 200 and int(j["top_pct"]) == 100, "journal tracks the day's mood")
	S.set_time(2, 6)
	var lines: Array = Emotions.on_day(2)
	S.expect(f, lines.size() == 2 and str(lines[0]).find("content") >= 0, "daily journal summary: %s" % str(lines))
	S.expect(f, not S.K.has_note("Mood journal") and not Emotions.last_journal.is_empty(), "quiet depth: the journal is kept, not toasted")
	S.expect(f, S.K.count_events("mood_journal") == 1, "journal event")
	S.expect(f, int(Emotions.journal_for(a.id)["samples"]) == 0, "journal resets each day")
	S.teardown()
