class_name CruiseCrew
extends RefCounted
## Who is aboard besides the party (task 22): the CREW (staff Folk at their posts: captain, waiters, bartenders, entertainer, cleaner, medical
## officer, security, lifeguard; data/destinations/ship.json "posts", capped by cruise_ship.json ship.crew_cap) and the PASSENGERS (a few real
## Story townies on holiday, plus the party's invited friends). Both are roster entries in trip["roster"], materialised as Folk by
## VacationLife.ensure_npcs and respawned after a load. Crew ids 7600+, passengers keep their townie id.
## Tier: crew stand at their posts (a long staff interaction, no autonomy); passengers are crowd-style (CrowdDrive picks their activities).
## Caps: crew_cap (11) + passengers (8) per ship.

const CREW_ID_BASE := 7600

static func cfg() -> Dictionary:
	return CruiseRoute.cfg()

static func start(t: Dictionary) -> void:
	var r := Vacation.rng_for(t)
	var rc := DestLoader.zone_rect(int(t["zone"]))
	var roster: Array = []
	var s: Dictionary = CruiseRoute.ship()
	var crew_defs: Dictionary = cfg().get("crew", {})
	var posts: Array = DestLoader.posts("ship", rc)
	var chosen: Array = []
	var seen: Dictionary = {}
	for p in posts:                                  # one of every role first, then the rest up to the cap
		if not seen.has(p["role"]):
			seen[p["role"]] = true
			chosen.append(p)
	for p2 in posts:
		if chosen.size() >= int(s.get("crew_cap", 11)):
			break
		if not chosen.has(p2):
			chosen.append(p2)
	var names: Array = Story.cfg().get("first_names", ["Sam"])
	var lasts: Array = Story.cfg().get("last_names", ["Reed"])
	var idx: int = 0
	for p3 in chosen:
		var role: String = str(p3["role"])
		var cd: Dictionary = crew_defs.get(role, {})
		var nm: String
		if cd.has("names"):
			nm = str((cd["names"] as Array)[r.randi_range(0, (cd["names"] as Array).size() - 1)])
		else:
			nm = "%s %s (%s)" % [names[r.randi_range(0, names.size() - 1)], lasts[r.randi_range(0, lasts.size() - 1)], str(cd.get("label", role.capitalize()))]
		roster.append({"id": CREW_ID_BASE + int(t["zone"]) * 40 + idx, "name": nm, "traits": [], "kind": "crew", "role": role, "outfit": str(cd.get("outfit", "")),
			"townie": -1, "tile": [p3["tile"].x, p3["tile"].y], "level": int(p3["level"])})
		idx += 1
	# passengers: the invited guests first, then townies chosen by the seeded stream
	var want: int = int(s.get("passengers", 8))
	var chosen_ids: Array = []
	for g in t["guests"]:
		if Story.townies.has(int(g)):
			chosen_ids.append(int(g))
	var pool: Array = []
	for tid in Story.townies.keys():
		var rec: Dictionary = Story.townies[tid]
		if not bool(rec.get("alive", false)) or chosen_ids.has(int(tid)) or SysUtil.folk(int(tid)) != null or CrimePerson.in_custody(int(tid)):
			continue
		if not (Story.stage_of(rec) in ["adult", "elder"]):
			continue
		pool.append(int(tid))
	pool.sort()
	while chosen_ids.size() < want and not pool.is_empty():
		chosen_ids.append(int(pool.pop_at(r.randi_range(0, pool.size() - 1))))
	for tid2 in chosen_ids:
		roster.append({"id": int(tid2), "name": str(Story.townies[tid2]["name"]), "traits": [], "kind": "passenger", "role": "", "outfit": "", "townie": int(tid2),
			"tile": [], "level": 0, "companion": (t["guests"] as Array).has(int(tid2))})
	t["roster"] = roster
	VacationLife.ensure_npcs(t, 40)

static func after_load(t: Dictionary) -> void:
	VacationLife.ensure_npcs(t, 40)

static func passengers(t: Dictionary) -> Array:
	var out: Array = []
	for npc in VacationLife.present_ids(t).values():
		if npc.has_meta("townie_id") and not npc.has_meta("staff"):
			out.append(npc)
	return out

static func crew(t: Dictionary, role: String = "") -> Array:
	var out: Array = []
	for npc in VacationLife.present_ids(t).values():
		if npc.has_meta("staff") and (role == "" or str(npc.get_meta("staff")) == role):
			out.append(npc)
	return out
