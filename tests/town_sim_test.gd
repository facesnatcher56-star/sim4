extends RefCounted
## TownSim (task 17.3 stages 2-3): the cheap TOWN schedule and needs curves, the hourly bucketed tier update, PROMOTION (a plausible Folk from the record)
## and DEMOTION (needs / last place go back into the record).

const HoodKit := preload("res://tests/hood_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	HoodKit.teardown()
	var folk: Array = HoodKit.new_game("classic", 33, 33)
	var me = folk[0]
	var townies: Array = Story.alive_townies()
	_check(townies.size() >= 6, "the town has townies (%d)" % townies.size())
	var t: Dictionary = townies[0]
	var tid: int = int(t["id"])
	# --- the schedule: asleep at night at home, only real lots, deterministic
	var acts: Dictionary = {}
	for day in 3:
		for h in 24:
			var mn: int = day * 1440 + h * 60 + 30
			var w: Dictionary = TownSim.where(t, mn)
			acts[str(w["act"])] = true
			_check(str(w["lot"]) == "" or not Neighborhood.lot(str(w["lot"])).is_empty(), "where() names a real lot (%s)" % str(w["lot"]))
			_check(TownSim.where(t, mn) == w, "where() is a pure function of the record and the clock")
	_check(acts.has(TownSim.SLEEP) and acts.has(TownSim.HOME_ACT), "over three days a townie sleeps and is at home (%s)" % str(acts.keys()))
	var asleep: Dictionary = TownSim.where(t, 3 * 60)
	_check(str(asleep["act"]) in [TownSim.SLEEP, TownSim.WORK], "03:00 is sleep (or a night shift): %s" % str(asleep["act"]))
	# --- needs curves stay inside the needs table
	var defs: Dictionary = SimEnv.data().needs()
	for h2 in 24:
		var ns: Dictionary = TownSim.needs_at(t, h2 * 60)
		for n in defs:
			var v: float = float(ns[n])
			_check(v >= float(defs[n]["min"]) and v <= float(defs[n]["max"]), "need %s inside its range (%.1f)" % [n, v])
	# --- the hourly update: contact => TOWN with a stored record; far with no contact => STATISTICAL
	Tiers.refresh()
	RelationshipService.add_both(int(me.id), tid, "friendship", 12.0)
	TownSim.hourly(tid)
	_check(TownSim.tier_of(tid) == Tiers.TOWN and Tiers.of(tid) == Tiers.TOWN, "a townie who knows the household is TOWN (%s)" % Tiers.NAMES[Tiers.of(tid)])
	var rec: Dictionary = Story.townies[tid].get("town", {})
	_check(rec.has("needs") and rec.has("place") and rec.has("act") and rec.has("min"), "the TOWN update stores needs / place / act / minute in the record")
	var other: Dictionary = townies[1]
	var radius_save = Tiers.cfg().get("town_radius", 96)
	Tiers.cfg()["town_radius"] = 0
	TownSim.hourly(int(other["id"]))
	Tiers.cfg()["town_radius"] = radius_save
	_check(TownSim.tier_of(int(other["id"])) == Tiers.STATISTICAL, "far with no contact: STATISTICAL (%s)" % Tiers.NAMES[Tiers.of(int(other["id"]))])
	_check(not (Story.townies[int(other["id"])].get("town", {}) as Dictionary).has("needs"), "STATISTICAL townies store nothing hourly")
	var ct: Array = Tiers.counts()
	_check(int(ct[2]) >= 1 and int(ct[3]) >= 1, "counts show TOWN and STATISTICAL people: %s" % str(ct))
	# --- promotion: a plausible Folk
	var lot := ""
	for lid in Neighborhood.lot_ids():
		if lid != Neighborhood.HOME and Venues.type_of_lot(lid) == "cafe":
			lot = lid
	if lot != "":
		HoodKit.set_time(2, 12)
		var f: Folk = Crowd.spawn_npc(t, lot, Venues.type_of_lot(lot))
		_check(f != null and SysUtil.folk(tid) != null, "the townie is in the world")
		var rc := NeighborhoodLots.rect_of(lot)
		_check(rc.has_point(f.tile) or f.tile == NeighborhoodLots.gate_tile(lot), "promoted onto the lot (its spawn tiles / gate): %s in %s" % [str(f.tile), str(rc)])
		var curve: Dictionary = TownSim.needs_at(t, SimEnv.now_min())
		var near_curve := 0
		var tuned: Dictionary = Venues.type_def(Venues.type_of_lot(lot)).get("crowd_needs", {})      # the venue tunes some needs of its regulars on arrival
		var free_needs := 0
		for n2 in f.needs:
			var sv: float = (f.needs[n2] as Stat).value
			_check(sv >= float((f.needs[n2] as Stat).min) and sv <= float((f.needs[n2] as Stat).max), "promoted need %s inside its range" % n2)
			if tuned.has(n2):
				continue
			free_needs += 1
			if absf(sv - float(curve[n2])) < 1.0:
				near_curve += 1
		_check(near_curve == free_needs, "the untuned needs are the curve values (%d of %d)" % [near_curve, free_needs])
		# --- demotion keeps the record
		(f.needs["hunger"] as Stat).set_value(-12.0)
		Crowd.dismiss(f)
		var rec2: Dictionary = Story.townies[tid].get("town", {})
		_check(SysUtil.folk(tid) == null, "demoted: the Folk is gone from the world")
		_check(is_equal_approx(float((rec2.get("needs", {}) as Dictionary).get("hunger", 99.0)), -12.0), "the record kept the needs (hunger %s)" % str((rec2.get("needs", {}) as Dictionary).get("hunger", "?")))
		_check(str(rec2.get("place", "x")) == lot or str(rec2.get("place", "x")) == "", "the record kept the last place (%s)" % str(rec2.get("place", "?")))
		_check(Tiers.of(tid) in [Tiers.TOWN, Tiers.STATISTICAL], "after demotion the person is TOWN / STATISTICAL again")
		# promoted again soon after: the stored need survives; much later: it relaxes to the curve
		var soon: Dictionary = TownSim.needs_for_promotion(Story.townies[tid], SimEnv.now_min() + 5)
		_check(float(soon["hunger"]) < float(TownSim.needs_at(t, SimEnv.now_min() + 5)["hunger"]) - 3.0, "5 minutes later the low hunger is still remembered (%.1f)" % float(soon["hunger"]))
		var late: Dictionary = TownSim.needs_for_promotion(Story.townies[tid], SimEnv.now_min() + 1440)
		_check(is_equal_approx(float(late["hunger"]), float(TownSim.needs_at(t, SimEnv.now_min() + 1440)["hunger"])), "a day later the need is back on the curve")
	HoodKit.teardown()
	return fails
