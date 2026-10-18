extends RefCounted
## UI tests with fake data. Convention: run() -> Array of failure strings.

class FakeStat:
	extends RefCounted
	var value := 0.0
	var min := -100.0
	var max := 100.0

class FakeFolk:
	extends RefCounted
	var id := 901
	var name := "Testy"
	var traits := ["neat", "glutton", "loner"]
	var needs := {}
	var skills := {}
	var buffs := []
	var queue := []
	var current = null
	var household_id := 1
	func get_mood() -> Dictionary:
		return {"mood": "happy", "intensity": 2}

class FakeIt:
	extends RefCounted
	var def_id := "sleep_bed"

func run() -> Array:
	var fails: Array = []
	var root: Window = Engine.get_main_loop().root
	var f := FakeFolk.new()
	for n in ["hunger", "energy", "bladder", "hygiene", "social", "fun"]:
		var s := FakeStat.new()
		s.value = 50.0
		f.needs[n] = s
	var sk := FakeStat.new()
	sk.min = 0.0
	sk.max = 10.0
	sk.value = 3.0
	f.skills["cooking"] = sk

	# --- HUD scene instantiation & node creation
	var ps: PackedScene = load("res://scenes/ui/hud.tscn")
	var hud: Hud = ps.instantiate()
	hud.folk_resolver = func(id): return f if id == f.id else null
	root.add_child(hud)
	if hud.folk_panel == null or hud.queue_bar == null or hud.pie == null or hud.build_panel == null or hud.toasts == null or hud.thoughts == null:
		fails.append("HUD missing sub-panels: %s" % [[hud.folk_panel, hud.queue_bar, hud.pie, hud.build_panel, hud.toasts, hud.thoughts]])
		hud.queue_free()
		return fails
	if hud.speed_buttons.size() != 4:
		fails.append("expected 4 speed buttons, got %d" % hud.speed_buttons.size())

	# --- folk panel + need bars
	hud.select_folk(f.id)
	var fp: FolkPanel = hud.folk_panel
	if fp.need_bars.size() != 6:
		fails.append("need bars: expected 6 got %d" % fp.need_bars.size())
	if fp.name_label.text != "Testy":
		fails.append("name label wrong: " + fp.name_label.text)
	if fp.trait_box.get_child_count() != 3:
		fails.append("trait chips: expected 3")
	f.needs["hunger"].value = -90.0
	Events.need_changed.emit(f.id, "hunger", -90.0)
	var bar: ProgressBar = fp.need_bars["hunger"]
	if absf(bar.value - 0.05) > 0.01:
		fails.append("hunger bar not updated on need_changed: %f" % bar.value)
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
	if fill.bg_color != UIU.level_color(0.05):
		fails.append("hunger bar color not red at low level")
	Events.need_changed.emit(999, "hunger", 100.0)   # other folk: ignored
	if absf(bar.value - 0.05) > 0.01:
		fails.append("bar changed for unrelated folk")

	# --- queue bar
	var it := FakeIt.new()
	f.queue.append(it)
	Events.queue_changed.emit(f.id)
	if hud.queue_bar.chips.size() != 1:
		fails.append("queue bar chips: expected 1 got %d" % hud.queue_bar.chips.size())
	hud.queue_bar.cancel(0)
	if f.queue.size() != 0 or hud.queue_bar.chips.size() != 0:
		fails.append("queue cancel failed")

	# --- pie menu entries from a fake object def
	var table := {
		"eat": {"label": "Eat", "category": "food"},
		"nap": {"label": "Nap", "category": "rest"},
		"secret": {"label": "Hidden", "hidden": true},
	}
	var entries := InteractionQuery.build_entries(f, ["eat", "nap", "secret", "missing"], table,
		func(id): return "" if id == "eat" else "Too awake")
	if entries.size() != 2:
		fails.append("pie entries: expected 2 got %d" % entries.size())
	else:
		if entries[0]["id"] != "eat" or not entries[0]["enabled"]:
			fails.append("pie entry eat should be enabled & first (Food < Rest)")
		if entries[1]["enabled"] or entries[1]["reason"] != "Too awake":
			fails.append("pie entry nap should be disabled with reason")
	hud.pie.open_with_entries(f, "object", 5, entries, Vector2(100, 100))
	if not hud.pie.visible or hud.pie.entry_buttons.size() != 2:
		fails.append("pie menu not populated")
	elif not hud.pie.entry_buttons[1].disabled or hud.pie.entry_buttons[1].tooltip_text != "Too awake":
		fails.append("disabled pie button lacks tooltip")

	# --- toasts, thoughts
	hud.toasts.push("Hello", "info")
	UIU.notify("Stacked", "warn")
	if hud.toasts.get_child_count() != 2:
		fails.append("toasts: expected 2 got %d" % hud.toasts.get_child_count())
	Events.thought.emit(f.id, "I'm hungry...")
	if hud.thoughts.balloons.size() != 1:
		fails.append("thought balloon not created")

	# --- coins
	Events.coins_changed.emit(1, 1234)
	if not hud.coins_label.text.begins_with("1234"):
		fails.append("coins label: " + hud.coins_label.text)

	# --- build panel catalog / undo
	hud.build_panel.build_catalog({"chair": {"label": "Chair", "price": 50, "tags": ["seating"]}, "bed": {"label": "Bed", "price": 400, "tags": ["bedroom"]}})
	if hud.build_panel.catalog_buttons.size() != 2:
		fails.append("catalog buttons wrong")
	if hud.build_panel.undo():
		fails.append("undo on empty stack should return false")

	# --- build mode toggles time controls
	hud.build_panel.set_active(true)
	if not hud.speed_buttons[1].disabled:
		fails.append("speed buttons not disabled in build mode")
	hud.build_panel.set_active(false)

	# --- new-game screen: Solo Start is the default; duplicate names fail household validation
	var sp := StartPicker.new()
	root.add_child(sp)
	if sp.selected_id != "solo":
		fails.append("new-game screen should pre-select Solo Start")
	var two := HouseholdSetup.make_household("couple")
	two["folk"][1]["name"] = two["folk"][0]["name"]
	if HouseholdSetup.validate(two) == "":
		fails.append("duplicate names should fail validation")
	sp.queue_free()
	var tm := TitleMenu.new()
	root.add_child(tm)
	var got: Array = []
	tm.new_game_requested.connect(func(): got.append(1))
	tm.main_box.get_child(2).pressed.emit()
	if got.size() != 1:
		fails.append("title menu New Game button should request the new-game screen")
	tm.queue_free()

	hud.queue_free()
	fails.append_array(_real_world_checks())
	return fails

## Pie entries against the real World/Data/Interaction (skipped if the starter house is unavailable).
func _real_world_checks() -> Array:
	var fails: Array = []
	if not World.has_method("load_starter_house") or UIU.cls("Folk") == null:
		return fails
	World.load_starter_house()
	var folk = UIU.cls("Folk").call("create", "PieTester", ["neat"])
	World.add_folk(folk, World.starter_spawn_tiles[0])
	var found := false
	for o in World.all_objects():
		var ents := InteractionQuery.entries_for(folk, "object", o.id)
		var defn: Dictionary = UIU.tbl("objects").get(o.def_id, {})
		if defn.get("interactions", []).size() > 0:
			found = true
			if ents.is_empty():
				fails.append("no pie entries for %s although def lists interactions" % o.def_id)
			for e in ents:
				if not e.has("enabled") or (not e["enabled"] and e["reason"] == ""):
					fails.append("disabled entry without reason: %s" % e["id"])
	if not found:
		fails.append("starter house has no interactable objects")
	World.remove_folk(folk.id)
	return fails
