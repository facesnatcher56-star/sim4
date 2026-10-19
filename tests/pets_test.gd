extends RefCounted
## Task 14 pets: buying and adopting, daily care with limits, moods, neglect (illness, running away), the vet, old age, company for the owners, the
## guard dog hook for burglars, strays, the Pets tab and the save round trip.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_getting_pets(f)
	_care(f)
	_daily(f)
	_guard_and_company(f)
	_strays(f)
	_save_and_ui(f)
	return f

func _world(coins: int = 3000) -> StubWorld:
	var w := K.setup()
	var ann := K.make_folk(w, "Ann Rowe")
	Aging.set_age_days(ann, 90.0)
	WorldIface.coins[1] = coins
	Story.generate_townies(12)
	SysContent.install_all()
	LifeTick.new_game()
	K.set_time(2, 11)                                   # Tuesday 11:00: the pet corner is open
	return w

func _getting_pets(f: Array) -> void:
	var w := _world()
	var teen := K.make_folk(w, "Tess", [], 1, Vector2i(14, 12), "teen")
	K.expect(f, PlaceUse.why_not(int(teen.id), "vet_clinic", "buy_puppy") == "Only for adults." or PlaceUse.why_not(int(teen.id), "vet_clinic", "buy_puppy") == "Too young for that.", "a teen cannot buy a puppy")
	var coins: int = Economy.balance(1)
	var r: Dictionary = PlaceUse.use(1, "vet_clinic", "buy_puppy", {"instant": true})
	K.expect(f, bool(r["ok"]) and Economy.balance(1) == coins - 150 and PetState.of_household(1).size() == 1, "a puppy costs 150 coins (%s)" % str(r.get("text", r.get("reason", ""))))
	var p: Dictionary = PetState.of_household(1)[0]
	K.expect(f, str(p["species"]) == "dog" and str(p["name"]) != "" and float(p["fullness"]) > 50.0, "a dog with a name and a full tummy (%s)" % p["name"])
	K.expect(f, PlaceUse.why_not(1, "vet_clinic", "adopt_stray") == "There are no strays at the pet corner right now.", "no stray, no adoption")
	PlaceUse.use(1, "vet_clinic", "buy_kitten", {"instant": true})
	PlaceUse.use(1, "vet_clinic", "buy_kitten", {"instant": true})
	K.expect(f, PetState.of_household(1).size() == 3 and PlaceUse.why_not(1, "vet_clinic", "buy_puppy").find("enough pets") >= 0, "three pets are enough for one home")
	var names: Array = PetState.of_household(1).map(func(x): return str(x["name"]))
	K.expect(f, names.size() == 3 and names[0] != names[1] and names[1] != names[2] and names[0] != names[2], "every pet has its own name (%s)" % ", ".join(names))
	K.set_time(7, 11)                                   # Sunday
	K.expect(f, not Places.open_at("vet_clinic"), "the pet corner is shut on Sundays")
	K.teardown()

func _care(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	var dog: Dictionary = PetState.add_pet(1, "dog", "Rex", 20.0)
	var cat: Dictionary = PetState.add_pet(1, "cat", "Mittens", 20.0)
	dog["fullness"] = 30.0
	K.expect(f, PlaceUse.why_not(1, "pet_care", "pet_feed", int(dog["id"])) == "", "a hungry dog can be fed")
	var r: Dictionary = PlaceUse.use(1, "pet_care", "pet_feed", {"instant": true, "target": int(dog["id"])})
	K.expect(f, bool(r["ok"]) and float(dog["fullness"]) == 75.0 and str(r["text"]).find("Rex") >= 0, "feeding fills the tummy (%s)" % str(r.get("text", "")))
	dog["fullness"] = 90.0
	K.expect(f, PlaceUse.why_not(1, "pet_care", "pet_feed", int(dog["id"])).find("not hungry") >= 0, "a full pet is not fed again")
	dog["fullness"] = 10.0
	for i in 2:
		PlaceUse.use(1, "pet_care", "pet_feed", {"instant": true, "target": int(dog["id"])})
		dog["fullness"] = 10.0
	K.expect(f, PlaceUse.why_not(1, "pet_care", "pet_feed", int(dog["id"])).find("not hungry") >= 0, "three feeds a day at most")
	# play, owner gains
	ann.needs["fun"].value = 0.0
	var bond0: float = float(dog["bond"])
	PlaceUse.use(1, "pet_care", "pet_play", {"instant": true, "target": int(dog["id"])})
	K.expect(f, ann.needs["fun"].value >= 10.0 and float(dog["bond"]) > bond0, "playing cheers the owner and builds the bond")
	# walk: dogs only
	HealthLife.rec(1)["fitness"] = 40.0
	K.expect(f, PlaceUse.why_not(1, "pet_care", "pet_walk", int(cat["id"])).find("do not go for walks") >= 0, "a cat does not go for walks")
	PlaceUse.use(1, "pet_care", "pet_walk", {"instant": true, "target": int(dog["id"])})
	K.expect(f, float(HealthLife.rec(1)["fitness"]) > 40.0, "a dog walk is exercise for the owner")
	# train
	var tricks := 0
	for i in 12:
		K.set_time(3 + i, 11)
		PlaceUse.last_used.clear()
		var tr: Dictionary = PlaceUse.use(1, "pet_care", "pet_train", {"instant": true, "target": int(dog["id"])})
		if bool(tr["ok"]):
			tricks = int(dog["tricks"])
	K.expect(f, int(dog["tricks"]) >= 1 and int(dog["tricks"]) <= 5, "a dog learns tricks over the days (%d)" % int(dog["tricks"]))
	dog["tricks"] = 5
	K.set_time(30, 11)
	K.expect(f, PlaceUse.why_not(1, "pet_care", "pet_train", int(dog["id"])).find("every trick") >= 0 and PlaceUse.why_not(1, "pet_care", "pet_train", int(cat["id"])).find("do not learn tricks") >= 0, "five tricks at most; cats do not learn them")
	# no target: the first suitable pet
	K.expect(f, PlaceUse.why_not(1, "pet_care", "pet_cuddle") == "" and bool(PlaceUse.use(1, "pet_care", "pet_cuddle", {"instant": true})["ok"]), "cuddling needs no choice of pet")
	# groom limit
	PlaceUse.use(1, "pet_care", "pet_groom", {"instant": true, "target": int(cat["id"])})
	K.expect(f, PlaceUse.why_not(1, "pet_care", "pet_groom", int(cat["id"])).find("tidy") >= 0, "grooming once a day")
	# nobody else's pet
	var other := K.make_folk(w, "Bob", [], 2, Vector2i(15, 12))
	Aging.set_age_days(other, 90.0)
	WorldIface.coins[2] = 100
	K.expect(f, PlaceUse.why_not(int(other.id), "pet_care", "pet_feed", int(dog["id"])) != "", "another household cannot care for your pet")
	K.teardown()

func _daily(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	var dog: Dictionary = PetState.add_pet(1, "dog", "Rex", 20.0)
	K.expect(f, PetState.mood(dog) == "happy" or PetState.mood(dog) == "content", "a new pet is content (%s)" % PetState.mood(dog))
	PetDay.on_day(3)
	K.expect(f, float(dog["fullness"]) < 70.0 and float(dog["fun"]) < 60.0, "a day makes it hungrier and less amused")
	dog["fullness"] = 10.0
	K.expect(f, PetState.mood(dog) == "hungry", "a hungry dog says so")
	# neglect: three days at zero and it is gone
	LifeDefs.config["pets"]["daily"]["sick_chance_hungry"] = 0.0
	LifeDefs.config["pets"]["daily"]["sick_chance"] = 0.0
	dog["fullness"] = 0.0
	for d in [4, 5, 6]:
		PetDay.on_day(d)
	K.expect(f, PetState.of_household(1).is_empty() and K.has_note("has run away"), "a pet left hungry for days runs away")
	K.expect(f, ChronicleHook.recent.any(func(p): return str(p["kind"]) == "pet_left"), "and it is news")
	# illness: forced, the vet cures it
	var cat: Dictionary = PetState.add_pet(1, "cat", "Mittens", 20.0)
	LifeDefs.config["pets"]["daily"]["sick_chance"] = 1.0
	PetDay.on_day(7)
	K.expect(f, bool(cat["sick"]) and PetState.mood(cat) == "unwell" and K.has_note("seems unwell"), "pets fall ill now and then")
	LifeDefs.config["pets"]["daily"]["sick_chance"] = 0.0
	K.set_time(8, 11)
	var coins: int = Economy.balance(1)
	var r: Dictionary = PlaceUse.use(1, "vet_clinic", "vet_treat", {"instant": true, "target": int(cat["id"])})
	K.expect(f, bool(r["ok"]) and not bool(cat["sick"]) and Economy.balance(1) == coins - 40, "the vet treats it for 40 coins (%s)" % str(r.get("text", r.get("reason", ""))))
	K.expect(f, PlaceUse.why_not(1, "vet_clinic", "vet_treat", int(cat["id"])).find("not sick") >= 0, "and nothing to treat when healthy")
	# old age
	var old: Dictionary = PetState.add_pet(1, "dog", "Grandpa", 300.0)
	LifeDefs.config["pets"]["daily"]["old_age_chance"] = 1.0
	PetDay.on_day(9)
	K.expect(f, not PetState.pets.has(int(old["id"])) and K.has_note("died peacefully"), "an old pet dies peacefully")
	K.teardown()

func _guard_and_company(f: Array) -> void:
	var w := _world()
	var ann = SysUtil.folk(1)
	var pup: Dictionary = PetState.add_pet(1, "dog", "Pup", 3.0)
	K.expect(f, not PetState.guards_home(1) and not bool(CrimeSecurity.home_profile(1)["dog"]), "a puppy is no guard dog")
	pup["born_day"] = SysUtil.day() - 40
	K.expect(f, PetState.guards_home(1) and bool(CrimeSecurity.home_profile(1)["dog"]), "a grown, fed dog counts as a guard dog for burglars")
	pup["fullness"] = 5.0
	K.expect(f, not PetState.guards_home(1), "a starving one does not")
	pup["fullness"] = 60.0
	pup["sick"] = true
	K.expect(f, not PetState.guards_home(1), "nor a sick one")
	var cat: Dictionary = PetState.add_pet(1, "cat", "Mittens", 40.0)
	pup["sick"] = false
	K.expect(f, float(CrimeSecurity.effects(CrimeSecurity.home_profile(1), true)["abort"]) > 0.0, "the security numbers see the dog")
	# company
	LifeDefs.config["pets"]["daily"]["sick_chance"] = 0.0
	ann.remove_buff("pet_company")
	PetDay.on_day(3)
	K.expect(f, ann.has_buff("pet_company"), "content pets keep their owners company")
	ann.remove_buff("pet_company")
	pup["fullness"] = 0.0
	cat["fullness"] = 0.0
	pup["fun"] = 0.0
	cat["fun"] = 0.0
	LifeDefs.config["pets"]["daily"]["runaway_hungry_days"] = 99
	PetDay.on_day(4)
	K.expect(f, not ann.has_buff("pet_company"), "neglected pets do not")
	K.teardown()

func _strays(f: Array) -> void:
	var w := _world()
	LifeDefs.config["pets"]["strays"]["chance_per_week"] = 1.0
	PetDay.on_day(7)
	K.expect(f, PetState.strays.size() == 1 and ChronicleHook.recent.any(func(p): return str(p["text"]).find("stray") >= 0), "a stray turns up (weekly) and the chronicle says so")
	PetDay.on_day(14)
	PetDay.on_day(21)
	PetDay.on_day(28)
	K.expect(f, PetState.strays.size() == 3, "no more than three strays (%d)" % PetState.strays.size())
	PetDay.on_day(40)
	K.expect(f, PetState.strays.is_empty() or PetState.strays.size() < 3, "strays move on after a while")
	PetState.strays.clear()
	PetState.strays.append({"species": "cat", "name": "Whiskers", "day": 40})
	K.set_time(2, 11)
	var coins: int = Economy.balance(1)
	var r: Dictionary = PlaceUse.use(1, "vet_clinic", "adopt_stray", {"instant": true})
	K.expect(f, bool(r["ok"]) and Economy.balance(1) == coins - 20 and PetState.of_household(1).size() == 1 and str(PetState.of_household(1)[0]["name"]) == "Whiskers", "adopting a stray costs 20 coins (%s)" % str(r.get("text", r.get("reason", ""))))
	K.expect(f, float(PetState.of_household(1)[0]["bond"]) <= 20.0 and ChronicleHook.recent.any(func(p): return str(p["kind"]) == "pet_adopted"), "it is shy at first, and the adoption is in the chronicle")
	K.teardown()

func _save_and_ui(f: Array) -> void:
	var w := _world()
	var dog: Dictionary = PetState.add_pet(1, "dog", "Rex", 20.0)
	dog["tricks"] = 3
	PetState.strays.append({"species": "cat", "name": "Whiskers", "day": 5})
	var d: Dictionary = JSON.parse_string(JSON.stringify(LifeTick.to_dict()))
	LifeTick.from_dict(d, true)
	var p: Dictionary = PetState.of_household(1)[0]
	K.expect(f, str(p["name"]) == "Rex" and int(p["tricks"]) == 3 and int(p["id"]) == 1 and PetState.next_id == 2 and PetState.strays.size() == 1, "pets, tricks and strays survive a save and load")
	var hub := LifeHub.new()
	Engine.get_main_loop().root.add_child(hub)
	hub.tab = "pets"
	hub.show_for(1)
	var texts: Array = []
	_collect(hub.body, texts)
	var all: String = "\n".join(texts)
	K.expect(f, all.find("REX THE DOG") >= 0 and all.find("[Feed]") >= 0 and all.find("[Walk]") >= 0 and all.find("Strays around town") >= 0, "the Pets tab shows the pet, the care buttons and the strays")
	hub.queue_free()
	K.teardown()

func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append("[" + (c as Button).text + "]")
		_collect(c, out)
