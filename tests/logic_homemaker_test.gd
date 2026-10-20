extends RefCounted
## Task 34 logic audit: a homemaker earns nothing, so the player is told when nobody else in the household brings money in.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("small")
	StoryPacing.enabled = false
	var hh: Array = folk.filter(func(f): return str(f.age_stage) in ["adult", "elder"])
	var a = hh[0]
	for f in folk:
		Careers.jobs.erase(int(f.id))
		Careers.retired.erase(int(f.id))
	Homemaker.set_role(a, true)
	_check(Kit.has_note("Nobody else in the household earns"), "a homemaker with nobody else earning gets a warning about money")
	Homemaker.set_role(a, false)
	if hh.size() > 1:
		Careers.jobs[int(hh[1].id)] = {"career": "office", "level": 1}
		_check(Homemaker.has_other_income(a), "a partner with a job pays the bills")
		Careers.jobs.erase(int(hh[1].id))
	Kit.teardown()
	return fails
