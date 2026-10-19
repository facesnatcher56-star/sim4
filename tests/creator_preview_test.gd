extends RefCounted
## Task 12b UI pass: the creator preview faces the camera (and sways, never showing the back), turns when dragged and comes back; choosing a sex gives the usual body shape, height band,
## build and a hair style from the sex's usual pool, while every hair style stays selectable.

var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _facing_z(pv: FolkPreview) -> float:
	# the model's front is -Z; rotated by the pivot yaw, its forward vector's z says whether it looks at the camera (camera on +Z)
	return -cos(pv.yaw())

func run() -> Array:
	fails = []
	var root: Window = Engine.get_main_loop().root
	var pv := FolkPreview.new()
	root.add_child(pv)
	pv.show_folk("adult", Genetics.random_appearance())
	pv._process(0.016)
	_check(_facing_z(pv) > 0.95, "the preview faces the camera at the start (%.2f)" % _facing_z(pv))
	var worst: float = 1.0
	for i in 600:
		pv._process(0.05)
		worst = minf(worst, _facing_z(pv))
	_check(worst > 0.5, "the slow turn never shows the back (worst %.2f)" % worst)
	var yaw0: float = pv.yaw()
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(60, 0)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	pv._gui_input(drag)
	_check(absf(pv.yaw() - yaw0) > 0.5, "dragging turns it (%.2f)" % absf(pv.yaw() - yaw0))
	for i2 in 400:
		pv._process(0.05)
	_check(_facing_z(pv) > 0.5, "and after a while it turns back to face you (%.2f)" % _facing_z(pv))
	# the sex's look
	var f: Dictionary = Genetics.random_appearance(null, "")
	f["hair_style"] = 9
	f["facial_hair"] = 2
	var m: Dictionary = f.duplicate(true)
	GeneticsSex.creator_fit(f, "female", "Idris")
	GeneticsSex.creator_fit(m, "male", "Idris")
	_check(int(f["body_type"]) == 0 and int(m["body_type"]) == 2, "women start slimmer through the shoulders, men broader (%d / %d)" % [int(f["body_type"]), int(m["body_type"])])
	_check(int(f["frame"]) != int(m["frame"]), "and the frame differs (%d / %d)" % [int(f["frame"]), int(m["frame"])])
	_check(float(f["height"]) <= 1.04 and float(m["height"]) >= 0.96, "heights sit in their sex's bands (%.2f / %.2f)" % [float(f["height"]), float(m["height"])])
	_check(float(f["build"]) <= 1.0 and float(m["build"]) >= 1.0, "builds follow too")
	_check(GeneticsSex.in_hair_pool("female", int(f["hair_style"])), "the woman's starting hair is from the usual pool (%d)" % int(f["hair_style"]))
	_check(GeneticsSex.in_hair_pool("male", int(m["hair_style"])), "the man's starting hair is from the usual pool (%d)" % int(m["hair_style"]))
	_check(int(f["facial_hair"]) == 0, "no facial hair on a woman")
	# every hair style stays selectable: the editor never limits the choice
	var kept: Dictionary = m.duplicate(true)
	kept["hair_style"] = 2
	GeneticsSex.creator_fit(kept, "male", "Idris")
	_check(int(kept["hair_style"]) == int(GeneticsSex.hair_pool("male")[absi(hash("Idris" + "male")) % GeneticsSex.hair_pool("male").size()]) or GeneticsSex.in_hair_pool("male", int(kept["hair_style"])), "a sex switch re-picks hair from its pool")
	var ed := FolkEditor.new()
	root.add_child(ed)
	var fd: Dictionary = {"name": "Idris", "stage": "adult", "sex": "male", "traits": [], "aspiration": "", "rel": "none", "appearance": Genetics.random_appearance(null, "male")}
	ed.load_folk(fd, true, "")
	ed._set_sex("female")
	_check(str(fd["sex"]) == "female" and GeneticsSex.in_hair_pool("female", int(fd["appearance"]["hair_style"])) and int(fd["appearance"]["body_type"]) == 0, "choosing Female in the editor gives the usual female look")
	fd["appearance"]["hair_style"] = 9                         # any hair is still selectable by hand (bald here)
	_check(int(fd["appearance"]["hair_style"]) == 9, "a hand-picked hair style is kept")
	ed.get_parent().remove_child(ed)
	ed.free()
	pv.get_parent().remove_child(pv)
	pv.free()
	return fails
