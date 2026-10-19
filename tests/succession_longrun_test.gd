extends RefCounted
## Slow tier (task 15): 168 game days (six years) with the whole sim running. A moved-out grown child exists; on day 5 the head dies. Control moves
## to the child (who moves back into the family home), every hour of every day the household has somebody in it, and the new head is still in
## charge at the end. The first FULL_DAYS days run the whole sim (folk live their days); the rest only the daily / hourly systems (aging, story,
## incidents, economy, deaths) with the folk frozen, so six years fit the time budget. `--days=N` after `--` shortens the run for a quick look.

const FULL_DAYS := 8

const K := preload("res://tests/succession_kit.gd")

func run() -> Array:
	var f: Array = []
	var folk: Array = K.new_game(3)
	var head = folk[0]
	var ada = K.housemate("Ada", "adult", 20.0)
	K.child_of(int(ada.id), int(head.id))
	FamilyHousehold.move_out(int(ada.id), 0.0)
	var days: int = _days()
	var empty_hours := 0
	var died_day: int = mini(5, days / 2)
	var changed_on := -1
	var dir = Engine.get_main_loop().root.get_node("SimDirector")
	for hour in days * 24:
		dir.enabled = hour < FULL_DAYS * 24
		if hour == died_day * 24:
			Aging.kill(int(head.id), "old age")
			changed_on = SysUtil.day()
		K.HoodKit.run(60)
		if hour >= died_day * 24 and K.household_count() == 0:
			empty_hours += 1
		if hour % (28 * 24) == 28 * 24 - 1:
			print("  day %d: head %s, folk in the house %d" % [hour / 24 + 1, Family.name_of(Succession.head_of(1)), K.household_count()])
		if hour == died_day * 24 + 1:
			if Succession.head_of(1) != int(ada.id):
				f.append("an hour after the death Ada should be the head, got %d" % Succession.head_of(1))
	print("  %d days, head died on day %d, empty-household hours: %d, folk now %d, pending %s" % [days, changed_on, empty_hours, K.household_count(), str(Succession.is_pending(1))])
	if empty_hours > 0:
		f.append("the household was empty for %d hours" % empty_hours)
	if Succession.is_pending(1):
		f.append("still waiting for a choice at the end")
	var h = K.world().get_folk(Succession.head_of(1))
	if h == null or int(h.household_id) != 1:
		f.append("the head at the end is not alive in the household")
	dir.enabled = true
	K.teardown()
	return f

func _days() -> int:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--days="):
			return int(str(a).substr(7))
	return 168
