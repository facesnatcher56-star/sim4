class_name PetDay
extends RefCounted
## The daily life of the pets (task 14): needs fall, a hungry pet may fall ill (and gets worse untreated), a pet that goes hungry for days runs away, old pets
## die, content pets cheer their owners (buff pet_company), and once a week a stray may turn up around town (and strays that nobody takes move on).
## Tier: household, daily; one dice or two per pet. Strays: town level, weekly, cap 3.

static func on_day(day: int) -> void:
	var dc: Dictionary = PetState.cfg().get("daily", {})
	for id in PetState.pets.keys():
		_pet_day(PetState.pets[id], dc)
	for hid in _households():
		if PetState.has_content_pet(hid):
			for f in SysUtil.residents():
				if int(f.household_id) == hid and not SysUtil.is_away(f):
					f.add_buff(str(dc.get("content_buff", "pet_company")))
	_strays(day)

static func _households() -> Array:
	var out: Array = []
	for id in PetState.pets:
		var h: int = int(PetState.pets[id]["hid"])
		if not out.has(h):
			out.append(h)
	out.sort()
	return out

static func _pet_day(p: Dictionary, dc: Dictionary) -> void:
	var sd: Dictionary = PetState.species_def(str(p["species"]))
	p["fullness"] = maxf(float(p["fullness"]) - float(sd.get("fullness_drop", 30.0)), 0.0)
	p["fun"] = maxf(float(p["fun"]) - float(sd.get("fun_drop", 20.0)), 0.0)
	if float(p["fullness"]) <= 0.0:
		p["hungry_days"] = int(p["hungry_days"]) + 1
		p["bond"] = maxf(float(p["bond"]) - float(dc.get("bond_loss_neglect", 2.0)), 0.0)
	else:
		p["hungry_days"] = 0
	var pname: String = str(p["name"])
	var owner_name: String = _owner(int(p["hid"]))
	if int(p["hungry_days"]) >= int(dc.get("runaway_hungry_days", 3)):
		PetState.pets.erase(int(p["id"]))
		LifeNote.say("pet_left", "%s the %s ran away from %s's home. Hungry pets do not stay." % [pname, sd.get("label", "pet"), owner_name], [], 0, false)
		_tell(int(p["hid"]), "%s the %s has run away." % [pname, sd.get("label", "pet")], "bad")
		return
	if bool(p["sick"]):
		p["sick_days"] = int(p["sick_days"]) + 1
		p["health"] = maxf(float(p["health"]) - 8.0 * float(int(p["sick_days"]) / maxi(int(dc.get("sick_days_to_worsen", 3)), 1)), 0.0)
	else:
		var chance: float = float(dc.get("sick_chance_hungry", 0.04)) if float(p["fullness"]) < 25.0 else float(dc.get("sick_chance", 0.012))
		if PetState.rng.randf() < chance:
			p["sick"] = true
			p["sick_days"] = 0
			_tell(int(p["hid"]), "%s the %s seems unwell. The vet can help." % [pname, sd.get("label", "pet")], "warn")
	var life: int = int(sd.get("lifespan_days", 150))
	if PetState.age_days(p) > life and PetState.rng.randf() < float(dc.get("old_age_chance", 0.12)):
		PetState.pets.erase(int(p["id"]))
		_tell(int(p["hid"]), "%s the %s died peacefully of old age. A good, long life." % [pname, sd.get("label", "pet")], "death")
		LifeNote.say("pet_died", "%s the %s of %s's home died of old age." % [pname, sd.get("label", "pet"), owner_name], [], 0, false)

static func _owner(hid: int) -> String:
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			return str(f.name).get_slice(" ", 1) if str(f.name).find(" ") > 0 else str(f.name)
	return "a"

static func _tell(hid: int, text: String, kind: String) -> void:
	for f in SysUtil.residents():
		if int(f.household_id) == hid:
			SysUtil.notify(text, kind)
			return

static func _strays(day: int) -> void:
	var sc: Dictionary = PetState.cfg().get("strays", {})
	PetState.strays = PetState.strays.filter(func(s): return day - int(s["day"]) <= int(sc.get("stay_days", 14)))
	if day % 7 != 0 or PetState.strays.size() >= int(sc.get("cap", 3)):
		return
	if PetState.rng.randf() >= float(sc.get("chance_per_week", 0.4)):
		return
	var sp: String = "dog" if PetState.rng.randf() < 0.5 else "cat"
	PetState.strays.append({"species": sp, "name": PetState._unused_name(sp), "day": day})
	LifeNote.news("vet_clinic", str(sc.get("news", "A stray was seen.")).replace("{species}", str(PetState.species_def(sp).get("label", sp))))
