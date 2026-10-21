class_name PhoneDialog
extends LifeHub
## Task 51: the phone as its own portrait screen (HUD "Phone" button): a status bar (time, signal, battery), a home screen of app icons (Messages, Jobs, Bank,
## News) and the opened app below. The apps are the LifeHubPhone / LifeHubJobs / LifeHubMedia builders; every action is a command like everywhere else.
## No working phone: the status bar says "No service" (or the reason) and the screen shows what to do instead (LifeHubPhone._no_phone).

func _init() -> void:
	dialog_width = 330.0
	tab = "phone"

func build() -> void:
	title_label.text = ""
	var f = folk_obj()
	if f == null:
		line("Pick somebody first.", 14, UITheme.MUTED)
		return
	_status_bar(f)
	LifeHubPhone.build(self)

func _status_bar(f) -> void:
	var row := HBoxContainer.new()
	body.add_child(row)
	var t := UIU.make_label("%02d:%02d" % [int(SysUtil.hour_f()), int((SysUtil.hour_f() - floorf(SysUtil.hour_f())) * 60.0)], 13)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var why: String = PhoneOwn.block(folk_id)
	var sig := UIU.make_label("No service" if why != "" else "Signal ▂▄▆█", 12)
	sig.modulate = UITheme.MUTED if why == "" else Color(0.95, 0.5, 0.45)
	sig.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(sig)
	var bat := UIU.make_label("▮▮▮▮", 12)
	bat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bat)
