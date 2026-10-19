extends RefCounted
## The Town Life window (headless): the Places, Study and Jobs tabs build, a Use button runs a command through the command layer.

const K = preload("res://tests/systems_kit.gd")

func _texts(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append("[" + (c as Button).text + "]")
		_texts(c, out)
	return out

func _button(n: Node, text: String) -> Button:
	for c in n.get_children():
		if c is Button and (c as Button).text == text and not (c as Button).disabled:
			return c
		var r: Button = _button(c, text)
		if r != null:
			return r
	return null

func run() -> Array:
	var f: Array = []
	var root: Window = Engine.get_main_loop().root
	var w := K.setup()
	var ann := K.make_folk(w, "Ann Rowe")
	Aging.set_age_days(ann, 90.0)
	WorldIface.coins[1] = 2000
	Story.generate_townies(12)
	LifeTick.new_game()
	K.set_time(1, 19)
	var hub := LifeHub.new()
	root.add_child(hub)
	hub.kind = "education"
	hub.place_id = "college"
	hub.show_for(1)
	var txt: String = "\n".join(_texts(hub.body))
	K.expect(f, txt.find("FERNWOOD COLLEGE") >= 0 and txt.find("Open until") >= 0 and txt.find("Lecture: Medicine") >= 0, "Places tab: the college, its hours and its lectures")
	K.expect(f, txt.find("[Learning]") >= 0 and txt.find("Staff:") >= 0, "kind buttons and the staff line")
	var use: Button = _button(hub.body, "Use")
	K.expect(f, use != null, "a Use button is enabled for a lecture")
	var log0: int = Commands.log.size()
	use.pressed.emit()
	K.run(K.director(), 190)               # the lecture takes three hours
	K.expect(f, not EduCollege.summary(1).is_empty() and Commands.log.size() == log0 + 1 and str(Commands.log[Commands.log.size() - 1]["action"]) == "life", "pressing it runs a life command and starts the course")
	hub.place_id = "night_school"
	hub.refresh()
	txt = "\n".join(_texts(hub.body))
	K.expect(f, txt.find("Cooking Basics: next lesson") >= 0, "other places list their lessons")
	hub._pick("study")
	txt = "\n".join(_texts(hub.body))
	K.expect(f, txt.find("College:") >= 0 and txt.find("[Drop out]") >= 0, "Study tab shows the college course")
	hub._pick("health")
	txt = "
".join(_texts(hub.body))
	K.expect(f, txt.find("Fitness:") >= 0 and txt.find("Overall health") >= 0 and txt.find("Stress from work") >= 0, "Health tab shows the meters")
	hub._pick("jobs")
	txt = "\n".join(_texts(hub.body))
	K.expect(f, txt.find("THIS WEEK'S OPENINGS") >= 0 or txt.find("No openings") >= 0, "Jobs tab shows the board")
	hub.queue_free()
	K.teardown()
	return f
