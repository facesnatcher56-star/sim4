extends RefCounted
## Task 12.4: taxes and the town budget, the mayor and council, elections (campaign, speeches, votes driven by the town's mood), policies and permits.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/city_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := C.setup()
	var h: Dictionary = C.home(w)
	var ada: Folk = h["ada"]
	K.set_time(5, 10)
	Story.generate_townies()
	CityGov.install()
	CityGov.ensure()
	# --- the first mayor and council
	K.expect(f, not CityGov.mayor.is_empty() and Story.townies.has(int(CityGov.mayor["id"])), "a townie is mayor at the start (%s)" % str(CityGov.mayor.get("name", "nobody")))
	K.expect(f, CityGov.council.size() == 4 and not CityGov.council.any(func(m): return int(m["id"]) == int(CityGov.mayor["id"])), "the council has four other townies")
	# --- budget
	K.expect(f, is_equal_approx(CityGov.tax, 1.0) and is_equal_approx(CityBudget.funding("police"), 1.0), "the standard budget funds every department at 1.0")
	CityGov.set_tax(1.3)
	K.expect(f, CityBudget.funding("police") > 1.25 and CityBudget.funding("roads") > 1.25, "higher taxes fund every department better")
	K.expect(f, CityGov.revenue(1.3) > CityGov.revenue(1.0), "and bring in more money")
	CityGov.set_tax(1.0)
	CityGov.shift("police", 0.06)
	K.expect(f, CityBudget.funding("police") > 1.3 and CityBudget.funding("roads") < 1.0 and CityBudget.funding("parks") < 1.0, "more for the police means less for the others")
	var sum: float = 0.0
	for d in CityGov.alloc:
		sum += float(CityGov.alloc[d])
	K.expect(f, absf(sum - 1.0) < 0.001, "the shares still add up to the whole budget (%.3f)" % sum)
	CityGov.alloc = CityGov.default_alloc().duplicate()
	CityGov.recompute()
	var t0: float = CityGov.treasury
	CityGov.budget_week()
	K.expect(f, CityGov.treasury > t0, "the reserve share is saved every week")
	CityGov.treasury = 0.0
	CityGov.set_tax(0.7)
	var thin: float = CityBudget.funding("fire")
	CityGov.treasury = 5000.0
	CityGov.recompute()
	K.expect(f, CityBudget.funding("fire") > thin, "savings top up a starved department")
	CityGov.treasury = -2000.0
	CityGov.set_tax(1.0)
	K.expect(f, CityBudget.funding("fire") < 1.0, "a town in debt has to cut services")
	CityGov.treasury = 0.0
	CityGov.recompute()
	# --- the council charges on the bill follow the tax
	Economy.usage[1] = 0.0
	var rates1: float = float(UtilityBills.parts(1)["rates"])
	CityGov.set_tax(1.5)
	K.expect(f, float(UtilityBills.parts(1)["rates"]) > rates1 * 1.45, "taxes show in the council charges of the household bill")
	CityGov.set_tax(1.0)
	# --- mood
	K.expect(f, CityMood.update() > -0.5, "an ordinary town is not angry (%.2f)" % CityGov.mood_now)
	CityGov.set_tax(1.6)
	var low: float = CityMood.update()
	CityGov.set_tax(0.7)
	K.expect(f, CityMood.update() > low, "heavy taxes make the town grumpy")
	CityGov.set_tax(1.0)
	K.expect(f, CityMood.complaint() in ["services", "utilities", "tax", "crime", "roads", "public"] and CityMood.words() != "", "the biggest complaint and the mood are in words: %s / %s" % [CityMood.complaint(), CityMood.words()])
	# --- the campaign
	var first_mayor: int = int(CityGov.mayor["id"])
	CityGov.mayor["term_end"] = SysUtil.day() + 10
	CityGov.on_day(SysUtil.day())
	K.expect(f, CityElection.phase == "campaign" and CityElection.candidates.size() >= 2, "two weeks before the vote the campaign starts with at least two candidates")
	K.expect(f, K.has_note("Election campaign"), "the player hears about it")
	ada.add_skill_xp("charisma", 400.0)
	K.expect(f, ada.skill_level("charisma") >= 1, "Ada has some charisma")
	CityGov.on_event("run_for_mayor", {"folk_id": ada.id})
	K.expect(f, CityElection.is_candidate(int(ada.id)), "a player folk can stand for mayor")
	var sup0: float = float(CityElection.candidates[CityElection._index_of(int(ada.id))]["support"])
	CityGov.on_event("campaign_speech", {"folk_id": ada.id})
	CityGov.on_event("campaign_speech", {"folk_id": ada.id})
	var sup1: float = float(CityElection.candidates[CityElection._index_of(int(ada.id))]["support"])
	K.expect(f, sup1 > sup0 + 1.0, "speeches win support (%.1f -> %.1f)" % [sup0, sup1])
	for i in 4:
		CityGov.on_event("campaign_speech", {"folk_id": ada.id})
	K.expect(f, int(CityElection.candidates[CityElection._index_of(int(ada.id))]["today"]) == 3, "but only three speeches a day count")
	CityGov.on_event("vote_mayor", {"folk_id": ada.id})
	K.expect(f, CityElection.votes.has(str(ada.id)), "the household can vote")
	# --- election day: a strong, noisy campaign
	var bo: Folk = h["bo"]
	CityGov.on_event("vote_mayor", {"folk_id": bo.id})
	var idx: int = CityElection._index_of(int(ada.id))
	CityElection.candidates[idx]["support"] = 30.0
	K.set_time(SysUtil.day() + 10, 8)
	CityGov.on_day(SysUtil.day())
	K.expect(f, CityElection.phase == "idle" and int(CityGov.mayor["id"]) == int(ada.id) and bool(CityGov.mayor["player"]), "with a huge campaign the player wins (%s)" % str(CityElection.last))
	K.expect(f, ada.has_buff("mayor") and Careers.jobs.has(int(ada.id)) and str(Careers.jobs[int(ada.id)]["career"]) == "politician", "the new mayor gets the buff and the politician job")
	K.expect(f, K.has_note("elected mayor"), "the result is announced")
	K.expect(f, int(CityGov.mayor["term_end"]) > SysUtil.day() + 80, "a new term starts")
	# --- the player mayor's levers
	var t_before: float = CityGov.tax
	CityGov.on_event("tax_up", {"folk_id": ada.id})
	K.expect(f, CityGov.tax > t_before, "a mayor can raise taxes")
	CityGov.on_event("tax_down", {"folk_id": bo.id})
	K.expect(f, CityGov.tax > t_before, "but nobody else can lower them")
	CityGov.on_event("focus_roads", {"folk_id": ada.id})
	K.expect(f, CityBudget.funding("roads") > 1.0, "the mayor can shift the budget")
	K.expect(f, (SimEnv.data().interactions()["tax_up"]["tests"] as Array).has({"has_buff": "mayor"}) and (SimEnv.data().interactions()["propose_curfew"]["tests"] as Array).has({"has_buff": "mayor"}), "the mayor's interactions need the mayor buff")
	# --- policies
	CityGov.alloc = CityGov.default_alloc().duplicate()
	CityGov.set_tax(1.0)
	for m in CityGov.council:
		m["lean"] = {"safety": 1.0, "freedom": -1.0, "thrift": 0.0, "services": 0.5, "peace": 1.0, "green": 1.0}
	var r: Dictionary = CityPolicy.propose("curfew", true)
	K.expect(f, bool(r["ok"]) and CityPolicy.active("curfew") and K.has_note("Curfew"), "a council that likes safety votes the curfew in")
	var kid := K.make_folk(w, "Kit Voss", [], 1, Vector2i(14, 12), "teen")
	K.set_time(40, 23)
	K.expect(f, str(CityPolicy.blocks_entry("cafe", [int(kid.id)])) != "" and CityPolicy.blocks_entry("cafe", [int(ada.id)]) == "", "under the curfew a teen cannot enter venues at night, an adult can")
	K.set_time(40, 14)
	K.expect(f, CityPolicy.blocks_entry("cafe", [int(kid.id)]) == "", "by day nothing changes")
	K.expect(f, CityPolicy.crime_mult() < 1.0 and Police.patrol_factor() < 1.0 / (1.0 + 0.0001) , "the curfew makes street crime rarer")
	r = CityPolicy.propose("curfew", true)
	K.expect(f, not bool(r["ok"]) and CityPolicy.active("curfew"), "a new law is not repealed at once")
	K.set_time(80, 12)
	for m4 in CityGov.council:
		m4["lean"] = {"safety": -1.0, "freedom": 1.0, "thrift": 0.0, "services": 0.0, "peace": 0.0, "green": 0.0}
	r = CityPolicy.propose("curfew", true)
	K.expect(f, bool(r["ok"]) and not CityPolicy.active("curfew"), "a month later a council that dislikes it can end it again")
	for m2 in CityGov.council:
		m2["lean"] = {"safety": -1.0, "freedom": 1.0, "thrift": -1.0, "services": -1.0, "peace": -1.0, "green": -1.0}
	K.expect(f, not bool(CityPolicy.propose("park_hours", true)["ok"]) and not CityPolicy.active("park_hours"), "a council that likes freedom turns the park closing hours down")
	for m3 in CityGov.council:
		m3["lean"] = {"safety": 1.0, "freedom": -1.0, "thrift": 0.3, "services": 1.0, "peace": 1.0, "green": 1.0}
	CityPolicy.propose("park_hours", true)
	CityPolicy.propose("noise_rules", true)
	CityPolicy.propose("free_buses", true)
	CityPolicy.propose("green_grants", true)
	CityPolicy.propose("permits", true)
	K.set_time(80, 23)
	K.expect(f, CityPolicy.active("park_hours") and CityPolicy.blocks_entry("park", [int(ada.id)]).find("park is closed") >= 0, "the parks close at night")
	K.expect(f, CityPolicy.fare_mult() == 0.0 and int(TransportBus.plan("school", "cafe")["fare"]) == 0, "free buses cost nothing")
	var bal: int = int(WorldIface.coins[1])
	CityPolicy.on_interaction(ada, "karaoke")
	CityPolicy.on_interaction(ada, "karaoke")
	CityPolicy.on_interaction(ada, "karaoke")
	CityPolicy.on_interaction(ada, "karaoke")
	CityPolicy.on_interaction(ada, "karaoke")
	CityPolicy.on_interaction(ada, "karaoke")
	K.expect(f, int(WorldIface.coins[1]) < bal and K.has_note("complained"), "loud things at night bring complaints and fines")
	K.set_time(80, 12)
	bal = int(WorldIface.coins[1])
	var res: Dictionary = CityPolicy.pay_permit(1, "build")
	K.expect(f, bool(res["ok"]) and int(res["fee"]) == 40 and int(WorldIface.coins[1]) == bal - 40, "building needs a permit once the council has voted for them")
	K.expect(f, int(CityPolicy.pay_permit(1, "build")["fee"]) == 0, "one permit covers the whole day")
	K.set_time(81, 12)
	WorldIface.coins[1] = 5
	res = CityPolicy.pay_permit(1, "build")
	K.expect(f, not bool(res["ok"]) and str(res.get("reason", "")).find("permit") >= 0, "without the money for the permit nothing is built (%s)" % str(res))
	K.expect(f, CityPolicy.permit_fee("business") == 120, "a business permit costs 120 coins")
	# --- townie mayor proposes things on their own
	CityGov.policies.clear()
	CityGov.mayor = {"id": first_mayor, "name": "Someone", "since": 1, "term_end": 9999, "platform": "safety", "player": false}
	var proposed: int = 0
	CityElection.reset()
	CityState.rng.seed = 7
	for dd in range(28, 28 * 40, 28):
		var before_n: int = CityGov.history.size()
		CityPolicy.on_day(dd)
		if CityGov.history.size() > before_n:
			proposed += 1
	K.expect(f, proposed > 5, "a townie mayor brings policies to the council every so often (%d in 39 months)" % proposed)
	# --- the notice board
	CityGov.on_event("town_notice", {"folk_id": ada.id})
	K.expect(f, K.has_note("Taxes are") and K.has_note("budget goes to") and K.has_note("Mayor "), "the town notice says who is mayor, the taxes and where the money goes")
	# --- save and load
	var before: String = JSON.stringify(CityState.to_dict())
	CityState.from_dict(JSON.parse_string(before))
	K.expect(f, JSON.stringify(CityState.to_dict()) == before, "the government survives a JSON round trip")
	K.teardown()
	return f
