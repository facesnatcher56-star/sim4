class_name ScenarioGoals
extends RefCounted
## Checks the active scenario's checklist (Scenario.goals()). Listens to the event bus; headless-safe.
## Goal "check" kinds (data/scenarios.json):
##   {"event": name, "count": n, "on_time": bool}   a game event happened n times (bill_paid + on_time: no late bill among the paid ones)
##   {"events": [names]}                             any of these events happened
##   {"jobs": n}                                     at least n residents are employed
##   {"cond": [SysCond...]}                          true for ANY resident
## Completing a goal pays its reward (coins to the household, satisfaction points to every resident) and fires
## game_event "scenario_goal_done" {goal}; the last one fires "scenario_finished".

const POLL_EVENTS := ["hired", "promoted", "left_job", "relationship_bit_changed", "relationship_status", "married", "engaged", "aged_up"]

static var _ev = null
static var _clk = null

## Connect to the event bus + clock once (idempotent; rebinds if the bus object changed, e.g. between tests).
static func install() -> void:
	var ev = SimEnv.events()
	var clk = SimEnv.clock()
	if ev != _ev:
		_ev = ev
		if not ev.game_event.is_connected(_on_event):
			ev.game_event.connect(_on_event)
	if clk != _clk:
		_clk = clk
		if not clk.hour_passed.is_connected(_on_hour):
			clk.hour_passed.connect(_on_hour)

static func _on_hour(_h: int) -> void:
	poll()

static func _on_event(ev_name: String, payload: Dictionary) -> void:
	if not Scenario.active() or Scenario.finished:
		return
	var touched := false
	for g in Scenario.goals():
		var gid: String = str(g["id"])
		if Scenario.is_done(gid):
			continue
		var ck: Dictionary = g.get("check", {})
		var names: Array = ck.get("events", [ck["event"]] if ck.has("event") else [])
		if not names.has(ev_name):
			continue
		if bool(ck.get("on_time", false)) and not _paid_on_time(int(payload.get("household_id", 0))):
			continue
		Scenario.progress[gid] = int(Scenario.progress.get(gid, 0)) + 1
		touched = true
		if int(Scenario.progress[gid]) >= int(ck.get("count", 1)):
			complete(gid)
	if ev_name in POLL_EVENTS:
		poll()
	elif touched:
		SimEnv.emit("game_event", "scenario_progress", {})

static func _paid_on_time(hid: int) -> bool:
	for b in Economy.bills:
		if int(b["hid"]) == hid and bool(b["paid"]) and bool(b["late"]):
			return false
	return true

## Re-evaluate the state-based goals (jobs / cond).
static func poll() -> void:
	if not Scenario.active() or Scenario.finished:
		return
	var res: Array = SysUtil.residents()
	for g in Scenario.goals():
		var gid: String = str(g["id"])
		if Scenario.is_done(gid):
			continue
		var ck: Dictionary = g.get("check", {})
		var ok := false
		if ck.has("jobs"):
			var n := 0
			for f in res:
				if Careers.has_job(int(f.id)):
					n += 1
			ok = n >= int(ck["jobs"])
		elif ck.has("cond"):
			for f2 in res:
				if SysCond.check(ck["cond"], f2):
					ok = true
					break
		if ok:
			complete(gid)

static func complete(goal_id: String) -> void:
	if Scenario.is_done(goal_id):
		return
	var goal: Dictionary = {}
	for g in Scenario.goals():
		if str(g["id"]) == goal_id:
			goal = g
	if goal.is_empty():
		return
	Scenario.done[goal_id] = SysUtil.day()
	var rw: Dictionary = goal.get("reward", {})
	var coins: int = int(rw.get("coins", 0))
	var pts: int = int(rw.get("points", 0))
	if coins > 0:
		Economy.deposit(Economy.primary_household(), coins, "goal: " + str(goal["label"]))
	for f in SysUtil.residents():
		var p: Dictionary = Goals.ensure_profile(f)
		p["points"] = int(p["points"]) + pts
		p["lifetime"] = int(p["lifetime"]) + pts
	SysUtil.notify("Goal done: %s  (+%d coins, +%d satisfaction)" % [str(goal["label"]), coins, pts], "goal")
	SysUtil.game_event("scenario_goal_done", {"goal": goal_id})
	if Scenario.done_count() >= Scenario.goals().size():
		Scenario.finished = true
		SysUtil.notify("Getting Started complete! Open Goals to pick a life aspiration and keep dreaming.", "goal")
		SysUtil.game_event("scenario_finished", {"scenario": Scenario.active_id})
