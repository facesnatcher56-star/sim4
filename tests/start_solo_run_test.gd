extends RefCounted
## A two-day headless run of Solo Start on the real World / SimDirector: the Folk survives (needs never collapse, no death) and the
## first scenario goal can be completed through the Careers API.

const Kit := preload("res://tests/start_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("solo")
	var f: Folk = folk[0]
	_check(Kit.clock().hour() == 8 and Kit.clock().day() == 1, "begins at 8:00 on day 1")
	_check(f.current == null or f.current.def_id != "sleep_bed", "the Folk is awake at the start")
	var worst := 100.0
	var hours: int = TestFixture.pick(48, 24)
	for h in hours:
		Kit.run(60)
		for nid in f.needs:
			worst = minf(worst, f.get_stat_value(nid))
		if h == 6:
			Careers.hire(f, Careers.career_ids()[0], 1)      # what Accept does on the job-offer card
			_check(Scenario.is_done("job"), "goal 1 completed by accepting a job")
		if h == 7:
			_check(Aging.records.has(f.id) and SysUtil.folk(f.id) != null, "the Folk is still alive and on the lot")
	_check(SysUtil.folk(f.id) != null, "the Folk survived %d hours" % hours)
	_check(worst > -98.0, "no need hit rock bottom (worst %f)" % worst)
	_check(Economy.balance(1) > 0, "still has money (%d)" % Economy.balance(1))
	_check(not Scenario.finished, "the checklist is not magically finished")
	Kit.teardown()
	return fails
