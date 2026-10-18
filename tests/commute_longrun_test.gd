extends RefCounted
## Slow tier: the commute_test scenarios with the whole shifts played (pay, school out, walk home, visible shift end, load inside).

const Base = preload("res://tests/commute_test.gd")

func run() -> Array:
	var t = Base.new()
	t.fails = []
	t.full = true
	return t._all()
