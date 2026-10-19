extends Node
## Game clock. Speeds: 0 paused, 1, 2, 3. Day 1 starts at 07:00.

signal minute_passed(total_minutes: int)
signal hour_passed(hour: int)
signal day_passed(day: int)
signal speed_changed(speed: int)

## Game minutes elapsed per real second at each speed.
const MIN_PER_SEC := [0.0, 1.0, 4.0, 12.0]
const START_MINUTE := 7 * 60

var total_minutes: int = START_MINUTE
var speed: int = 1
var _accum: float = 0.0
## Co-op (CoopTime on the host): >= 0 = the fixed pace in game minutes per real second (0 = voted pause) and manual speed changes
## are ignored. -1 = solo behaviour. A co-op client never advances time itself (speed stays 0, CoopView sets total_minutes).
var coop_rate: float = -1.0
const COOP_MAX_PER_FRAME := 6      # a skip at 60x never freezes one slow frame

func _process(delta: float) -> void:
	if coop_rate >= 0.0:
		_accum += delta * coop_rate
		var c := mini(int(_accum), COOP_MAX_PER_FRAME)
		_accum = minf(_accum - c, 2.0)
		if c > 0:
			advance_minutes(c)
		return
	if speed <= 0:
		return
	_accum += delta * MIN_PER_SEC[clampi(speed, 0, 3)]
	var n := int(_accum)
	if n > 0:
		_accum -= n
		advance_minutes(n)

func set_speed(s: int) -> void:
	if coop_rate >= 0.0:
		return          # no manual fast-forward / pause in co-op (CoopTime decides)
	s = clampi(s, 0, 3)
	if s != speed:
		speed = s
		speed_changed.emit(s)

## Advance game time by n minutes, emitting signals for every minute/hour/day boundary.
## Usable by tests; independent of real time.
func advance_minutes(n: int) -> void:
	for i in n:
		var old_day := day()
		total_minutes += 1
		minute_passed.emit(total_minutes)
		if minute() == 0:
			hour_passed.emit(hour())
		if day() != old_day:
			day_passed.emit(day())

func reset(start_total: int = START_MINUTE) -> void:
	total_minutes = start_total
	_accum = 0.0

func minute() -> int: return total_minutes % 60
func hour() -> int: return (total_minutes / 60) % 24
func day() -> int: return total_minutes / 1440 + 1
## Fractional hour of day, e.g. 13.5 = 13:30
func hour_f() -> float: return float(total_minutes % 1440) / 60.0
func time_string() -> String: return "Day %d %02d:%02d" % [day(), hour(), minute()]
