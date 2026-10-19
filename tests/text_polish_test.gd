extends RefCounted
## Player text polish (task 19j): "left 1 friends" -> "1 friend" (SysUtil.count_text), and "is in trimester 2" never comes before "is expecting a baby!".

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	K.expect(f, SysUtil.count_text(1, "friend") == "1 friend", "1 friend")
	K.expect(f, SysUtil.count_text(0, "friend") == "0 friends" and SysUtil.count_text(2, "friend") == "2 friends", "0 and 2 friends")
	K.expect(f, SysUtil.count_text(1, "child", "children") == "1 child" and SysUtil.count_text(3, "child", "children") == "3 children", "irregular plural")
	K.expect(f, SysUtil.count_text(1, "person", "people") == "1 person" and SysUtil.count_text(5, "person", "people") == "5 people", "person / people")
	_order(f)
	_no_bad_plurals(f)
	return f

## The trimester line follows the announcement (a woman who finds out late in the pregnancy gets both in the same minute).
func _order(f: Array) -> void:
	var w := K.setup(81)
	var mom := K.make_folk(w, "Mina Lane", [])
	mom.sex = "female"
	var dad := K.make_folk(w, "Sam Lane", [], 1, Vector2i(13, 12))
	dad.sex = "male"
	Aging.set_age_days(mom, 90.0)
	Pregnancy.start(int(mom.id), int(dad.id), true, {"kids": 1})
	var r: Dictionary = Pregnancy.rec(int(mom.id))
	r["started_min"] = SysUtil.now() - int(float(Pregnancy.length_days()) * 1440.0 * 0.5)       # half way: second trimester
	K.notes.clear()
	PregnancyStage.reveal(int(mom.id), "doctor")
	var first_expect := -1
	var first_tri := -1
	for i in K.notes.size():
		var t: String = str(K.notes[i][0])
		if first_expect < 0 and t.find("is expecting a baby") >= 0:
			first_expect = i
		if first_tri < 0 and t.find("trimester") >= 0:
			first_tri = i
	K.expect(f, first_expect >= 0, "the announcement is made (%s)" % str(K.notes))
	K.expect(f, first_tri < 0 or first_tri > first_expect, "and the trimester line, if any, comes after it (announce %d, trimester %d)" % [first_expect, first_tri])
	Family.update_pregnancies()
	K.expect(f, first_tri >= 0 or K.has_note("trimester 2"), "the trimester is still announced (%s)" % str(K.notes))
	K.teardown()

## No "1 friends"-style plural left in the lines this task touched: a quick grep over the sources.
func _no_bad_plurals(f: Array) -> void:
	for path in ["res://scripts/systems/aging.gd", "res://scripts/systems/careers.gd", "res://scripts/systems/case_text.gd", "res://scripts/systems/utilities.gd", "res://scripts/systems/justice_orders.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		for bad in ["%d friends", "%d children", "%d days of", "%d minutes\"", "%d hours\"", "%d descendants"]:
			K.expect(f, src.find(bad) < 0, "%s has no hand-made plural '%s'" % [path, bad])
