class_name SharePageTown
extends RefCounted
## Export this town (save + Chronicle) / import a town file as a NEW save slot.

static func build(h: ShareHub) -> void:
	if h.page == "exp_town":
		_export(h)
	else:
		_import(h)

static func _export(h: ShareHub) -> void:
	h.heading("Export this town")
	h.folder_line()
	h.line("Writes the whole town, its people and its Chronicle to one file for a friend to continue.", 13)
	h.action_button("Write the file", func():
		var r := ShareExport.export_town("")
		h.say(("Saved %s to the exports folder." % r["file"]) if bool(r["ok"]) else ("Could not export: %s." % r["error"])))

static func _import(h: ShareHub) -> void:
	h.heading("Import a town")
	h.folder_line()
	var files: Array = ShareFile.list("town")
	if files.is_empty():
		h.line("No town files yet. Put a .%s file from a friend into the folder above." % ShareFile.ext_of("town"), 13, UITheme.MUTED)
		return
	for f in files:
		h.pick_button(str(f), str(f))
	if h.choice == "":
		return
	if h.preview.is_empty():
		var rd := ShareFile.read("town", h.choice)
		h.preview = ShareValidateTown.town(rd["data"]) if bool(rd["ok"]) else rd
	if not bool(h.preview["ok"]):
		h.line("This file cannot be used: %s." % h.preview["error"], 14, UITheme.sem("error"))
		return
	var d: Dictionary = h.preview["data"]
	h.heading(str(d["title"]) + ((" - from " + str(d["from"])) if str(d["from"]) != "" else ""))
	h.line("Day %d, %d people, %d Chronicle lines." % [int(d["day"]), (d["save"]["folk"] as Array).size(), (d["chronicle"] as Array).size()], 13)
	if not (d["inbox"] as Array).is_empty():
		h.line("%d gift or letter waiting for you inside." % (d["inbox"] as Array).size(), 13, UITheme.ACCENT)
	h.line("It opens in a new, empty save slot. Your current game is not touched.", 12, UITheme.MUTED)
	h.action_button("Add to my saved games", func():
		var r := ShareImport.town(d)
		h.say(("Saved in slot %d. Use Load to play it." % int(r["data"]["slot"])) if bool(r["ok"]) else ("Could not import: %s." % r["error"])))
