class_name OfferToast
extends PanelContainer
## Job-offer card with Accept / Decline. Stays until answered (or the offer lapses); Careers also shows it in the Work dialog.
var folk_id := -1
var text_label: Label
var accept_btn: Button
var decline_btn: Button

func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.PANEL, 0.98), 8, Color("#4cc78a"), 2, 10))
	var v := VBoxContainer.new()
	add_child(v)
	text_label = UIU.make_label("", 14)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(320, 0)
	v.add_child(text_label)
	var row := HBoxContainer.new()
	v.add_child(row)
	accept_btn = Button.new()
	accept_btn.text = "Accept"
	accept_btn.pressed.connect(func(): _answer(true))
	row.add_child(accept_btn)
	decline_btn = Button.new()
	decline_btn.text = "Decline"
	decline_btn.pressed.connect(func(): _answer(false))
	row.add_child(decline_btn)
	var later := Button.new()
	later.text = "Later"
	later.tooltip_text = "Decide later: the offer stays open for a few days (Work button on the Folk panel)."
	later.pressed.connect(func(): visible = false)
	row.add_child(later)

func show_offer(fid: int) -> void:
	var o: Dictionary = Careers.pending_offer(fid)
	if o.is_empty():
		return
	folk_id = fid
	var ld: Dictionary = Careers.level_def(str(o["career"]), int(o["level"]))
	text_label.text = "%s has a job offer: %s (%s), %d coins/hour, %s to %s." % [SysUtil.folk_name(fid), str(ld.get("title", "?")),
		str(Careers.career_def(str(o["career"])).get("label", "")), int(ld.get("pay", 0)),
		CareerDialog.hours_text(float(ld.get("start", 0))), CareerDialog.hours_text(float(ld.get("end", 0)))]
	visible = true

func _answer(accept: bool) -> void:
	if accept:
		Commands.run({"folk_id": folk_id, "action": "career_accept"})
	else:
		Commands.run({"folk_id": folk_id, "action": "career_decline"})
		UIU.notify("%s turned the job down." % SysUtil.folk_name(folk_id), "info")
	visible = false
