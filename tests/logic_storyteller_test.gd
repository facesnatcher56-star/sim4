extends RefCounted
## Task 34 logic audit: storyteller events must fit the household. A recruiter rings somebody who has a job (not a retiree or a homemaker), and a
## traffic jam does not make the neighbours anxious.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("small")
	StoryPacing.enabled = false
	var hid: int = int(folk[0].household_id)
	var key: String = "h%d" % hid
	var c: Dictionary = StorytellerDeck.card("headhunter")
	for f in StorytellerPlay.residents_of(hid):
		Careers.jobs.erase(int(f.id))
	_check(not StorytellerPlay.can_play("headhunter", c, key), "no recruiter rings a household where nobody has a job")
	var adult = null
	for f2 in StorytellerPlay.residents_of(hid):
		if str(f2.age_stage) in ["adult", "elder"]:
			adult = f2
			break
	if adult != null:
		Careers.jobs[int(adult.id)] = {"career": "office", "level": 1}
		_check(StorytellerPlay.can_play("headhunter", c, key), "a recruiter can ring somebody with a job")
		Careers.jobs.erase(int(adult.id))
	_check(str((StorytellerDeck.card("crash_avenue").get("ripple", {}).get("near", {}) as Dictionary).get("buff", "x")) == "", "a traffic jam does not make the neighbours anxious")
	# a ripple unsettles those who can notice it, not somebody in hospital
	var res: Array = StorytellerPlay.residents_of(hid)
	if res.size() >= 2 and not SimEnv.data().buff_def("anxious_jitters").is_empty():
		var keep = StorytellerRipple.rcfg().get("near_buff_chance", 0.7)
		StorytellerRipple.rcfg()["near_buff_chance"] = 1.0
		res[1].add_buff("in_hospital")
		StorytellerRipple._near(hid, {"text": "Sirens.", "buff": "anxious_jitters"}, {})
		StorytellerRipple.rcfg()["near_buff_chance"] = keep
		_check(res[0].has_buff("anxious_jitters") and not res[1].has_buff("anxious_jitters"), "somebody in hospital is not unsettled by sirens they cannot hear")
	Kit.teardown()
	return fails
