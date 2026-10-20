extends RefCounted
## Task 34 logic audit: a burglar does not break in while somebody is at home and awake (they see the lights and slip away).

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("small")
	StoryPacing.enabled = false
	Kit.set_time(3, 14)
	var hid: int = int(folk[0].household_id)
	var awake: Array = CrimePlace.awake_at_home(hid)
	if awake.is_empty():
		Kit.run(5)
		awake = CrimePlace.awake_at_home(hid)
	_check(float(CrimeBurglary.cfg().get("awake_abort", 0.0)) >= 0.95, "somebody awake at home puts nearly every burglar off")
	_check(not awake.is_empty(), "a resident is home and awake in the afternoon")
	if not awake.is_empty():
		var stopped := 0
		for i in 300:
			if CrimeBurglary._prevented(hid, "home:%d" % hid, false) != "":
				stopped += 1
		_check(stopped >= 270, "with somebody awake at home the break-in is called off nearly always (%d of 300)" % stopped)
	Kit.teardown()
	return fails
