extends SceneTree
## Windowed screenshots of the social UI (not a test):
##   godot --path . --script res://tests/social_shot.gd -- <people.png> <pie.png> [mood.png]
## Boots main.tscn, builds up some relationship history between the starting folk, then captures the People tab and the
## social pie menu.
var _frames := 0
var _main: Node = null
var _out_people := "user://social_people.png"
var _out_pie := "user://social_pie.png"
var _out_mood := "user://social_mood.png"
var _a = null
var _b = null
var _c = null

func _process(_d: float) -> bool:
	if _main == null:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			_out_people = args[0]
		if args.size() > 1:
			_out_pie = args[1]
		if args.size() > 2:
			_out_mood = args[2]
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if _frames == 5 and _main.has_method("start_new_game"):
		_main.start_new_game(_main.default_household())
	if _frames == 40:
		_setup_story()
	if _frames == 70:
		var tabs: TabContainer = _main.hud.folk_panel.tabs
		for i in tabs.get_tab_count():
			if tabs.get_tab_title(i) == "People":
				tabs.current_tab = i
	if _frames == 100:
		_save(_out_people)
		_main.hud.pie.open_for(_a, "folk", _b.id, Vector2(120, 160))
	if _frames == 104:
		_main.hud.pie.set_category_open("Friendly", false)
		for cat in ["Romantic", "Mean"]:
			_main.hud.pie.set_category_open(cat, true)
	if _frames == 130:
		_save(_out_pie)
		_main.hud.pie.close()
		_main.hud.select_folk(_b.id)
	if _frames == 150:
		_save(_out_mood)
		quit(0)
	return false

func _save(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("saved ", path, " ", img.get_size())

func _setup_story() -> void:
	var folks: Array = root.get_node("World").all_folk()
	_a = folks[0]
	_b = folks[1]
	_c = folks[2] if folks.size() > 2 else folks[1]
	var A: int = _a.id
	var B: int = _b.id
	var C: int = _c.id
	RelationshipService.add_both(A, B, "friendship", 58.0)
	RelationshipService.add_both(A, B, "romance", 52.0)
	RelationshipService.add_both(A, B, "trust", 34.0)
	RelationshipService.start_dating(A, B, false)
	RelationshipService.reveal(A, B, "trait")
	RelationshipService.reveal(A, B, "career")
	RelationshipService.note_topic(A, B, "food")
	RelationshipService.add_history(A, B, "go_on_date", 0.8, A)
	RelationshipService.add_history(B, A, "kiss", 0.6, B)
	RelationshipService._tag_last_history(A, B, "great", "Magical kiss")
	RelationshipService.add_both(A, C, "friendship", 24.0)
	RelationshipService.add_value(A, C, "trust", -6.0)
	SocialDynamics.escalate(A, C, 38.0)
	RelationshipService.add_history(A, C, "insult", -0.9, C)
	_a.add_buff("laughing_fit")
	_a.add_buff("confident_glow")
	_a.add_buff("stage_glow")
	_b.add_buff("anxious_jitters")
	_b.add_buff("jealous_pang")
	Emotions.sync(_a)
	Emotions.sync(_b)
	_main.hud.select_folk(A)
