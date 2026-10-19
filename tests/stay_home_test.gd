extends RefCounted
## "Stay at home" (a homemaker role) and job offers that wait: nobody takes an offer on their own unless they are looking for work, and
## nobody changes career again within a week.

const K = preload("res://tests/systems_kit.gd")
const Kit = preload("res://tests/sim_testkit.gd")

func run() -> Array:
	var f: Array = []
	_homemaker(f)
	_offers_wait(f)
	_no_churn(f)
	return f

func _cmd(fid: int, on: bool) -> Dictionary:
	return CommandActions.dispatch({"action": "set_homemaker", "folk_id": fid, "args": {"on": on}})

func _homemaker(f: Array) -> void:
	var w := K.setup(3, true)
	var a := K.make_folk(w, "Mia Rowe", [], 1)
	var o: Dictionary = Kit.furnish(w)
	K.mgr.new_game([1])
	Careers.hire(a, "coder", 1)
	K.expect(f, Careers.jobs.has(int(a.id)), "setup: employed")
	K.expect(f, bool(_cmd(int(a.id), true)["ok"]) and Homemaker.is_homemaker(a) and not Careers.jobs.has(int(a.id)), "Stay at home through the command layer ends the job")
	K.expect(f, Careers.make_offer(a).is_empty() and not Careers.hire(a, "coder", 1), "a homemaker gets no offer and cannot be hired")
	WorldIface.state_set(o["table"], "dirtiness", 5.0)
	WorldIface.state_set(o["fridge"], "spoiled", 3.0)
	var kid := K.make_folk(w, "Pip Rowe", [], 1, Vector2i(12, 13), "toddler")
	(kid.needs["social"] as Stat).set_value(0.0)
	Homemaker.on_day()
	K.expect(f, float(WorldIface.state_get(o["table"], "dirtiness", 5.0)) < 5.0, "daily bonus: a cleaner house")
	K.expect(f, float(WorldIface.state_get(o["fridge"], "spoiled", 3.0)) == 0.0, "daily bonus: the fridge is cleared of spoiled food")
	K.expect(f, (kid.needs["social"] as Stat).value > 0.0, "daily bonus: the little one gets attention")
	var cook := {"tags": ["cook"]}
	K.expect(f, Homemaker.mult(a, cook) > 1.0 and Homemaker.mult(kid, cook) == 1.0, "autonomy weighs cooking higher for a homemaker only")
	var snap: Dictionary = Careers.to_dict()
	Careers.from_dict(snap)
	K.expect(f, Careers.homemakers.has(int(a.id)), "the role survives a save and load")
	_cmd(int(a.id), false)
	K.expect(f, not Homemaker.is_homemaker(a), "and can be switched off")
	K.teardown()

## Offers wait for an answer; a household that is fine for money never takes one on its own.
func _offers_wait(f: Array) -> void:
	var w := K.setup(4, true)
	var a := K.make_folk(w, "Una Rowe", [], 1)
	var h := K.make_folk(w, "Hal Rowe", [], 1, Vector2i(14, 12))
	K.mgr.new_game([1])
	WorldIface.coins[1] = 5000
	Economy.deposit(1, 5000, "test")
	Careers.confirm_offers = true
	_cmd(int(h.id), true)
	for d in range(2, 60):
		K.set_time(d, 6)
		Careers.on_day(d)
		OpportunityTaker.on_day(d)
	Careers.confirm_offers = false
	K.expect(f, not Careers.jobs.has(int(a.id)), "an unemployed adult who is not looking for work takes no offer on their own (60 days)")
	K.expect(f, not Careers.jobs.has(int(h.id)) and not K.has_note("Hal Rowe got a job offer"), "a homemaker is never offered anything")
	K.teardown()

## Somebody short of money does take a job, but even with a probe quitting each one nobody changes career more than once a week.
func _no_churn(f: Array) -> void:
	var w := K.setup(5, true)
	var a := K.make_folk(w, "Una Rowe", [], 1)
	K.mgr.new_game([1])
	WorldIface.coins[1] = 20          # short of money: looking for work
	Careers.confirm_offers = true
	var hires: Array = []
	for d in range(2, 80):
		K.set_time(d, 6)
		Careers.on_day(d)
		OpportunityTaker.on_day(d)
		if Careers.jobs.has(int(a.id)):
			hires.append(d)
			Careers.quit_job(a)
	Careers.confirm_offers = false
	var min_gap: int = 999
	for i in range(1, hires.size()):
		min_gap = mini(min_gap, int(hires[i]) - int(hires[i - 1]))
	K.expect(f, hires.size() >= 1, "somebody short of money takes a job")
	K.expect(f, min_gap >= 7, "no career change within 7 days of the last (closest %d days apart, %d jobs in 78 days)" % [min_gap, hires.size()])
	K.teardown()
