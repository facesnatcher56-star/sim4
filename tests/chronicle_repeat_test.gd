extends RefCounted
## The Chronicle does not repeat itself (fixes38): the holiday parade is once a year, the same line is told once a day, and a town
## event that reaches the Chronicle twice in the same minute (card text + ripple news) is one story.

const Kit = preload("res://tests/hood_kit.gd")

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	Kit.new_game("classic")
	ChronicleHook.reset()
	Kit.set_time(3, 10)
	ChronicleHook.note("scandal_hall", "Whispers are going round the town hall.", [], "town:0", 2, true)
	ChronicleHook.note("scandal_hall", "Whispers at the town hall: someone on the council is in trouble.", [], "town:0", 2, true)
	_check(ChronicleHook.recent.size() == 1, "two routes, same minute, same card: one line (%d)" % ChronicleHook.recent.size())
	ChronicleHook.note("place_news", "The bakery has a special.", [], "place:bakery", 0, true)
	Kit.run(30)
	ChronicleHook.note("place_news", "The bakery has a special.", [], "place:bakery", 0, true)
	_check(ChronicleHook.recent.size() == 2, "the same text twice in a day is told once (%d)" % ChronicleHook.recent.size())
	Kit.set_time(4, 10)
	ChronicleHook.note("place_news", "The bakery has a special.", [], "place:bakery", 0, true)
	_check(ChronicleHook.recent.size() == 3, "the next day it may be told again")
	# the parade: exactly one festival per year has it
	var n := 0
	for d in range(1, 57):
		Kit.set_time(d, 12)
		if Places.open_at("holiday_parade", (d - 1) * 1440 + 12 * 60):
			n += 1
	_check(n == 2, "56 days = 2 game years = 2 parade days (%d)" % n)
	Kit.teardown()
	return fails
