extends RefCounted
## Family tab of the folk panel (headless): sections, ages, action buttons wired to interaction ids, portrait colour.

const K = preload("res://tests/systems_kit.gd")

class FakeFolk:
	extends RefCounted
	var id := 905
	var name := "Fakey"
	var traits := []
	var needs := {}
	var skills := {}
	var buffs := []
	var queue := []
	var current = null
	var household_id := 1
	func get_mood() -> Dictionary:
		return {"mood": "happy", "intensity": 1}

func _texts(box: Node) -> String:
	var out: Array = []
	for c in box.get_children():
		if c is Label:
			out.append((c as Label).text)
	return "\n".join(out)

func run() -> Array:
	var f: Array = []
	var w := K.setup(61)
	var root: Window = Engine.get_main_loop().root
	var a := K.make_folk(w, "Ann Rowe", [], 1, Vector2i(12, 12))
	var b := K.make_folk(w, "Bo Rowe", [], 1, Vector2i(13, 12))
	var kid := K.make_folk(w, "Kit Rowe", [], 1, Vector2i(14, 12), "child")
	var sib := K.make_folk(w, "Sam Rowe", [], 1, Vector2i(15, 12), "child")
	Aging.set_age_days(a, 60.0)
	Aging.set_age_days(b, 60.0)
	Aging.set_age_days(kid, 15.0)
	Aging.set_age_days(sib, 16.0)
	RelationshipService.add_both(a.id, b.id, "romance", 85.0)
	RelationshipService.add_both(a.id, b.id, "friendship", 80.0)
	RelationshipService.set_flag(a.id, b.id, "partner", true, false)
	Family.link_parent(kid.id, a.id)
	Family.link_parent(kid.id, b.id)
	Family.link_parent(sib.id, a.id)
	Family.link_parent(sib.id, b.id)
	var fp := FolkPanel.new()
	root.add_child(fp)
	var tab_names: Array = []
	for i in fp.tabs.get_tab_count():
		tab_names.append(fp.tabs.get_tab_title(i))
	K.expect(f, tab_names.has("Family"), "the folk panel has a Family tab: %s" % str(tab_names))
	fp.show_folk(a)
	var txt: String = _texts(fp.family_box)
	K.expect(f, txt.find("PARTNER") >= 0 and txt.find("Bo Rowe") >= 0 and txt.find("Partner") >= 0, "partner section lists Bo")
	K.expect(f, txt.find("CHILDREN") >= 0 and txt.find("Kit Rowe") >= 0 and txt.find("Sam Rowe") >= 0, "children listed")
	K.expect(f, txt.find("Child, 3") >= 0 or txt.find("(Child,") >= 0, "ages / stages shown: %s" % txt)
	K.expect(f, fp.family_buttons.has("propose") and not fp.family_buttons["propose"].disabled, "Propose is enabled for a partner")
	K.expect(f, not fp.family_buttons["try_for_baby"].disabled and not fp.family_buttons["adopt_child"].disabled, "Try for Baby / Adopt enabled for an adult couple")
	K.expect(f, fp.family_buttons["have_wedding"].disabled, "Hold Wedding disabled until engaged")
	fp.family_buttons["propose"].pressed.emit()
	K.expect(f, a.queue.size() == 1 and (a.queue[0] as Interaction).def_id == "propose" and (a.queue[0] as Interaction).target_id == b.id, "the button queues the propose interaction on the partner")
	fp.family_buttons["try_for_baby"].pressed.emit()
	K.expect(f, a.queue.size() == 2, "Try for Baby queued through the same pathway")
	a.clear_queue()
	# the siblings view
	fp.show_folk(kid)
	txt = _texts(fp.family_box)
	K.expect(f, txt.find("PARENTS") >= 0 and txt.find("Ann Rowe") >= 0 and txt.find("Bo Rowe") >= 0, "child sees parents")
	K.expect(f, txt.find("SIBLINGS") >= 0 and txt.find("Sam Rowe") >= 0 and txt.find("Sibling") >= 0, "child sees the sibling with its relation label")
	K.expect(f, fp.family_buttons["propose"].disabled and fp.family_buttons["adopt_child"].disabled, "children cannot propose or adopt")
	# engagement flows into the tab
	fp.show_folk(a)
	Family.propose_marriage(a.id, b.id)
	Events.game_event.emit("engaged", {"folk_id": a.id, "target_id": b.id})     # the panel refreshes itself on family events
	K.expect(f, not fp.family_buttons["have_wedding"].disabled and fp.family_buttons["propose"].disabled, "once engaged the wedding is offered")
	K.expect(f, _texts(fp.family_box).find("Engaged") >= 0, "engagement shown")
	# a dead / off-lot relative
	Aging.kill(b.id, "old age")
	fp.show_folk(a)
	txt = _texts(fp.family_box)
	K.expect(f, txt.find("Bo Rowe") >= 0 and txt.find("passed away") >= 0, "a late partner is shown as passed away")
	K.expect(f, fp.family_buttons["propose"].disabled, "no proposing to someone who is gone")
	# portrait colour comes from the shirt
	a.appearance["shirt"] = "#112233"
	K.expect(f, FolkPanel.portrait_color(a).is_equal_approx(Color.html("#112233")), "portrait colour is the shirt colour")
	# fake folk (no sim data) must not break the panel
	var fake := FakeFolk.new()
	fp.show_folk(fake)
	K.expect(f, fp.family_box.get_child_count() > 0 and _texts(fp.family_box).find("PARTNER") >= 0, "works with a fake folk")
	root.remove_child(fp)
	fp.free()
	K.teardown()
	return f
