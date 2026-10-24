extends SceneTree
## Task 65 shots (not a test suite): the real game, a solo start, then each fix set up and photographed: the empty driveway with filler traffic
## passing, a visitor knocking at the front door, the door opened, a guest asking to use the bathroom, a street scene at the park.
## Prints what it checks; shots in coord/shots/real65/.   powershell -File tools/quiet_godot.ps1 --script res://tools/real65_shots.gd
const OUT := "coord/shots/real65/"

var _main: Node = null
var _hud = null
var _frames := 0
var _step := 0
var _wait_until := 0
var _guest_id := -1

func _process(_d: float) -> bool:
	if _main == null:
		TestFixture.isolate_user_files()
		root.unfocusable = true
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + OUT))
		UIPrefs.set_flag("tips_seen", true)
		_main = load("res://scenes/main.tscn").instantiate()
		root.add_child(_main)
		root.get_node("Events").connect("notification", func(text, kind): print("[%s] TOAST %-8s %s" % [_time(), kind, text]))
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
	_step += 1
	match _step:
		1:
			_speed(3)
			_wait(600)          # let the town's traffic run for a while
		2:
			_speed(1)
			_hud.lot_view.focus_tile(Neighborhood.entry_tile(Neighborhood.HOME))
			_wait(60)
		3:
			_shot("01_driveway")
			print("CHECK filler cars parked at a home lot: %d (want 0); tracker visible: %s (want false)" % [_filler_at_homes(), str(_hud.tracker.visible)])
			var f = pawn()
			var tid: int = -1
			for t in Story.free_townies():
				if Story.stage_of(t) == "adult" and SysUtil.folk(int(t["id"])) == null:
					tid = int(t["id"])
					break
			RelationshipService.add_both(int(f.id), tid, "friendship", 20.0)
			_guest_id = tid
			StoryVisits.schedule_visit([tid], int(f.id), SysUtil.now() + 1, 120)
			print("STEP visit scheduled from %s" % Story.name_of(tid))
			_wait(30)
		4:
			if not _hud.case_prompt.visible and _frames < 3000:
				_wait(20)
				_step -= 1
				return false
			_hud.lot_view.focus_tile(DoorActs.doorstep(Neighborhood.HOME))
			_shot("02_visitor_knocks")
			var g = SysUtil.folk(_guest_id)
			print("CHECK guest at the doorstep: %s (tile %s, step %s), inside the house: %s" % [str(g != null), str(g.tile) if g != null else "-", str(DoorActs.doorstep(Neighborhood.HOME)), str(g != null and not WorldIface.world().is_outdoor(g.tile))])
			_hud.case_prompt._pick("answer")
			_wait(20)
		5:
			_shot("03_door_opened")
			_hud.case_prompt._pick("in")
			_wait(240)
		6:
			_shot("04_guest_inside")
			var g2 = SysUtil.folk(_guest_id)
			var toilet = null
			for o in WorldIface.world().objects_of_def("toilet"):
				if NeighborhoodLots.lot_at(o.tile) == Neighborhood.HOME:
					toilet = o
			if g2 != null and toilet != null:
				(g2.needs["bladder"] as Stat).set_value(-40.0)
				g2.cancel_current("test")
				g2.clear_queue()
				var ir := Interaction.create("use_toilet", g2, int(toilet.id), false)
				if ir != null:
					g2.enqueue(ir)
			print("STEP guest heads for the bathroom (toilet %s)" % str(toilet != null))
			_wait(30)
		7:
			if _hud.case_prompt.visible and str(_hud.case_prompt._current.get("title", "")) == "At your door":
				print("STEP another visitor knocks (%s): ignored for this shot" % str(_hud.case_prompt._current.get("text", "")))
				_hud.case_prompt._pick("ignore")
			var gx = SysUtil.folk(_guest_id)
			if _frames % 200 < 20:
				print("DIAG guest %s current=%s state=%s sit=%s" % [str(gx != null), str(gx.current.def_id) if gx != null and gx.current != null else "-", str(gx.current.state) if gx != null and gx.current != null else "-", str(Story.situations.map(func(s): return s["state"]))])
			if (not _hud.case_prompt.visible or str(_hud.case_prompt._current.get("title", "")) != "Your guest") and _frames < 6000:
				_wait(20)
				_step -= 1
				return false
			_shot("05_guest_asks_bathroom")
			_hud.case_prompt._pick("yes")
			_wait(20)
		8:
			var f2 = pawn()
			print("STEP to the park: %s" % str(Commands.run({"player_id": 1, "folk_id": f2.id, "action": "travel", "args": {"folk_ids": [f2.id], "lot_id": "park"}})))
			_speed(2)
			_wait(30)
		9:
			if Neighborhood.lot_of(pawn()) != "park" and _frames < 12000:
				_wait(30)
				_step -= 1
				return false
			_speed(1)
			_hud.lot_view.focus_on("folk", int(pawn().id))
			var played: bool = StreetScenes._play(pawn(), "park")
			print("CHECK street scene played at the park: %s; threads %s" % [str(played), str(TownDrama.threads.map(func(t): return "%s:%s/%s" % [t["kind"], str(StreetScenes._free(int(t["a"]))), str(StreetScenes._free(int(t["b"])))]))])
			if not played and _frames < 14000:
				_wait(300)
				_step -= 1
				return false
			_wait(30)          # they walk over from the gate; the line comes when they are in view
		10:
			if not (_hud.case_prompt.visible and str(_hud.case_prompt._current.get("title", "")) == "Out here") and _frames < 16000:
				_wait(20)
				_step -= 1
				return false
			_hud.lot_view.focus_on("folk", int(pawn().id))
			_shot("06_street_scene")
			if _hud.case_prompt.visible:
				_hud.case_prompt._pick("watch")
			_wait(60)
		11:
			_shot("07_after_scene")
			var s2: Dictionary = StreetScenes._cause("arrest", pawn(), "park")
			print("CHECK arrest cause at the park: %s (open cases %d)" % [str(s2), CaseStore.open_cases().size()])
			if not s2.is_empty():
				StreetScenes._stage(pawn(), "park", s2)
			_wait(30)
		12:
			if not StreetScenes.pending.is_empty() or (not _hud.case_prompt.visible and _frames < 20000 and not StreetScenes._used.keys().any(func(k): return str(k).begins_with("arrest"))):
				if _frames < 20000:
					_wait(20)
					_step -= 1
					return false
			if _hud.case_prompt.visible:
				_shot("08_arrest")
				_hud.case_prompt._pick("watch")
			_wait(30)
		13:
			quit()
			return true
	return false

func pawn():
	return _hud._resolve(_hud.selected_folk_id)

func _filler_at_homes() -> int:
	var vv = _main.find_child("VehicleView", true, false)
	var n: int = 0
	if vv != null and vv.sim != null:
		for v in vv.sim.vehicles:
			if str(v["tag"]) == "ambient" and Venues.type_of_lot(str(v.get("lot", v.get("dest_lot", "park")))) in ["home", "townie_home", "shelter"]:
				n += 1
	return n

func _speed(s: int) -> void:
	root.get_node("Clock").set_speed(s)

func _time() -> String:
	var c = root.get_node_or_null("Clock")
	return "d%d %02d:%02d" % [c.day(), c.hour(), c.minute()] if c != null else "-"

func _wait(n: int) -> void:
	_wait_until = _frames + n

func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("res://" + OUT + name + ".png")
	print("[%s] SHOT %s" % [_time(), name])
