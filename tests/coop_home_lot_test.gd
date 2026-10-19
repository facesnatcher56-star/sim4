extends RefCounted
## Co-op: "home" is per household. A guest's worker commutes out and comes back to the guest's OWN lot (not the host's), and the other
## "go home" paths (visit/party door, holiday return, hospital discharge, stranded walk) ask PlayerLots.home_of too. Solo stays on "home".

const HoodKit := preload("res://tests/hood_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _household(names: Array) -> Dictionary:
	var folk: Array = []
	for n in names:
		folk.append(HouseholdSetup.random_folk("adult", "none", names.duplicate()))
		folk[folk.size() - 1]["name"] = n
	return {"name": "Newcomers", "folk": folk}

func run() -> Array:
	fails = []
	var host_folk: Array = HoodKit.new_game("classic")
	StoryPacing.enabled = false
	Players.set_player(1, 1, "Hosty")
	HoodKit.run(5)
	# solo / host behaviour is unchanged
	_check(PlayerLots.home_of(host_folk[0]) == Neighborhood.HOME, "the host's folk live on 'home'")
	_check(PlayerLots.home_of_household(999) == Neighborhood.HOME and PlayerLots.home_of(null) == Neighborhood.HOME, "unknown households and no folk fall back to 'home'")
	_check(StoryVisits.entrance() == StoryVisits.entrance(int(host_folk[0].id)), "a host's visitors use the usual door")
	# a guest joins
	var r := CoopHouseholds.join(2, "Ann", _household(["Zed", "Zoe"]), "")
	_check(r["ok"], "player 2 joined: %s" % str(r["msg"]))
	if not r["ok"]:
		HoodKit.teardown()
		return fails
	var lot: String = r["lot"]
	var hid: int = r["hid"]
	var zed: Folk = WorldIface.get_folk(int(r["folk_ids"][0]))
	_check(PlayerLots.home_of(zed) == lot and lot != Neighborhood.HOME, "the guest's folk live on their own lot (%s)" % lot)
	_check(PlayerLots.home_of(host_folk[0]) == Neighborhood.HOME, "the host's folk still live on 'home'")
	_check(StoryVisits.entrance(int(zed.id)) == NeighborhoodLots.entry_tile(lot), "visitors and party guests come to the guest's door")
	_check(StoryVisits.entrance(int(host_folk[0].id)) == NeighborhoodLots.entry_tile("home"), "and to the host's door for the host")
	_check(VacationTrip.home_tile({"hid": hid}) == NeighborhoodLots.entry_tile(lot) and VacationTrip.home_tile({"hid": 1}) == NeighborhoodLots.entry_tile("home"),
		"a holiday ends at the traveller's own door")
	# the guest's worker commutes out and comes back to their own lot
	for f in WorldIface.all_folk():
		if f != zed:
			Careers.retired[int(f.id)] = {"career": "", "level": 1, "pension": 0}      # only Zed has a job: no other commutes in the event counts
	Careers.hire(zed, "coder")
	HoodKit.set_time(2, 6, 30)
	var plan: float = Workplace.commute_minutes(zed, NeighborhoodLots.entry_tile("office"))
	_check(plan > 0.0, "the guest has a route to the office (%.0f min)" % plan)
	var out_ok := false
	for _m in 4 * 60:
		HoodKit.run(1)
		if HoodKit.count_events("arrived_at_work") > 0:
			out_ok = true
			break
	_check(out_ok and Commute.on_shift(int(zed.id)), "the guest's worker commuted to the office and is on shift")
	var back := false
	var seen_host_home := false
	for _m2 in 12 * 60:
		HoodKit.run(1)
		if NeighborhoodLots.lot_at(zed.tile) == "home":
			seen_host_home = true
		if HoodKit.count_events("returned_home") > 0:
			back = true
			break
	_check(back, "the shift ended and the worker walked home")
	_check(NeighborhoodLots.lot_at(zed.tile) == lot, "back on their OWN lot (%s), not '%s'" % [lot, NeighborhoodLots.lot_at(zed.tile)])
	_check(not seen_host_home, "never routed through the host's home lot")
	_check(not Commute.trips.has(int(zed.id)), "the trip is closed")
	HoodKit.teardown()
	return fails
