extends Node
## Boot: title -> new-game screen (StartPicker: scenario + difficulty + household) -> home lot -> Folk -> gameplay.
## Pass `-- --autostart` to skip the menus (3 roommates in the classic house, no scenario).
const LOT_VIEW_PATH := "res://scenes/world/lot_view.tscn"

var lot_view: Node = null
var hud: Hud
var title: TitleMenu
var start_picker: StartPicker
var household_name := "Fernwood"
var playing := false

var systems: SystemsManager

func _ready() -> void:
	Careers.confirm_offers = true      # the player answers job offers (Accept / Decline) instead of 'Look for Jobs' hiring instantly
	GameSettings.load_settings()      # before anything shows: window, quality, audio, keys
	SettingsApply.apply_all()
	GameSettings.bus.changed.connect(_on_setting_changed)
	Clock.day_passed.connect(_autosave_check)
	systems = SystemsManager.install(self)
	systems.autosave_enabled = false      # Main autosaves itself so the interval setting applies
	if ResourceLoader.exists(LOT_VIEW_PATH):
		var ps: PackedScene = load(LOT_VIEW_PATH)
		lot_view = ps.instantiate() if ps != null else null
		if lot_view != null:
			add_child(lot_view)
			move_child(lot_view, 0)
	hud = $UILayer/Hud
	hud.set_lot_view(lot_view)
	hud.visible = false
	hud.load_requested.connect(load_game)
	hud.quit_to_title.connect(show_title)
	title = TitleMenu.new()
	title.theme = UITheme.build()
	$TitleLayer.add_child(title)
	title.new_game_requested.connect(_on_title_new_game)
	start_picker = StartPicker.new()
	start_picker.theme = UITheme.build()
	start_picker.visible = false
	$TitleLayer.add_child(start_picker)
	start_picker.chosen.connect(_on_start_chosen)
	start_picker.cancelled.connect(func():
		start_picker.visible = false
		title.visible = true)
	title.continue_game.connect(load_game)
	title.quit_game.connect(func(): get_tree().quit())
	if "--autostart" in OS.get_cmdline_user_args():
		start_new_game(default_household())
	else:
		show_title()

func default_household() -> Dictionary:
	var names := ["Mira", "Tobin", "Wren"]
	var colors := [Color("#e07a5f"), Color("#3d85c6"), Color("#81b29a")]
	var trait_ids: Array = UIU.tbl("traits").keys()
	trait_ids.sort()
	var folk: Array = []
	for i in 3:
		var ts: Array = []
		for k in 3:
			if trait_ids.size() > 0:
				var t = trait_ids[(i * 3 + k) % trait_ids.size()]
				if not (t in ts):
					ts.append(t)
		folk.append({"name": names[i], "traits": ts, "color": colors[i]})
	return {"name": "Fernwood", "folk": folk}

## Title -> New Game screen (Solo Start pre-selected) -> game.
func _on_title_new_game() -> void:
	title.visible = false
	start_picker.open()
	start_picker.visible = true

func _on_start_chosen(cfg: Dictionary) -> void:
	start_picker.visible = false
	start_new_game(cfg["household"], str(cfg["start_id"]), cfg)

func show_title() -> void:
	playing = false
	if start_picker != null:
		start_picker.visible = false
	while hud.close_top_dialog():
		pass      # close dialogs first, otherwise closing one would restore the old game speed
	hud.visible = false
	hud.tips.visible = false
	UIU.set_speed(0)
	title.refresh()
	title.visible = true

func _clear_world() -> void:
	for f in World.all_folk().duplicate():
		World.remove_folk(f.id)
	if World.has_method("reset"):
		World.call("reset")

## `opts` (from the StartPicker): {scenario, difficulty, funds}. Without it: no scenario, Normal, the start's own funds.
func start_new_game(h: Dictionary, start_id: String = "classic", opts: Dictionary = {}) -> void:
	household_name = h.get("name", "Household")
	hud.household_name = household_name
	var folk: Array = NewGame.start(systems, h, start_id, opts)
	UIU.folk_colors.clear()
	for i in folk.size():
		UIU.folk_colors[folk[i].id] = h["folk"][i]["color"]
	UIU.set_speed(1)
	_enter_game()
	var scen: Dictionary = Scenario.def(str(opts.get("scenario", "")))
	hud.toasts.clear()      # setup chatter (e.g. the spouses' 'now married') is not news
	if not scen.is_empty():
		if folk.size() == 1 and lot_view != null:
			lot_view.focus_tile(folk[0].tile)
		UIU.notify(str(scen.get("moved_in", "Welcome home!")) % str(folk[0].name), "good")

func load_game(slot: int) -> void:
	_clear_world()
	if not SaveSlots.load_slot(slot):
		UIU.notify("Could not load slot %d" % slot, "bad")
		return
	UIU.set_speed(1)
	_enter_game()

func _enter_game() -> void:
	playing = true
	title.visible = false
	Economy.auto_pay = GameSettings.get_bool("auto_pay")      # the player's preference wins over what a save stored
	hud.visible = true
	hud.rebuild_folk_row()
	if lot_view != null:
		lot_view.frame_home()
	var all = World.all_folk()
	if all.size() > 0:
		hud.select_folk(all[0].id)
	hud.tracker.reset_for_game()
	hud.tips.start(false, Scenario.def(Scenario.active_id).get("tips", []))
	if World.has_method("get_coins"):
		Events.coins_changed.emit(1, int(World.call("get_coins")))

# ------------------------------------------------------------ settings
func _on_setting_changed(key: String, _v) -> void:
	if key == "high_contrast":
		for c in [hud, title, start_picker]:
			if c != null:
				c.theme = UITheme.build()

## Autosave on the player's interval, only while a game is running.
func _autosave_check(day: int) -> void:
	if playing and GameSettings.get_bool("autosave") and day % GameSettings.get_int("autosave_days") == 0:
		SaveLoad.autosave()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameSettings.flush()
