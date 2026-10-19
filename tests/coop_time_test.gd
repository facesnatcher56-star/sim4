extends RefCounted
## Co-op stage 3, the time model without sockets or a world: fixed pace per setting, auto-skip only when EVERY player is passive, skip stops on an
## alert and tells the right players, pause needs unanimity, menus never pause, idle players go on autopilot, dropped players are not waited for.

class StubClock:
	var coop_rate: float = -1.0
	var total_minutes: int = 0

var fails: Array = []
var passive: Dictionary = {}
var told: Array = []
var pids: Array = [1, 2]

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _make() -> Array:
	var clk := StubClock.new()
	var t := CoopTime.new()
	t.players_fn = func(): return pids
	t.passive_fn = func(p): return bool(passive.get(p, false))
	t.alert_fn = func(p, text, fid, _k): told.append([p, text, fid])
	t.name_fn = func(p): return "P%d" % p
	t.start(clk)
	return [t, clk]

func run() -> Array:
	fails = []
	pids = [1, 2]
	# fixed pace per setting
	var a := _make()
	var t: CoopTime = a[0]
	var clk: StubClock = a[1]
	passive = {1: false, 2: false}
	t.update(0.0, 100)
	_check(clk.coop_rate == 1.0 and not t.is_skipping(), "normal pace = 1 game minute per second")
	for p in [["relaxed", 0.5], ["quick", 2.0], ["normal", 1.0]]:
		t.set_pace(p[0])
		t.update(1.0, 100)
		_check(is_equal_approx(clk.coop_rate, p[1]), "%s pace = %s" % [p[0], str(p[1])])
	_check(not t.set_pace("warp") and t.pace == "normal", "unknown pace refused")
	_check(CoopTime.active, "co-op owns the clock (menus must not pause)")
	# auto-skip needs everyone passive
	passive = {1: true, 2: false}
	t.update(2.0, 100)
	_check(not t.is_skipping() and clk.coop_rate == 1.0, "one free player: no skip")
	passive = {1: true, 2: true}
	t.update(3.0, 100)
	_check(t.is_skipping() and clk.coop_rate == CoopTime.SKIP_RATE and t.reason != "", "everyone passive: skipping, with a reason (%s)" % t.reason)
	_check(CoopTime.SKIP_RATE >= 30.0 and CoopTime.SKIP_RATE <= 60.0, "skip speed within 30 to 60")
	passive[2] = false
	t.update(4.0, 101)
	_check(not t.is_skipping() and clk.coop_rate == 1.0, "anyone free again: back to normal pace")
	# skip stops on an alert and tells the right player
	passive = {1: true, 2: true}
	t.update(5.0, 200)
	_check(t.is_skipping(), "skipping again")
	told.clear()
	t.alert([2], "Fire at your home!", 7, 200)
	_check(not t.is_skipping() and clk.coop_rate == 1.0, "the alert stops the skip at once")
	_check(told.size() == 1 and told[0][0] == 2 and told[0][2] == 7, "only player 2 is alerted")
	t.update(6.0, 205)
	_check(not t.is_skipping(), "no skip right after the alert (held %d game minutes)" % CoopTime.ALERT_HOLD_MIN)
	t.update(7.0, 200 + CoopTime.ALERT_HOLD_MIN + 1)
	_check(t.is_skipping(), "the skip resumes once the hold is over and everyone is still passive")
	# the same through game events (CoopAlerts)
	var al := CoopAlerts.new(t)
	t.update(8.0, 400)
	told.clear()
	al.on_event("disaster", {"kind": "tornado", "phase": "siren"})
	_check(told.size() == 2 and not t.is_skipping(), "a disaster warning alerts everybody and stops the skip")
	t.update(9.0, 500)
	told.clear()
	al.on_event("coop_alert", {"alert_players": [1], "text": "Phone!", "folk_id": -1})
	_check(told.size() == 1 and told[0][0] == 1, "an explicit alert_players list is honoured")
	al.on_event("fire_alarm", {"lot": "nowhere", "folk_id": -1})
	_check(told.size() == 1, "an event nobody owns alerts nobody")
	# pause needs unanimity
	var b := _make()
	t = b[0]
	clk = b[1]
	passive = {1: false, 2: false}
	pids = [1, 2]
	_check(t.call_vote(1, 0.0) and not t.paused and not t.vote.is_empty(), "calling a vote does not pause yet")
	t.update(1.0, 10)
	_check(clk.coop_rate == 1.0, "time still runs while the vote is open")
	t.answer_vote(2, false)
	_check(not t.paused and t.vote.is_empty() and t.vote_note != "", "a 'no' cancels it (%s)" % t.vote_note)
	t.call_vote(2, 5.0)
	t.answer_vote(1, true)
	_check(t.paused and clk.coop_rate == 0.0, "everyone accepted: paused")
	t.resume(2)
	_check(not t.paused and clk.coop_rate == 1.0, "any player can resume")
	t.call_vote(1, 10.0)
	t.update(10.0 + CoopTime.VOTE_TIMEOUT_S + 1.0, 10)
	_check(t.vote.is_empty() and not t.paused, "an unanswered vote times out")
	pids = [1]
	_check(t.call_vote(1, 100.0) and t.paused, "alone, a vote passes at once")
	t.resume(1)
	pids = [1, 2]
	# idle players are on autopilot, dropped players are not waited for
	var c := _make()
	t = c[0]
	clk = c[1]
	t.passive_fn = Callable()           # use the real rule; no household for these ids so only idleness can make them passive
	passive = {}
	t.note_input(1, 0.0)
	t.note_input(2, 0.0)
	t.update(10.0, 50)
	_check(not t.is_skipping(), "active players with no folk to command are not passive")
	t.update(CoopTime.IDLE_S + 5.0, 50)
	_check(t.is_idle(1, CoopTime.IDLE_S + 5.0) and t.is_skipping(), "both idle = autopilot = passive")
	t.note_input(2, CoopTime.IDLE_S + 5.0)
	t.update(CoopTime.IDLE_S + 6.0, 50)
	_check(not t.is_skipping(), "one player back at the keyboard: no skip")
	t.passive_fn = func(p): return bool(passive.get(p, false))
	pids = [1]
	passive = {1: true}
	t.update(CoopTime.IDLE_S + 7.0, 50)
	_check(t.is_skipping(), "a dropped player (not in the connected list) is not waited for")
	# state for clients
	var s := t.state()
	_check(s.has("pace") and s.has("skip") and s.has("paused") and s.has("reason") and CoopProto.encode(CoopProto.TIME, {"d": s}).size() > 0, "state() fits a TIME message")
	t.stop()
	_check(not CoopTime.active and clk.coop_rate == -1.0, "stopping gives the clock back")
	return fails
