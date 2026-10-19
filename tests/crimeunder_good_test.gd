extends RefCounted
## Task 23, the good side and the reputations. A cop who takes a bribe protects the briber and carries an internal-affairs risk that grows with each
## bribe (an investigation can clear, dismiss or charge them); refusing earns honour. Stings, undercover work and a hero stopping a crime in progress.
## Redemption clears the record over time (and old contacts can pull a person back). Guilt and pride follow traits; relatives disown, cover up or join.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_bribe(f)
	_ia(f)
	_sting_and_cover(f)
	_hero(f)
	_redeem(f)
	_rep(f)
	_family(f)
	return f

func _cop(pid: int) -> void:
	Story.townies[pid]["career"] = "police_officer"
	Story.townies[pid]["level"] = 1

func _dealer(pid: int) -> void:
	CrimeLifePath.join(pid, "chose")
	CrimeLifePath.member(pid)["cred"] = 30.0
	CrimeUnderState.lines[pid] = {"deal": {"standing": 5.0, "since": 0, "acts": 0, "via": "contact"}}
	CrimeUnderDeal.ensure(pid)["stock"] = {"glow": 6}

func _bribe(f: Array) -> void:
	var w := C.town(20)
	var ids: Array = C.adults()
	var cop: int = int(ids[0])
	var dealer: int = int(ids[1])
	_cop(cop)
	_dealer(dealer)
	Story.townies[dealer]["coins"] = 2000
	Story.townies[cop]["traits"] = ["dishonest"]
	CrimeUnderState.sect("good")["bribe"]["townie_take"] = 5.0
	var before: int = CrimePerson.coins(cop)
	var r: Dictionary = CrimeUnderGood.offer(cop, dealer, 300)
	K.expect(f, bool(r["taken"]) and CrimePerson.coins(cop) == before + 300, "a dishonest cop takes the envelope")
	K.expect(f, CrimeUnderGood.protection(dealer) >= 0.4, "and the briber is protected")
	var rec: Dictionary = CrimeUnderState.cops[cop]
	var low: float = CrimeUnderGood.ia_risk(cop)
	rec["taken"] = 6
	var high: float = CrimeUnderGood.ia_risk(cop)
	K.expect(f, high > low * 4.0 and low > 0.0, "internal-affairs risk grows with each bribe taken (%.3f -> %.3f)" % [low, high])
	# the honest refuse
	var cop2: int = int(ids[2])
	_cop(cop2)
	Story.townies[cop2]["traits"] = ["honest"]
	CrimeUnderState.sect("good")["bribe"]["townie_take"] = 0.0
	var r2: Dictionary = CrimeUnderGood.offer(cop2, dealer, 300)
	K.expect(f, not bool(r2["taken"]) and CrimeUnderRep.rec(cop2)["honour"] > 0.0, "an honest cop refuses and it counts for honour")
	K.teardown()
	# the player's cop is asked
	var w2 := C.town(14)
	var d2: int = int(C.adults()[0])
	_dealer(d2)
	Story.townies[d2]["coins"] = 2000
	var folk = SysUtil.folk(1)
	Careers.hire(folk, "police_officer", 1)
	K.expect(f, CrimeUnderGood.is_cop(1) or not Careers.has_job(1), "(the player's folk can be a police officer)")
	if CrimeUnderGood.is_cop(1):
		JusticePlayer.auto = "take"
		var c0: int = CrimePerson.coins(1)
		CrimeUnderGood.offer(1, d2, 200)
		K.expect(f, CrimePerson.coins(1) >= c0 + 200 and CrimeUnderState.cops[1]["taken"] == 1, "the player chooses to take it")
		JusticePlayer.auto = ""
	K.teardown()

func _ia(f: Array) -> void:
	var w := C.town(20)
	var ids: Array = C.adults()
	var cop: int = int(ids[0])
	_cop(cop)
	CrimeUnderState.cops[cop] = {"taken": 3, "corruption": 3.0, "protecting": [int(ids[1])], "refused": 0}
	CrimeUnderState.sect("good")["ia"]["per_bribe"] = 1.0
	CrimeUnderGood.on_day()
	K.expect(f, str(CrimeUnderState.cops[cop]["ia"]["state"]) == "investigating", "enough bribes start an internal-affairs investigation")
	CrimeUnderState.sect("good")["ia"]["cleared"] = 0.0
	CrimeUnderState.sect("good")["ia"]["convict"] = 1.0
	SimEnv.clock().total_minutes += 6 * 1440
	CrimeUnderGood.on_day()
	K.expect(f, CrimeUnderState.counter("ia_guilty") == 1 and not CrimePerson.has_job(cop), "a guilty verdict ends the career")
	K.expect(f, CrimeUnderGood.protection(int(ids[1])) == 0.0, "and the protection with it")
	K.expect(f, not CaseStore.cases_of_culprit(cop).is_empty() and str(CaseStore.cases_of_culprit(cop)[0].get("charge_hint", "")) == "bribery", "the cop is charged with bribery")
	K.teardown()

func _sting_and_cover(f: Array) -> void:
	var w := C.town(24)
	var ids: Array = C.adults()
	var cop: int = int(ids[0])
	var dealer: int = int(ids[1])
	_cop(cop)
	_dealer(dealer)
	CrimeUnderState.sect("good")["sting"]["base"] = 5.0
	var r: Dictionary = CrimeUnderGood.sting(cop, dealer)
	K.expect(f, bool(r["ok"]) and bool(r["caught"]) and (CrimePerson.in_custody(dealer) or not CaseStore.cases_of_culprit(dealer).is_empty()), "a cop's sting catches a dealer")
	# undercover
	_member_gang_setup(ids)
	var gid: int = 1
	var u: Dictionary = CrimeUnderGood.go_undercover(cop, gid)
	K.expect(f, bool(u["ok"]) and CrimeUnderGang.of(cop) == gid, "an officer goes undercover in a gang")
	CrimeUnderState.sect("good")["undercover"]["exposed_daily"] = 0.0
	for d in 14:
		CrimeUnderGood.undercover_day()
	K.expect(f, not CrimeUnderState.undercover.has(cop) and CrimeUnderState.counter("undercover_bust") == 1, "trust and evidence grow, then the gang is brought down from inside")
	K.expect(f, CrimeUnderRep.hero(cop) >= 3.0, "the officer's name is made")
	K.teardown()

func _member_gang_setup(ids: Array) -> void:
	for i in [2, 3, 4]:
		CrimeLifePath.join(int(ids[i]), "chose")
		CrimeLifePath.member(int(ids[i]))["cred"] = 50.0
		CrimeLifePath.member(int(ids[i]))["rank"] = "crew_boss" if i == 2 else "burglar"
	var g: int = CrimeUnderGang.found(int(ids[2]), "the Test Crew")
	CrimeUnderGang.add_member(g, int(ids[3]))
	CrimeUnderGang.add_member(g, int(ids[4]))

func _hero(f: Array) -> void:
	var w := C.town(14)
	var c: Dictionary = CaseStore.create("burglary", int(C.adults()[0]), -1, "home:1", {"witnessed": false, "trace": 0.3})
	c["on_scene"] = true
	c["state"] = "hidden"
	var folk = SysUtil.folk(1)
	CrimeUnderState.sect("good")["hero"]["intervene_base"] = 5.0
	var r: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimeunder", "args": {"action": "intervene", "case": int(c["id"])}})
	K.expect(f, bool(r["ok"]) and bool(r.get("won", false)), "stepping in on a burglary can stop it")
	K.expect(f, CrimeUnderRep.hero(1) >= 3.0 and folk.has_buff("hero_of_the_day"), "the town's hero standing rises")
	K.expect(f, CrimePerson.in_custody(int(c["culprit"])) or str(c["state"]) in ["charged", "arrested", "trial"], "and the intruder is arrested")
	var c2: Dictionary = CaseStore.create("burglary", int(C.adults()[1]), -1, "home:1", {"witnessed": false, "trace": 0.3})
	c2["on_scene"] = true
	CrimeUnderState.sect("good")["hero"]["intervene_base"] = -5.0
	CrimeUnderState.sect("good")["hero"]["hurt"] = 1.0
	var r2: Dictionary = CrimeUnderGood.intervene(1, int(c2["id"]))
	K.expect(f, not bool(r2.get("won", true)), "it can also go wrong")
	var h0: float = CrimeUnderRep.hero(1)
	CrimeUnderFlow.on_event("accident_rescued", {"folk_id": 1, "target_id": int(C.adults()[2])})
	K.expect(f, CrimeUnderRep.hero(1) > h0, "rescuing someone counts as heroism too")
	K.teardown()

func _redeem(f: Array) -> void:
	var w := C.town(16)
	var ids: Array = C.adults()
	var p: int = int(ids[0])
	Story.townies[p]["coins"] = 100
	CrimeLifePath.join(p, "chose")
	var entries: Array = []
	for ch in ["theft", "burglary", "assault", "murder"]:
		JusticeRecords.add(p, ch, 1, "guilty", -1, "")
	K.expect(f, JusticeRecords.convictions(p).size() == 4, "four convictions on file")
	var mentor: int = int(ids[1])
	RelationshipService.set_value(mentor, p, "friendship", 70.0)
	Story.townies[mentor]["traits"] = ["honest"]
	Story.townies[p]["career"] = "cook"
	var r: Dictionary = CrimeUnderRedeem.begin(p)
	K.expect(f, bool(r["ok"]) and not CrimeLifePath.is_member(p) and CrimeUnderRedeem.active(p), "going straight starts the way back")
	K.expect(f, int(CrimeUnderRedeem.rec(p)["mentor"]) == mentor, "a clean friend steps up as mentor")
	CrimeUnderState.sect("redeem")["tempt_daily"] = 0.0
	var seen_cleared: int = 0
	for d in 140:
		K.set_time(5 + d, 12)
		CrimeUnderRedeem.day_of(p)
		if not CrimeUnderRedeem.active(p):
			break
		seen_cleared = int(CrimeUnderRedeem.rec(p).get("cleared", 0))
	K.expect(f, not CrimeUnderRedeem.active(p) and CrimeUnderState.counter("redeemed") == 1, "after enough clean days the redemption is complete")
	var left: Array = JusticeRecords.visible(p)
	K.expect(f, left.size() == 1 and str(left[0]["charge"]) == "murder", "old convictions are expunged, the gravest stays (%d left)" % left.size())
	K.expect(f, SysUtil.day() >= 0 and seen_cleared >= 1, "it happens gradually (cleared %d before the end)" % seen_cleared)
	K.expect(f, CrimeUnderRep.rec(p).has("redeemed"), "the town remembers the change")
	# temptation: an old contact calls and pulls a weak person back
	var q: int = int(ids[2])
	CrimeLifeContacts.add(q, int(ids[3]), "fence", 0.5)
	CrimeUnderRedeem.begin(q)
	CrimeUnderState.sect("redeem")["tempt_daily"] = 1.0
	CrimeUnderState.sect("redeem")["pull_back"] = 1.0
	Story.townies[q]["traits"] = ["dishonest"]
	Story.townies[q]["coins"] = 0
	var fell: bool = false
	for d in 30:
		CrimeUnderRedeem.rec(q)["last_tempt"] = -99
		CrimeUnderRedeem.day_of(q)
		if CrimeLifePath.is_member(q):
			fell = true
			break
	K.expect(f, fell or CrimeUnderState.counter("redeem_resist") > 0, "old contacts call; some resist, some fall back")
	K.teardown()

func _rep(f: Array) -> void:
	var w := C.town(14)
	var ids: Array = C.adults()
	var shrug: int = int(ids[0])
	var soft: int = int(ids[1])
	Story.townies[shrug]["traits"] = ["vengeful"]
	Story.townies[soft]["traits"] = ["empath"]
	K.expect(f, CrimeUnderRep.deed(shrug, "kill") == "", "a ruthless nature feels nothing about a killing")
	K.expect(f, CrimeUnderRep.deed(soft, "kill") == "guilt" and float(CrimeUnderRep.rec(soft)["guilt"]) >= 2.0, "an empath suffers badly")
	var folk = SysUtil.folk(1)
	folk.traits.clear()
	folk.traits.append("empath")
	CrimeUnderRep.deed(1, "kill")
	K.expect(f, folk.has_buff("troubled_conscience"), "guilt shows as a mood")
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["cred"] = 30.0
	CrimeUnderRep.add_hero(1, 4.0, "")
	var s: Dictionary = CrimeUnderRep.summary(1)
	K.expect(f, int(s["underworld"]) >= 30 and int(s["hero"]) == 4, "both reputations are tracked side by side")
	var kn: Dictionary = CrimeUnderRep.known_to(shrug, 1)
	K.expect(f, bool(kn["public"]) and not bool(kn["underworld"]), "a stranger knows the public name, not the underworld one")
	CrimeLifePath.join(shrug, "chose")
	K.expect(f, bool(CrimeUnderRep.known_to(shrug, 1)["underworld"]), "someone in the underworld knows the street name")
	# shops refuse a known thief
	JusticeRecords.add(soft, "theft", 1, "guilty", -1, "")
	RelationshipKnowledge.add_reputation(soft, -60.0)
	K.expect(f, CrimeUnderRep.refused_service(soft), "shops refuse a known thief with a poor name")
	CrimeUnderRep.add_hero(soft, 40.0, "")
	K.expect(f, not CrimeUnderRep.refused_service(soft), "unless the town thinks highly of them for something else")
	K.teardown()

func _family(f: Array) -> void:
	var w := C.town(16)
	var ids: Array = C.adults()
	var culprit: int = int(ids[0])
	var kin: int = int(ids[1])
	C.set_family(culprit, kin)
	Story.townies[kin]["traits"] = ["honest"]
	var seen: Dictionary = {}
	for i in 60:
		var r: String = CrimeUnderRep.family_reaction(culprit, kin)
		seen[r] = int(seen.get(r, 0)) + 1
	K.expect(f, seen.has("disown") and seen.has("cover"), "relatives react in different ways: %s" % str(seen))
	K.expect(f, CrimeUnderRep.rec(culprit).get("disowned", 0) > 0, "a disowned culprit carries it")
	K.expect(f, CrimeUnderRep.legacy_lines(culprit).size() >= 1, "the legacy remembers the turned backs")
	CrimeUnderRep.add_hero(culprit, 20.0, "")
	var lines: Array = CrimeUnderRep.legacy_lines(culprit)
	K.expect(f, lines.any(func(l): return str(l).contains("stepped in")), "and the honour side too")
	K.teardown()
