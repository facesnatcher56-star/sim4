class_name PlaceAutoNow
extends RefCounted
## The things that cannot wait for tomorrow's plan (task 14b), checked once an hour: somebody who falls ill goes to the family doctor, and the pets are
## fed, played with and walked by whoever is at home. Pet care at home uses the very same service of the place "Pets at Home" the Pets tab uses.

static func on_hour(hour: int) -> void:
	_ill(hour)
	_pets(hour)

static func _sorted_residents() -> Array:
	var out: Array = SysUtil.residents()
	out.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return out

static func _ill(hour: int) -> void:
	var day: int = SysUtil.day()
	var span: Array = PlaceAuto.cfg().get("ill_delay_hours", [1, 3])
	var kd: Dictionary = PlaceAutoPlan.kind_def("clinic_sick")
	if kd.is_empty():
		return
	for f in _sorted_residents():
		var fid: int = int(f.id)
		if str(f.age_stage) in ["baby", "toddler"] or not PlaceAutoGate._sick(f):
			continue
		var key := "%d|ill_try" % fid
		if int(PlaceAuto.last.get(key, -1)) == day:
			continue
		PlaceAuto.last[key] = day
		if PlaceAuto.rng.randf() >= float(kd.get("base", 0.9)):
			continue
		PlaceAutoPlan.make_one(f, "clinic_sick", hour + PlaceAuto.rng.randi_range(int(span[0]), int(span[1])))

# ------------------------------------------------------------------ pets
static func _pets(hour: int) -> void:
	var pc: Dictionary = PlaceAuto.cfg().get("pet", {})
	var hrs: Array = pc.get("hours", [7, 21])
	if hour < int(hrs[0]) or hour > int(hrs[1]) or PetState.pets.is_empty():
		return
	var homes: Array = []
	for id in PetState.pets:
		var h: int = int(PetState.pets[id]["hid"])
		if not homes.has(h):
			homes.append(h)
	homes.sort()
	for hid in homes:
		for p in PetState.of_household(int(hid)):
			var act: String = _need(p, pc)
			if act == "":
				continue
			var who = _carer(int(hid), pc)
			if who == null:
				break
			var res: Dictionary = LifeCommand.run(PlaceAutoTrip.PLAYER, int(who.id), "use", {"place": "pet_care", "service": act, "target": int(p["id"]), "quiet": PlaceAuto.quiet_for(who)})
			if bool(res.get("ok", false)):
				PlaceAuto.count("pet_care")
				PlaceAuto.tick("kinds", act)
				break            # one pet job per household per hour

## The pet service this pet needs now ("" = nothing).
static func _need(p: Dictionary, pc: Dictionary) -> String:
	var sd: Dictionary = PetState.species_def(str(p["species"]))
	if float(p["fullness"]) < float(pc.get("feed_below", 55)):
		return "pet_feed"
	if bool(p["sick"]):
		return ""
	if float(p["fun"]) < float(pc.get("play_below", 40)):
		return "pet_walk" if bool(sd.get("walk", false)) else "pet_play"
	if PlaceAuto.rng.randf() < float(pc.get("care_per_hour", 0.05)):
		var opts: Array = ["pet_groom", "pet_cuddle", "pet_play"]
		if bool(sd.get("tricks", false)) and float(p["bond"]) >= 20.0 and int(p["tricks"]) < 5:
			opts.append("pet_train")
		return str(opts[PlaceAuto.rng.randi_range(0, opts.size() - 1)])
	return ""

## Somebody at home who can do it: weighted by age and traits.
static func _carer(hid: int, pc: Dictionary):
	var who: Array = []
	var ws: Array = []
	for f in _sorted_residents():
		if int(f.household_id) != hid or str(f.age_stage) in ["baby", "toddler"] or not PlaceAutoTrip.can_go(f) or not Places.is_there(f, "pet_care"):
			continue
		var w: float = 0.6 if str(f.age_stage) == "child" else 1.0
		for t in (pc.get("traits", {}) as Dictionary):
			if f.has_trait(str(t)):
				w *= float(pc["traits"][t])
		who.append(f)
		ws.append(w)
	return PlaceAutoGate._weighted(who, ws)
