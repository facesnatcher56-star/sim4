class_name LifeHubMedia
extends RefCounted
## The "News" tab of LifeHub: what is on the radio and the TV now, the town's latest news (the newspaper), and buttons for the radio and the TV at home.

static func build(dlg: LifeHub) -> void:
	var fid: int = dlg.folk_id
	dlg.heading("On now")
	dlg.line("Radio, %s: %s" % [str(MediaServices.cfg().get("radio", {}).get("label", "Radio")), MediaServices.now("radio")], 14)
	dlg.line("TV, %s: %s" % [str(MediaServices.cfg().get("tv", {}).get("label", "TV")), MediaServices.now("tv")], 14)
	for pid in ["radio", "tv"]:
		for sid in Places.services(pid):
			var why: String = PlaceUse.why_not(fid, pid, str(sid))
			dlg.row_with(Places.service_label(pid, str(sid)), [dlg.button("Use", why if why != "" else "At home", func(): dlg.act("use", {"place": pid, "service": sid}), why == "")], why != "")
	dlg.heading("The Fernwood Courier")
	var items: Array = TownNews.latest(10)
	if items.is_empty():
		dlg.line("No news yet. The town is quiet.", 13, UITheme.MUTED)
	for it in items:
		dlg.line("Day %d: %s" % [int(it["day"]), str(it["text"])], 13, UITheme.TEXT if int(it["severity"]) >= 2 else UITheme.MUTED)
