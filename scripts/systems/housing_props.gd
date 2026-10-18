class_name HousingProps
extends RefCounted
## The housing market's properties (task 13, slice 4). The 4 map houses (your home + 3 townie homes) plus a rotating set of listings (flats and
## houses elsewhere in town, statistical: no lot on the map). Owner / tenant can be a player household, a townie or the bank.
## Value = base x neighbourhood x schools x parks x condition x crime x market. Tier: town-wide, DAILY (condition, market index) + a weekly
## listing refresh. Active set: <= ~12 properties. Caps: listings.count. Data: data/housing.json. Rent/eviction: HousingRent. Player actions: HousingAgent.

static var props: Dictionary = {}       # id -> prop dict (see make())
static var value_idx: float = 1.0       # the housing market index
static var next_refresh: int = 0
static var _seq: int = 1
static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

static func reset() -> void:
	props.clear()
	value_idx = 1.0
	next_refresh = 0
	_seq = 1
	rng = RandomNumberGenerator.new()
	rng.seed = 130041

static func cfg() -> Dictionary:
	return SysUtil.table("housing")

static func make(id: String, label: String, kind: String, base: int, hood: float, condition: float, lot: String = "") -> Dictionary:
	return {"id": id, "label": label, "kind": kind, "lot": lot, "base": base, "hood": hood, "condition": condition,
		"owner_kind": "bank", "owner": 0, "tenant_kind": "", "tenant": 0, "rent": 0, "to_let": false, "for_sale": false, "ask": 0,
		"mortgage": 0, "arrears": 0, "missed": 0, "listed_day": 0, "last_rent_change": 0, "bought_day": 0, "paid": 0}

# ------------------------------------------------------------------ setup
## Create the map houses once (idempotent). The primary household owns the home lot; townies own and live in (or let) the others.
static func ensure() -> void:
	if not props.is_empty():
		return
	var homes: Dictionary = cfg().get("map_homes", {})
	var ids: Array = homes.keys()
	ids.sort()
	var townies: Array = Story.alive_townies()
	var ti: int = 0
	for lot_id in ids:
		var h: Dictionary = homes[lot_id]
		var p: Dictionary = make("map_" + str(lot_id), str(h["label"]), str(h["kind"]), int(h["base"]), float(h["hood"]), 85.0, str(lot_id))
		if str(lot_id) == "home":
			p["owner_kind"] = "player"
			p["owner"] = Economy.primary_household()
			p["tenant_kind"] = "player"
			p["tenant"] = int(p["owner"])
			p["condition"] = 90.0
		else:
			var t: Dictionary = townies[ti % townies.size()] if not townies.is_empty() else {}
			ti += 1
			if not t.is_empty():
				p["owner_kind"] = "townie"
				p["owner"] = int(t["id"])
				p["tenant_kind"] = "townie"
				p["tenant"] = int(t["id"])
				t["home_prop"] = str(p["id"])
		props[str(p["id"])] = p
	refresh_listings(SysUtil.day())

static func home_prop(hid: int) -> Dictionary:
	ensure()
	for id in props:
		var p: Dictionary = props[id]
		if str(p["lot"]) == "home" and (int(p["tenant"]) == hid or int(p["owner"]) == hid):
			return p
	return props.get("map_home", {})

static func get_prop(id: String) -> Dictionary:
	return props.get(id, {})

static func owned_by(hid: int) -> Array:
	var out: Array = []
	for id in props:
		var p: Dictionary = props[id]
		if str(p["owner_kind"]) == "player" and int(p["owner"]) == hid:
			out.append(p)
	return out

static func listings() -> Array:
	var out: Array = []
	for id in props:
		if bool(props[id]["for_sale"]):
			out.append(props[id])
	return out

# ------------------------------------------------------------------ value
static func neighbourhood_mult(p: Dictionary) -> float:
	var v: Dictionary = cfg().get("value", {})
	var m: float = 1.0 + float(v.get("hood_swing", 0.5)) * (float(p["hood"]) - 0.5)
	if Neighborhood.lot_ids().has("school"):
		m *= 1.0 + float(v.get("school_bonus", 0.06))
	if Neighborhood.lot_ids().has("park"):
		m *= 1.0 + float(v.get("park_bonus", 0.05))
	return m

static func condition_mult(p: Dictionary) -> float:
	var v: Dictionary = cfg().get("value", {})
	return float(v.get("condition_floor", 0.7)) + float(v.get("condition_span", 0.4)) * clampf(float(p["condition"]) / 100.0, 0.0, 1.0)

static func value(p: Dictionary) -> int:
	if p.is_empty():
		return 0
	return int(round(float(p["base"]) * neighbourhood_mult(p) * condition_mult(p) * CrimeRate.value_mult() * value_idx))

static func ask_price(p: Dictionary) -> int:
	return int(round(float(value(p)) * (1.0 + float(cfg().get("value", {}).get("sale_spread", 0.04)))))

static func market_rent(p: Dictionary) -> int:
	var y: float = float(cfg().get("rent", {}).get("yield", 0.012))
	return maxi(int(round(float(value(p)) * y * MarketEconomy.rent_mult() / maxf(MarketEconomy.price_mult(), 0.5))), 1)

static func condition_text(p: Dictionary) -> String:
	var c: float = float(p["condition"])
	return "Excellent" if c >= 85.0 else ("Good" if c >= 65.0 else ("Fair" if c >= 45.0 else "Run down"))

## What drives the price, in plain words for the dialog.
static func value_notes(p: Dictionary) -> Array:
	var out: Array = []
	out.append("Neighbourhood: %s" % ("sought after" if float(p["hood"]) >= 0.65 else ("pleasant" if float(p["hood"]) >= 0.4 else "rough")))
	out.append("Condition: %s" % condition_text(p))
	var cm: float = CrimeRate.value_mult()
	if cm < 0.97:
		out.append("Crime in town is pulling prices down.")
	if value_idx > 1.05:
		out.append("The housing market is up.")
	elif value_idx < 0.95:
		out.append("The housing market is down.")
	return out

# ------------------------------------------------------------------ daily
static func on_day(day: int) -> void:
	if not MarketEconomy.enabled:
		return
	ensure()
	var c: Dictionary = cfg()
	var target: float = MarketEconomy.price_idx * (1.0 + 0.2 * MarketEconomy.prosperity)
	value_idx = lerpf(value_idx, target, float(c.get("value", {}).get("follow", 0.15)) * 0.4)
	var decay: float = float(c.get("condition", {}).get("decay_per_day", 0.12))
	var broken_pen: float = float(c.get("condition", {}).get("broken_penalty", 6))
	for id in props:
		var p: Dictionary = props[id]
		if str(p["id"]) == "map_home" and str(p["owner_kind"]) == "player":
			p["condition"] = clampf(92.0 - broken_pen * float(_broken_count(int(p["owner"]))) - 0.0, 20.0, 100.0)
			continue
		p["condition"] = clampf(float(p["condition"]) - decay, 20.0, 100.0)
		if str(p["owner_kind"]) != "player" and float(p["condition"]) < 50.0 and rng.randf() < 0.1:
			p["condition"] = 80.0           # townie / bank owners fix their property now and then
	if day >= next_refresh:
		refresh_listings(day)

static func _broken_count(hid: int) -> int:
	var n: int = 0
	for o in Economy.objects_of(hid):
		if bool(WorldIface.state_get(o, "broken", false)):
			n += 1
	return n

## Keep about `count` properties for sale: unsold ones age out, new ones appear (flats and houses on named streets).
static func refresh_listings(day: int) -> void:
	var c: Dictionary = cfg().get("listings", {})
	next_refresh = day + int(c.get("refresh_days", 7))
	for id in props.keys():
		var p: Dictionary = props[id]
		if bool(p["for_sale"]) and str(p["lot"]) == "" and str(p["owner_kind"]) == "bank" and day - int(p["listed_day"]) >= 2 * int(c.get("refresh_days", 7)):
			props.erase(id)
	var want: int = int(c.get("count", 5))
	var kinds: Dictionary = c.get("kinds", {})
	var kind_ids: Array = kinds.keys()
	kind_ids.sort()
	var streets: Array = c.get("streets", ["Main Street"])
	var guard: int = 0
	while listings().size() < want and guard < 12:
		guard += 1
		var kind: String = str(kind_ids[rng.randi_range(0, kind_ids.size() - 1)])
		var rngb: Array = kinds[kind]["base"]
		var num: int = rng.randi_range(2, 60)
		var lbl: String = "%d %s (%s)" % [num, str(streets[rng.randi_range(0, streets.size() - 1)]), str(kinds[kind]["label"])]
		var hb: Array = c.get("hood", [0.25, 0.8])
		var cb: Array = c.get("condition", [55, 95])
		var p2: Dictionary = make("L%d" % _seq, lbl, kind, rng.randi_range(int(rngb[0]), int(rngb[1])), rng.randf_range(float(hb[0]), float(hb[1])),
			rng.randf_range(float(cb[0]), float(cb[1])))
		_seq += 1
		p2["for_sale"] = true
		p2["listed_day"] = day
		p2["ask"] = ask_price(p2)
		props[str(p2["id"])] = p2

## Everything `from_hid` owns passes to `to` (a household id for kind "player", a townie id for "townie"). Returns how many.
static func transfer(from_hid: int, to: int, to_kind: String) -> int:
	var n: int = 0
	for p in owned_by(from_hid):
		if int(p["mortgage"]) > 0:
			var l: Dictionary = BankAccounts.find(int(p["mortgage"]))
			if not l.is_empty():
				l["hid"] = to if to_kind == "player" else l["hid"]
				if to_kind != "player":
					BankAccounts.loans.erase(l)
					p["mortgage"] = 0
		p["owner_kind"] = to_kind
		p["owner"] = to
		if str(p["tenant_kind"]) == "player" and int(p["tenant"]) == from_hid:
			p["tenant_kind"] = "player" if to_kind == "player" else ""
			p["tenant"] = to if to_kind == "player" else 0
		n += 1
	return n

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"props": props.duplicate(true), "value_idx": value_idx, "next_refresh": next_refresh, "seq": _seq, "rng_seed": str(rng.seed), "rng_state": str(rng.state)}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	props = (d.get("props", {}) as Dictionary).duplicate(true)
	for id in props:
		var p: Dictionary = props[id]
		SysUtil.ints_in(p, ["base", "owner", "tenant", "rent", "ask", "mortgage", "arrears", "missed", "listed_day", "last_rent_change", "bought_day", "paid"])
		p["hood"] = float(p["hood"])
		p["condition"] = float(p["condition"])
	value_idx = float(d.get("value_idx", 1.0))
	next_refresh = int(d.get("next_refresh", 0))
	_seq = int(d.get("seq", 1))
	rng.seed = int(str(d.get("rng_seed", "130041")))
	rng.state = int(str(d.get("rng_state", str(rng.state))))
