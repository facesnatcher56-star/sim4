class_name Hud
extends Control
## Root of the in-game HUD. Everything is built in code so the scene stays trivial.
signal save_requested(slot: int)
signal load_requested(slot: int)
signal quit_to_title

var lot_view = null
var theme_res: Theme
var top_bar: PanelContainer
var time_label: Label
var day_label: Label
var coins_label: Button
var speed_buttons: Dictionary = {}     # speed int -> Button
var build_button: Button
var save_button: Button
var map_button: Button
var money_button: Button
var lot_label: Label
var travel_panel: TravelPanel
var folk_panel: FolkPanel
var queue_bar: QueueBar
var pie: PieMenu
var thoughts: ThoughtLayer
var toasts: ToastFeed
var build_panel: BuildPanel
var floor_selector: FloorSelector
var goals_dialog: GoalsDialog
var career_dialog: CareerDialog
var money_hub: BankHub                  # task 13: Town & Money window
var vacation_dialog: VacationDialog
var household_dialog: HouseholdDialog
var help_dialog: HelpDialog
var incident_debug: IncidentDebug
var case_board: CaseBoard
var case_prompt: CasePrompt
var pause_menu: PauseMenu
var share_hub: ShareHub
var settings_dialog: SettingsDialog
var confirm_dialog: ConfirmDialog
var menu_button: Button
var _settings_from_pause := false
var tips: FirstRunTips
var tracker: ScenarioTracker
var offer_toast: OfferToast
var help_button: Button
var folk_row: HBoxContainer
var save_menu: PanelContainer
var selected_folk_id := -1
var selected_object_id := -1
var coins := 0
var household_name := "Household"
var prev_speed := 1
var folk_resolver: Callable = Callable()
var _ctx_handled := false
var _pending_tile := Vector2i(-1, -1)

func _ready() -> void:
	SettingsKeys.ensure_actions()
	theme_res = UITheme.build()
	theme = theme_res
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_left()
	thoughts = ThoughtLayer.new()
	add_child(thoughts)
	# top-centre column under the bar: job-offer card first, then the toast stack (never overlaps the folk panel or the build panel)
	var top_center := VBoxContainer.new()
	top_center.anchor_left = 0.5
	top_center.anchor_right = 0.5
	top_center.offset_left = -170
	top_center.offset_right = 170
	top_center.offset_top = 60
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_center)
	offer_toast = OfferToast.new()
	top_center.add_child(offer_toast)
	toasts = ToastFeed.new()
	toasts.offer = offer_toast
	top_center.add_child(toasts)
	build_panel = BuildPanel.new()
	build_panel.anchor_left = 1.0
	build_panel.anchor_right = 1.0
	build_panel.anchor_top = 0.0
	build_panel.anchor_bottom = 1.0
	build_panel.offset_left = -324
	build_panel.offset_right = -12
	build_panel.offset_top = 64
	build_panel.offset_bottom = -12
	build_panel.mode_changed.connect(_on_build_mode)
	add_child(build_panel)
	pie = PieMenu.new()
	add_child(pie)
	_build_save_menu()
	travel_panel = TravelPanel.new()
	add_child(travel_panel)
	tips = FirstRunTips.new()
	add_child(tips)
	tracker = ScenarioTracker.new()      # 'Getting Started' checklist (top-left), only visible with a scenario
	tracker.goals_requested.connect(func(): goals_dialog.toggle_for(selected_folk_id))
	add_child(tracker)
	var coop_hud := CoopHud.new()      # pace / why time is skipping / pause vote / alerts / name tags; invisible outside a co-op session
	coop_hud.hud = self
	add_child(coop_hud)
	_build_dialogs()      # added after the tips so dialogs always sit on top of them
	UIU.connect_ev("game_event", func(n, _p): if n == "lot_changed" or n == "coop_clock": _update_clock())
	UIU.connect_ev("selection_changed", _on_selection_changed)
	UIU.connect_ev("coins_changed", _on_coins_changed)
	UIU.connect_ev("folk_added", func(_i): rebuild_folk_row())
	UIU.connect_ev("folk_removed", func(_i): rebuild_folk_row())
	UIU.connect_ev("game_event", func(n, _p): if n == "open_town_law": TownLawDialog.open_from(case_board))
	UIU.connect_ev("game_event", func(n, _p): if n in ["left_for_work", "returned_from_work", "left_for_school", "returned_from_school", "left_lot", "returned_to_lot", "moved_in", "moved_out", "adopted", "married", "divorced"]: rebuild_folk_row())
	if Clock.has_signal("minute_passed"):
		Clock.connect("minute_passed", _update_clock)
	_update_clock()
	_update_speed_buttons()

func _process(_d: float) -> void:
	# Cheap poll keeps speed highlight right even if something else changes Clock.speed.
	if not build_panel.active:
		_update_speed_buttons()

# ------------------------------------------------------------ construction
func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.anchor_right = 1.0
	top_bar.offset_left = 8
	top_bar.offset_right = -8
	top_bar.offset_top = 8
	add_child(top_bar)
	var h := HBoxContainer.new()
	top_bar.add_child(h)
	day_label = UIU.make_label("Day 1", 18)
	h.add_child(day_label)
	time_label = UIU.make_label("--:--", 18, UITheme.ACCENT)
	time_label.custom_minimum_size = Vector2(70, 0)
	h.add_child(time_label)
	h.add_child(VSeparator.new())
	for s in [[0, "||"], [1, ">"], [2, ">>"], [3, ">>>"]]:
		var b := Button.new()
		b.text = s[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(44, 0)
		b.tooltip_text = "Pause (Space)" if s[0] == 0 else ("Normal speed (1)" if s[0] == 1 else "Fast (2)" if s[0] == 2 else "Fastest (3)")
		b.pressed.connect(set_speed.bind(s[0]))
		h.add_child(b)
		speed_buttons[s[0]] = b
	h.add_child(WeatherHud.new())    # weather + season + date widget (scripts/ui/weather_hud.gd)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	lot_label = UIU.make_label("", 15, UITheme.ACCENT)
	h.add_child(lot_label)
	coins_label = Button.new()
	coins_label.text = "0 Coins"
	coins_label.flat = true
	coins_label.add_theme_font_size_override("font_size", 18)
	coins_label.add_theme_color_override("font_color", Color("#f2c94c"))
	coins_label.add_theme_color_override("font_hover_color", Color("#ffe38a"))
	coins_label.tooltip_text = "Household money, bills and last week's income and spending"
	coins_label.pressed.connect(func(): household_dialog.toggle_for(selected_folk_id))
	h.add_child(coins_label)
	map_button = Button.new()
	map_button.text = "Map"
	map_button.tooltip_text = "Neighbourhood map and travel (M)"
	map_button.pressed.connect(func(): travel_panel.toggle())
	h.add_child(map_button)
	money_button = Button.new()
	money_button.text = "Money"
	money_button.tooltip_text = "Shops, your business, homes and the bank (optional)"
	money_button.pressed.connect(func(): money_hub.toggle_for(selected_folk_id))
	h.add_child(money_button)
	build_button = Button.new()
	build_button.text = "Build/Buy"
	build_button.toggle_mode = true
	build_button.tooltip_text = "Toggle Build/Buy mode (B)"
	build_button.pressed.connect(func(): build_panel.set_active(build_button.button_pressed))
	h.add_child(build_button)
	save_button = Button.new()
	save_button.text = "Save/Load"
	save_button.tooltip_text = "Save, load, or go back to the title screen"
	save_button.pressed.connect(func():
		_refresh_save_menu()
		save_menu.visible = not save_menu.visible)
	h.add_child(save_button)
	help_button = Button.new()
	help_button.text = "?"
	help_button.tooltip_text = "Controls and help (F1)"
	help_button.pressed.connect(func(): help_dialog.toggle_for(selected_folk_id))
	h.add_child(help_button)
	menu_button = Button.new()
	menu_button.text = "Menu"
	menu_button.tooltip_text = "Pause menu and settings (Esc)"
	menu_button.pressed.connect(func(): pause_menu.toggle_for(-1))
	h.add_child(menu_button)

func _build_left() -> void:
	var left := VBoxContainer.new()
	left.anchor_top = 1.0
	left.anchor_bottom = 1.0
	left.offset_left = 12
	left.offset_bottom = -12
	left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	folk_row = HBoxContainer.new()
	left.add_child(folk_row)
	queue_bar = QueueBar.new()
	left.add_child(queue_bar)
	folk_panel = FolkPanel.new()
	left.add_child(folk_panel)
	folk_panel.goals_requested.connect(func(id): goals_dialog.toggle_for(id))
	folk_panel.career_requested.connect(func(id): career_dialog.toggle_for(id))

func _build_dialogs() -> void:
	goals_dialog = GoalsDialog.new()
	career_dialog = CareerDialog.new()
	money_hub = BankHub.new()
	vacation_dialog = VacationDialog.new()
	UIU.connect_ev("game_event", func(n, p): if n == "vacation_open_booking": vacation_dialog.show_for(int(p.get("folk_id", selected_folk_id))))
	household_dialog = HouseholdDialog.new()
	help_dialog = HelpDialog.new()
	help_dialog.tips_requested.connect(func(): tips.start(true))
	share_hub = ShareHub.new()
	pause_menu = PauseMenu.new()
	pause_menu.chosen.connect(_on_pause_choice)
	settings_dialog = SettingsDialog.new()
	settings_dialog.closed.connect(func():
		if _settings_from_pause:
			_settings_from_pause = false
			pause_menu.show_for(-1))
	confirm_dialog = ConfirmDialog.new()
	IncidentDebug.ensure_action()
	incident_debug = IncidentDebug.new()
	CaseBoard.ensure_action()
	case_board = CaseBoard.new()
	case_prompt = CasePrompt.new()
	JusticePlayer.ask_fn = case_prompt.ask
	for d in [goals_dialog, career_dialog, money_hub, vacation_dialog, household_dialog, help_dialog, pause_menu, settings_dialog, confirm_dialog, incident_debug, case_board, case_prompt, share_hub]:
		add_child(d)
	save_menu.visibility_changed.connect(func(): UIDialog.track_open(save_menu.get_instance_id(), save_menu.visible))

func dialogs() -> Array:
	return [confirm_dialog, settings_dialog, share_hub, pause_menu, goals_dialog, career_dialog, money_hub, vacation_dialog, household_dialog, help_dialog, incident_debug, case_board, case_prompt]

func _on_pause_choice(id: String) -> void:
	pause_menu.hide_dialog()
	match id:
		"settings":
			_settings_from_pause = true
			settings_dialog.show_for(-1)
		"save", "load":
			_refresh_save_menu()
			save_menu.visible = true
		"share":
			share_hub.show_for(-1)
		"help":
			help_dialog.show_for(selected_folk_id)
		"quit":
			request_quit_to_title()

## Quit to Title, asking first unless the player turned the confirmation off.
func request_quit_to_title() -> void:
	if not GameSettings.get_bool("confirm_quit"):
		quit_to_title.emit()
		return
	confirm_dialog.ask("Quit to title?", "Unsaved progress will be lost.", "Quit to Title", func(): quit_to_title.emit(), "Stay")

## Closes the topmost open dialog; returns true if one was open.
func close_top_dialog() -> bool:
	for d in dialogs():
		if d.visible:
			d.hide_dialog()
			return true
	if save_menu.visible:
		save_menu.visible = false
		return true
	return false

func _build_save_menu() -> void:
	save_menu = PanelContainer.new()
	save_menu.visible = false
	save_menu.anchor_left = 0.5
	save_menu.anchor_right = 0.5
	save_menu.anchor_top = 0.5
	save_menu.anchor_bottom = 0.5
	save_menu.offset_left = -200
	save_menu.offset_right = 200
	save_menu.offset_top = -140
	save_menu.offset_bottom = 140
	add_child(save_menu)
	var v := VBoxContainer.new()
	save_menu.add_child(v)
	v.add_child(UIU.make_label("Save / Load", 20))
	v.add_child(UIU.make_label("Saving over a slot replaces what was there.", 12, UITheme.MUTED))
	for i in range(1, SaveSlots.SLOTS + 1):
		var row := HBoxContainer.new()
		v.add_child(row)
		var lab := UIU.make_label("Slot %d: %s" % [i, SaveSlots.slot_summary(i)], 14)
		lab.name = "SlotLabel%d" % i
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var sb := Button.new()
		sb.text = "Save"
		sb.pressed.connect(func(): do_save(i, lab))
		row.add_child(sb)
		var lb := Button.new()
		lb.name = "LoadBtn%d" % i
		lb.disabled = not SaveSlots.can_load(i)
		lb.text = "Load"
		lb.pressed.connect(func():
			save_menu.visible = false
			load_requested.emit(i))
		row.add_child(lb)
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): save_menu.visible = false)
	hb.add_child(close)
	var qt := Button.new()
	qt.text = "Quit to Title"
	qt.tooltip_text = "Leave this game and return to the title screen. Unsaved progress is lost."
	qt.pressed.connect(func():
		save_menu.visible = false
		request_quit_to_title())
	hb.add_child(qt)

func _refresh_save_menu() -> void:
	for i in range(1, SaveSlots.SLOTS + 1):
		var lab: Label = save_menu.find_child("SlotLabel%d" % i, true, false)
		var lb: Button = save_menu.find_child("LoadBtn%d" % i, true, false)
		if lab != null:
			lab.text = "Slot %d: %s" % [i, SaveSlots.slot_summary(i)]
		if lb != null:
			lb.disabled = not SaveSlots.can_load(i)

func do_save(slot: int, lab: Label = null) -> bool:
	var ok := SaveSlots.save(slot, household_name)
	if lab:
		lab.text = "Slot %d: %s" % [slot, SaveSlots.slot_summary(slot)]
	_refresh_save_menu()
	UIU.notify("Game saved (slot %d)" % slot if ok else "Save failed", "good" if ok else "bad")
	save_requested.emit(slot)
	return ok

# ------------------------------------------------------------ wiring
func set_lot_view(lv) -> void:
	lot_view = lv
	if floor_selector == null:
		floor_selector = FloorSelector.new()
		add_child(floor_selector)
	floor_selector.lot_view = lv
	thoughts.lot_view = lv
	build_panel.lot_view = lv
	if lv != null and lv.has_signal("tile_clicked"):
		lv.tile_clicked.connect(_on_tile_clicked)
		lv.context_requested.connect(_on_context_requested)

func _resolve(id: int):
	if folk_resolver.is_valid():
		return folk_resolver.call(id)
	return UIU.get_folk(id)

func select_folk(id: int) -> void:
	selected_folk_id = id
	Neighborhood.selected = id
	var f = _resolve(id)
	folk_panel.show_folk(f)
	queue_bar.set_folk(f)
	rebuild_folk_row()
	for d in [goals_dialog, career_dialog, money_hub]:
		if d != null and d.visible:
			d.show_for(id)

func rebuild_folk_row() -> void:
	for c in folk_row.get_children():
		c.queue_free()
	if not World.has_method("all_folk"):
		return
	for f in World.all_folk():
		if f.has_meta("visitor") or f.has_meta("away"):
			continue
		if CoopTime.active and not CoopVisibility.is_mine(f):
			continue      # co-op: the folk row (and every panel behind it) is YOUR household only
		var b := Button.new()
		b.custom_minimum_size = Vector2(46, 46)
		b.tooltip_text = str(f.name)
		b.toggle_mode = true
		b.button_pressed = (f.id == selected_folk_id)
		var fi := FaceIcon.new()
		fi.color = FolkPanel.portrait_color(f)
		fi.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(fi)
		var fid: int = f.id
		b.pressed.connect(func():
			select_folk(fid)
			if lot_view != null and lot_view.has_method("focus_on"):
				lot_view.call("focus_on", "folk", fid))      # the camera goes to wherever that folk is (another lot on the big map)
		folk_row.add_child(b)

func _on_selection_changed(kind: String, id: int) -> void:
	if build_panel.active:
		return
	match kind:
		"folk":
			var cur = _resolve(selected_folk_id)
			var other = _resolve(id)
			var same_house: bool = cur == null or other == null or id == selected_folk_id \
				or UIU.prop(cur, "household_id", 0) == UIU.prop(other, "household_id", 0)
			if same_house:
				select_folk(id)
			else:
				pie.open_for(cur, "folk", id, get_viewport().get_mouse_position())
		"object":
			selected_object_id = id
			var f = _resolve(selected_folk_id)
			if f != null:
				pie.open_for(f, "object", id, get_viewport().get_mouse_position())
		_:
			selected_object_id = -1
			pie.close()

func _on_coins_changed(_hh: int, amount: int) -> void:
	if _hh <= 0:
		return      # ambient NPCs (household -1) pay with their own pocket money
	if CoopTime.active and _hh != Players.primary_household():
		return      # co-op: the top bar shows only your own household's money
	coins = amount
	coins_label.text = "%d Coins" % amount

# ------------------------------------------------------------ time
func _update_clock(_t = 0) -> void:
	time_label.text = UIU.clock_text()
	var here: String = Neighborhood.lot_of_selected()
	lot_label.text = "" if here == Neighborhood.HOME or here == "" else "at %s  " % Neighborhood.label_of(here)
	day_label.text = "Day %d" % UIU.day_number()

func set_speed(s: int) -> void:
	if build_panel.active:
		return
	UIU.set_speed(s)
	_update_speed_buttons()

func _update_speed_buttons() -> void:
	var cur := UIU.get_speed()
	for k in speed_buttons:
		speed_buttons[k].button_pressed = (k == cur)
		speed_buttons[k].disabled = build_panel != null and build_panel.active

func _on_build_mode(on: bool) -> void:
	build_button.set_pressed_no_signal(on)
	pie.close()
	if on:
		prev_speed = maxi(UIU.get_speed(), 1)
		UIU.set_speed(0)
	else:
		UIU.set_speed(prev_speed)
	folk_panel.visible = not on
	queue_bar.visible = not on
	_update_speed_buttons()

# ------------------------------------------------------------ input
func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	# rebindable actions (SettingsKeys); Esc, "?" and "/" stay fixed
	if ev.is_action_pressed("sim_pause"):
		if not build_panel.active:
			set_speed(0 if UIU.get_speed() != 0 else maxi(prev_speed, 1))
	elif ev.is_action_pressed("sim_speed_1"): set_speed(1)
	elif ev.is_action_pressed("sim_speed_2"): set_speed(2)
	elif ev.is_action_pressed("sim_speed_3"): set_speed(3)
	elif ev.is_action_pressed("sim_build"): build_panel.set_active(not build_panel.active)
	elif ev.is_action_pressed("sim_map"): travel_panel.toggle()
	elif ev.is_action_pressed("sim_wall_mode"):
		if lot_view: lot_view.call("cycle_wall_mode")
	elif ev.is_action_pressed("sim_help"): help_dialog.toggle_for(selected_folk_id)
	elif ev.is_action_pressed("sim_debug_incidents"): incident_debug.toggle_for(selected_folk_id)
	elif ev.is_action_pressed("sim_case_board"): case_board.toggle_for(selected_folk_id)
	else:
		match ev.keycode:
			KEY_SLASH:
				if ev.shift_pressed:
					help_dialog.toggle_for(selected_folk_id)
			KEY_QUESTION:
				help_dialog.toggle_for(selected_folk_id)
			KEY_ESCAPE:
				if pie.visible: pie.close()
				elif not close_top_dialog() and _can_open_pause():
					pause_menu.show_for(-1)
	if UIU.get_speed() != 0:
		prev_speed = UIU.get_speed()

## In Build/Buy, Esc first belongs to the build tool (back to select); only then does it open the menu.
func _can_open_pause() -> bool:
	if not visible:
		return false
	if build_panel.active and lot_view != null and str(lot_view.get("tool")) != "select":
		return false
	return true

func _on_tile_clicked(tile: Vector2i, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT and not build_panel.active:
		_ctx_handled = false
		_pending_tile = tile
		call_deferred("_maybe_go_here")

func _on_context_requested(_kind: String, _id: int, _tile: Vector2i) -> void:
	_ctx_handled = true

func _maybe_go_here() -> void:
	if not _ctx_handled:
		go_here(_pending_tile)

## Right-click on bare ground: send the selected folk there.
func go_here(tile: Vector2i) -> bool:
	var f = _resolve(selected_folk_id)
	if f == null or tile.x < 0:
		return false
	var lvl := 0
	if lot_view != null and lot_view.get("level_view") != null and lot_view.level_view.active():
		lvl = lot_view.build_level()                      # right-click on the floor you are looking at
	return UIU.enqueue(f, "go_here", -1, {"tile": tile, "level": lvl})
