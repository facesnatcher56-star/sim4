class_name CarActs
extends RefCounted
## Task 53: other people's cars. Right-clicking a parked car that is not yours offers what a person standing at it could physically try: the door. Whether it
## is locked, has keys in it or an alarm is hidden until tried (stable per car and day, data/cars.json). Once the door is found locked: pick it, break a window.
## Inside: search it, hotwire it (SkillCheck "hotwire"), and once it runs, drive off: that is car theft. Every act makes its own noise; whoever is really there
## and notices (Notice: the owner at home, passers-by) reacts by their own nature, and the player answers. A taken car becomes the pawn's to drive (flagged
## stolen: no papers to sell it); a witness reports it at once, otherwise it is found missing hours later, and the case runs through justice.
##   CarActs.entries(f, car)   car: {key, lot, pos: Vector2, glb} from the vehicle view      CarActs.held(key) (the view keeps that car parked)

static var known_locked: Dictionary = {}          # "fid|key" -> true
static var opened: Dictionary = {}                # key -> day: unlocked / broken into today
static var inside: Dictionary = {}                # fid -> key
static var running: Dictionary = {}               # key -> true: started (keys or hotwired)
static var searched: Dictionary = {}              # key -> day
static var taken: Dictionary = {}                 # key -> car id (Transport.cars)
static var seen_by: Dictionary = {}               # key -> noticer id (a witness while working at it)
static var pending: Dictionary = {}               # fid -> {key, then: Callable}: walking up to the car
static var reports: Array = []                    # [{case, due_min}] a theft that will be found out

static func reset() -> void:
	known_locked = {}
	opened = {}
	inside = {}
	running = {}
	searched = {}
	taken = {}
	seen_by = {}
	pending = {}
	reports = []

static func cfg() -> Dictionary:
	return SysUtil.table("cars")

static func _line(k: String, vars: Dictionary = {}) -> String:
	var lines: Array = cfg().get("lines", {}).get(k, [""])
	var t: String = str(lines[PlayerPrompt._pick("car|" + k, lines.size())])
	for v in vars:
		t = t.replace("{%s}" % v, str(vars[v]))
	return t

static func _frac(key: String, salt: String) -> float:
	return float(absi(hash("%s|%d|%s" % [key, SysUtil.day(), salt])) % 1000) / 1000.0

static func is_locked(key: String) -> bool:
	if int(opened.get(key, -1)) == SysUtil.day():
		return false
	var c: Dictionary = cfg().get("locked", {})
	return _frac(key, "lock") < float(c.get("night" if DoorActs.night() else "day", 0.8))

static func has_alarm(key: String) -> bool:
	return _frac(key, "alarm") < float(cfg().get("alarm", 0.25))

static func held(key: String) -> bool:
	if inside.values().has(key) or taken.has(key):
		return true
	for p in pending.values():
		if str(p["key"]) == key:
			return true
	return false

static func own_car(f, car: Dictionary) -> bool:
	var key: String = str(car.get("key", ""))
	if not key.begins_with("car:"):
		return false
	var c: Dictionary = Transport.cars.get(key.get_slice(":", 1), {})
	return not c.is_empty() and int(c.get("hid", -1)) == int(f.household_id)

## Owners: the residents of the townie home the car stands at (at a shop or a park the owner is somewhere else).
static func owners(car: Dictionary) -> Array:
	var lot: String = str(car.get("lot", ""))
	if str(Neighborhood.lot(lot).get("type", "")) != "townie_home":
		return []
	return Neighborhood.residents_of(lot).map(func(t): return int(t["id"]))

static func _scene(car: Dictionary) -> String:
	var lot: String = str(car.get("lot", ""))
	return DoorActs.scene_of(lot) if str(Neighborhood.lot(lot).get("type", "")) == "townie_home" else "street"

static func _tile(car: Dictionary) -> Vector2i:
	var p: Vector2 = car.get("pos", Vector2.ZERO)
	var w = WorldIface.world()
	var c := Vector2i(floori(p.x), floori(p.y))
	if w == null:
		return c
	for rad in 4:
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) == rad and w.is_walkable(c + Vector2i(dx, dy)):
					return c + Vector2i(dx, dy)
	return c

static func _entry(id: String, label: String, fn: Callable) -> Dictionary:
	return {"id": id, "label": label, "category": "Car", "enabled": true, "reason": "", "action": fn}

static func entries(f, car: Dictionary) -> Array:
	var key: String = str(car.get("key", ""))
	if key == "" or own_car(f, car) or taken.has(key):
		return []
	var fid: int = int(f.id)
	var out: Array = []
	if str(inside.get(fid, "")) == key:
		if running.has(key):
			out.append(_entry("car_drive", "Drive off", func(): drive_off(f, car)))
		else:
			out.append(_entry("car_search", "Search the car", func(): search(f, car)))
			out.append(_entry("car_hotwire", "Hotwire it", func(): hotwire(f, car)))
		out.append(_entry("car_out", "Get out", func(): inside.erase(fid)))
		return out
	out.append(_entry("car_try", "Try the door", func(): _go(f, car, func(): try_door(f, car))))
	if bool(known_locked.get("%d|%s" % [fid, key], false)) and is_locked(key):
		out.append(_entry("car_pick", "Pick the lock", func(): _go(f, car, func(): pick(f, car))))
		out.append(_entry("car_window", "Break a window", func(): _go(f, car, func(): window(f, car))))
	return out

# ------------------------------------------------------------------ walking up to it
static func _go(f, car: Dictionary, then: Callable) -> void:
	var t: Vector2i = _tile(car)
	if f.tile == t or not NeighborhoodLots.walk_to(f, t, ""):
		then.call()
		return
	pending[int(f.id)] = {"key": str(car["key"]), "then": then}

static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	if iid != "go_here" or not pending.has(folk_id):
		return
	var p: Dictionary = pending[folk_id]
	pending.erase(folk_id)
	if success:
		(p["then"] as Callable).call()

# ------------------------------------------------------------------ the acts
static func try_door(f, car: Dictionary) -> void:
	var key: String = str(car["key"])
	if is_locked(key):
		known_locked["%d|%s" % [int(f.id), key]] = true
		SysUtil.notify(_line("locked"), "story")
		_noticed(f, car, 0.05, 0.5)
		return
	SysUtil.notify(_line("open"), "story")
	_get_in(f, car)

static func _get_in(f, car: Dictionary) -> void:
	inside[int(f.id)] = str(car["key"])
	_noticed(f, car, 0.1, 0.6)

static func pick(f, car: Dictionary) -> void:
	TimedAttempt.start(f, "car_lock", "Working the car lock", {"scene": _scene(car), "wants": "unseen"}, func(r):
		_noticed(f, car, float(r["noise"]), 0.6, float(r["minutes"]))
		if bool(r["ok"]):
			opened[str(car["key"])] = SysUtil.day()
			SysUtil.notify(_line("open"), "story")
			_get_in(f, car)
		elif str(r["grade"]) != "catastrophic":
			SysUtil.notify(_line("pick_fail"), "story"))

static func window(f, car: Dictionary) -> void:
	TimedAttempt.start(f, "car_window", "Breaking the car window", {"scene": _scene(car)}, func(r):
		var key: String = str(car["key"])
		var noise: float = float(r["noise"])
		if has_alarm(key):
			SysUtil.notify(_line("alarm"), "bad")
			noise = 1.0
		CrimePetty.commit("vandalism", int(f.id), _scene(car), {"seen": seen_by.has(key), "trace": float(r["trace"])})
		_noticed(f, car, noise, 0.8, float(r["minutes"]))
		if bool(r["ok"]):
			opened[key] = SysUtil.day()
			SysUtil.notify(_line("window_ok"), "story")
			_get_in(f, car)
		elif str(r["grade"]) != "catastrophic":
			SysUtil.notify(_line("window_fail"), "story"))

static func search(f, car: Dictionary) -> void:
	var key: String = str(car["key"])
	if int(searched.get(key, -1)) == SysUtil.day():
		SysUtil.notify(_line("searched_none"), "story")
		return
	searched[key] = SysUtil.day()
	var found: bool = false
	if _frac(key, "keys") < float(cfg().get("keys_inside", 0.03)):
		running[key] = true
		SysUtil.notify(_line("searched_keys"), "story")
		found = true
	var cc: Array = cfg().get("coins_inside", [0.3, 2, 15])
	if _frac(key, "coins") < float(cc[0]):
		var n: int = int(cc[1]) + int(_frac(key, "coins_n") * float(int(cc[2]) - int(cc[1])))
		Economy.deposit(int(f.household_id), n, "found in a car")
		SysUtil.notify(_line("searched_coins", {"c": n}), "story")
		found = true
	if not found:
		SysUtil.notify(_line("searched_none"), "story")
	_noticed(f, car, 0.05, 0.5)

static func hotwire(f, car: Dictionary) -> void:
	TimedAttempt.start(f, "hotwire", "Hotwiring", {"scene": _scene(car), "wants": "unseen"}, func(r):
		_noticed(f, car, float(r["noise"]), 0.5, float(r["minutes"]))
		if bool(r["ok"]):
			running[str(car["key"])] = true
			SysUtil.notify(_line("started"), "story")
		elif str(r["grade"]) != "catastrophic":
			SysUtil.notify(_line("hotwire_fail"), "story"))

## Taking it: the car becomes the pawn's household's to drive (stolen), the parked body becomes that car, and a car theft case starts.
static func drive_off(f, car: Dictionary) -> void:
	var key: String = str(car["key"])
	var glb: String = str(car.get("glb", "car_hatchback"))
	var model: String = "hatch"
	var mg: Dictionary = cfg().get("model_of_glb", {})
	for g in mg:
		if glb.begins_with(str(g)):
			model = str(mg[g])
	var d: Dictionary = Transport.model_def(model)
	var id: int = Transport.seq
	Transport.seq += 1
	var c: Dictionary = {"id": id, "hid": int(f.household_id), "model": model, "glb": glb, "plate": TransportCars.new_plate(), "fuel": float(d.get("tank", 40)) * (0.2 + _frac(key, "fuel") * 0.6),
		"cond": 0.8, "at": str(car.get("lot", "")), "spot": "drive", "bought": SysUtil.day(), "wreck": false, "ready_day": -1, "towed": false, "pound_day": -1, "trips": 0, "stolen": true, "from": key}
	Transport.cars[str(id)] = c
	taken[key] = id
	inside.erase(int(f.id))
	SysUtil.game_event("car_taken", {"key": key, "car": id, "folk_id": int(f.id)})
	var own: Array = owners(car)
	var witness: int = int(seen_by.get(key, -1))
	var cs: Dictionary = CaseStore.create("car_theft", int(f.id), int(own[0]) if not own.is_empty() else -1, _scene(car),
		{"witnessed": witness >= 0, "witnesses": [witness] if witness >= 0 else [], "witness_clarity": 0.6 if witness >= 0 else 0.0, "trace": 0.25, "loot_value": TransportCars.value(c)})
	CrimePlace.place_at_scene(int(f.id), _scene(car))
	if witness >= 0:
		CaseDiscovery.report(cs, witness, "saw")
	else:
		var hr: Array = cfg().get("discover_hours", [1, 6])
		reports.append({"case": int(cs["id"]), "due_min": SysUtil.now() + 60 * SysUtil.rng.randi_range(int(hr[0]), int(hr[1]))})
	SysUtil.notify(_line("drive"), "story")

static func on_hour() -> void:
	if reports.is_empty():
		return
	var keep: Array = []
	for r in reports:
		if int(r["due_min"]) > SysUtil.now():
			keep.append(r)
			continue
		var cs: Dictionary = CaseStore.get_case(int(r["case"]))
		if not cs.is_empty():
			CaseDiscovery.report(cs, int(cs.get("victim", -1)), "found")
	reports = keep

# ------------------------------------------------------------------ somebody notices
## Who is really there notices by their own senses (Notice); the owner at home may glance out (owner_looks, less at night) or hear it.
## The first one to notice reacts; the player answers.
static func _noticed(f, car: Dictionary, noise: float, visibility: float, minutes: float = 1.0) -> void:
	var key: String = str(car["key"])
	var fid: int = int(f.id)
	var own: Array = owners(car)
	var who: Array = Notice.who(fid, _tile(car), {"noise": noise, "visibility": clampf(visibility * sqrt(maxf(minutes, 1.0)) / 2.0, 0.0, 1.0), "unseen": true})
	var nid: int = -1
	if not who.is_empty():
		nid = int(who[0]["id"])
	else:
		var look: float = float(cfg().get("owner_looks", 0.2)) * (0.5 if DoorActs.night() else 1.0)
		for t in DoorActs.awake_residents(str(car.get("lot", ""))):
			if SysUtil.rng.randf() < maxf(look, noise * 0.6):
				nid = int(t["id"])
				break
	if nid < 0:
		return
	seen_by[key] = nid
	var re: Dictionary = Notice.react(nid, fid, "car", "owner" if own.has(nid) else "passerby")
	if str(re["id"]) == "ignore":
		return
	SysUtil.notify(str(re["line"]), "bad")
	match str(re["id"]):
		"call":
			CrimePetty.commit("trespassing", fid, _scene(car), {"seen": true})
		"fight":
			var r: Dictionary = SkillCheck.attempt(fid, "fight", {"opponent": nid})
			if not bool(r["ok"]):
				Health.injure(f, 1, "fight")
			inside.erase(fid)
		_:
			JusticePlayer.ask(fid, "At the car", str(re["line"]),
				[{"id": "walk", "label": "Walk away"}, {"id": "run", "label": "Run"}, {"id": "lie", "label": "Say it's a friend's car"}, {"id": "stay", "label": "Ignore them"}],
				func(ch): _answer(f, car, nid, str(ch)), "walk")

static func _answer(f, car: Dictionary, nid: int, ch: String) -> void:
	var fid: int = int(f.id)
	var nm: String = SysUtil.folk_name(nid)
	match ch:
		"walk", "run":
			inside.erase(fid)
			var away: Interaction = Interaction.create_goto(f, _tile(car) + Vector2i(0, 6 if ch == "run" else 3), true, 0)
			if away != null:
				f.enqueue(away)
			if ch == "run":
				CrimePetty.commit("trespassing", fid, _scene(car), {"seen": true})
		"lie":
			var r: Dictionary = SkillCheck.attempt(fid, "lie", {"opponent": nid})
			if bool(r["ok"]):
				seen_by.erase(str(car["key"]))
				SysUtil.notify("%s shrugs and moves on." % nm, "story")
			else:
				SysUtil.notify("%s doesn't buy it, and takes out a phone." % nm, "bad")
				CrimePetty.commit("trespassing", fid, _scene(car), {"seen": true})
		_:
			SysUtil.notify("%s takes out a phone." % nm, "bad")
			CrimePetty.commit("trespassing", fid, _scene(car), {"seen": true})
