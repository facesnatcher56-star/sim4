extends RefCounted
## Task 14 pets over years of game time (SLOW tier): illness per pet-year when the pet is fed every day, how long pets live, how fast a neglected pet
## leaves, how often strays turn up.

const K = preload("res://tests/systems_kit.gd")
const YEAR := 28

func run() -> Array:
	var f: Array = []
	var w := K.setup(1417)
	var ann := K.make_folk(w, "Ann Rowe")
	Aging.set_age_days(ann, 90.0)
	WorldIface.coins[1] = 1000000
	Story.generate_townies(12)
	SysContent.install_all()
	LifeTick.new_game()
	LifeDefs.ensure()
	var pets_n: int = TestFixture.pick(60, 25)
	# cared-for pets: fed and treated every day
	var sick_events := 0
	var pet_days := 0
	var lifespans: Array = []
	for i in pets_n:
		var p: Dictionary = PetState.add_pet(1, "dog" if i % 2 == 0 else "cat", "P%d" % i, 0.0)
		var born: int = 1
		var d := 1
		while PetState.pets.has(int(p["id"])) and d < 400:
			d += 1
			K.set_time(d, 6)
			var was_sick: bool = bool(p["sick"])
			p["fullness"] = 100.0
			p["fun"] = 100.0
			p["bond"] = 60.0
			p["born_day"] = born
			PetDay.on_day(d)
			if PetState.pets.has(int(p["id"])):
				if bool(p["sick"]) and not was_sick:
					sick_events += 1
				if bool(p["sick"]):
					p["sick"] = false              # the vet cured it
				pet_days += 1
		lifespans.append(d - born)
	var sick_rate: float = float(sick_events) / (float(pet_days) / float(YEAR))
	var mean_life := 0.0
	for l in lifespans:
		mean_life += float(l)
	mean_life /= float(lifespans.size())
	K.expect(f, sick_rate > 0.15 and sick_rate < 0.7, "a looked-after pet falls ill %.2f times a game year" % sick_rate)
	K.expect(f, mean_life > 138.0 and mean_life < 185.0, "pets live about their span, %.0f game days" % mean_life)
	# neglected pets: gone within a week
	var gone_in: Array = []
	for i in 30:
		var q: Dictionary = PetState.add_pet(1, "dog", "N%d" % i, 20.0)
		var n := 0
		while PetState.pets.has(int(q["id"])) and n < 30:
			n += 1
			PetDay.on_day(500 + i * 40 + n)
		gone_in.append(n)
	var worst := 0
	for g in gone_in:
		worst = maxi(worst, int(g))
	K.expect(f, worst <= 8, "a pet never fed leaves within %d days" % worst)
	# strays
	PetState.strays.clear()
	var spawned := 0
	var years: int = TestFixture.pick(30, 10)
	for d2 in range(1000, 1000 + years * YEAR):
		var before: int = PetState.strays.size()
		var names_before: Array = PetState.strays.map(func(s): return str(s["name"]))
		PetDay.on_day(d2)
		for s in PetState.strays:
			if not names_before.has(str(s["name"])):
				spawned += 1
	var per_year: float = float(spawned) / float(years)
	K.expect(f, per_year > 0.8 and per_year < 2.2, "strays turn up %.2f times a game year" % per_year)
	print("pets_longrun: sick %.2f per pet-year, life %.0f days, neglect leaves in at most %d days, %.2f strays a year" % [sick_rate, mean_life, worst, per_year])
	K.teardown()
	return f
