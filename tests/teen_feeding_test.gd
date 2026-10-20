extends RefCounted
## A teen with an empty fridge and adult siblings at home does not faint with hunger over three days: they feed themselves
## (snack, cook, order or fetch groceries) or an adult sibling feeds them.

const Kit = preload("res://tests/hood_kit.gd")

func run() -> Array:
	var fails: Array = []
	var folk: Array = Kit.new_game("classic", 777, 1)
	StoryPacing.enabled = false
	var teen: Folk = folk[1]
	teen.age_stage = "teen"
	Aging.apply_stage_buff(teen)
	for o in folk:
		Careers.retired[int(o.id)] = {"career": "", "level": 1, "pension": 0}
	for o in WorldIface.world().all_objects():
		if str(o.def_id) == "fridge":
			WorldIface.state_set(o, "stock", 0.0)
	WorldIface.coins[1] = 300
	Kit.set_time(2, 7)
	var low: float = 100.0
	var weak := 0
	var ate := 0
	for h in 72:
		Kit.run(60)
		low = minf(low, teen.get_stat_value("hunger"))
		if teen.has_buff("weak_hunger"):
			weak += 1
		if teen.current != null and str(teen.current.def_id) in ["eat_meal", "grab_snack", "feed_baby", "eat_out", "order_food"]:
			ate += 1
	print("  teen over 72 hours with an empty fridge: lowest hunger %.0f, hours faint %d, hours eating %d" % [low, weak, ate])
	if weak > 0 or low < -60.0:
		fails.append("the teen went faint with hunger (lowest %.0f, %d hours)" % [low, weak])
	# an adult at home steps in when the teen is very hungry: the care list and the interaction know the teen
	var adult: Folk = folk[0]
	Aging.apply_stage_buff(adult)
	teen.add_to_stat("hunger", -200.0)
	teen.add_to_stat("hunger", -70.0 - teen.get_stat_value("hunger"))
	teen.age_stage = "teen"          # (three days may have grown them up)
	Aging.apply_stage_buff(teen)
	teen.cancel_current("test")
	teen.clear_queue()
	var wants: Array = BabyCare.wanted_care(teen)
	if wants.is_empty() or str((wants[0] as Dictionary)["iid"]) != "feed_baby":
		fails.append("a very hungry teen is on the care list (hunger %.0f)" % teen.get_stat_value("hunger"))
	if not Interaction.create("feed_baby", adult, teen.id, true).can_run(adult):
		fails.append("an adult can feed a hungry teen")
	teen.add_to_stat("hunger", 100.0)
	if not BabyCare.wanted_care(teen).is_empty():
		fails.append("a teen who is only a little hungry is left to feed themselves")
	Kit.teardown()
	return fails
