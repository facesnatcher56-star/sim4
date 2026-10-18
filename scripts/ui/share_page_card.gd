class_name SharePageCard
extends RefCounted
## Family-history card: pick a household, see the card, save it as a card file (JSON) or a picture (PNG).

static func build(h: ShareHub) -> void:
	h.heading("Family-history card")
	h.folder_line()
	var list: Array = ShareExport.households()
	for e in list:
		h.pick_button(str(e["label"]), str(e["key"]))
	if h.choice == "":
		return
	h.card = {}
	for e2 in list:
		if str(e2["key"]) == h.choice:
			h.card = ShareCards.for_ids(e2["ids"])
	if h.card.is_empty():
		h.line("No card could be made.", 13, UITheme.MUTED)
		return
	var panel := PanelContainer.new()
	h.body.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(UIU.make_label(str(h.card["title"]), 20, UITheme.ACCENT))
	for m in h.card["members"]:
		box.add_child(UIU.make_label(str(m), 13))
	for l in h.card["lines"]:
		var lb := UIU.make_label(str(l), 13)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size = Vector2(440, 0)
		box.add_child(lb)
	var card: Dictionary = h.card
	h.action_button("Save as a card file", func():
		var r := ShareCards.export_json(card)
		h.say(("Saved %s." % r["file"]) if bool(r["ok"]) else ("Could not save: %s." % r["error"])))
	h.action_button("Save as a picture (PNG)", func():
		h.say(await _png(card)))

## Renders the card text on a plain background in a SubViewport and saves it to the exports folder.
static func _png(card: Dictionary) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or DisplayServer.get_name() == "headless":
		return "Pictures need the game window."
	var vp := SubViewport.new()
	vp.size = Vector2i(520, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var bg := ColorRect.new()
	bg.color = Color("#1c2430")
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	var lab := Label.new()
	lab.text = ShareCards.text(card)
	lab.position = Vector2(16, 12)
	lab.custom_minimum_size = Vector2(488, 0)
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bg.add_child(lab)
	tree.root.add_child(vp)
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	if img == null:
		return "Could not make the picture."
	DirAccess.make_dir_recursive_absolute(ShareFile.dir())
	var file := "%s.png" % ShareFile.stem(str(card.get("title", "card")))
	img.save_png("%s/%s" % [ShareFile.dir(), file])
	return "Saved %s." % file
