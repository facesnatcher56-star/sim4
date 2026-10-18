extends Node
## Boot: title/new-game menu -> starter house -> 3 Folk -> gameplay. Pass `-- --autostart` to skip the menu.
const LOT_VIEW_PATH := "res://scenes/world/lot_view.tscn"
const SPAWN_FALLBACK := [Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)]

var lot_view: Node = null
var hud: Hud
var title: TitleMenu
var picker: LotPicker
var pending_household: Dictionary = {}
var household_name := "Fernwood"
var playing := false

var systems: SystemsManager

func _ready() -> void:
	systems = SystemsManager.install(self)
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
	title.new_game.connect(_on_title_new_game)
	picker = LotPicker.new()
	picker.theme = UITheme.build()
	picker.visible = false
	$TitleLayer.add_child(picker)
	picker.picked.connect(_on_lot_picked)
	picker.cancelled.connect(func():
		picker.visible = false
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

## Title menu -> household created -> choose the home lot.
func _on_title_new_game(h: Dictionary) -> void:
	pending_household = h
	title.visible = false
	picker.visible = true

func _on_lot_picked(start_id: String) -> void:
	picker.visible = false
	start_new_game(pending_household, start_id)

func show_title() -> void:
	playing = false
	if picker != null:
		picker.visible = false
	UIU.set_speed(0)
	hud.visible = false
	title.refresh()
	title.visible = true

func _clear_world() -> void:
	for f in World.all_folk().duplicate():
		World.remove_folk(f.id)
	if World.has_method("reset"):
		World.call("reset")

func start_new_game(h: Dictionary, start_id: String = "classic") -> void:
	household_name = h.get("name", "Household")
	hud.household_name = household_name
	_clear_world()
	World.current_household_id = 1
	var start_def: Dictionary = Neighborhood.start_def(start_id)
	Neighborhood.start_game(str(start_def.get("template", LotLoader.CLASSIC)))
	var spawns: Array = World.starter_spawn_tiles if World.get("starter_spawn_tiles") != null else []
	if spawns.size() < 3:
		spawns = SPAWN_FALLBACK
	var fc = UIU.cls("Folk")
	var i := 0
	UIU.folk_colors.clear()
	for fd in h["folk"]:
		var f = fc.call("create", fd["name"], fd["traits"])
		f.household_id = 1
		UIU.folk_colors[f.id] = fd["color"]
		World.add_folk(f, spawns[i % spawns.size()])
		i += 1
	if Clock.has_method("reset"):
		Clock.call("reset")
	systems.new_game([1])
	Neighborhood.finish_new_game(start_id)
	UIU.set_speed(1)
	_enter_game()

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
	hud.visible = true
	hud.rebuild_folk_row()
	if lot_view != null:
		lot_view.set_zoom(18.0)
		lot_view.focus_tile(Vector2i(World.width / 2, World.height / 2 - 2))
	var all = World.all_folk()
	if all.size() > 0:
		hud.select_folk(all[0].id)
	if World.has_method("get_coins"):
		Events.coins_changed.emit(1, int(World.call("get_coins")))
