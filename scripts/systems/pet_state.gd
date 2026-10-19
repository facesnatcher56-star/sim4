class_name PetState
extends RefCounted
## Pets (task 14): dogs and cats as household records, with needs, mood, bond to the family, training and health. There is no body on the map yet:
## the pets are cared for through the places "pet_care" (at home) and "vet_clinic" (the pet corner), and shown in the Pets tab of the Town window.
##   fullness 0..100 (falls each day, food raises it)   fun 0..100   bond 0..100   health 0..100 and a sick flag   tricks (dogs) 0..5
## Daily (PetDay): needs fall, a hungry pet may fall ill, a pet hungry for days runs away, old pets die, content pets cheer their owners (buff pet_company:
## the loss of the social need is cut), stray animals turn up around town and can be adopted at the pet corner.
## A well-kept adult dog counts as a guard dog for burglars (CrimeSecurity.home_profile asks guards_home).
## Data: data/life/70_pets.json config.pets. Tier: household, daily + care commands; strays are town-level, weekly. Saved in the `life` block (`pets`). Own seeded rng.

const SEED := 140091

static var pets: Dictionary = {}          # pet id -> record
static var strays: Array = []             # [{species, name, day}]
static var today: Dictionary = {}         # pet id -> {day, feed, play, walk, train, groom, cuddle}
static var next_id: int = 1
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	pets.clear()
	strays.clear()
	today.clear()
	next_id = 1
	rng = RandomNumberGenerator.new()
	rng.seed = SEED

static func cfg() -> Dictionary:
	return LifeDefs.cfg("pets")

static func species_def(sp: String) -> Dictionary:
	return (cfg().get("species", {}) as Dictionary).get(sp, {})

static func of_household(hid: int) -> Array:
	var out: Array = []
	for id in pets:
		if int(pets[id]["hid"]) == hid:
			out.append(pets[id])
	out.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return out

static func get_pet(id: int) -> Dictionary:
	return pets.get(id, {})

static func _unused_name(sp: String) -> String:
	var names: Array = species_def(sp).get("names", ["Buddy"])
	var taken: Array = pets.values().map(func(p): return str(p["name"])) + strays.map(func(s): return str(s["name"]))
	for i in names.size():
		var n: String = str(names[(i + rng.randi_range(0, names.size() - 1)) % names.size()])
		if not taken.has(n):
			return n
	return "%s %d" % [str(names[0]), next_id]

static func add_pet(hid: int, sp: String, nm: String = "", age_days: float = 3.0) -> Dictionary:
	if species_def(sp).is_empty():
		return {}
	var p := {"id": next_id, "hid": hid, "species": sp, "name": nm if nm != "" else _unused_name(sp), "born_day": SysUtil.day() - int(age_days),
		"fullness": 70.0, "fun": 60.0, "bond": 25.0, "health": 100.0, "sick": false, "sick_days": 0, "tricks": 0, "hungry_days": 0, "vet_day": -99}
	pets[next_id] = p
	next_id += 1
	return p

static func age_days(p: Dictionary) -> int:
	return SysUtil.day() - int(p["born_day"])

static func counter(id: int) -> Dictionary:
	var c: Dictionary = today.get(id, {})
	if int(c.get("day", -1)) != SysUtil.day():
		c = {"day": SysUtil.day(), "feed": 0, "play": 0, "walk": 0, "train": 0, "groom": 0, "cuddle": 0}
		today[id] = c
	return c

## "happy", "content", "hungry", "bored" or "unwell".
static func mood(p: Dictionary) -> String:
	if bool(p["sick"]):
		return "unwell"
	if float(p["fullness"]) < 25.0:
		return "hungry"
	if float(p["fun"]) < 25.0:
		return "bored"
	if float(p["bond"]) >= 50.0 and float(p["fullness"]) >= 50.0 and float(p["fun"]) >= 50.0:
		return "happy"
	return "content"

## A well-fed grown dog keeps burglars away: the home counts as having a guard dog.
static func guards_home(hid: int) -> bool:
	var g: Dictionary = cfg().get("guard_dog", {})
	for p in of_household(hid):
		if str(p["species"]) == "dog" and age_days(p) >= int(g.get("min_age_days", 10)) and float(p["fullness"]) >= float(g.get("min_fullness", 25)) and not bool(p["sick"]):
			return true
	return false

## Pets of the household make the people who live there less lonely.
static func has_content_pet(hid: int) -> bool:
	for p in of_household(hid):
		if mood(p) in ["happy", "content"]:
			return true
	return false

static func forget_household(hid: int) -> void:
	for p in of_household(hid):
		pets.erase(int(p["id"]))

static func to_dict() -> Dictionary:
	return {"pets": SysUtil.str_keys(pets).duplicate(true), "strays": strays.duplicate(true), "next_id": next_id, "rng_state": str(rng.state)}

static func from_dict(d: Dictionary) -> void:
	reset()
	pets = SysUtil.int_keys((d.get("pets", {}) as Dictionary).duplicate(true))
	for id in pets:
		var p: Dictionary = pets[id]
		for k in ["id", "hid", "born_day", "sick_days", "tricks", "hungry_days", "vet_day"]:
			p[k] = int(p[k])
		for k2 in ["fullness", "fun", "bond", "health"]:
			p[k2] = float(p[k2])
	strays = (d.get("strays", []) as Array).duplicate(true)
	for s in strays:
		s["day"] = int(s["day"])
	next_id = int(d.get("next_id", 1))
	if d.has("rng_state"):
		rng.state = int(str(d["rng_state"]))
