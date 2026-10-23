extends Node
## The sweep itself (tools/sweep.gd starts it): see there for how to run it and what the log tags mean.
var _main: Node = null
var _hud = null
var _out := "user://sweep/"
var _phases: Array = []
var _cur := ""                       # the action being tried (for toasts / lines it causes)
var _started := {}
var _finished := {}
var _n := 0

var _IQ = InteractionQuery
var root: Window
var _skip := 0                       # skip=<n>: start the object phase at the n-th kind (to resume after a hang)
var _beat := 0
var _only: Array = []                # only=<def>,<def>: just these kinds of object

func _process(_d: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _beat > 5000:          # heartbeat: the outside watcher kills the run when these stop (a frozen frame)
		_beat = now
		print("[%s] BEAT  fps %d | %s" % [_t(), Engine.get_frames_per_second(), _cur])

func _ready() -> void:
	root = get_tree().root
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a in ["ui", "self", "objects", "social"]:
			_phases.append(a)
		elif a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a.begins_with("skip="):
			_skip = int(a.substr(5))
		elif not a.begins_with("--") and not a.begins_with("run="):
			_out = a.trim_suffix("/") + "/"
	if _phases.is_empty():
		_phases = ["ui", "self", "objects", "social"]
	DirAccess.make_dir_recursive_absolute(_out)
	TestFixture.isolate_user_files()
	root.unfocusable = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child.call_deferred(_main)
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _until(cond: Callable, cap: int) -> bool:
	for i in cap:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return false

func _t() -> String:
	var c = root.get_node("Clock")
	return "d%d %02d:%02d" % [c.day(), c.hour(), int(c.total_minutes) % 60]

func _log(tag: String, text: String) -> void:
	print("[%s] %-5s %s" % [_t(), tag, text])

func _shot(name: String) -> void:
	_n += 1
	var file := "%s%03d_%s.png" % [_out, _n, name.validate_filename()]
	root.get_texture().get_image().save_png(file)
	_log("SHOT", file.get_file())

func pawn():
	return _hud._resolve(_hud.selected_folk_id)

func _run() -> void:
	await _wait(5)
	_shot("title")
	UIPrefs.set_flag("tips_seen", false)
	_main.title.visible = false
	_main.start_picker.open()
	_main.start_picker.visible = true
	await _wait(5)
	_shot("start_picker")
	_main.start_picker.select("solo")
	_main.start_picker._open_creator(false)
	await _wait(10)
	_shot("creator")
	_main.start_picker._emit_chosen()
	await _wait(60)
	_hud = _main.hud
	var ev = root.get_node("Events")
	ev.connect("notification", func(text, kind): _log("TOAST", "%s | %s | during %s" % [kind, text, _cur]))
	ev.speech.connect(func(fid, text, to): if fid == _pid() or to == _pid(): _log("SAY", "%s -> %s: %s" % [_nm(fid), _nm(to), text]))
	ev.thought.connect(func(fid, text): if fid == _pid(): _log("THINK", text))
	ev.interaction_started.connect(func(fid, iid, _tg): if fid == _pid() and _cur != "": _started[iid] = true)
	ev.interaction_finished.connect(func(fid, iid, ok): if fid == _pid() and _started.has(iid): _finished[iid] = ok)
	JusticePlayer.ask_fn = func(pid, title, text, options, on_choice, default_id):
		_log("ASK", "%s | %s | %s (during %s)" % [title, text, str(options.map(func(o): return o["label"])), _cur])
		on_choice.call(default_id)
	_shot("start")
	if "ui" in _phases:
		await _ui()
	Economy.deposit(pawn().household_id, 50000, "sweep")          # so money never hides an action
	if "self" in _phases:
		await _self_menu()
	if "objects" in _phases:
		await _objects()
	if "social" in _phases:
		await _social()
	_log("END", "sweep done")
	get_tree().quit(0)

func _pid() -> int:
	return _hud.selected_folk_id if _hud != null else -1

func _nm(fid: int) -> String:
	var f = UIU.get_folk(fid)
	return str(f.name) if f != null else "nobody"

# ------------------------------------------------------------------ windows
func _ui() -> void:
	var fid: int = _hud.selected_folk_id
	for d in [_hud.goals_dialog, _hud.career_dialog, _hud.household_dialog, _hud.help_dialog, _hud.case_board, _hud.share_hub, _hud.vacation_dialog, _hud.town_dialog, _hud.pause_menu]:
		d.show_for(fid)
		await _wait(8)
		_shot("ui_" + d.get_class() + "_" + str(d.name))
		d.visible = false
	for t in LifeHub.TABS:
		_hud.life_hub.tab = t[0]
		_hud.life_hub.show_for(fid)
		await _wait(8)
		_shot("ui_life_" + t[0])
		_hud.life_hub.visible = false
	for t in BankHub.TABS:
		_hud.money_hub.tab = t[0]
		_hud.money_hub.show_for(fid)
		await _wait(8)
		_shot("ui_money_" + t[0])
		_hud.money_hub.visible = false
	for app in ["", "messages", "jobs", "bank", "news", "contacts", "social"]:
		LifeHubPhone.app = app
		_hud.phone_dialog.show_for(fid)
		await _wait(8)
		_shot("ui_phone_" + (app if app != "" else "home"))
		_hud.phone_dialog.visible = false
	LifeHubPhone.app = ""
	for t in GameSettings.TABS:
		_hud.settings_dialog.tab = t[0]
		_hud.settings_dialog.show_for(fid)
		await _wait(8)
		_shot("ui_settings_" + t[0])
		_hud.settings_dialog.visible = false
	_hud.build_panel.set_active(true)
	await _wait(10)
	_shot("ui_build")
	_hud.build_panel.set_active(false)
	_hud.travel_panel.visible = true
	await _wait(8)
	_shot("ui_map")
	_hud.travel_panel.visible = false
	await _wait(4)

# ------------------------------------------------------------------ trying one action
func _fresh() -> void:
	var f = pawn()
	for n in ["hunger", "energy", "bladder", "hygiene", "fun", "social", "comfort"]:
		if f.needs.has(n):
			f.add_to_stat(n, 100.0)
	f.clear_queue()
	if f.current != null:
		f.cancel_current("sweep")
	for d in _hud.dialogs():          # a window the last action opened (Manage Money, the town notice) stays up otherwise
		if d != null and d.visible and d != _hud.case_prompt:
			_log("WIN", "left open after %s: %s" % [_cur if _cur != "" else "the last action", str(d.name)])
			d.visible = false

## Press one pie entry and watch it: started? finished? which clips? how far from the target? a close-up halfway.
func _try(e: Dictionary, kind: String, target_id: int, target_tile: Vector2i, label: String) -> void:
	var f = pawn()
	_fresh()
	await _wait(2)
	_started.clear()
	_finished.clear()
	_cur = "%s / %s" % [label, e["label"]]
	var id := str(e.get("id", ""))
	if not e.has("action"):          # the menu was read before the earlier actions ran: ask again now, the way a fresh click would
		var again: Array = _IQ.self_entries(f) if kind == "self" else _IQ.entries_for(f, kind, target_id)
		var now: Array = again.filter(func(x): return str(x.get("id", "")) == id)
		if not now.is_empty() and not bool(now[0].get("enabled", true)):
			_log("SKIP", "%s / %s: greyed now (%s)" % [label, e["label"], str(now[0].get("reason", ""))])
			return
	var coins0: int = Economy.balance(f.household_id)
	var t0: int = int(root.get_node("Clock").total_minutes)
	if e.has("action"):
		e["action"].call()
	else:
		UIU.enqueue(f, id, target_id)
	root.get_node("Clock").set_speed(3)
	var clips := {}
	var postures := {}
	var far := 0.0
	var shot_done := false
	var frames := 0
	var lv = _main.find_child("LotView", true, false)
	var ms0 := Time.get_ticks_msec()
	while frames < 900 and Time.get_ticks_msec() - ms0 < 30000:
		await get_tree().process_frame
		frames += 1
		f = pawn()
		if f == null:
			_log("ODD", "%s: the character is gone (died?)" % _cur)
			return
		var running: bool = f.current != null and _started.has(str(f.current.def_id))          # what the press started (a counter order runs as another id)
		if running and f.current.state == "running":
			postures[f.posture] = true
			var fv = lv.get_folk_view(f.id) if lv != null else null
			if fv != null:
				clips[fv._desired_clip(f)] = true
			if target_tile.x >= 0:
				far = max(far, Vector2(f.tile).distance_to(Vector2(target_tile)))
			if not shot_done and f.current.progress() >= 0.4:
				root.get_node("Clock").set_speed(1)
				lv.focus_tile(f.tile)
				lv.set_zoom(8.0)
				await _wait(6)
				_shot("act_" + _cur.replace(" / ", "__"))
				shot_done = true
				root.get_node("Clock").set_speed(3)
		if not _started.is_empty() and f.current == null and f.queue.is_empty() and not _finished.is_empty():
			break
		if _started.is_empty() and frames > 400 and f.current == null and f.queue.is_empty():
			break
	var mins: int = int(root.get_node("Clock").total_minutes) - t0
	var coins: int = Economy.balance(f.household_id) - coins0
	var bad: Array = _finished.keys().filter(func(k): return not _finished[k])
	var res := "never started" if _started.is_empty() else ("still running" if f.current != null and _started.has(str(f.current.def_id)) else ("FAILED " + ",".join(bad) if not bad.is_empty() else "finished ok"))
	_log("ACT", "%s | %s | ran %s | %d min | coins %+d | posture %s | clips %s | far %.1f" % [_cur, res, ",".join(_started.keys()), mins, coins, ",".join(postures.keys()), ",".join(clips.keys()), far])
	if res == "never started":
		_log("ODD", "%s: offered as enabled but never started" % _cur)
	if not _started.is_empty() and mins <= 0 and res != "still running":
		_log("ODD", "%s: took no time at all" % _cur)
	if kind == "object" and far > 2.5 and clips.size() > 0 and not shot_done:
		_log("ODD", "%s: ran %.1f tiles away from the object" % [_cur, far])
	if res == "still running":
		_shot("stuck_" + _cur.replace(" / ", "__"))
		_log("ODD", "%s: still running after 900 frames / 30 s" % _cur)
	_cur = ""

func _menu(kind: String, target_id: int, label: String) -> Array:
	var f = pawn()
	var entries: Array
	if kind == "self":
		entries = _IQ.self_entries(f)
		_hud.pie.open_with_entries(f, "self", -1, entries, Vector2(700, 400))
	else:
		entries = _IQ.entries_for(f, kind, target_id)
		_hud.pie.open_for(f, kind, target_id, Vector2(700, 400))
	await _wait(3)
	for h in _hud.pie.category_headers.values():
		h.pressed.emit()
		await _wait(1)
	await _wait(3)
	_shot("menu_" + label)
	var shown: Array = _hud.pie.entry_buttons.map(func(b): return ("(off) " if b.disabled else "") + str(b.text))
	_log("MENU", "%s: %s" % [label, " ; ".join(shown)])
	for e in entries:
		if not bool(e.get("enabled", true)):
			_log("OFF", "%s / %s: %s" % [label, e["label"], str(e.get("reason", ""))])
	_hud.pie.close()
	return entries.filter(func(e): return bool(e.get("enabled", true)))

# ------------------------------------------------------------------ phases
func _self_menu() -> void:
	for e in await _menu("self", -1, "myself"):
		await _try(e, "self", -1, Vector2i(-1, -1), "myself")

func _teleport(t: Vector2i) -> void:
	var f = pawn()
	_fresh()
	f.tile = t
	f.level = 0
	Neighborhood.refresh_view(f.id)
	_main.find_child("LotView", true, false).focus_tile(t)
	await _wait(10)

func _free_near(t: Vector2i) -> Vector2i:
	var w = root.get_node("World")
	for r in range(1, 4):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var c := t + Vector2i(dx, dy)
				if w.is_walkable(c) and NeighborhoodLots.lot_at(c) == NeighborhoodLots.lot_at(t):
					return c
	return t

func _objects() -> void:
	var seen := {}
	var picks: Array = []
	var home: String = Neighborhood.lot_of(pawn())
	for o in root.get_node("World").all_objects():
		var d := str(o.def_id)
		var lot: String = NeighborhoodLots.lot_at(o.tile)
		if lot == "" or int(UIU.prop(o, "level", 0)) != 0 or (not _only.is_empty() and not _only.has(d)):
			continue
		if not seen.has(d) or (lot == home and seen[d][1] != home):
			seen[d] = [o, lot]
	for d in seen:
		picks.append(seen[d])
	picks.sort_custom(func(a, b): return str(a[1]) + str(a[0].def_id) < str(b[1]) + str(b[0].def_id))
	_log("INFO", "%d kinds of object on ground floors" % picks.size())
	for i in picks.size():
		var p: Array = picks[i]
		var o = p[0]
		if i < _skip:
			continue
		_log("KIND", "%d/%d %s" % [i, picks.size(), str(o.def_id)])
		if root.get_node("World").get_object(o.id) == null:
			continue
		await _teleport(_free_near(o.tile))
		var label := "%s@%s" % [o.def_id, p[1]]
		for e in await _menu("object", int(o.id), label):
			if root.get_node("World").get_object(o.id) == null:
				break
			await _try(e, "object", int(o.id), o.tile, label)

const ROUGH := ["shove", "punch", "attack", "fight", "pocket", "grab", "mug", "rob", "weapon", "stab", "shoot", "kill", "kidnap", "threat", "steal", "assault", "slap", "kick", "trip", "spit", "insult"]

func _stranger(f, skip: Array = []):
	var others: Array = WorldIface.all_folk().filter(func(o): return int(o.household_id) != int(f.household_id) and str(o.age_stage) == "adult" and not Neighborhood.traveling(int(o.id)) and NeighborhoodLots.lot_at(o.tile) != "" and not skip.has(int(o.id)))
	return null if others.is_empty() else others[0]

func _social() -> void:
	var f = pawn()
	var t = _stranger(f)
	if t == null:
		_log("ODD", "no grown-up stranger anywhere in town to talk to")
		return
	var tid: int = int(t.id)
	var seen: Array = [tid]
	await _teleport(_free_near(t.tile))
	var entries: Array = await _menu("folk", tid, "person_" + _nm(tid))
	var gentle := entries.filter(func(e): return not ROUGH.any(func(r): return r in str(e["label"]).to_lower() or r in str(e.get("id", ""))))
	var rough := entries.filter(func(e): return not gentle.has(e))
	for e in gentle + rough:
		t = UIU.get_folk(tid)
		if t == null or Neighborhood.traveling(tid) or NeighborhoodLots.lot_at(t.tile) == "":
			_log("ODD", "%s left in the middle of the person list; switching to someone else" % _nm(tid))
			t = _stranger(pawn(), seen)
			if t == null:
				return
			tid = int(t.id)
			seen.append(tid)
		if Vector2(t.tile).distance_to(Vector2(pawn().tile)) > 6:
			await _teleport(_free_near(t.tile))
		await _try(e, "folk", tid, t.tile, "person_" + _nm(tid))
	await _menu("folk", tid, "person_after_" + _nm(tid))
