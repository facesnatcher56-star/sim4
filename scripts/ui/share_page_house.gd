class_name SharePageHouse
extends RefCounted
## Export a household (pick one, write the file) / import a household (pick a file, preview, move in).

static func build(h: ShareHub) -> void:
	if h.page == "exp_house":
		_export(h)
	else:
		_import(h)

static func _export(h: ShareHub) -> void:
	h.heading("Export a household")
	h.folder_line()
	var list: Array = ShareExport.households()
	for e in list:
		h.pick_button("%s - %d people" % [e["label"], (e["ids"] as Array).size()], str(e["key"]))
	if h.choice == "":
		return
	h.action_button("Write the file", func():
		for e in list:
			if str(e["key"]) == h.choice:
				var r := ShareExport.export_household(e["ids"])
				h.say(("Saved %s to the exports folder." % r["file"]) if bool(r["ok"]) else ("Could not export: %s." % r["error"])))

static func _import(h: ShareHub) -> void:
	h.heading("Import a household")
	h.folder_line()
	var files: Array = ShareFile.list("household")
	if files.is_empty():
		h.line("No household files yet. Put a .%s file from a friend into the folder above." % ShareFile.ext_of("household"), 13, UITheme.MUTED)
		return
	for f in files:
		h.pick_button(str(f), str(f))
	if h.choice == "":
		return
	if h.preview.is_empty():
		var rd := ShareFile.read("household", h.choice)
		h.preview = ShareValidate.household(rd["data"]) if bool(rd["ok"]) else rd
	if not bool(h.preview["ok"]):
		h.line("This file cannot be used: %s." % h.preview["error"], 14, UITheme.sem("error"))
		return
	var d: Dictionary = h.preview["data"]
	h.heading(str(d["title"]))
	for m in d["members"]:
		h.line("%s, %s" % [m["name"], str(m["stage"])], 13)
	for l in (d["history"] as Array).slice(-5):
		h.line(str(l), 12, UITheme.MUTED)
	h.line("They move in as townies. They will not know anyone here yet.", 12, UITheme.MUTED)
	h.action_button("Move them in", func():
		var r := ShareImport.household(d)
		h.say(("The %s moved to town." % str(d["title"]).trim_prefix("The ")) if bool(r["ok"]) else ("Could not import: %s." % r["error"])))
