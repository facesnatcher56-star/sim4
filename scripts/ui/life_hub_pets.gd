class_name LifeHubPets
extends RefCounted
## The "Pets" tab of LifeHub: the household's pets with their mood and needs, and the care buttons (feed, play, walk, train, groom, cuddle). The vet,
## the shelter for strays and the pet shop are under Places > Pets (the pet corner at the market).

const CARE := [["pet_feed", "Feed"], ["pet_play", "Play"], ["pet_walk", "Walk"], ["pet_train", "Train"], ["pet_groom", "Groom"], ["pet_cuddle", "Cuddle"]]

static func build(dlg: LifeHub) -> void:
	var f = dlg.folk_obj()
	var pets: Array = PetState.of_household(int(f.household_id))
	if pets.is_empty():
		dlg.line("No pets at home yet. The pet corner at the market has a shelter for strays and a few puppies and kittens.", 13, UITheme.MUTED)
	for p in pets:
		var sd: Dictionary = PetState.species_def(str(p["species"]))
		dlg.heading("%s the %s" % [p["name"], sd.get("label", "pet")])
		dlg.line("Feeling %s. Age %d days, %d trick%s, bond %d." % [PetState.mood(p), PetState.age_days(p), int(p["tricks"]), "" if int(p["tricks"]) == 1 else "s", int(float(p["bond"]))], 14)
		dlg.line("Fullness", 12, UITheme.MUTED)
		dlg.bar(float(p["fullness"]), 100.0, "Feed every day")
		dlg.line("Fun", 12, UITheme.MUTED)
		dlg.bar(float(p["fun"]), 100.0, "Play and walks")
		var row := HFlowContainer.new()
		dlg.body.add_child(row)
		for c in CARE:
			var why: String = PlaceUse.why_not(dlg.folk_id, "pet_care", str(c[0]), int(p["id"]))
			row.add_child(dlg.button(str(c[1]), why if why != "" else "Go ahead", func(): dlg.act("use", {"place": "pet_care", "service": c[0], "target": p["id"]}), why == ""))
	if not PetState.strays.is_empty():
		dlg.line("Strays around town: " + ", ".join(PetState.strays.map(func(s): return "%s the %s" % [s["name"], PetState.species_def(str(s["species"])).get("label", "pet")])) + ".", 13, UITheme.MUTED)
