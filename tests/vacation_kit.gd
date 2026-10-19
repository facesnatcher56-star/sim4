extends RefCounted
## Helpers for the vacation / cruise tests (no run(): the runner skips kits). Real autoloads like hood_kit, a household with money, quiet defaults
## (no autonomy for the household unless asked: the trips themselves do not need it and 4000 game minutes stay cheap).

const Kit = preload("res://tests/hood_kit.gd")

static func new_game(start: String = "small", coins: int = 6000, autonomy: bool = false, seed_value: int = 777) -> Array:
	var folk: Array = Kit.new_game(start, seed_value)
	VacationContent.install()
	WorldIface.coins[1] = coins
	director().autonomy_enabled = autonomy
	Kit.set_time(2, 8, 0)
	return folk

static func director() -> Node:
	return Kit.root().get_node("SimDirector")

static func teardown() -> void:
	director().autonomy_enabled = true
	Kit.teardown()

## Advance the clock; hourly + daily systems run through the clock signals exactly like in the game.
static func run(minutes: int) -> void:
	Kit.run(minutes)

## Fast-forward: the clock jumps in `step`-minute pieces; Vacation (due minutes, hourly) and the daily systems (bills, home upkeep...) run at their boundaries, the
## per-minute folk simulation (needs, autonomy, interactions) does not. This is the "town advanced cheaply" mode for long stays.
static func warp(minutes: int, step: int = 20) -> void:
	var clk: Node = Kit.clock()
	var left: int = minutes
	while left > 0:
		var n: int = mini(step, left)
		var h0: int = clk.total_minutes / 60
		var d0: int = clk.total_minutes / 1440
		clk.total_minutes += n
		Vacation.on_minute()
		CrimeFlow.on_minute()                          # queued trials, verdicts, police arrivals
		if clk.total_minutes / 60 != h0:
			Vacation.on_hour()
		if clk.total_minutes / 1440 != d0:
			Kit.mgr._on_day(clk.day())
		left -= n

static func run_until(cond: Callable, max_minutes: int, step: int = 5) -> bool:
	var n: int = 0
	while n < max_minutes:
		if bool(cond.call()):
			return true
		Kit.run(step)
		n += step
	return bool(cond.call())

static func now() -> int:
	return SimEnv.now_min()

static func add_folk_ids(folk: Array) -> Array:
	return folk.map(func(f): return int(f.id))

static func log_has(tag: String, trip_id: int = -1) -> bool:
	return VacationLog.count(tag, trip_id) > 0
