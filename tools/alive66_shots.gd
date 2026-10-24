extends SceneTree
## Task 66 shots (not a test suite): the real game, a solo start, out in town; scenes from the town's own life play near the player:
## a scene at the park, an arrest (a real open case, its top suspect picked up by an officer who walks in), a scene at the cafe.
## Shots in coord/shots/66/.   powershell -File tools/quiet_godot.ps1 --script res://tools/alive66_shots.gd
const OUT := "coord/shots/66/"
const STOPS := [["park", "scene", "01_scene_park"], ["park", "arrest", "02_arrest"], ["cafe", "scene", "03_scene_cafe"]]

var _main: Node = null
var _hud = null
var _frames := 0
var _wait_until := 0
var _i := 0
var _phase := "go"

func _process(_d: float) -> bool:
	if _main == null:
		TestFixture.isolate_user_files()
		root.unfocusable = true
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
		UIPrefs.set_flag("tips_seen", true)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		root.get_node("Events").connect("notification", func(text, kind): print("TOAST %-8s %s" % [kind, text]))
		return false
	_frames += 1
	if _frames == 5:
		_main.title.visible = false
		_main.start_picker.open()
		_main.start_picker.select("solo")
		_main.start_picker._emit_chosen()
	if _frames < 90 or _frames < _wait_until:
		return false
	_hud = _main.hud
	if _i >= STOPS.size() or _frames > 30000:
		quit()
		return true
	var stop: Array = STOPS[_i]
	var f = _hud._resolve(_hud.selected_folk_id)
	match _phase:
		"go":
			if Neighborhood.lot_of(f) != str(stop[0]):
				Commands.run({"player_id": 1, "folk_id": f.id, "action": "travel", "args": {"folk_ids": [f.id], "lot_id": str(stop[0])}})
				root.get_node("Clock").set_speed(2)
			_phase = "arrive"
			_wait_until = _frames + 30
		"arrive":
			if Neighborhood.lot_of(f) != str(stop[0]):
				_wait_until = _frames + 30
				return false
			root.get_node("Clock").set_speed(1)
			_hud.lot_view.focus_on("folk", int(f.id))
			var ok: bool = false
			if str(stop[1]) == "arrest":
				ok = _arrest(f, str(stop[0]))
			else:
				ok = StreetScenes.play(f, str(stop[0]))
			print("SCENE %s at %s: %s" % [stop[1], stop[0], str(ok)])
			_phase = "wait" if ok else "next"
			_wait_until = _frames + 30
		"wait":
			if not (_hud.case_prompt.visible and str(_hud.case_prompt._current.get("title", "")) == StreetScenes.TITLE):
				_wait_until = _frames + 20
				return false
			_hud.lot_view.focus_on("folk", int(f.id))
			_wait_until = _frames + 10
			_phase = "shot"
		"shot":
			root.get_texture().get_image().save_png("res://" + OUT + str(stop[2]) + ".png")
			print("SHOT %s: %s" % [stop[2], str(_hud.case_prompt._current.get("text", ""))])
			_hud.case_prompt._pick("watch" if str(stop[1]) == "arrest" else "walk")
			_phase = "next"
			_wait_until = _frames + 60
		"next":
			_i += 1
			_phase = "go"
	return false

## A real open case at this place, its top suspect a free townie on the lot: the police come for them.
func _arrest(f, lot: String) -> bool:
	var sus: int = -1
	for p in Crowd.crowd_folk(lot):
		sus = int(p.get_meta("townie_id", -1))
		if sus >= 0:
			break
	if sus < 0:
		for t in Story.free_townies():
			if Story.stage_of(t) == "adult" and SysUtil.folk(int(t["id"])) == null:
				sus = int(t["id"])
				break
	var c: Dictionary = CaseStore.create("burglary", sus, -1, "venue:" + lot, {"witnessed": true, "trace": 0.5})
	c["state"] = "open"
	c["disc_day"] = SysUtil.day() - 2
	c["suspect_ids"] = [sus]
	c["progress"] = 0.7
	var s: Dictionary = StreetScenes.cause("arrest", f, lot)
	if s.is_empty():
		return false
	StreetScenes.stage(f, lot, s)
	return true
