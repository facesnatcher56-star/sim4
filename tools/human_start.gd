extends SceneTree
## The start a human makes, by pressing the real buttons (not a test suite): title > New Game > Solo Start > Normal > Customise...
## (the Points page: a background, a few points) > Use this character > Start, then the first in-game hour: the first toasts, the phone,
## a walk. Prints every toast, prompt and step; a screenshot per step in coord/shots/human_start/. Any SCRIPT ERROR or "STUCK" line is the failure.
##   powershell -File tools/quiet_godot.ps1 --script res://tools/human_start.gd
const OUT := "coord/shots/human_start/"

var _main: Node = null
var _frames := 0
var _step := 0
var _wait_until := 0
var _hud = null

func _process(_d: float) -> bool:
	if _main == null:
		TestFixture.isolate_user_files()
		root.unfocusable = true
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
		UIPrefs.set_flag("tips_seen", false)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		root.get_node("Events").connect("notification", func(text, kind): print("[%s] TOAST %-8s %s" % [_time(), kind, text]))
		return false
	_frames += 1
	if _frames < _wait_until:
		return false
	_step += 1
	match _step:
		1:
			_wait(30)
		2:
			_shot("01_title")
			_press(_main.title, "New Game")
			_wait(20)
		3:
			_shot("02_new_game")
			var sp = _main.start_picker
			sp.select("solo")
			sp.set_difficulty("normal")
			_wait(10)
		4:
			_shot("03_solo_normal")
			_press(_main.start_picker, "Customise")          # the creator ("Customise..." on the picker)
			_wait(20)
		5:
			var cr = _main.start_picker.creator
			print("STEP creator visible=%s" % str(cr.visible))
			if not cr.visible:
				print("STUCK the creator did not open")
			var pts = cr.editor.points
			if pts != null and pts._bg_opt != null and pts._bg_opt.item_count > 1:
				pts._bg_opt.select(1)
				pts._bg_opt.item_selected.emit(1)
			var plus: Array = _buttons(cr, "+")
			for i in mini(plus.size(), 4):
				(plus[i] as Button).pressed.emit()
			print("STEP points: background=%s, pressed %d of %d '+' buttons, total label=%s" % [pts._bg_opt.get_item_text(pts._bg_opt.selected) if pts != null else "-", mini(plus.size(), 4), plus.size(), pts._total.text if pts != null else "-"])
			_wait(10)
		6:
			_shot("04_points_page")
			var cr2 = _main.start_picker.creator
			cr2.go_btn.pressed.emit()
			print("STEP creator done, error=%s" % str(cr2.error_label.text if cr2.error_label != null else ""))
			_wait(10)
		7:
			_shot("05_back_on_picker")
			print("STEP summary: %s" % _main.start_picker.summary.text)
			_main.start_picker.start_btn.pressed.emit()
			_wait(120)
		8:
			_hud = _main.get("hud")
			if _hud == null or pawn() == null:
				print("STUCK no game after Start")
				quit(1)
				return true
			_shot("06_first_frame")
			_wait(240)          # the first toasts (the landlord's note, the tips)
		9:
			_shot("07_first_seconds")
			_hud.phone_dialog.show_for(_hud.selected_folk_id)
			_wait(20)
		10:
			_shot("08_phone")
			_hud.phone_dialog.visible = false
			var f = pawn()
			var dest: Vector2i = NeighborhoodLots.entry_tile("park")
			print("STEP walk ordered: %s" % str(_hud.go_here(dest)))
			root.get_node("Clock").set_speed(2)
			_wait(400)
		11:
			_shot("09_walking")
			var f2 = pawn()
			print("STEP after walk: at %s doing %s" % [Neighborhood.lot_of(f2), str(f2.current.def_id) if f2.current != null else "-"])
			_wait(400)
		12:
			_shot("10_first_hour")
			print("STEP time %s, done" % _time())
			quit()
			return true
	return false

func pawn():
	return SysUtil.folk(Pawn.of()) if Pawn.of() >= 0 else null

func _time() -> String:
	var c = root.get_node_or_null("Clock")
	return "d%d %02d:%02d" % [c.day(), c.hour(), c.minute()] if c != null and c.has_method("minute") else "-"

func _wait(n: int) -> void:
	_wait_until = _frames + n

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("res://" + OUT + name + ".png")
	print("[%s] SHOT %s" % [_time(), name])

## Every visible button under `node` whose text starts with `text`.
func _buttons(node: Node, text: String) -> Array:
	var out: Array = []
	for c in node.find_children("*", "Button", true, false):
		if (c as Button).is_visible_in_tree() and (c as Button).text.begins_with(text):
			out.append(c)
	return out

func _press(node: Node, text: String) -> void:
	var bs: Array = _buttons(node, text)
	if bs.is_empty():
		print("STUCK no '%s' button" % text)
		return
	print("STEP press '%s'" % (bs[0] as Button).text)
	(bs[0] as Button).pressed.emit()
