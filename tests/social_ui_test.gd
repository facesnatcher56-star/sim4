extends RefCounted
## Social UI (headless): People tab cards (tracks, bit, '?' knowledge, history, tension), mood tooltip detail, pie menu categories with
## specific disabled reasons.

const S = preload("res://tests/social_kit.gd")

func _labels(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		_labels(c, out)
	return out

func run() -> Array:
	var f: Array = []
	var w := S.setup(601)
	var root: Window = Engine.get_main_loop().root
	var a := S.folk(w, "Ann", ["social", "romantic"])
	var b := S.folk(w, "Bo", ["foodie", "neat", "gamer"])
	var c := S.folk(w, "Cy", ["hot_headed"])
	RelationshipService.add_both(a.id, b.id, "friendship", 45.0)
	RelationshipService.add_both(a.id, b.id, "romance", 30.0)
	RelationshipService.add_both(a.id, b.id, "trust", 20.0)
	RelationshipService.add_both(a.id, c.id, "friendship", 15.0)
	SocialDynamics.escalate(a.id, c.id, 35.0)
	RelationshipService.add_history(a.id, b.id, "go_on_date", 0.8, a.id)
	RelationshipService._tag_last_history(a.id, b.id, "great", "Magical date")
	var fp := FolkPanel.new()
	root.add_child(fp)
	fp.show_folk(a)
	S.expect(f, fp.rel_box != null and fp.rel_box.get_child_count() >= 2, "People tab lists the people Ann knows (%d)" % fp.rel_box.get_child_count())
	var card = fp.rel_box.get_node_or_null("rel_%d" % b.id)
	S.expect(f, card != null, "a card per person")
	var txt: String = "\n".join(_labels(card)) if card != null else ""
	S.expect(f, txt.find("Friendship 45") >= 0 and txt.find("Romance 30") >= 0 and txt.find("Trust 20") >= 0, "friendship / romance / trust meters: %s" % txt)
	S.expect(f, txt.find("Acquaintance") >= 0 or txt.find("Friend") >= 0, "relationship bit chip shown")
	S.expect(f, txt.find("?") >= 0 and txt.find("Job: ?") >= 0 and txt.find("Dream: ?") >= 0, "undiscovered info is '?': %s" % txt)
	S.expect(f, txt.find("Magical date") >= 0, "shared history snippets shown")
	S.expect(f, txt.find("Spark") >= 0, "spark shown for romance")
	S.expect(f, (card as Control).tooltip_text.find("Trust") >= 0, "card tooltip is RelationshipService.describe")
	var ccard = fp.rel_box.get_node_or_null("rel_%d" % c.id)
	var ctxt: String = "\n".join(_labels(ccard)) if ccard != null else ""
	S.expect(f, ctxt.find("Tense") >= 0, "tension chip on the person Ann argued with: %s" % ctxt)
	# discovering things updates the card
	RelationshipService.reveal(a.id, b.id, "all")
	fp._build_relationships()
	var card2 = fp.rel_box.get_node_or_null("rel_%d" % b.id)
	var txt2: String = "\n".join(_labels(card2))
	S.expect(f, txt2.find("Foodie") >= 0 and txt2.find("Job: Unemployed") >= 0 and txt2.find("?") < 0, "after discovery the real info shows: %s" % txt2)
	# deferred rebuild on relationship events
	fp._on_rel_changed(a.id, b.id)
	fp._on_rel_changed(a.id, c.id)
	S.expect(f, fp._rel_pending, "relationship changes schedule a single deferred rebuild")
	# mood tooltip
	a.add_buff("confident_glow")
	a.add_buff("stage_glow")
	a.add_buff("laughing_fit")
	Emotions.sync(a)
	fp._refresh_mood()
	var tip: String = fp.mood_area.tooltip_text
	S.expect(f, tip.find("Driven by") >= 0 and tip.find("Confident") >= 0 and tip.find("Stage Glow") >= 0, "mood tooltip lists the driving buffs: %s" % tip)
	S.expect(f, tip.find("Effects") >= 0 and tip.find("Learning") >= 0, "mood tooltip lists the effects")
	S.expect(f, tip.find("Mood: ") >= 0 and tip.find("mfx_") < 0 and tip.find("Mood: Confident") < 0, "hidden mood-effect buffs are not listed as buffs")
	S.expect(f, fp.mood_label.text.begins_with("Confident"), "mood label uses the display name (%s)" % fp.mood_label.text)
	S.expect(f, fp.mood_color("confident") != UIU.MOOD_COLORS["neutral"], "new moods have their own colour")
	# --- pie menu: add the target to the real World so the UI can resolve it
	var pie := PieMenu.new()
	root.add_child(pie)
	var wd = root.get_node_or_null("World")
	if wd != null:
		var keep_next: int = Folk._next_id
		var fake_target := Folk.create("PieTarget", ["shy"], 8801)
		Folk._next_id = keep_next
		fake_target.household_id = 1
		wd.add_folk(fake_target, Vector2i(3, 3))
		var actor := S.folk(w, "Pia", [])
		w.add_folk(fake_target, Vector2i(12, 12))
		var entries: Array = []
		var defs: Dictionary = SimEnv.data().interactions()
		for iid in defs:
			if str(defs[iid].get("target", "")) == "folk" and defs[iid].has("category"):
				entries.append({"id": iid, "label": str(defs[iid]["label"]), "category": str(defs[iid]["category"]).capitalize(), "enabled": SocialDynamics.reason_unavailable(actor, fake_target, str(iid)) == "", "reason": "Unavailable"})
		entries.sort_custom(func(x, y): return str(x["category"]) + str(x["label"]) < str(y["category"]) + str(y["label"]))
		pie.open_with_entries(actor, "folk", 8801, entries, Vector2(50, 50))
		S.expect(f, pie.category_headers.size() >= 6 and pie.category_headers.has("Friendly") and pie.category_headers.has("Mean"), "pie groups socials by category: %s" % str(pie.category_headers.keys()))
		var order: Array = pie.category_headers.keys()
		S.expect(f, order.slice(0, 6) == ["Friendly", "Funny", "Romantic", "Deep", "Group", "Mean"], "categories are in a fixed friendly order: %s" % str(order))
		S.expect(f, pie.entry_buttons.size() >= 40, "all social entries are listed (%d)" % pie.entry_buttons.size())
		var reasons := 0
		var specific := 0
		for bt in pie.entry_buttons:
			if bt.disabled:
				reasons += 1
				if (bt.tooltip_text as String) != "" and (bt.tooltip_text as String) != "Unavailable":
					specific += 1
		S.expect(f, reasons > 5 and specific == reasons, "every disabled entry carries a specific reason (%d/%d)" % [specific, reasons])
		var kiss: Button = pie.entry_buttons.filter(func(bt): return bt.name == "btn_kiss")[0]
		S.expect(f, kiss.disabled and kiss.tooltip_text.find("romance") >= 0, "kiss is disabled for strangers with a reason: %s" % kiss.tooltip_text)
		pie.set_category_open("Mean", true)
		S.expect(f, (pie.category_boxes["Mean"] as Control).visible, "sections expand")
		S.expect(f, pie.category_headers["Mean"].text.find("MEAN") >= 0 and pie.category_headers["Mean"].text.find("/") >= 0, "headers show enabled/total counts: %s" % pie.category_headers["Mean"].text)
		wd.remove_folk(8801)
	pie.queue_free()
	fp.queue_free()
	S.teardown()
	return f
