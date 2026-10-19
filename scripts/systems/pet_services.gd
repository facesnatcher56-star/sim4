class_name PetServices
extends RefCounted
## The handlers (PlaceHandlers) of the pet places:
##   pet      care of one pet of the household: feed, play, walk (dogs), train (dogs), groom, cuddle, and at the vet: vet (check-up) and treat (a sick pet)
##   pet_new  a new pet: adopt a stray at the pet corner, or buy a puppy or a kitten
## Which pet: `target` (the pet id, from the Pets tab); without one the first pet of the household that the care applies to. Daily limits per pet come
## from data/life/70_pets.json config.pets.care (a dog is fed three times a day at most, and so on). Care builds the BOND; the bond is why a pet stays.

static func care() -> Dictionary:
	return PetState.cfg().get("care", {})

static func owner() -> Dictionary:
	return PetState.cfg().get("owner", {})

## The pet this service is for, or {}.
static func pick(f, target: int, act: String) -> Dictionary:
	var mine: Array = PetState.of_household(int(f.household_id))
	if target >= 0:
		var p: Dictionary = PetState.get_pet(target)
		return p if not p.is_empty() and int(p["hid"]) == int(f.household_id) else {}
	for p in mine:
		if act == "walk" and not bool(PetState.species_def(str(p["species"])).get("walk", false)):
			continue
		if act == "train" and not bool(PetState.species_def(str(p["species"])).get("tricks", false)):
			continue
		if act == "treat" and not bool(p["sick"]):
			continue
		return p
	return {}

static func check(handler: String, f, _pid: String, _sid: String, svc: Dictionary) -> String:
	var a: Dictionary = svc.get("args", {})
	if handler == "pet_new":
		var hid: int = int(f.household_id)
		if str(a.get("act", "")) == "stray" and PetState.strays.is_empty():
			return "There are no strays at the pet corner right now."
		if PetState.of_household(hid).size() >= int(PetState.cfg().get("max_per_household", 3)):
			return "That is enough pets for one home."
		return ""
	var act: String = str(a.get("act", ""))
	var p: Dictionary = pick(f, int(svc.get("_target", -1)), act)
	if p.is_empty():
		return "There is no pet at home for that." if PetState.of_household(int(f.household_id)).is_empty() else "None of the pets can do that now."
	var sd: Dictionary = PetState.species_def(str(p["species"]))
	var c: Dictionary = PetState.counter(int(p["id"]))
	var cc: Dictionary = care()
	match act:
		"feed":
			if int(c["feed"]) >= int(cc.get("feed_cap", 3)) or float(p["fullness"]) > 85.0:
				return "%s is not hungry." % p["name"]
		"play":
			if int(c["play"]) >= int(cc.get("play_cap", 2)):
				return "%s has played enough today." % p["name"]
		"walk":
			if not bool(sd.get("walk", false)):
				return "%ss do not go for walks." % str(sd.get("label", "pet")).capitalize()
			if int(c["walk"]) >= int(cc.get("walk_cap", 2)) or bool(p["sick"]):
				return "%s is not up to a walk." % p["name"]
		"train":
			if not bool(sd.get("tricks", false)):
				return "%ss do not learn tricks." % str(sd.get("label", "pet")).capitalize()
			if int(p["tricks"]) >= int(cc.get("tricks_max", 5)):
				return "%s knows every trick." % p["name"]
			if int(c["train"]) >= int(cc.get("train_cap", 2)) or float(p["bond"]) < float(cc.get("train_bond_min", 20.0)):
				return "%s is not ready to learn (the bond has to grow first)." % p["name"] if float(p["bond"]) < float(cc.get("train_bond_min", 20.0)) else "%s has trained enough today." % p["name"]
		"groom":
			if int(c["groom"]) >= int(cc.get("groom_cap", 1)):
				return "%s is already tidy." % p["name"]
		"cuddle":
			if int(c["cuddle"]) >= int(cc.get("cuddle_cap", 3)):
				return "%s has had enough cuddles." % p["name"]
		"treat":
			if not bool(p["sick"]):
				return "%s is not sick." % p["name"]
	return ""

static func finish(handler: String, f, _pid: String, _sid: String, svc: Dictionary) -> Dictionary:
	var a: Dictionary = svc.get("args", {})
	var hid: int = int(f.household_id)
	if handler == "pet_new":
		return _new(f, hid, a)
	var act: String = str(a.get("act", ""))
	var p: Dictionary = pick(f, int(svc.get("_target", -1)), act)
	if p.is_empty():
		return {}
	var c: Dictionary = PetState.counter(int(p["id"]))
	var cc: Dictionary = care()
	var oc: Dictionary = owner()
	var pname: String = str(p["name"])
	match act:
		"feed":
			c["feed"] = int(c["feed"]) + 1
			p["fullness"] = minf(float(p["fullness"]) + float(cc.get("feed_fullness", 45.0)), 100.0)
			p["bond"] = minf(float(p["bond"]) + float(cc.get("bond_feed", 0.5)), 100.0)
			return {"text": "%s fed %s, who ate every scrap." % [f.name, pname]}
		"play":
			c["play"] = int(c["play"]) + 1
			p["fun"] = minf(float(p["fun"]) + float(cc.get("play_fun", 30.0)), 100.0)
			p["bond"] = minf(float(p["bond"]) + float(cc.get("bond_play", 1.5)), 100.0)
			f.add_to_stat("fun", float(oc.get("play_fun", 10.0)))
			f.add_to_stat("social", float(oc.get("play_social", 6.0)))
			return {"text": "%s played with %s until they were both worn out." % [f.name, pname]}
		"walk":
			c["walk"] = int(c["walk"]) + 1
			p["fun"] = minf(float(p["fun"]) + float(cc.get("walk_fun", 40.0)), 100.0)
			p["bond"] = minf(float(p["bond"]) + float(cc.get("bond_walk", 2.0)), 100.0)
			f.add_to_stat("social", float(oc.get("walk_social", 8.0)))
			HealthLife.add_meter(int(f.id), "fitness", float(oc.get("walk_fitness", 1.2)))
			f.add_buff("venue_fresh_air")
			return {"text": "%s took %s for a long walk." % [f.name, pname]}
		"train":
			c["train"] = int(c["train"]) + 1
			var p_ok: float = clampf(0.35 + float(p["bond"]) / 200.0 + 0.04 * float(f.skill_level("charisma")), 0.2, 0.95)
			if PetState.rng.randf() < p_ok:
				p["tricks"] = int(p["tricks"]) + 1
				p["bond"] = minf(float(p["bond"]) + 1.0, 100.0)
				return {"text": "%s taught %s a new trick (%d of %d)." % [f.name, pname, int(p["tricks"]), int(cc.get("tricks_max", 5))]}
			return {"text": "%s tried to teach %s a trick. Not today." % [f.name, pname]}
		"groom":
			c["groom"] = int(c["groom"]) + 1
			p["bond"] = minf(float(p["bond"]) + 0.8, 100.0)
			p["health"] = minf(float(p["health"]) + 2.0, 100.0)
			return {"text": "%s brushed %s until the coat shone." % [f.name, pname]}
		"cuddle":
			c["cuddle"] = int(c["cuddle"]) + 1
			p["bond"] = minf(float(p["bond"]) + float(cc.get("bond_cuddle", 1.0)), 100.0)
			f.add_to_stat("comfort", float(oc.get("cuddle_comfort", 8.0)))
			f.add_to_stat("social", float(oc.get("cuddle_social", 8.0)))
			return {"text": "%s had a cuddle with %s." % [f.name, pname]}
		"vet":
			p["vet_day"] = SysUtil.day()
			p["health"] = minf(float(p["health"]) + 20.0, 100.0)
			var sick_now: bool = bool(p["sick"])
			if sick_now:
				p["sick"] = false
				p["sick_days"] = 0
			return {"text": "The vet gave %s a check-up%s." % [pname, " and cured the illness" if sick_now else ". Healthy and happy"]}
		"treat":
			p["sick"] = false
			p["sick_days"] = 0
			p["health"] = minf(float(p["health"]) + 25.0, 100.0)
			p["vet_day"] = SysUtil.day()
			return {"text": "The vet treated %s, who is already wagging and purring again." % pname}
	return {}

static func _new(f, hid: int, a: Dictionary) -> Dictionary:
	if str(a.get("act", "")) == "stray":
		var s: Dictionary = PetState.strays.pop_front()
		var p: Dictionary = PetState.add_pet(hid, str(s["species"]), str(s["name"]), 40.0)
		p["bond"] = 15.0
		p["fullness"] = 40.0
		LifeNote.say("pet_adopted", "%s adopted a stray %s called %s." % [f.name, PetState.species_def(str(s["species"])).get("label", "pet"), s["name"]], [int(f.id)], 1, false)
		return {"text": "%s took in a stray %s called %s." % [f.name, PetState.species_def(str(s["species"])).get("label", "pet"), s["name"]]}
	var sp: String = str(a.get("species", "dog"))
	var p2: Dictionary = PetState.add_pet(hid, sp)
	return {"text": "%s brought home a %s called %s." % [f.name, "puppy" if sp == "dog" else "kitten", p2["name"]]}
