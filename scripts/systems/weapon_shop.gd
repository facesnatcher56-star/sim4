class_name WeaponShop
extends RefCounted
## Task 57: how weapons reach people in normal play, around the owner's WeaponPermits / WeaponActs (data/weapons.json):
##   the real shops sell them by their `sources` (shops.json: the hardware store, the market, the sporting goods counter, the gun counter);
##   at the gun counter the till checks the permit (WeaponPermits.has, the age) and a sale registers the gun to the buyer;
##   under the counter, a fence or the crew sells the underground ones: unregistered, dearer (underground.markup), sometimes tied to an old case;
##   a pickpocket or a mugging can lift a carried weapon (PersonActs);
##   the permit desks: "Gun permit" at the police station front desk, "Hunting licence" at city hall (WeaponPermits.apply after paying);
##   the screening posts: the courthouse, city hall and bank doors search the pawn on the way in (WeaponPermits.searched).
##   WeaponShop.why_not(fid, it)   receive(pid, iid, it)   underground(pid)   buy_underground(pid, wid)   lift(victim, thief, pocket_only)
##   permit_entries(f, target)     on_minute()

const PERMIT_LOT := {"police_station": "police", "city_hall": "city_hall"}
const SCREEN_TYPES := ["courthouse", "city_hall", "bank"]

static var _last_lot: Dictionary = {}          # pid -> the lot they were last on (a search happens on the way in)
static var _posed: Dictionary = {}             # task 57b: pid -> game minute until which the threat / aim pose holds

static func reset() -> void:
	_last_lot = {}
	_posed = {}

# ------------------------------------------------------------------ the body (task 57b)
## WeaponActs: a threat, a demand or an attack with the weapon holds the threat / aim pose for a little while.
static func posed(pid: int, _aid: String) -> void:
	_posed[pid] = SysUtil.now() + 3

## The grip of the weapon a person holds out: "" none, else one | knuckles | pistol | long (weapons.json hold).
static func grip_of(pid: int) -> String:
	for e in Inventory.items(pid):
		if bool(e.get("shown", false)):
			var hd: Dictionary = (cfg().get("hold", {}) as Dictionary).get(str(e["id"]), {})
			if not hd.is_empty():
				return str(hd.get("grip", "one"))
	return ""

## The clip of a standing person with a weapon out (FolkView), "" for none.
static func clip_of(pid: int) -> String:
	var g: String = grip_of(pid)
	if g == "":
		return ""
	var using: bool = SysUtil.now() <= int(_posed.get(pid, -1))
	match g:
		"pistol":
			return "Threaten_Pistol" if using else "Hold_Pistol"
		"long":
			return "Aim_Long" if using else "Hold_Long"
	return "Threaten_1H" if using else "Hold_1H"


static func cfg() -> Dictionary:
	return SysUtil.table("weapons")

# ------------------------------------------------------------------ the gun counter
## The till's check for a gun or rounds: the permit the weapon needs, and the age. "" = may buy.
static func why_not(fid: int, it: Dictionary) -> String:
	if not (str(it.get("kind", "")) in ["gun", "ammo"]):
		return ""
	if WeaponPermits.under_21(fid):
		return "The counter only sells to adults."
	var permit: String = str(it.get("permit", "gun"))
	if not WeaponPermits.has(fid, permit):
		return "The counter needs to see your %s first." % str(WeaponPermits.def(permit).get("label", "permit")).to_lower()
	return ""

## The goods reach the buyer: a gun is registered to them, rounds come by the box.
static func receive(pid: int, iid: String, it: Dictionary) -> void:
	match str(it.get("kind", "")):
		"gun":
			Inventory.add(pid, iid)
			WeaponPermits.register_gun(pid, iid)
		"ammo":
			Inventory.add(pid, iid, {"stack": true, "n": int((cfg().get("ammo", {}) as Dictionary).get(iid, {}).get("per_box", 10))})

# ------------------------------------------------------------------ under the counter
## Who sells to this person off the books: a fence they know, else their crew. -1 = nobody.
static func seller(pid: int) -> int:
	var fences: Array = CrimeLifeFence.fences_for(pid)
	if not fences.is_empty():
		return int(fences[0])
	if SoloPressure.member and Pawn.is_pawn_id(pid):
		for t in Story.alive_townies():
			if CrimeLifePath.is_member(int(t["id"])):
				return int(t["id"])
	return -1

## [{id, label, price}] the underground has (weapons with source "underground", and rounds for its guns).
static func underground(pid: int) -> Array:
	if seller(pid) < 0:
		return []
	var mk: float = float((cfg().get("underground", {}) as Dictionary).get("markup", 1.6))
	var out: Array = []
	var w: Dictionary = cfg().get("weapons", {})
	for id in w:
		if (w[id].get("sources", []) as Array).has("underground"):
			out.append({"id": str(id), "label": str(w[id]["label"]), "price": int(round(float(w[id].get("price", 0)) * mk))})
			var ammo: String = str(w[id].get("ammo", ""))
			if ammo != "" and not out.any(func(x): return str(x["id"]) == ammo):
				var ad: Dictionary = (cfg().get("ammo", {}) as Dictionary).get(ammo, {})
				out.append({"id": ammo, "label": "A box of %s" % str(ad.get("label", ammo)).to_lower(), "price": int(round(float(ad.get("price", 15)) * mk))})
	return out

static func buy_underground(pid: int, wid: String) -> Dictionary:
	var row: Array = underground(pid).filter(func(x): return str(x["id"]) == wid)
	if row.is_empty():
		return {"ok": false, "msg": "Nobody you know can get that."}
	var price: int = int(row[0]["price"])
	if CrimePerson.coins(pid) < price:
		return {"ok": false, "msg": "Not enough coins."}
	CrimePerson.pay(pid, price, "bought under the counter")
	var ad: Dictionary = (cfg().get("ammo", {}) as Dictionary).get(wid, {})
	if not ad.is_empty():
		Inventory.add(pid, wid, {"stack": true, "n": int(ad.get("per_box", 10))})
		return {"ok": true, "msg": "%s hands over a box, no questions asked." % CrimePerson.name_of(seller(pid))}
	var dirty: int = -1
	if SysUtil.rng.randf() < float((cfg().get("underground", {}) as Dictionary).get("dirty_chance", 0.25)):
		var old: Array = JusticeState.cases.values().filter(func(c): return str(c.get("state", "")) in ["open", "cold"] and str(c.get("kind", "")) in ["assault", "robbery", "murder", "attempted_murder"])
		if not old.is_empty():
			dirty = int(old[SysUtil.rng.randi_range(0, old.size() - 1)]["id"])          # the gun already has a past
	Inventory.add(pid, wid, {"dirty_case": dirty})
	CrimeLifePath.add_cred(pid, 0.5)
	return {"ok": true, "msg": "%s sells you a %s, wrapped in a towel." % [CrimePerson.name_of(seller(pid)), str(row[0]["label"]).to_lower()]}

# ------------------------------------------------------------------ taken from a person
## A pickpocket (pocket only) or a mugging can lift what the victim carries. Returns the label taken, "" for nothing.
static func lift(victim: int, thief: int, pocket_only: bool) -> String:
	for e in Inventory.items(victim):
		var d: Dictionary = WeaponPermits.def_weapon(str(e["id"]))
		if d.is_empty() or (pocket_only and str(d.get("conceal", "none")) != "pocket"):
			continue
		var taken: Dictionary = Inventory.take(victim, str(e["id"]))
		var ne: Dictionary = Inventory.add(thief, str(taken["id"]), {"ammo": int(taken.get("ammo", 0)), "dirty_case": int(taken.get("dirty_case", -1))})
		ne["registered_to"] = int(taken.get("registered_to", -1))          # still registered to its owner: a stolen gun
		ne["serial"] = int(taken.get("serial", ne["serial"]))
		return str(d.get("label", e["id"])).to_lower()
	return ""

# ------------------------------------------------------------------ the permit desks
static func permit_entries(f, target) -> Array:
	if f == null or target == null or not Pawn.is_pawn(f) or not (target is Folk) or str(target.get_meta("staff", "")) == "":
		return []
	var lot: String = Neighborhood.lot_of(target)
	var out: Array = []
	var perms: Dictionary = cfg().get("permits", {})
	for pid in perms:
		var d: Dictionary = perms[pid]
		if str(PERMIT_LOT.get(str(d.get("where", "")), str(d.get("where", "")))) != lot:
			continue
		var held: bool = WeaponPermits.has(int(f.id), str(pid))
		var price: int = int(d.get("price", 0))
		out.append({"id": "permit_" + str(pid), "label": "Apply for a %s (%d coins)" % [str(d["label"]).to_lower(), price], "category": "Ask",
			"enabled": not held, "reason": "You already have one." if held else "",
			"action": func(): WalkThen.go(f, WalkThen.near(target.tile), func(): apply_at_desk(f, str(pid)))})
	return out

static func apply_at_desk(f, permit_id: String) -> void:
	var d: Dictionary = WeaponPermits.def(permit_id)
	var price: int = int(d.get("price", 0))
	var why: String = WeaponPermits.refused(int(f.id), permit_id)
	if why == "" and not Economy.spend(int(f.household_id), price, str(d.get("label", "permit")).to_lower()):
		SysUtil.notify("The fee is %d coins. You don't have it." % price, "warn")
		return
	WeaponPermits.apply(int(f.id), permit_id)          # refused or granted after its wait days; it says so itself

# ------------------------------------------------------------------ screening at the door
## The pawn walks onto a lot with a screening post: their bag is checked once on the way in.
static func on_minute() -> void:
	var f = SysUtil.folk(Pawn.of())
	if f == null or SysUtil.is_away(f):
		return
	var pid: int = int(f.id)
	var lot: String = NeighborhoodLots.lot_at(f.tile)
	if lot == str(_last_lot.get(pid, "")):
		return
	_last_lot[pid] = lot
	if lot == "" or not (Venues.type_of_lot(lot) in SCREEN_TYPES) or StaffPosts.front(lot).is_empty():
		return
	if not Inventory.items(pid).any(func(e): return not WeaponPermits.def_weapon(str(e["id"])).is_empty()):
		return
	var r: Dictionary = WeaponPermits.searched(pid, Venues.type_of_lot(lot))
	if (r["found"] as Array).is_empty():
		return
	var what: String = str(WeaponPermits.def_weapon(str(r["found"][0])).get("label", "it")).to_lower()
	if (r["charges"] as Array).is_empty():
		SysUtil.notify("Security checks your bag at the door and waves the %s through." % what if not WeaponPermits.place_forbids(Venues.type_of_lot(lot))
			else "Security finds the %s at the door and holds it until you leave." % what, "story")
	else:
		SysUtil.notify("Security finds the %s at the door." % what, "bad")

static func busy() -> bool:
	return Pawn.of() >= 0
