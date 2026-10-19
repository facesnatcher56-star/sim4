extends RefCounted
## SLOW tier: the yearly rates of the 07b incidents (life events, good surprises, mould, gas) against config.chaos.targets_b. Only the 07b incidents are
## kept in the definitions while this runs (the other tasks are measured by their own long runs), and every day the household is put back into the
## state that qualifies it (a job, a miserable teen, a ticket, a rich old relative, overdue bills ...), so the rate under test is the dice, not the
## player. Rates are per QUALIFYING subject-year (the exposure counts only subjects that passed the conditions, far townies included for the folk-scope
## incidents). Warned incidents (layoff, eviction notice, runaway teen) are counted when the warning goes out, plus the far townies' statistical ones. Gas is hourly and very rare: it is rolled directly, hour by hour, for a long time.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")
const YEAR := 28
const DAILY := ["mould_growth", "layoff", "midlife_crisis", "identity_theft", "eviction_notice", "runaway_teen", "lottery_win", "inheritance", "long_lost_family"]
const WARNED := ["layoff", "eviction_notice", "runaway_teen"]
## Factor on the base rate from always-on risk entries (heating season x1.5 for a quarter of the year for gas). The far townies share the exposure of the folk-scope
## incidents, so household-only entries such as the computer for identity theft are tested in chaos_money_test, not here.
const RISK := {"gas_leak": 1.125}

var _kin_next := 9000

func run() -> Array:
	var f: Array = []
	var h: Dictionary = C.setup()
	StoryPacing.enabled = false
	Weather.force("sunny")
	Story.generate_townies()
	var w: StubWorld = h["w"]
	var ada: Folk = h["ada"]
	var teen := K.make_folk(w, "Teo Voss", [], 1, Vector2i(14, 12), "teen")
	var kid := K.make_folk(w, "Kit Voss", [], 1, Vector2i(15, 12), "child")
	Aging.records[int(ada.id)]["age_days"] = 130.0
	Aging.records[int(h["bo"].id)]["age_days"] = 100.0
	var objs: Dictionary = h["objs"]
	_keep_only(DAILY + ["gas_leak"])
	var years: int = TestFixture.pick(120, 60)
	var t0: int = Time.get_ticks_msec()
	var t_daily: int = 0
	for d in years * YEAR:
		K.set_time(2 + d, 9)
		_tidy(h, teen)
		IncidentChecks.run("day")
	t_daily = Time.get_ticks_msec() - t0
	var gas_def: Dictionary = IncidentDefs.get_def("gas_leak")
	var subj := IncidentSubject.of_household(1)
	var gas_years: int = TestFixture.pick(300, 150)
	for d2 in gas_years * YEAR:
		K.set_time(2 + d2, 12)
		ChaosState.gas.clear()
		for hr in 24:
			IncidentChecks._roll("gas_leak", gas_def, subj)
	var targets: Dictionary = ChaosState.cfg("targets_b")
	var report: Array = []
	for id in DAILY + ["gas_leak"]:
		var c: Dictionary = Incidents.stat(id)
		var events: int = int(c["warned"]) + int(c["statistical"]) if WARNED.has(id) else int(c["triggered"])
		var rate: float = float(events) / maxf(float(c["exposure"]), 0.0001)
		var target: float = float(targets[id]) * float(RISK.get(id, 1.0))
		var enough: bool = events >= 10 or (id == "long_lost_family" and events >= 5)
		var tol: float = clampf(2.5 / sqrt(maxf(float(events), 1.0)), 0.3, 0.6)             # about 2.5 standard deviations of a count, never tighter than 30 percent
		var ok: bool = enough and rate >= target * (1.0 - tol) and rate <= target * (1.0 + tol)
		K.expect(f, ok, "%s: %d events in %.0f subject-years = %.3f/yr (target %.3f)" % [id, events, float(c["exposure"]), rate, target])
		report.append("%s %d/%.0fy=%.3f" % [id, events, float(c["exposure"]), rate])
	# children and babies never roll the adult-only events
	for p in [kid]:
		for id2 in ["layoff", "midlife_crisis", "identity_theft", "runaway_teen"]:
			K.expect(f, Incidents.effective_rate(id2, IncidentSubject.of_folk(p)) == 0.0, "%s can never get %s" % [p.name, id2])
	K.expect(f, Incidents.effective_rate("runaway_teen", IncidentSubject.of_folk(ada)) == 0.0, "adults never run away")
	print("    chaos 07b longrun: %d years daily (%d ms) + %d years gas (%d ms): %s" % [years, t_daily, gas_years, Time.get_ticks_msec() - t0 - t_daily, "; ".join(report)])
	Weather.unforce()
	IncidentDefs.reset()
	K.teardown()
	return f

## Drop every incident but ours (and refresh the cached maxima).
func _keep_only(ids: Array) -> void:
	IncidentDefs.ensure()
	for id in IncidentDefs.defs.keys():
		if not ids.has(id):
			IncidentDefs.defs.erase(id)
	IncidentRisk._max_cache.clear()

## The household as it must be for every 07b incident to qualify, every day.
func _tidy(h: Dictionary, teen: Folk) -> void:
	var ada: Folk = h["ada"]
	var objs: Dictionary = h["objs"]
	Incidents.pending.clear()
	ChaosState.gas.clear()
	ChaosState.theft.clear()
	ChaosState.gone.clear()
	Away.pending.clear()
	Away.active.clear()
	teen.clear_queue()
	ChaosState.unhappy[int(teen.id)] = 6
	DisasterState.lots.clear()
	for id in ["sink", "bathtub", "shower"]:
		WorldIface.state_set(objs[id], "dirtiness", 8.0)             # a damp, grubby bathroom
	WorldIface.coins[1] = 3000
	for who in [ada, h["bo"]]:
		if not Careers.has_job(int(who.id)):
			Careers.hire(who, "cook", 1)
		Careers.jobs[int(who.id)]["performance"] = 40.0
	ada.remove_buff("identity_theft")
	BankGamble.tickets[1] = 1
	Economy.bills.clear()
	Economy.bills.append({"id": 1, "hid": 1, "amount": 80, "base": 70, "issued": 1, "due": 2, "paid": false, "late": true, "fee": 10})
	Economy.repossessed = [{"day": SysUtil.day(), "hid": 1, "def_id": "tv", "value": 100}]
	if ChaosKin.estate_relative(1) == null:                           # a rich old grandparent of Ada's, as often as needed
		var gp: Dictionary = Story.add_townie(185.0, "Old Rowan %d" % _kin_next, [], "")
		gp["coins"] = 1000
		_kin_next += 1
		Family.note_person(_kin_next, "Nell Voss")
		Family.link_parent(int(ada.id), _kin_next)
		Family.link_parent(_kin_next, int(gp["id"]))
		_kin_next += 1
