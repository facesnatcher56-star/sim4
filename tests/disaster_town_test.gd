extends RefCounted
## Town scope + persistence: one roll for the town then damage per lot (home FULL, far lots STATISTICAL with damage records and
## chronicle lines), insurance (premium on the bill, share of damage and hospital bills paid), save/load and reset safety, determinism.

const K = preload("res://tests/systems_kit.gd")
const D = preload("res://tests/disaster_kit.gd")

func run() -> Array:
	var f: Array = []
	_far_lots(f)
	_insurance(f)
	_persistence(f)
	_determinism(f)
	return f

func _far_lots(f: Array) -> void:
	var w := D.setup()
	D.home(w)
	Story.generate_townies()
	var lots: int = IncidentChecks.lot_subjects().size()
	K.expect(f, lots >= 3, "home plus townie lots exist (%d)" % lots)
	var r: Dictionary = Incidents.force("tornado", {"outcome": 1})
	K.expect(f, bool(r["ok"]), "a forced tornado hits every lot")
	var hist: Array = Incidents.history(60).filter(func(x): return x["id"] == "tornado")
	var modes: Array = hist.map(func(x): return x["mode"])
	K.expect(f, hist.size() == lots and modes.has("full") and modes.has("statistical"), "home FULL, the rest STATISTICAL (%s)" % str(modes))
	var far_records: int = 0
	for key in DisasterState.lots:
		if str(key).begins_with("town:") and int(DisasterState.lots[key]["cost"]) > 0:
			far_records += 1
	K.expect(f, far_records == lots - 1, "every far lot got a damage record (%d)" % far_records)
	var chron: int = 0
	for c in ChronicleHook.recent:
		if str(c["kind"]) == "tornado" and str(c["lot"]).begins_with("town:"):
			chron += 1
	K.expect(f, chron >= 1, "far lots appear in the chronicle (%d lines)" % chron)
	K.expect(f, int(DisasterState.counts.get("tornado", 0)) == 1, "the town event is counted once, not per lot")
	var toasts: int = 0
	for n in K.notes:
		if str(n[0]).find("tornado") >= 0 or str(n[0]).find("Tornado") >= 0:
			toasts += 1
	K.expect(f, toasts <= 3, "toast volume stays low: headline + home lot only (%d)" % toasts)
	# far repairs
	var any_key: String = ""
	for key2 in DisasterState.lots:
		if str(key2).begins_with("town:"):
			any_key = str(key2)
			break
	DisasterFar.on_day(SysUtil.day() + 20)
	K.expect(f, any_key != "" and int(DisasterState.lots[any_key]["cost"]) == 0, "far lots are repaired after some days")
	K.teardown()

func _insurance(f: Array) -> void:
	var w := D.setup()
	D.home(w)
	var plain: int = Economy.compute_bill(1)
	DisasterInsurance.set_level(1, "basic")
	K.expect(f, Economy.compute_bill(1) == plain + 30, "basic cover adds its weekly premium to the bill")
	DisasterInsurance.set_level(1, "full")
	K.expect(f, Economy.compute_bill(1) == plain + 70, "full cover costs more")
	K.expect(f, Incidents.insurance_cover(1000, 1) == 750, "full cover pays 75 percent of a loss")
	var before: int = WorldIface.get_coins(1)
	var paid: int = Hospital.charge(1, 200, "Ada")
	K.expect(f, paid == 50 and WorldIface.get_coins(1) == before - 50, "insurance also covers hospital bills (net %d)" % paid)
	DisasterInsurance.set_level(1, "")
	K.expect(f, Economy.compute_bill(1) == plain and Incidents.insurance_cover(1000, 1) == 0, "no policy, no premium, no payout")
	# the mailbox interaction cycles none -> basic -> full -> none
	var ada := K.make_folk(w, "Ada Voss", [], 1)
	SimEnv.emit("game_event", "change_insurance", {"folk_id": ada.id, "object_id": -1, "target_id": -1})
	K.expect(f, DisasterInsurance.level(1) == "basic" and K.has_note("Basic cover"), "mailbox: first click buys basic cover")
	SimEnv.emit("game_event", "change_insurance", {"folk_id": ada.id, "object_id": -1, "target_id": -1})
	SimEnv.emit("game_event", "change_insurance", {"folk_id": ada.id, "object_id": -1, "target_id": -1})
	K.expect(f, DisasterInsurance.level(1) == "", "and cancels again after full")
	K.teardown()

func _persistence(f: Array) -> void:
	var w := D.setup()
	D.home(w)
	DisasterInsurance.set_level(1, "full")
	DisasterState.siren_when_forced = true
	D.force_home("tornado", 1)
	D.force_home("power_outage")
	DisasterState.lot("home:1")["mould"] = 0.4
	DisasterState.rain_days = 2
	var snap: Dictionary = JSON.parse_string(JSON.stringify(Incidents.to_dict()))
	var before: Dictionary = DisasterState.to_dict()
	Incidents.reset()
	K.expect(f, DisasterState.active.is_empty() and DisasterState.lots.is_empty() and DisasterState.insurance.is_empty(), "reset clears the disaster state")
	Incidents.from_dict(snap)
	var out: Array = []
	K.expect(f, K.deep_eq(JSON.parse_string(JSON.stringify(before)), JSON.parse_string(JSON.stringify(DisasterState.to_dict())), "", out), "save/load round trip keeps the state: %s" % str(out.slice(0, 3)))
	K.expect(f, DisasterInsurance.level(1) == "full" and DisasterState.active.size() >= 2, "insurance and running events survive")
	# a pending siren still lands after loading
	D.run_minutes(8)
	var tor: Dictionary = DisasterState.find("tornado")
	K.expect(f, str(tor.get("phase", "")) == "on" and int(DisasterState.lot("home:1")["cost"]) > 0, "the siren timer survives a save and the tornado lands")
	K.teardown()

func _run_seed(seed_v: int) -> String:
	var w := D.setup()
	D.home(w)
	Incidents.seed_rng(seed_v)
	Story.generate_townies()
	Incidents.force("tornado", {"outcome": 1})
	Incidents.force("earthquake", {"outcome": 1})
	var out: String = ""
	for x in Incidents.history(40):
		out += str(x["text"]) + "|"
	K.teardown()
	return out

func _determinism(f: Array) -> void:
	var a: String = _run_seed(5)
	var b: String = _run_seed(5)
	K.expect(f, a != "" and a == b, "same seed, same disaster history")
