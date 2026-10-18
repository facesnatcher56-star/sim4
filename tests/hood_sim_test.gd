extends RefCounted
## Headless run: three game days with trips to the park and the cafe (and the gym / market), jobs and school keep working
## from wherever the folk are, nobody starves, bookkeeping stays consistent.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_three_days()
	_work_from_elsewhere()
	Kit.teardown()
	return fails

func _worst(folk: Array) -> float:
	var w := 1000.0
	for f in folk:
		for n in ["hunger", "energy", "bladder", "hygiene"]:
			w = minf(w, f.get_stat_value(n))
	return w

func _three_days() -> void:
	var folk: Array = Kit.new_game("classic")
	var W: Node = Kit.world()
	var ids: Array = [folk[0].id, folk[1].id, folk[2].id]
	Kit.set_time(2, 7)                         # Tuesday morning
	var worst := 1000.0
	var trips := 0
	var plan := {
		8 * 60: ["park", [0, 1, 2]], 12 * 60: ["cafe", [0, 1]], 15 * 60: ["home", [0, 1, 2]],
		16 * 60: ["market", [2]], 18 * 60: ["home", [0, 1, 2]],
		24 * 60 + 9 * 60: ["gym", [0]], 24 * 60 + 12 * 60: ["park", [0, 1, 2]], 24 * 60 + 17 * 60: ["cafe", [1, 2]],
		24 * 60 + 20 * 60: ["home", [0, 1, 2]],
		48 * 60 + 10 * 60: ["park", [1]], 48 * 60 + 13 * 60: ["cafe", [0, 1, 2]], 48 * 60 + 19 * 60: ["home", [0, 1, 2]],
	}
	WorldIface.coins[1] = 4000
	for m in 3 * 1440:
		var tod: int = m + 7 * 60                 # minutes since day-2 00:00 (the run starts at 07:00)
		if plan.has(tod):
			var step: Array = plan[tod]
			var who: Array = []
			for i in step[1]:
				who.append(ids[i])
			var res: Dictionary = Neighborhood.travel(who, str(step[0]), {"quiet": true, "fast": true})
			if bool(res["ok"]):
				trips += 1
		Kit.run(1)
		if m % 15 == 0:
			worst = minf(worst, _worst(folk))
	_check(trips >= 9, "most planned trips happened (%d)" % trips)
	_check(worst > -85.0, "nobody starved or collapsed over three days (worst need %.1f)" % worst)
	for f in folk:
		_check(W.get_folk(f.id) != null, "%s still exists" % f.name)
	for lid in Neighborhood.lot_ids():
		_check(Crowd.count(lid) <= Venues.crowd_cap(), "crowd cap held in %s (%d)" % [lid, Crowd.count(lid)])
	# consistent bookkeeping at the end: where a folk is follows from its tile, nobody is stuck hidden
	for f in folk:
		_check(not f.has_meta("away") or Away.active.has(f.id) or Away.pending.has(f.id), "%s is hidden without an away record" % f.name)
		_check(World.is_walkable(f.tile) or f.current != null, "%s stands somewhere sane" % f.name)
	_check(Kit.count_events("lot_changed") >= trips, "lot_changed events were emitted")

## A job keeps running from wherever the folk is: at the park and at home.
func _work_from_elsewhere() -> void:
	var folk: Array = Kit.new_game("classic")
	var mira: Folk = folk[0]
	var tobin: Folk = folk[1]
	Careers.hire(mira, "coder", 1)
	Careers.hire(tobin, "coder", 1)
	Kit.set_time(2, 7, 40)                     # Tuesday, shift starts at 09:00
	WorldIface.coins[1] = 1000
	var r: Dictionary = Neighborhood.travel([mira.id], "park", {"quiet": true, "fast": true})      # tobin stays home
	_check(bool(r["ok"]), "mira heads to the park")
	var coins_before: int = Economy.balance(1)
	Kit.run(30)                                # 08:10: the real commute (task 11) sets off ~08:20 for the 09:00 shift, so look before that
	_check(Neighborhood.where(tobin.id) == "home" and Neighborhood.where(mira.id) == "park", "mira at the park, tobin at home")
	Kit.run(60 + 70)                           # 09:20
	_check(Away.active.has(mira.id) and str(Away.info(mira.id).get("reason", "")) == "work", "mira left the park for work")
	_check(Away.active.has(tobin.id) and str(Away.info(tobin.id).get("reason", "")) == "work", "tobin at home was dispatched to work too (reason %s)" % str(Away.info(tobin.id).get("reason", "")))
	Kit.run(9 * 60)                            # past 17:00 + margin
	_check(str(Away.info(mira.id).get("reason", "")) != "work" and str(Away.info(tobin.id).get("reason", "")) != "work", "both are back from work")
	_check(Economy.balance(1) > coins_before + 150, "wages were paid (%d -> %d)" % [coins_before, Economy.balance(1)])
	# A real commute (task 11) walks the folk HOME when the shift ends, wherever she set off from (the old instant rabbit hole left her at the park).
	_check(Neighborhood.where(mira.id) == "home" and not mira.has_meta("away"), "mira commuted home from work (she had set off from the park)")
	Kit.run(5)
	_check(Neighborhood.where(tobin.id) == "home", "tobin is back at home")
	_check(Careers.jobs[mira.id]["days_worked"] >= 1 and Careers.jobs[tobin.id]["days_worked"] >= 1, "both shifts were completed")
