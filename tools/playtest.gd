extends SceneTree
## A scripted playtest of the real game (not a test suite): a new solo character's first day and a half, played the way a player would, through the real
## HUD, pie menus and prompts. It prints every toast and prompt and saves a screenshot at each step to coord/shots/playtest/.
##   powershell -File tools/quiet_godot.ps1 --script res://tools/playtest.gd            (hidden: minimized, off-screen)
##   <godot> --path . --script res://tools/playtest.gd -- --watch                       (a normal window you can watch)
const OUT := "coord/shots/playtest/"

var _main: Node = null
var _frames := 0
var _step := 0
var _wait_until := 0                 # frame
var _wait_cond: Callable = Callable()
var _wait_cap := 0
var _hud = null
var _prompts := 0
var _prompt_seen := 0                # frame a prompt was first seen (answered a few frames later, after its screenshot)
const ANSWERS := ["Ask for the job", "Pay", "Help out", "Accept", "Yes", "Go", "I'll be there", "Lend"]

func _process(_d: float) -> bool:
	if _main == null:
		TestFixture.isolate_user_files()
		if not "--watch" in OS.get_cmdline_user_args():
			root.unfocusable = true
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		return false
	_frames += 1
	if "--film" in OS.get_cmdline_user_args() and _frames > 60 and _frames % 20 == 0:          # a frame every 20: what a player watching would see
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT + "film"))
		root.get_texture().get_image().save_png("res://%sfilm/f%05d.png" % [OUT, _frames])
	if _frames == 5:
		UIPrefs.set_flag("tips_seen", false)
		_main.title.visible = false
		_main.start_picker.open()
		_main.start_picker.select("solo")
		_main.start_picker._emit_chosen()
	if _frames < 60:
		return false
	if _frames == 60:
		_hud = _main.hud
		root.get_node("Events").connect("notification", func(text, kind): print("[%s] TOAST %-10s %s" % [_time(), kind, text]))
		JusticePlayer.ask_fn = func(pid, title, text, options, on_choice, default_id):
			print("[%s] PROMPT %s | %s | %s" % [_time(), title, text, str(options.map(func(o): return o["label"]))])
			_hud.case_prompt.ask(pid, title, text, options, on_choice, default_id)
	if _hud.case_prompt.visible and _step != 5:          # a question for the player: look at it, then answer like a decent person would
		if _prompt_seen == 0:
			_prompt_seen = _frames
		elif _frames - _prompt_seen == 3:
			_prompts += 1
			_shot("prompt_%02d" % _prompts)
			for a in ANSWERS:
				if _answer_prompt(a):
					break
			_prompt_seen = 0
		return false
	if _frames < _wait_until:
		return false
	if _wait_cond.is_valid():
		if not bool(_wait_cond.call()) and _frames < _wait_cap:
			return false
		if _frames >= _wait_cap:
			print("[%s] (gave up waiting)" % _time())
		_wait_cond = Callable()
	_run_step()
	return false

func _time() -> String:
	var c = root.get_node("Clock")
	return "d%d %02d:%02d" % [c.day(), c.hour(), int(c.total_minutes) % 60]

func pawn():
	return _hud._resolve(_hud.selected_folk_id)

func _wait(frames: int) -> void:
	_wait_until = _frames + frames

func _until(cond: Callable, cap_frames: int) -> void:
	_wait_cond = cond
	_wait_cap = _frames + cap_frames

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("res://" + OUT + name + ".png")
	var f = pawn()
	print("[%s] SHOT %s  (at %s, coins %d, hunger %.0f energy %.0f bladder %.0f hygiene %.0f, doing %s)" % [_time(), name, Neighborhood.lot_of(f), Economy.balance(f.household_id),
		f.get_stat_value("hunger"), f.get_stat_value("energy"), f.get_stat_value("bladder"), f.get_stat_value("hygiene"), str(f.current.def_id) if f.current != null else "-"])

func _close_all() -> void:
	for d in [_hud.money_hub, _hud.life_hub, _hud.phone_dialog, _hud.career_dialog, _hud.goals_dialog]:
		if d != null and d.visible:
			d.visible = false
	_hud.pie.close()

func _speed(s: int) -> void:
	root.get_node("Clock").set_speed(s)

## Open a pie menu the way a click does and press the first entry whose label starts with one of `labels`. Returns what was pressed.
func _press(kind: String, target_id: int, labels: Array, shot: String = "") -> String:
	var f = pawn()
	if kind == "self":
		_hud.pie.open_with_entries(f, "self", -1, load("res://scripts/ui/interaction_query.gd").self_entries(f), Vector2(700, 400))          # loaded at run time: autoload names only exist once the game runs
	else:
		_hud.pie.open_for(f, kind, target_id, Vector2(700, 400))
	var have: Array = _hud.pie.entry_buttons.map(func(b): return ("" if not b.disabled else "(off) ") + b.text)
	print("[%s] MENU %s %d: %s" % [_time(), kind, target_id, str(have)])
	if shot != "":
		for h in _hud.pie.category_headers.values():          # open the groups, the way a player browses
			h.pressed.emit()
		await process_frame
		await process_frame
		_shot(shot)
	for want in labels:
		for b in _hud.pie.entry_buttons:
			if not b.disabled and str(b.text).begins_with(str(want)):
				var t: String = b.text
				b.pressed.emit()
				print("[%s] PICK %s" % [_time(), t])
				return t
	_hud.pie.close()
	print("[%s] PICK none of %s" % [_time(), str(labels)])
	return ""

func _answer_prompt(prefix: String) -> bool:
	var cp = _hud.case_prompt
	if not cp.visible:
		return false
	for b in cp.body.find_children("*", "Button", true, false):
		if str(b.text).begins_with(prefix):
			print("[%s] ANSWER %s" % [_time(), b.text])
			b.pressed.emit()
			return true
	return false

func _nearest(def_id: String):
	var f = pawn()
	var best = null
	var bd := 1e9
	for o in root.get_node("World").all_objects():
		if str(o.def_id) == def_id and NeighborhoodLots.lot_at(o.tile) == Neighborhood.lot_of(f):
			var d: float = Vector2(o.tile).distance_to(Vector2(f.tile))
			if d < bd:
				bd = d
				best = o
	return best

func _travel(lot: String) -> void:
	var f = pawn()
	print("[%s] ORDER travel to %s: %s" % [_time(), lot, str(Commands.run({"player_id": 1, "folk_id": f.id, "action": "travel", "args": {"folk_ids": [f.id], "lot_id": lot}}))])

## --tour: the same town from several places, at several times of day and zoom levels (the owner: "shots from several places and several times... zoom
## out and in"), with the clock running so people walk and talk. Shots: coord/shots/playtest/tour/<place>_<hour>_<zoom>.png
const TOUR_PLACES := ["home", "cafe", "market", "park", "bank", "police", "courthouse", "hospital", "city_hall", "works", "office", "gym"]
const TOUR_HOURS := [10, 18, 22]
const TOUR_ZOOMS := {"close": 9.0, "mid": 22.0, "far": 48.0}
var _tour: Array = []

func _tour_step() -> void:
	var talk: bool = "--talk" in OS.get_cmdline_user_args()          # --talk: busy places at midday, four shots a second apart (who says what, in order)
	if _tour.is_empty():
		for l in (["cafe", "park", "market", "gym"] if talk else TOUR_PLACES):
			if not Neighborhood.lot(l).is_empty():
				for h in ([12] if talk else TOUR_HOURS):
					for z in (["close", "mid"] if talk else TOUR_ZOOMS.keys()):
						for k in (4 if talk else 1):
							_tour.append([l, h, z, k])
		_tour.push_front(null)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT + "tour"))
		_speed(1)
	var prev = _tour.pop_front()
	var tl = _hud.thoughts
	if tl != null:
		print("[%s] BALLOONS %d visible %d" % [_time(), tl.balloons.size(), tl.balloons.filter(func(b): return is_instance_valid(b["node"]) and b["node"].visible).size()])
	if prev != null:
		_shot("tour/%s_%02d_%s%s" % [prev[0], int(prev[1]), prev[2], ("_%d" % int(prev[3])) if talk else ""])
	if _tour.is_empty():
		print("[%s] TOUR END" % _time())
		quit(0)
		return
	var nxt: Array = _tour[0]
	if talk and prev != null and int(nxt[3]) > 0 and str(prev[0]) == str(nxt[0]) and str(prev[2]) == str(nxt[2]):
		if int(nxt[3]) == 1:          # a line and its reply between two people on screen: does it read who said what, in order?
			var here: Array = WorldIface.all_folk().map(func(f): return int(f.id))
			var lv2 = _main.find_child("LotView", true, false)
			here = here.filter(func(i): var sp = lv2.screen_pos("folk", int(i)); return sp is Vector2 and Rect2(Vector2(300, 150), Vector2(1300, 750)).has_point(sp))
			print("[%s] SPEECH TEST at %s: %d on screen" % [_time(), nxt[0], here.size()])
			if here.size() >= 2:
				SimEnv.emit("speech", int(here[0]), "Have you tried the new place on Elm Court?", int(here[1]))
				SimEnv.emit("speech", int(here[1]), "Not yet. Is it any good?", int(here[0]))
		_wait(50)          # the same spot again a moment later
		return
	var c = root.get_node("Clock")
	var want: int = (c.day() - 1) * 1440 + int(nxt[1]) * 60
	if int(c.total_minutes) % 1440 != int(nxt[1]) * 60:
		c.total_minutes = want + (1440 if want < int(c.total_minutes) else 0)
	var lv = _main.find_child("LotView", true, false)
	var rc: Rect2i = NeighborhoodLots.rect_of(str(nxt[0]))
	lv.select("none", -1)
	lv.focus_tile(rc.position + Vector2i(rc.size.x / 2, rc.size.y - 4))
	lv.set_zoom(float(TOUR_ZOOMS[nxt[2]]))
	_wait(120)          # two seconds of life: people walk, talk, toasts come and go

func _run_step() -> void:
	if "--tour" in OS.get_cmdline_user_args():
		_tour_step()
		return
	_step += 1
	match _step:
		1:
			_shot("01_start")
			_speed(1)
			_wait(30)
		2:          # read the tips, then look for work on the phone
			_hud.phone_dialog.show_for(_hud.selected_folk_id)
			_wait(20)
		3:
			_shot("02_phone")
			load("res://scripts/ui/life_hub_phone.gd").set("app", "jobs")
			_hud.phone_dialog.show_for(_hud.selected_folk_id)
			_wait(20)
		4:
			_shot("03_jobs_app")
			_close_all()
			_travel("cafe")          # walk to the cafe: food, and maybe a job
			_speed(2)
			_until(func(): return Neighborhood.lot_of(pawn()) == "cafe" and pawn().current == null, 1500)
		5:
			_speed(1)
			_shot("04_at_cafe")
			var staff: Array = Crowd.staff_folk("cafe")
			if staff.is_empty():
				print("no staff at the cafe")
				_wait(5)
			else:
				_press("folk", int(staff[0].id), ["Ask if they're hiring"], "04b_staff_menu")
				_until(func(): return _hud.case_prompt.visible, 600)
		6:
			_shot("05_hiring_prompt")
			if not _answer_prompt("Ask for the job"):
				_answer_prompt("Not now")
			_wait(60)
		7:
			_shot("06_after_asking")
			var counter = _nearest("cafe_counter")
			if counter == null:
				counter = _nearest("bar_counter")
			if counter != null:
				_press("object", int(counter.id), ["Order a Meal", "Order Meal", "Order", "Buy"])
			_speed(2)
			_until(func(): return pawn().get_stat_value("hunger") > 60.0 or false, 900)
		8:
			_speed(1)
			_shot("07_ate")
			_hud.career_dialog.show_for(_hud.selected_folk_id)
			_wait(20)
		9:
			_shot("08_work_panel")
			_close_all()
			_travel("park")
			_speed(2)
			_until(func(): return Neighborhood.lot_of(pawn()) == "park" and pawn().current == null, 1500)
		10:
			_speed(1)
			var others: Array = Neighborhood.folk_at("park").filter(func(o): return int(o) != int(pawn().id))
			if not others.is_empty():
				_press("folk", int(others[0]), ["Introduce", "Chat", "Say Hello", "Small Talk", "Talk"])
			_wait(90)
		11:
			_shot("09_park_chat")
			_travel(Neighborhood.HOME)
			_speed(3)
			_until(func(): return Neighborhood.lot_of(pawn()) == Neighborhood.HOME and pawn().current == null, 2000)
		12:
			_shot("10_home_evening")
			_until(func(): return root.get_node("Clock").hour() >= 21 or root.get_node("Clock").hour() < 5, 4000)
		13:
			_speed(1)
			_press("self", -1, ["Sleep on the Floor", "Sleep", "Nap"])
			var bed = _nearest("sofa_bed")
			if bed == null:
				bed = _nearest("bed")
			if bed != null:
				_press("object", int(bed.id), ["Sleep"])
			_speed(3)
			_until(func(): return root.get_node("Clock").hour() >= 8 and root.get_node("Clock").hour() < 12, 6000)
		14:
			_speed(1)
			_shot("11_next_morning")
			_answer_prompt("Help out")
			_hud.phone_dialog.show_for(_hud.selected_folk_id)
			_wait(20)
		15:
			_shot("12_phone_morning")
			_close_all()
			_speed(3)
			_until(func(): return root.get_node("Clock").hour() >= 18, 6000)
		16:
			_speed(1)
			_shot("13_after_work")
			_wait(10)
		_:
			print("[%s] PLAYTEST END" % _time())
			quit(0)
