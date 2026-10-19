extends RefCounted
## Task 12b / 12.6: the map grows. The east side has a real fire station, city hall and car park as lots and reserved empty plots; a town-planning project takes a plot,
## shows scaffolding, a rising building site and then the finished building, renames the plot, and the save keeps it.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	Kit.new_game("small")
	StoryPacing.enabled = false
	CityState.reset()
	CityPlan.reset()
	UtilityEvents.dice_on = false
	# the new lots are real: they have rectangles on the map, templates and a street frontage
	for lot in ["fire_station", "city_hall", "car_park"]:
		var rc: Rect2i = NeighborhoodLots.rect_of(lot)
		_check(rc.size != Vector2i.ZERO and rc.position.x >= 159, "%s is a lot on the east side (%s)" % [lot, str(rc)])
		_check(not VehicleRoads.frontage(lot).is_empty(), "%s meets the street" % lot)
		_check(Neighborhood.template_of(lot) != "", "%s has a building template" % lot)
	_check(str(CityServices.station("fire")["lot"]) == "fire_station", "the fire station is its own lot, not the police lot")
	_check(Workplace.lot_for("politician") == "city_hall" or Careers.career_def("politician").is_empty(), "the politician works at city hall")
	var plots: Array = CityPlan.plot_ids()
	_check(plots.size() == 4, "four reserved plots (%d)" % plots.size())
	var w = WorldIface.world()
	for pid in plots:
		var rc2: Rect2i = MapBuilder.plot_rect(str(pid))
		_check(rc2.size != Vector2i.ZERO and w.get_floor(rc2.position + Vector2i(3, 3)) == "lawn", "%s is open lawn" % pid)
		_check(str((w.regions as WorldRegions).by_lot(str(pid)).get("label", "")) == "Empty plot", "%s is labelled Empty plot" % pid)
	# a project takes the first free plot
	var keep: Variant = CityPlan.cfg().get("fill_trigger", 0.9)
	CityPlan.cfg()["fill_trigger"] = 0.0
	CityGov.treasury = 5000.0
	CityPlan._consider(SysUtil.day())
	CityPlan.cfg()["fill_trigger"] = keep
	_check(CityPlan.projects.size() == 1, "a project started")
	var p: Dictionary = CityPlan.projects[0] if CityPlan.projects.size() > 0 else {}
	var pid1: String = str(p.get("plot", ""))
	_check(pid1 == "plot_1" and CityPlan.plot_state(pid1) == "scaffold", "it took plot_1 and the plot shows scaffolding (%s)" % pid1)
	_check(str((w.regions as WorldRegions).by_lot(pid1).get("label", "")).begins_with("Building site"), "the plot is a building site")
	var pv := PlotView.new()
	Kit.root().add_child(pv)
	pv.sync_now()
	var n_scaffold: int = pv.node_count(pid1)
	_check(pv.state_drawn(pid1) == "scaffold" and n_scaffold > 10, "scaffolding is drawn (%d parts)" % n_scaffold)
	# workers build
	p["scaffold_end"] = SysUtil.day()
	p["ready"] = SysUtil.day() + 10
	CityPlan._progress(SysUtil.day())
	pv.sync_now()
	_check(CityPlan.plot_state(pid1) == "building" and pv.state_drawn(pid1) == "building" and pv.node_count(pid1) > n_scaffold, "a building site rises (%d parts)" % pv.node_count(pid1))
	# it opens
	var cap0: int = CityPlan.extra_capacity()
	CityPlan._progress(SysUtil.day() + 11)
	pv.sync_now()
	_check(CityPlan.plot_state(pid1) == "built" and pv.state_drawn(pid1) == "built" and pv.node_count(pid1) >= 1, "the finished building stands on the plot")
	_check(CityPlan.extra_capacity() == cap0 + 4, "flats raise the population cap")
	_check(str((w.regions as WorldRegions).by_lot(pid1).get("label", "")).begins_with("New "), "the plot is renamed")
	# the next project takes the next plot
	CityPlan.cfg()["fill_trigger"] = 0.0
	CityGov.treasury = 5000.0
	CityPlan._consider(SysUtil.day())
	CityPlan.cfg()["fill_trigger"] = keep
	_check(CityPlan.projects.size() == 1 and str(CityPlan.projects[0]["plot"]) == "plot_2", "the next project takes plot_2")
	# the save keeps the plots
	var d: Dictionary = CityPlan.to_dict()
	CityPlan.reset()
	CityPlan.from_dict(d)
	_check(CityPlan.built_plots.get(pid1, "") != "" and CityPlan.plot_state("plot_2") == "scaffold", "the save keeps built plots and open projects")
	# no free plot, no project
	for q in plots:
		CityPlan.built_plots[str(q)] = "commercial"
	CityPlan.projects.clear()
	CityPlan.cfg()["fill_trigger"] = 0.0
	CityGov.treasury = 5000.0
	CityPlan._consider(SysUtil.day())
	CityPlan.cfg()["fill_trigger"] = keep
	_check(CityPlan.projects.is_empty(), "a town with no reserved land left starts nothing")
	pv.get_parent().remove_child(pv)
	pv.free()
	Kit.teardown()
	return fails
