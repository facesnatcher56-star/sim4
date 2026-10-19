extends RefCounted
## Task 23: the hired gun. Joining the trade needs a contact, a record or desperation; contracts come from furious townies (and are very rare against
## the player's folk); the hitman researches the target, picks an opportunity and the killing goes through 04's flow with a case; mistakes raise the
## trace; a contract can be refused, tipped off (reward, the client's anger) and a charged hitman may name the client. A contract on the player's folk
## shows warning signs and offers counterplay.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_gate(f)
	_posting(f)
	_flow(f)
	_command_flow(f)
	_refuse_and_tip(f)
	_mistakes(f)
	_client_named(f)
	_player_target(f)
	return f

func _hitman(pid: int) -> void:
	CrimeLifePath.join(pid, "chose")
	CrimeLifePath.member(pid)["cred"] = 40.0
	CrimeLifeContacts.add(pid, int(C.adults()[0]), "driver", 0.5)
	K.expect([], CrimeUnderLines.join(pid, "hit")["ok"], "")

func _gate(f: Array) -> void:
	var w := C.town(12)
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["cred"] = 40.0
	K.expect(f, not bool(CrimeUnderLines.join(1, "hit")["ok"]), "nobody vouches for a stranger: no contact, no record, not desperate")
	CrimeLifeContacts.add(1, int(C.adults()[0]), "driver", 0.5)
	var r: Dictionary = CrimeUnderLines.join(1, "hit")
	K.expect(f, bool(r["ok"]) and str(r["via"]) == "contact" and CrimeUnderLines.has(1, "hit"), "a contact gets them in")
	K.expect(f, CrimeUnderLines.rank_label(1, "hit") == "Errand runner", "at the bottom rank")
	CrimeUnderLines.add_standing(1, "hit", 12.0)
	K.expect(f, CrimeUnderLines.rank_label(1, "hit") == "Gun for hire", "standing earns rank")
	K.teardown()

func _posting(f: Array) -> void:
	var w := C.town(14)
	var ids: Array = C.adults()
	var a: int = int(ids[0])
	var b: int = int(ids[1])
	Story.townies[a]["coins"] = 3000
	JusticeState.grudges[CrimeMurder.key(a, b)] = {"rage": 80.0}
	CrimeUnderState.sect("hit")["client_daily"] = 1.0
	CrimeUnderHit.on_day()
	var live: Array = CrimeUnderHit.live()
	K.expect(f, live.size() == 1 and int(live[0]["client"]) == a and int(live[0]["target"]) == b, "a furious townie with money puts a contract on the person they hate")
	K.expect(f, int(live[0]["fee"]) >= 260 and int(live[0]["deadline"]) > SysUtil.day(), "it has a fee and a deadline")
	K.expect(f, float(JusticeState.grudges[CrimeMurder.key(a, b)]["rage"]) < 80.0, "the anger is outsourced (rage drops)")
	CrimeUnderHit.on_day()
	K.expect(f, CrimeUnderHit.live().size() == 1, "one contract per grudge")
	# a weak grudge, or one against the player's folk, does not do it
	JusticeState.grudges[CrimeMurder.key(int(ids[2]), 1)] = {"rage": 70.0}
	Story.townies[int(ids[2])]["coins"] = 3000
	CrimeUnderState.sect("hit")["player_daily"] = 1.0
	CrimeUnderHit.on_day()
	K.expect(f, CrimeUnderHit.against(1).is_empty(), "against the player's folk it needs a much stronger grudge")
	JusticeState.grudges[CrimeMurder.key(int(ids[2]), 1)]["rage"] = 95.0
	CrimeUnderHit.on_day()
	K.expect(f, not CrimeUnderHit.against(1).is_empty(), "a very strong grudge can put one out, even on the player")
	# expiry
	SimEnv.clock().total_minutes += 40 * 1440
	CrimeUnderState.sect("hit")["client_daily"] = 0.0
	CrimeUnderState.sect("hit")["player_daily"] = 0.0
	CrimeUnderHit.on_day()
	K.expect(f, CrimeUnderHit.live().is_empty(), "contracts expire at the deadline")
	K.teardown()

func _flow(f: Array) -> void:
	var w := C.town(14)
	var ids: Array = C.adults()
	var client: int = int(ids[0])
	var target: int = int(ids[1])
	Story.townies[client]["coins"] = 3000
	_hitman(1)
	var c: Dictionary = CrimeUnderHit.post(client, target, "grudge", {"fee": 500})
	K.expect(f, not c.is_empty() and CrimeUnderHit.board(1).size() == 1, "the contract is on the board")
	var take: Dictionary = CrimeUnderHitRun.take(1, int(c["id"]))
	K.expect(f, bool(take["ok"]) and str(c["state"]) == "taken" and int(c["hitman"]) == 1, "the hitman takes it")
	var before: float = float(c["research"])
	for i in 3:
		CrimeUnderHitRun.session(1, c)
	K.expect(f, float(c["research"]) > before + 0.4, "research builds knowledge of the routine (%.2f)" % float(c["research"]))
	K.set_time(3, 23, 0)
	C.hours(2)
	var ops: Array = CrimeUnderHitRun.opportunities(1, int(c["id"]))
	K.expect(f, not ops.is_empty(), "well-researched targets have opportunities to pick from")
	C.quiet_witnesses()
	var coins_before: int = CrimePerson.coins(1)
	var res: Dictionary = CrimeUnderHitRun.resolve(1, c, str(ops[0]["scene"]), {"force": "clean", "alone": true})
	K.expect(f, str(res["outcome"]) == "clean" and str(c["state"]) == "done", "the contract is carried out")
	var cs: Dictionary = CaseStore.get_case(int(res["case"]))
	K.expect(f, not cs.is_empty() and int(cs["contract"]) == int(c["id"]) and int(cs["hired_by"]) == client and str(cs["kind"]) == "murder", "through 04's murder flow, with the contract on the case")
	K.expect(f, CrimePerson.coins(1) > coins_before and int(res["paid"]) > 0, "the fee is paid by the client (%d)" % int(res["paid"]))
	K.expect(f, not CrimePerson.alive(target) or CrimePerson.death_hidden(target), "the target is gone")
	K.expect(f, CrimeUnderLines.standing(1, "hit") > 0.0 and CrimeLifePath.member(1)["heat"] > 0.0, "standing and heat both rise")
	K.expect(f, CrimeLifeMoral.ledger_of(1).size() == 1, "the moral ledger remembers")
	# discovery and the police reach the case
	C.days(30)
	K.expect(f, int(cs.get("disc_day", -1)) >= 0 or str(cs["state"]) != "hidden", "the death is discovered (state %s)" % str(cs["state"]))
	K.teardown()

func _command_flow(f: Array) -> void:
	var w := C.town(14)
	var ids: Array = C.adults()
	Story.townies[int(ids[0])]["coins"] = 3000
	_hitman(1)
	var c: Dictionary = CrimeUnderHit.post(int(ids[0]), int(ids[1]), "grudge", {"fee": 400})
	var cid: int = int(c["id"])
	var r: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimeunder", "args": {"action": "hit_take", "contract": cid}})
	K.expect(f, bool(r["ok"]), "take the contract through the command layer")
	var bad: Dictionary = Commands.run({"player_id": 2, "folk_id": 1, "action": "crimeunder", "args": {"action": "hit_take", "contract": cid}})
	K.expect(f, not bool(bad["ok"]), "only the owner of the folk can act for them")
	K.set_time(3, 12, 0)
	var rs: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimeunder", "args": {"action": "hit_research", "contract": cid}})
	K.expect(f, bool(rs["ok"]) and CrimeLifeState.pending.size() == 1, "research takes time away from home")
	C.minutes(130)
	K.expect(f, float(c["research"]) > 0.0 and CrimeLifeState.pending.is_empty(), "when the time is up the research is applied")
	C.quiet_witnesses()
	var ex: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimeunder", "args": {"action": "hit_execute", "contract": cid, "scene": ""}})
	K.expect(f, bool(ex["ok"]) and CrimeLifeState.pending.size() == 1, "the act is queued as timed work")
	C.minutes(100)
	K.expect(f, str(c["state"]) in ["done", "botched"], "and resolved when it ends (%s)" % str(c["state"]))
	K.teardown()

func _refuse_and_tip(f: Array) -> void:
	var w := C.town(14)
	var ids: Array = C.adults()
	_hitman(1)
	Story.townies[int(ids[0])]["coins"] = 3000
	Story.townies[int(ids[1])]["coins"] = 2000
	var c: Dictionary = CrimeUnderHit.post(int(ids[0]), int(ids[1]), "grudge", {"fee": 400})
	var cred: float = CrimeLifePath.cred(1)
	var r: Dictionary = CrimeUnderHitRun.refuse(1, int(c["id"]))
	K.expect(f, bool(r["ok"]) and CrimeLifePath.cred(1) < cred, "refusing a contract costs a little standing")
	K.expect(f, str(c["state"]) == "open" and (c["refused_by"] as Array).has(1), "the contract stays on the board")
	CrimeUnderHitRun.take(1, int(c["id"]))
	var coins: int = CrimePerson.coins(1)
	var target_coins: int = CrimePerson.coins(int(ids[1]))
	var tip: Dictionary = CrimeUnderHitRun.tip(1, int(c["id"]))
	K.expect(f, bool(tip["ok"]) and str(c["state"]) == "tipped", "the hitman warns the target")
	K.expect(f, CrimePerson.coins(1) > coins and CrimePerson.coins(int(ids[1])) < target_coins, "the target pays a reward")
	K.expect(f, CrimeUnderRep.rec(1)["honour"] > 0.0, "mercy counts toward honour")
	K.expect(f, CrimePerson.alive(int(ids[1])), "the target lives")
	K.teardown()

func _mistakes(f: Array) -> void:
	var w := C.town(40)
	var ids: Array = C.adults()
	_hitman(1)
	CrimeLifeState.cfg()
	C.quiet_witnesses()
	K.set_time(3, 23, 0)
	var low: float = 0.0
	var high: float = 0.0
	var n: int = mini(ids.size() - 2, 8)
	for i in n:
		var cl: Dictionary = {"id": 900 + i, "client": int(ids[0]), "target": int(ids[2 + i]), "fee": 300, "cond": {"quiet": false, "alone": false}, "research": 0.0, "mistakes": 3, "state": "taken", "hitman": 1}
		var r1: Dictionary = CrimeUnderHitRun.resolve(1, cl, "street", {"force": "clean"})
		low += float(CaseStore.get_case(int(r1["case"])).get("trace", 0.0))
	for i in n:
		if 2 + n + i >= ids.size():
			break
		var ch: Dictionary = {"id": 950 + i, "client": int(ids[0]), "target": int(ids[2 + n + i]), "fee": 300, "cond": {"quiet": false, "alone": false}, "research": 1.0, "mistakes": 0, "state": "taken", "hitman": 1}
		var r2: Dictionary = CrimeUnderHitRun.resolve(1, ch, "street", {"force": "clean"})
		high += float(CaseStore.get_case(int(r2["case"])).get("trace", 0.0))
	K.expect(f, low > high * 1.8, "careless jobs leave far more to find than careful ones (trace %.2f vs %.2f)" % [low, high])
	CrimeLifePath.member(1)["heat"] = 0.0
	var careful: Dictionary = {"research": 1.0, "mistakes": 0}
	var sloppy: Dictionary = {"research": 0.0, "mistakes": 3}
	K.expect(f, float(CrimeUnderHitRun.odds(1, careful, "street", true)["pull"]) > float(CrimeUnderHitRun.odds(1, sloppy, "street", false)["pull"]) + 0.2, "research and a quiet scene raise the odds of pulling it off")
	K.teardown()

func _client_named(f: Array) -> void:
	var w := C.town(14)
	var ids: Array = C.adults()
	var client: int = int(ids[0])
	var target: int = int(ids[1])
	var hm: int = int(ids[2])
	Story.townies[client]["coins"] = 3000
	CrimeLifePath.join(hm, "chose")
	CrimeLifePath.member(hm)["cred"] = 40.0
	var l: Dictionary = {"hit": {"standing": 20.0, "since": 0, "acts": 0, "via": "contact"}}
	CrimeUnderState.lines[hm] = l
	var c: Dictionary = CrimeUnderHit.post(client, target, "grudge", {"fee": 400})
	c["state"] = "taken"
	c["hitman"] = hm
	var res: Dictionary = CrimeUnderHitRun.resolve(hm, c, CrimePerson.home_key(target), {"force": "clean"})
	var cs: Dictionary = CaseStore.get_case(int(res["case"]))
	cs["state"] = "open"
	cs["disc_day"] = SysUtil.day()
	CrimeUnderState.sect("hit")["conspiracy_link"] = 1.0
	JusticeProcess.arrest(cs, hm)
	K.expect(f, bool(cs.get("client_named", false)) and bool(cs.get("deal", false)), "a caught hitman may name the client")
	var named: Array = CaseStore.cases_of_culprit(client).filter(func(x): return str(x["kind"]) == "conspiracy")
	K.expect(f, named.size() == 1 and (CrimePerson.in_custody(client) or str(named[0]["state"]) in ["charged", "arrested", "trial"]), "and the client faces a conspiracy case")
	K.teardown()

func _player_target(f: Array) -> void:
	var w := C.town(14)
	var ids: Array = C.adults()
	var client: int = int(ids[0])
	Story.townies[client]["coins"] = 3000
	JusticePlayer.auto = "pay"
	WorldIface.coins[1] = 5000
	var c: Dictionary = CrimeUnderHit.post(client, 1, "grudge", {"fee": 500})
	CrimeUnderHit.on_day()
	K.expect(f, str(c["state"]) == "taken" and int(c["hitman"]) >= 0 and not CrimePerson.is_player(int(c["hitman"])), "a contract on the player's folk is staffed by a real townie")
	c["taken_day"] = SysUtil.day() - 3
	CrimeUnderHit._hunted_signs(CrimeUnderHit.cfg())
	K.expect(f, bool(c.get("warned", false)) and K.has_note("stranger has been asking"), "warning sign: a stranger asking around")
	K.expect(f, SysUtil.folk(1).has_buff("hunted"), "and the folk feels hunted")
	var coins: int = CrimePerson.coins(1)
	c["due_day"] = SysUtil.day()
	CrimeUnderHit.on_day()
	K.expect(f, str(c["state"]) == "bought_off" and CrimePerson.coins(1) < coins, "counterplay: paying them off ends it")
	JusticePlayer.auto = "ignore"
	var c2: Dictionary = CrimeUnderHit.post(int(ids[3]), 1, "grudge", {"fee": 300})
	Story.townies[int(ids[3])]["coins"] = 3000
	c2["state"] = "taken"
	c2["hitman"] = int(ids[4])
	c2["due_day"] = SysUtil.day()
	c2["npc"] = true
	var protect_police: float = float(CrimeUnderHit.cfg()["attack"]["protect_police"])
	var o_plain: float = float(CrimeUnderHitRun.odds(int(ids[4]), c2, "street", false)["pull"])
	K.expect(f, protect_police > 0.0 and o_plain > 0.0, "the odds exist and the police option protects (%.2f)" % protect_police)
	JusticePlayer.auto = ""
	K.teardown()
