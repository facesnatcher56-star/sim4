extends RefCounted
## Co-op time model against the REAL sim: two players' households, a 2-day host run. While both sleep (or are away) the clock skips; the skip ends
## when anyone is free again; menus never pause. Time is driven like the game does (real seconds -> game minutes through CoopTime.rate()).

const HoodKit := preload("res://tests/hood_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

class StubClock:
	var coop_rate: float = -1.0
	var total_minutes: int = 0

func run() -> Array:
	fails = []
	HoodKit.new_game("classic")
	for f in WorldIface.all_folk().duplicate():
		if f.name != "Mira":
			WorldIface.world().remove_folk(f.id)
	Players.set_player(1, 1, "Hosty")
	var folk := HouseholdSetup.random_folk("adult", "none", ["Mira"])
	folk["name"] = "Zed"
	var r := CoopHouseholds.join(2, "Ann", {"name": "Zeds", "folk": [folk]}, "")
	_check(r["ok"], "second player joined: " + str(r["msg"]))
	HoodKit.set_time(1, 20, 0)
	var clk := StubClock.new()
	var t := CoopTime.new()
	t.players_fn = func(): return [1, 2]
	t.start(clk)
	var now := 0.0
	var accum := 0.0
	var minutes := 0
	var skipped := 0
	var skip_steps := 0
	var bad_skip := 0
	var first_skip_end := -1
	var was_skipping := false
	var dt := 0.5
	while minutes < 2 * 1440:
		now += dt
		t.note_input(1, now)
		t.note_input(2, now)
		t.update(now, SimEnv.now_min())
		if t.is_skipping():
			var all_passive := CoopTime.household_passive(1) and CoopTime.household_passive(Players.household_of(2))
			if not all_passive:
				bad_skip += 1
			skip_steps += 1
		elif was_skipping and first_skip_end < 0:
			first_skip_end = SimEnv.now_min()
			_check(not (CoopTime.household_passive(1) and CoopTime.household_passive(Players.household_of(2))) or t.reason != "",
				"the skip ended because someone is free (or an alert held it)")
		was_skipping = t.is_skipping()
		accum += t.rate() * dt
		var n := int(accum)
		accum -= n
		if t.is_skipping():
			skipped += n
		if n > 0:
			HoodKit.run(n)
			minutes += n
	_check(skip_steps > 0, "the clock skipped at least once in 2 days")
	_check(bad_skip == 0, "never skipped while someone was free (%d bad steps)" % bad_skip)
	_check(skipped >= 240, "most of the night was skipped (%d of %d game minutes)" % [skipped, minutes])
	_check(first_skip_end >= 0, "the skip ended again (at minute %d, hour %d)" % [first_skip_end, (first_skip_end / 60) % 24])
	var wake_hour := (first_skip_end / 60) % 24
	_check(wake_hour >= 4 and wake_hour <= 12, "and resumed at a morning wake-up hour (%d)" % wake_hour)
	t.stop()
	# menus never pause in co-op
	t.start(clk)
	Clock.set_speed(1)
	GameSettings.set_value("pause_on_dialog", true, false)
	var dlg := Control.new()
	UIDialog.track_open(dlg.get_instance_id(), true)
	_check(Clock.speed == 1, "opening a dialog in co-op does not pause")
	UIDialog.track_open(dlg.get_instance_id(), false)
	dlg.free()
	t.stop()
	Clock.coop_rate = -1.0
	HoodKit.teardown()
	Players.reset()
	return fails
