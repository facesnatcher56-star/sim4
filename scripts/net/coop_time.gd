class_name CoopTime
extends RefCounted
## The co-op time model (task 24C stage 3), host side, transport-free. The host's Clock is the only clock; clients never advance time.
##  - ONE fixed pace chosen by the host before the session (`PACES`, game minutes per real second). No manual fast-forward, menus never pause.
##  - AUTOMATIC SKIP: while every connected player is passive (all their folk asleep / away: work, school, hospital, jail, a trip) the clock runs
##    at SKIP_RATE until anyone's folk is free again, then back to the pace. A player with no input for IDLE_S real seconds is on autopilot (counts
##    as passive); a dropped player is not waited for.
##  - The skip STOPS on big moments (`alert()`): normal pace for ALERT_HOLD_MIN game minutes, and the right players are told (`alert_fn`).
##  - PAUSE only by unanimous vote (`call_vote` / `answer_vote`); while paused any player may resume.
## Drive it with `update(now_s, now_min)` a few times per real second. `state()` is the dictionary clients receive as a TIME message.

signal changed

const PACES := {"relaxed": 0.5, "normal": 1.0, "quick": 2.0}
const PACE_LABELS := {"relaxed": "Relaxed", "normal": "Normal", "quick": "Quick"}
const SKIP_RATE := 45.0                 # game minutes per real second while skipping (30 to 60)
const IDLE_S := 180.0                   # no input for this long = autopilot
const ALERT_HOLD_MIN := 20              # game minutes at normal pace after a big moment
const VOTE_TIMEOUT_S := 30.0
const SLEEP_IDS := ["sleep_bed", "nap_bed", "nap_sofa", "sleep_crib"]

## True while a co-op session owns the clock (UIDialog and friends check it: menus must not pause in co-op).
static var active: bool = false

var pace: String = "normal"
var paused: bool = false
var skipping: bool = false
var reason: String = ""
var vote: Dictionary = {}                # {} or {caller, yes: {pid: true}, at}
var vote_note: String = ""               # last vote outcome in plain words ("Sam said no")
var clock = null                         # object with coop_rate (Clock); tests may pass a stub
var players_fn: Callable = Callable()    # () -> Array of connected player ids (host included)
var passive_fn: Callable = Callable()    # (player_id) -> bool, default: all the player's household folk are passive
var alert_fn: Callable = Callable()      # (player_id, text, folk_id, kind)
var name_fn: Callable = Callable()       # (player_id) -> String
var last_alert: Dictionary = {}
var alerts_sent: int = 0
var _last_input: Dictionary = {}         # player id -> real seconds
var _hold_until_min: int = -1
var _sig: String = ""

# ------------------------------------------------------------------ lifecycle
func start(p_clock = null) -> void:
	clock = p_clock if p_clock != null else Clock
	active = true
	_apply_rate()

func stop() -> void:
	active = false
	if clock != null:
		clock.coop_rate = -1.0
	skipping = false
	paused = false
	vote = {}

func set_pace(p: String) -> bool:
	if not PACES.has(p):
		return false
	pace = p
	_apply_rate()
	_notify()
	return true

func rate() -> float:
	if paused:
		return 0.0
	return SKIP_RATE if skipping else float(PACES[pace])

func is_skipping() -> bool:
	return skipping

func _apply_rate() -> void:
	if clock != null:
		clock.coop_rate = rate()

# ------------------------------------------------------------------ players
func players() -> Array:
	return players_fn.call() if players_fn.is_valid() else [Players.LOCAL]

func note_input(player_id: int, now_s: float) -> void:
	_last_input[player_id] = now_s

func forget(player_id: int) -> void:
	_last_input.erase(player_id)

func is_idle(player_id: int, now_s: float) -> bool:
	return _last_input.has(player_id) and now_s - float(_last_input[player_id]) > IDLE_S

func _name(player_id: int) -> String:
	return str(name_fn.call(player_id)) if name_fn.is_valid() else Players.name_of(player_id)

## Passive = every folk of the player's household is asleep or away (or the player has none to command: not passive, they are still choosing).
func passive(player_id: int, now_s: float = 0.0) -> bool:
	if is_idle(player_id, now_s):
		return true                       # autopilot
	if passive_fn.is_valid():
		return bool(passive_fn.call(player_id))
	return household_passive(Players.household_of(player_id))

static func household_passive(hid: int) -> bool:
	if hid <= 0:
		return false
	var n := 0
	for f in WorldIface.all_folk():
		if int(f.household_id) != hid or f.has_meta("visitor"):
			continue
		n += 1
		if not folk_passive(f):
			return false
	return n > 0

static func folk_passive(f) -> bool:
	if Away.is_away(int(f.id)) or f.has_meta("away"):
		return true
	return f.current != null and SLEEP_IDS.has(str(f.current.def_id))

# ------------------------------------------------------------------ the decision
func update(now_s: float, now_min: int) -> void:
	if vote.size() > 0 and now_s - float(vote["at"]) > VOTE_TIMEOUT_S:
		_end_vote("Nobody answered the pause request in time.")
	var pids := players()
	var all_passive := not pids.is_empty()
	var waiting := ""
	for pid in pids:
		if not passive(int(pid), now_s):
			all_passive = false
			break
	var was := skipping
	if paused:
		skipping = false
		reason = "Paused: everyone agreed."
	elif all_passive and now_min >= _hold_until_min:
		skipping = true
		var idle: Array = []
		for pid in pids:
			if is_idle(int(pid), now_s):
				idle.append(_name(int(pid)))
		reason = "Everyone is asleep or away, so time is skipping ahead."
		if not idle.is_empty():
			reason = "Everyone is asleep, away or idle (%s), so time is skipping ahead." % ", ".join(idle)
	else:
		skipping = false
		reason = "Something is happening: normal speed for a while." if now_min < _hold_until_min else ""
	if was and not skipping and not paused and reason == "":
		reason = ""
	_apply_rate()
	_notify()

# ------------------------------------------------------------------ big moments
## Stop any skip and tell `pids`. Returns the number of players told.
func alert(pids: Array, text: String, folk_id: int = -1, now_min: int = -1, kind: String = "alert") -> int:
	var nm: int = now_min if now_min >= 0 else int(clock.total_minutes if clock != null else 0)
	_hold_until_min = maxi(_hold_until_min, nm + ALERT_HOLD_MIN)
	if skipping:
		skipping = false
		reason = "Something is happening: normal speed for a while."
		_apply_rate()
	var n := 0
	var seen := {}
	for pid in pids:
		if seen.has(int(pid)):
			continue
		seen[int(pid)] = true
		last_alert = {"player": int(pid), "text": text, "folk_id": folk_id, "minute": nm}
		if alert_fn.is_valid():
			alert_fn.call(int(pid), text, folk_id, kind)
		n += 1
	alerts_sent += n
	_notify()
	return n

# ------------------------------------------------------------------ pause vote
func call_vote(player_id: int, now_s: float) -> bool:
	if paused or not vote.is_empty() or not players().has(player_id):
		return false
	vote = {"caller": player_id, "yes": {player_id: true}, "at": now_s}
	vote_note = ""
	_check_vote()
	_notify()
	return true

func answer_vote(player_id: int, yes: bool) -> void:
	if vote.is_empty() or not players().has(player_id):
		return
	if not yes:
		_end_vote("%s does not want to pause." % _name(player_id))
		return
	(vote["yes"] as Dictionary)[player_id] = true
	_check_vote()
	_notify()

func _check_vote() -> void:
	for pid in players():
		if not (vote["yes"] as Dictionary).has(int(pid)):
			return
	vote = {}
	vote_note = ""
	paused = true
	skipping = false
	_apply_rate()

func _end_vote(note: String) -> void:
	vote = {}
	vote_note = note
	_notify()

func resume(_player_id: int) -> void:
	if paused:
		paused = false
		vote_note = ""
		_apply_rate()
		_notify()

# ------------------------------------------------------------------ what clients see
func state() -> Dictionary:
	var yes: Array = []
	for k in (vote.get("yes", {}) as Dictionary):
		yes.append(int(k))
	return {"pace": pace, "label": PACE_LABELS.get(pace, pace), "skip": skipping, "paused": paused, "reason": reason, "rate": rate(),
		"vote": int(vote.get("caller", 0)), "yes": yes, "note": vote_note,
		"who": _name(int(vote.get("caller", 0))) if not vote.is_empty() else ""}

func _notify() -> void:
	var sig := JSON.stringify(state())
	if sig != _sig:
		_sig = sig
		changed.emit()
