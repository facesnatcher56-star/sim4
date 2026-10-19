extends RefCounted
## Household chaos (task 07b), neglect and child services through the EXISTING path (ChildServices, task 20): the player is warned first, days of unmet
## needs with nobody looking after the child lead to a report, a home visit the next day, a safety plan, and a placement when it happens again.
## Care from a grown-up, or a child who is fine, never triggers anything. No new harm content: only reports, visits and placements.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")

func run() -> Array:
	var f: Array = []
	_warning_and_gate(f)
	_report_and_plan(f)
	_repeat_removal(f)
	_unfounded(f)
	return f

func _home(extra_adult: bool = true) -> Dictionary:
	var h: Dictionary = C.setup()
	JusticeState.reset()
	JusticeState.enabled = true
	var kid := K.make_folk(h["w"], "Kit Voss", [], 1, Vector2i(15, 12), "child")
	Family.link_parent(int(kid.id), int(h["ada"].id))
	Family.link_parent(int(kid.id), int(h["bo"].id))
	h["kid"] = kid
	return h

func _services(plan: bool) -> void:
	JusticeState.sect("child_abuse")["services"]["substantiated_base"] = 1.0 if plan else 0.0
	JusticeState.sect("child_abuse")["services"]["per_incident"] = 0.0
	JusticeState.sect("child_abuse")["services"]["injury_bonus"] = 0.0

func _warning_and_gate(f: Array) -> void:
	var h: Dictionary = _home()
	var kid: Folk = h["kid"]
	var ada: Folk = h["ada"]
	ChaosNeglect.on_neglect(ada, {})
	K.expect(f, not K.has_note("child services"), "no warning for a grown-up")
	ChaosNeglect.on_neglect(kid, {})
	K.expect(f, K.has_note("child services may be told"), "the player is warned in plain words first")
	C.days(5)
	K.expect(f, ChildServices.kids().is_empty() and ChaosState.neglect.is_empty(), "a child who is fine is never reported")
	kid.add_buff("neglected")
	var ir := Interaction.new()
	ir.target_id = int(kid.id)
	ada.current = ir
	C.days(5)
	K.expect(f, ChildServices.kids().is_empty(), "while a grown-up is looking after the child, the days do not count")
	ada.current = null
	K.teardown()

func _report_and_plan(f: Array) -> void:
	var h: Dictionary = _home()
	var kid: Folk = h["kid"]
	_services(true)
	kid.add_buff("neglected")
	C.days(1)
	K.expect(f, int(ChaosState.neglect.get(int(kid.id), 0)) == 1 and ChildServices.kids().is_empty(), "one bad day is only counted")
	C.days(1)
	var rec: Dictionary = ChildServices.kids().get(int(kid.id), {})
	K.expect(f, bool(rec.get("reported", false)) and bool(rec.get("neglect", false)), "two days with nobody acting: child services is told")
	K.expect(f, str(rec.get("source", "")) == "teacher" and K.has_note("Child services have been told"), "a teacher raised concerns, and the player is informed")
	K.expect(f, not ChaosState.neglect.has(int(kid.id)), "the counter starts over")
	K.set_time(SysUtil.day() + 1, 10)
	ChildServices.on_day()
	K.expect(f, bool(ChildServices.kids()[int(kid.id)].get("visited", false)), "the social worker visits the next day")
	K.expect(f, K.has_note("safety plan") or K.has_note("parenting course"), "and a safety plan is made")
	K.expect(f, (ChildServices.kids()[int(kid.id)].get("placed", {}) as Dictionary).is_empty(), "the child stays at home the first time")
	K.teardown()

func _repeat_removal(f: Array) -> void:
	var h: Dictionary = _home()
	var kid: Folk = h["kid"]
	_services(true)
	kid.add_buff("neglected")
	C.days(2)
	K.set_time(SysUtil.day() + 1, 10)
	ChildServices.on_day()
	K.expect(f, (ChildServices.kids()[int(kid.id)].get("placed", {}) as Dictionary).is_empty(), "first time: safety plan only")
	K.set_time(SysUtil.day() + 3, 10)
	C.days(2)
	K.expect(f, int(ChildServices.kids()[int(kid.id)]["incidents"]) == 2, "it happens again: a repeat is on file")
	K.set_time(SysUtil.day() + 1, 10)
	ChildServices.on_day()
	var placed: Dictionary = ChildServices.kids()[int(kid.id)].get("placed", {})
	K.expect(f, not placed.is_empty(), "a repeat means placement with a relative or foster family")
	K.expect(f, K.has_note("placed"), "the player is told")
	K.teardown()

func _unfounded(f: Array) -> void:
	var h: Dictionary = _home()
	var kid: Folk = h["kid"]
	_services(false)
	kid.add_buff("neglected")
	C.days(2)
	K.set_time(SysUtil.day() + 1, 10)
	ChildServices.on_day()
	C.days(1)
	K.expect(f, K.has_note("found nothing to act on") and (ChildServices.kids()[int(kid.id)].get("placed", {}) as Dictionary).is_empty(), "a visit that finds nothing says so and closes the file")
	K.teardown()
