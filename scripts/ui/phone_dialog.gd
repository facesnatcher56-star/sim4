class_name PhoneDialog
extends LifeHub
## Task 51: the phone as its own portrait screen (HUD "Phone" button), made to look and feel like a modern touch phone: a black bezel with rounded corners, a status
## bar (time, signal or "No service", battery), a home screen with a big clock, app icons and a dock, app screens with a coloured app bar, and a navigation bar
## (back / home / close). Everything is clickable like a touchscreen: icons shrink when pressed and light up under the pointer.
## The apps are the LifeHubPhone / LifeHubJobs / LifeHubMedia builders; every action is a command like everywhere else. No working phone: the status bar says
## "No service" and the screen shows what to do instead (LifeHubPhone._no_phone).

const APPS := [
	{"id": "messages", "label": "Messages", "glyph": "bubble", "color": "#2fbf71"},
	{"id": "contacts", "label": "Contacts", "glyph": "person", "color": "#3b82f6"},
	{"id": "jobs", "label": "Jobs", "glyph": "case", "color": "#f59e0b"},
	{"id": "calendar", "label": "Calendar", "glyph": "calendar", "color": "#6b8af5"},
	{"id": "bank", "label": "Bank", "glyph": "coin", "color": "#c99a12"},
	{"id": "news", "label": "News", "glyph": "news", "color": "#ef4444"},
	{"id": "social", "label": "Social", "glyph": "heart", "color": "#ec4899"},
]
const DOCK := ["messages", "contacts", "jobs"]
const DAYS := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

var _status: PhoneStatus
var _bar_holder: VBoxContainer
var _nav: HBoxContainer
var _wall: Panel
static var _themes: Dictionary = {}

func _init() -> void:
	dialog_width = 372.0
	tab = "phone"

func _ready() -> void:
	super._ready()
	var root: VBoxContainer = _scroll.get_parent()
	root.get_child(0).visible = false              # the generic title row: a phone has no title bar
	root.add_theme_constant_override("separation", 0)
	var bez := StyleBoxFlat.new()
	bez.bg_color = Color("#06080b")
	bez.set_corner_radius_all(44)
	bez.border_color = Color("#2d343f")
	bez.set_border_width_all(2)
	bez.set_content_margin_all(11)
	bez.shadow_color = Color(0, 0, 0, 0.5)
	bez.shadow_size = 18
	add_theme_stylebox_override("panel", bez)
	_wall = Panel.new()
	_wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wall)
	move_child(_wall, 0)
	_status = PhoneStatus.new()
	root.add_child(_status)
	root.move_child(_status, 1)
	_bar_holder = VBoxContainer.new()
	root.add_child(_bar_holder)
	root.move_child(_bar_holder, 2)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_nav = HBoxContainer.new()
	_nav.add_theme_constant_override("separation", 0)
	root.add_child(_nav)
	var back := PhoneNav.new("back")
	back.tapped.connect(func():
		if LifeHubPhone.app != "":
			LifeHubPhone.app = ""
			refresh()
		else:
			hide_dialog())
	var home := PhoneNav.new("home")
	home.tapped.connect(func():
		LifeHubPhone.app = ""
		refresh())
	var recents := PhoneNav.new("recents")
	recents.tapped.connect(hide_dialog)
	for b in [back, home, recents]:
		_nav.add_child(b)

func _phone_theme(accent: Color) -> Theme:
	var key: String = accent.to_html(false)
	if _themes.has(key):
		return _themes[key]
	var t := Theme.new()
	for c in ["Button", "OptionButton"]:
		t.set_stylebox("normal", c, UITheme.box(Color("#222c3b"), 18, Color(1, 1, 1, 0.06), 1, 12))
		t.set_stylebox("hover", c, UITheme.box(Color("#2c394c"), 18, accent, 1, 12))
		t.set_stylebox("pressed", c, UITheme.box(accent.darkened(0.35), 18, accent, 1, 12))
		t.set_stylebox("disabled", c, UITheme.box(Color("#1a212c"), 18, Color(0, 0, 0, 0), 0, 12))
		t.set_stylebox("focus", c, UITheme.box(Color(0, 0, 0, 0), 18, accent, 1, 12))
	_themes[key] = t
	return t

func _app_def(id: String) -> Dictionary:
	for a in APPS:
		if str(a["id"]) == id:
			return a
	return {}

func build() -> void:
	title_label.text = ""
	var f = folk_obj()
	if f == null:
		line("Pick somebody first.", 14, UITheme.MUTED)
		return
	var why: String = PhoneOwn.block(folk_id)
	var h: float = SysUtil.hour_f()
	_status.set_state("%02d:%02d" % [int(h), int((h - floorf(h)) * 60.0)], 4, PhoneOwn.battery(), why)
	var def: Dictionary = _app_def(LifeHubPhone.app)
	var accent := Color(str(def.get("color", "#5bb8ff")))
	if why != "":
		accent = Color("#ef6a6a")
	accent_color = accent
	theme = _phone_theme(accent)
	for c in _bar_holder.get_children():
		_bar_holder.remove_child(c)
		c.queue_free()
	var home: bool = LifeHubPhone.app == "" and why == ""
	var wall := StyleBoxFlat.new()
	wall.bg_color = Color("#162239") if home else Color("#10151d")
	wall.set_corner_radius_all(34)
	_wall.add_theme_stylebox_override("panel", wall)
	if not home:
		_app_bar(str(def.get("label", "Phone")) if why == "" else "No phone", accent)
	LifeHubPhone.build(self)

func _app_bar(title: String, accent: Color) -> void:
	var bar := PanelContainer.new()
	var sb := UITheme.box(accent, 16, Color(0, 0, 0, 0), 0, 10)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	bar.add_child(row)
	var l := UIU.make_label(title, 20, Color("#0d1117") if accent.get_luminance() > 0.45 else Color.WHITE)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	_bar_holder.add_child(bar)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	_bar_holder.add_child(gap)

## The home screen: a big clock and date, the apps, a dock with the three main apps.
func build_home(fid: int) -> void:
	var clock := VBoxContainer.new()
	clock.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(clock)
	var h: float = SysUtil.hour_f()
	var big := UIU.make_label("%02d:%02d" % [int(h), int((h - floorf(h)) * 60.0)], 54, Color.WHITE)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.add_child(big)
	var d := UIU.make_label("%s, day %d" % [DAYS[(SysUtil.day() - 1) % 7], SysUtil.day()], 15, Color(1, 1, 1, 0.7))
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.add_child(d)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	body.add_child(gap)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for a in APPS:
		if DOCK.has(str(a["id"])):
			continue
		grid.add_child(_icon(a, fid, true))
	var widget := PanelContainer.new()
	widget.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.08), 20, Color(1, 1, 1, 0.08), 1, 12))
	var wv := VBoxContainer.new()
	widget.add_child(wv)
	var hid: int = int(SysUtil.folk(fid).household_id)
	wv.add_child(UIU.make_label("Wallet", 12, Color(1, 1, 1, 0.55)))
	wv.add_child(UIU.make_label("%d coins" % Economy.balance(hid), 22, Color("#f2c94c")))
	var due: Array = Economy.outstanding(hid)
	wv.add_child(UIU.make_label("Nothing due" if due.is_empty() else "%d to pay: %d coins" % [due.size(), Economy.owed(hid)], 13, Color(1, 1, 1, 0.7) if due.is_empty() else Color("#ff9f6b")))
	var wgap := Control.new()
	wgap.custom_minimum_size = Vector2(0, 14)
	body.add_child(wgap)
	body.add_child(widget)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	var dock := PanelContainer.new()
	dock.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.1), 26, Color(1, 1, 1, 0.08), 1, 8))
	var drow := HBoxContainer.new()
	drow.alignment = BoxContainer.ALIGNMENT_CENTER
	drow.add_theme_constant_override("separation", 10)
	dock.add_child(drow)
	for id in DOCK:
		drow.add_child(_icon(_app_def(id), fid, true))          # dock icons carry small labels too (reviewer 0700)
	body.add_child(dock)
	var d2: Dictionary = PhoneOwn.kind_def(str(PhoneOwn.own.get(fid, {}).get("kind", "")))
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_child(UIU.make_label("Line %d coins a week" % int(SoloCfg.by_diff("phone", "bill_amount")), 12, Color(1, 1, 1, 0.5)))
	var pawn := Button.new()
	pawn.text = "Pawn (%d)" % int(d2.get("sell", 0))
	pawn.flat = true
	pawn.add_theme_font_size_override("font_size", 12)
	pawn.tooltip_text = "Sell the phone. You will have none until you buy another."
	pawn.pressed.connect(func(): act("phone_sell"))
	foot.add_child(pawn)
	body.add_child(foot)

func _icon(a: Dictionary, fid: int, labelled: bool) -> PhoneIcon:
	var badge: String = ""
	match str(a["id"]):
		"messages":
			var n: int = PhoneState.inbox_of(fid).size()
			badge = str(n) if n > 0 else ""
		"jobs":
			badge = "1" if not Careers.pending_offer(fid).is_empty() else ("!" if not SoloOpening.said.has("t_jobs_app") and not Careers.has_job(fid) else "")          # task 61: lit until first opened
	var ic := PhoneIcon.new(str(a["glyph"]), str(a["label"]), Color(str(a["color"])), badge)
	ic.show_label = labelled
	ic.custom_minimum_size = Vector2(80, 92 if labelled else 74)
	ic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var id: String = str(a["id"])
	ic.tapped.connect(func():
		LifeHubPhone.app = id
		refresh())
	return ic

func _center() -> void:
	var vp := get_viewport_rect().size
	var h: float = clampf(vp.y - 110.0, 460.0, 760.0)
	_scroll.custom_minimum_size = Vector2(0, h - 130.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.clip_contents = true
	reset_size()
	position = Vector2(maxf(vp.x - size.x - 40.0, 8.0), maxf(floorf((vp.y - size.y) * 0.5), 62.0))
