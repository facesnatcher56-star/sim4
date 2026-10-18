extends RefCounted
## The Share window: every page builds, the folder path is shown, import previews validate and a bad file shows a message.

const K = preload("res://tests/systems_kit.gd")
const S = preload("res://tests/share_kit.gd")

func _texts(n: Node, out: Array) -> void:
	if n is Label:
		out.append((n as Label).text)
	if n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_texts(c, out)

func _has(h: ShareHub, frag: String) -> bool:
	var t: Array = []
	_texts(h.body, t)
	for s in t:
		if str(s).find(frag) >= 0:
			return true
	return false

func run() -> Array:
	var f: Array = []
	S.prepare()
	S.world()
	var h := ShareHub.new()
	Engine.get_main_loop().root.add_child(h)
	h.show_for(-1)
	K.expect(f, h.visible and _has(h, "Export a household") and _has(h, "Gifts"), "the menu lists the pages")
	for p in ["exp_house", "imp_house", "exp_town", "imp_town", "inbox", "card"]:
		h.go(p)
		K.expect(f, h.page == p and (p == "inbox" or _has(h, "Folder:")), "page %s builds and shows the folder" % p)
	h.go("exp_house")
	h.choice = h.page
	var list := ShareExport.households()
	K.expect(f, not list.is_empty(), "households are offered")
	h.choice = str(list[0]["key"])
	h.refresh()
	K.expect(f, _has(h, "Write the file"), "picking a household offers to write the file")
	var r := ShareExport.export_household(list[0]["ids"])
	h.go("imp_house")
	h.choice = str(r["file"])
	h.refresh()
	K.expect(f, _has(h, "Move them in") and _has(h, "Ann Vale"), "the import page previews the family")
	var bad := FileAccess.open(S.TMP + "/bad.sim4household", FileAccess.WRITE)
	bad.store_string("{\"format\": \"sim4household\", \"version\": 7}")
	bad.close()
	h.choice = "bad.sim4household"
	h.preview = {}
	h.refresh()
	K.expect(f, _has(h, "cannot be used") and not _has(h, "Move them in"), "a bad file shows why it cannot be used")
	h.go("card")
	h.choice = str(list[0]["key"])
	h.refresh()
	K.expect(f, _has(h, "Save as a card file") and _has(h, "Ann Vale"), "the card page shows the card")
	h.queue_free()
	S.finish()
	K.teardown()
	return f
