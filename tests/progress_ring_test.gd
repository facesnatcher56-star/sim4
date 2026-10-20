extends RefCounted
## Task 33.4: the progress ring over a folk's head and the bar on the queue chip. Fraction maths (Interaction.progress is a pure read), hidden when there is no timed
## action, the settings modes (off / selected only / household / everyone), icons, the queue chip, and balloons keeping clear of rings.

var fails: Array = []
var W: Node


func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)


func _folk(name: String, hh: int, tile: Vector2i) -> Folk:
	var f := Folk.create(name)
	f.age_stage = "adult"
	f.household_id = hh
	W.add_folk(f, tile)
	return f


func _run_inter(f: Folk, def_id: String, obj_id: int, elapsed: float) -> Interaction:
	var it := Interaction.create(def_id, f, obj_id)
	it.state = "running"
	it.elapsed_min = elapsed
	f.current = it
	return it


func run() -> Array:
	fails = []
	W = Engine.get_main_loop().root.get_node_or_null("World")
	if W == null:
		return ["World autoload missing"]
	ProgressRing.reload()
	_maths()
	_modes()
	_candidates()
	_icons()
	_queue_chip()
	_layout()
	_clear_of_name_tags()
	_settings()
	return fails


func _maths() -> void:
	W.reset()
	var pid: int = W.place_object("plant", Vector2i(6, 6), 0)
	var f := _folk("Gardener", 1, Vector2i(6, 7))
	var it := Interaction.create("water_plant", f, pid)
	_check(it != null, "water_plant missing")
	_check(is_equal_approx(it.duration(), 5.0), "water_plant lasts 5 minutes")
	_check(it.progress() == -1.0, "a queued action has no progress")
	_check(ProgressRing.fraction(it) == -1.0 and ProgressRing.fraction(null) == -1.0, "no ring when nothing is running")
	it.state = "walking"
	_check(ProgressRing.fraction(it) == -1.0, "no ring while still walking to it")
	it.state = "running"
	for pair in [[0.0, 0.0], [1.5, 0.3], [2.5, 0.5], [4.0, 0.8], [5.0, 1.0], [9.0, 1.0]]:
		it.elapsed_min = pair[0]
		_check(is_equal_approx(ProgressRing.fraction(it), pair[1]), "elapsed %s of 5 should be %s, got %s" % [pair[0], pair[1], ProgressRing.fraction(it)])
	_check(is_equal_approx(ProgressRing.arc_end(0.0), -PI * 0.5) and is_equal_approx(ProgressRing.arc_end(0.25), 0.0) and is_equal_approx(ProgressRing.arc_end(1.0), PI * 1.5), "arc angles: 0 at 12 o'clock, quarter at 3 o'clock, full circle")
	_check(ProgressRing.percent_text(0.304) == "30%" and ProgressRing.percent_text(0.8) == "80%" and ProgressRing.percent_text(-1.0) == "", "percent text")
	# too short for a ring (1 minute) but the chip still shows it
	var sid: int = W.place_object("sink", Vector2i(10, 6), 0)
	var wash := Interaction.create("wash_hands", f, sid)
	wash.state = "running"
	wash.elapsed_min = 0.5
	_check(ProgressRing.fraction(wash) == -1.0, "a 1 minute action gets no ring")
	_check(is_equal_approx(ProgressRing.chip_fraction(wash), 0.5), "but its chip shows progress")
	# a pure read: nothing changes
	var before := [it.elapsed_min, it.state, f.needs["hunger"].value]
	for i in 5:
		ProgressRing.fraction(it)
		it.progress()
	_check(before == [it.elapsed_min, it.state, f.needs["hunger"].value], "progress() is a pure read")
	W.remove_folk(f.id)
	W.reset()


func _modes() -> void:
	# selected folk 1 in household 1; folk 2 same household; folk 3 another household
	_check(not ProgressRing.shows_for(ProgressRing.OFF, 1, 1, 1, 1), "off: never, not even the selected folk")
	_check(ProgressRing.shows_for(ProgressRing.SELECTED, 1, 1, 1, 1) and not ProgressRing.shows_for(ProgressRing.SELECTED, 2, 1, 1, 1), "selected only")
	_check(ProgressRing.shows_for(ProgressRing.HOUSEHOLD, 2, 1, 1, 1) and not ProgressRing.shows_for(ProgressRing.HOUSEHOLD, 3, 2, 1, 1), "household: the selected folk's housemates, nobody else")
	_check(ProgressRing.shows_for(ProgressRing.HOUSEHOLD, 1, 1, 1, 1), "household includes the selected folk")
	_check(ProgressRing.shows_for(ProgressRing.EVERYONE, 3, 2, 1, 1), "everyone")
	_check(not ProgressRing.shows_for(ProgressRing.HOUSEHOLD, 4, -1, 1, 1), "townies are not a household")


func _candidates() -> void:
	W.reset()
	var oid: int = W.place_object("plant", Vector2i(6, 6), 0)
	var a := _folk("Selected", 1, Vector2i(6, 7))
	var b := _folk("Housemate", 1, Vector2i(7, 7))
	var c := _folk("Neighbour", 2, Vector2i(8, 7))
	var d := _folk("Idle", 1, Vector2i(9, 7))
	for f in [a, b, c]:
		_run_inter(f, "water_plant", oid, 2.0)
	_run_inter(d, "water_plant", oid, 0.0).state = "walking"
	var ids := func(mode: int) -> Array:
		var out: Array = []
		for x in ProgressLayer.candidates(mode, a.id):
			out.append(x["id"])
		out.sort()
		return out
	_check((ids.call(0) as Array).is_empty(), "mode off: no rings")
	_check(ids.call(1) == [a.id], "selected only: %s" % str(ids.call(1)))
	_check(ids.call(2) == [a.id, b.id], "household: selected + housemate, not the neighbour, not the walker: %s" % str(ids.call(2)))
	_check(ids.call(3) == [a.id, b.id, c.id], "everyone with a timed action running: %s" % str(ids.call(3)))
	# nobody selected: only 'everyone' shows anything
	_check(ProgressLayer.candidates(1, -1).is_empty() and ProgressLayer.candidates(2, -1).is_empty(), "no selection: no ring in selected / household modes")
	# the selected folk with no action: nothing
	a.current = null
	_check((ids.call(1) as Array).is_empty(), "hidden when the folk has no timed action")
	W.remove_folk(a.id)
	W.remove_folk(b.id)
	W.remove_folk(c.id)
	W.remove_folk(d.id)
	W.reset()


func _icons() -> void:
	_check(str(ProgressRing.icon_for("water_plant", ["chore", "plant"])["shape"]) == "drop", "watering: a drop")
	_check(str(ProgressRing.icon_for("cook_meal", ["food", "cook", "skill"])["shape"]) == "flame", "cooking: a flame")
	_check(str(ProgressRing.icon_for("sleep_bed", ["sleep", "rest"])["shape"]) == "moon", "sleeping: a moon")
	_check(str(ProgressRing.icon_for("repair_object", ["repair"])["shape"]) == "bolt", "repairing: a bolt")
	_check(str(ProgressRing.icon_for("nothing_known", [])["shape"]) == "dots", "unknown actions get the fallback icon")
	# every interaction resolves to a drawable icon
	var shapes := ["drop", "flame", "leaf", "star", "bolt", "moon", "book", "note", "heart", "plate", "dots"]
	for iid in SimEnv.data().interactions():
		var d: Dictionary = SimEnv.data().interaction_def(str(iid))
		var ic := ProgressRing.icon_for(str(iid), d.get("tags", []))
		_check(str(ic.get("shape", "")) in shapes, "%s: icon shape '%s' is not drawable" % [iid, ic.get("shape", "")])
		_check(str(ic.get("color", "")) != "", "%s: icon has a colour" % iid)


func _queue_chip() -> void:
	W.reset()
	var oid: int = W.place_object("plant", Vector2i(6, 6), 0)
	var f := _folk("Gardener", 1, Vector2i(6, 7))
	var it := _run_inter(f, "water_plant", oid, 2.0)
	var txt := QueueBar.chip_text("water_plant", true, ProgressRing.chip_fraction(it))
	_check(txt.begins_with("> ") and txt.ends_with("40%"), "running chip text shows the percent: '%s'" % txt)
	_check(QueueBar.chip_text("water_plant", false, -1.0) == UIU.interaction_label("water_plant"), "queued chips show no percent")
	_check(not QueueBar.chip_text("water_plant", true, -1.0).contains("%"), "still walking: no percent")
	var qb := QueueBar.new()
	Engine.get_main_loop().root.add_child(qb)
	qb.set_folk(f)
	_check(qb.bars.size() == 1, "one progress bar for the running chip, got %d" % qb.bars.size())
	if qb.bars.size() == 1:
		_check(is_equal_approx((qb.bars[0][1] as ProgressBar).value, 0.4), "the chip bar is at 40%%, got %s" % str((qb.bars[0][1] as ProgressBar).value))
	it.elapsed_min = 4.0
	qb._tick = 0.0
	qb._process(0.5)
	if qb.bars.size() == 1:
		_check(is_equal_approx((qb.bars[0][1] as ProgressBar).value, 0.8), "the chip bar follows the action (80%%), got %s" % str((qb.bars[0][1] as ProgressBar).value))
		_check((qb.bars[0][0] as Button).text.ends_with("80%"), "chip text follows too")
	f.current = null
	qb.rebuild()
	_check(qb.bars.is_empty(), "no running action: no bar")
	qb.free()
	W.remove_folk(f.id)
	W.reset()


func _layout() -> void:
	var sz := Vector2(120, 30)
	var ring := Rect2(Vector2(290, 150), Vector2(32, 32))
	var items: Array = [{"id": 1, "pos": Vector2(250, 160), "size": sz}]
	var placed: Array = ThoughtLayer.layout_rects(items, [ring])
	_check(not Rect2(placed[0], sz).intersects(ring), "a balloon is pushed above the ring")
	_check(placed[0].y < ring.position.y, "above, not below")
	var free: Array = ThoughtLayer.layout_rects(items)
	_check(free[0] == items[0]["pos"], "without rings nothing moves")


func _clear_of_name_tags() -> void:
	var tag := Rect2(Vector2(280, 150), Vector2(80, 30))
	var p := ProgressLayer.place_clear(Vector2(320, 170), 16.0, [tag])
	_check(not Rect2(p - Vector2(16, 16), Vector2(32, 32)).intersects(tag), "ring is pushed above the name tag")
	_check(p.y < tag.position.y, "above, not below")
	var icon := Rect2(Vector2(300, 100), Vector2(26, 26))
	var q := ProgressLayer.place_clear(Vector2(320, 170), 16.0, [tag, icon])
	_check(not Rect2(q - Vector2(16, 16), Vector2(32, 32)).intersects(tag) and not Rect2(q - Vector2(16, 16), Vector2(32, 32)).intersects(icon), "ring clears the name tag AND the mood icon above it")
	_check(ProgressLayer.place_clear(Vector2(50, 50), 16.0, [tag]) == Vector2(50, 50), "nothing in the way: the ring stays")


func _settings() -> void:
	GameSettings.ensure_loaded()
	var def := {}
	for d in GameSettings.DEFS:
		if str(d["k"]) == "progress_rings":
			def = d
	_check(not def.is_empty() and int(def["def"]) == 2 and str(def["tab"]) == "gameplay", "Settings: Gameplay 'Show progress rings', default selected + household")
	_check((def.get("opts", []) as Array).size() == 4, "four choices: off / selected / household / everyone")
	var old: Variant = GameSettings.get_value("progress_rings")
	GameSettings.set_value("progress_rings", 3, false)
	_check(GameSettings.progress_rings_mode() == 3, "mode read back")
	GameSettings.set_value("progress_rings", old, false)
