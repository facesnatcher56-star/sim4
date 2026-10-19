class_name StorytellerBudget
extends RefCounted
## The drama budget. Every key (household "h<id>", townie lot "l<n>", district "d<zone>", "town") gains points each day in proportion to its hidden chaos level
## (StorytellerChaos) and spends them on cards weighted by size (small 1, medium 3, big 7; data). There is no schedule: whether and when a key spends depends on the
## wandering level, a daily hesitation chance and the size it happens to draw. Soft guards (all data, per personality):
##   max quiet days  a household or district with nothing notable for N days gets a small card (Calm 10, Classic 5, Chaotic 3), preferably a city event that ripples to it
##   big gap         big cards are spaced out (Classic 7 days); a BAD big card needs bad_big_gap_days since the last one (the Classic pile-on cap), natural ones count
##   mercy           after a bad medium or big card or a natural loss, bad cards weigh less and good ones more for a while (not Chaotic)
## Natural events (chronicle lines of severity 2+) count as notable for the key they touch and spend a little budget too.

static func bcfg() -> Dictionary:
	return Storyteller.cfg().get("budget", {})

static func kind_of(key: String) -> String:
	if key == Storyteller.KEY_TOWN:
		return "town"
	return {"h": "home", "l": "lot", "d": "district"}.get(key.substr(0, 1), "home")

static func id_of(key: String) -> int:
	return int(key.substr(1)) if key.length() > 1 and key != Storyteller.KEY_TOWN and key.substr(0, 1) in ["h", "l"] else 0

static func zone_of_key(key: String) -> String:
	match kind_of(key):
		"district":
			return key.substr(1)
		"home":
			return CityState.zone_of_household(id_of(key))
		"lot":
			return CityState.zone_of_town_lot(id_of(key))
	return ""

static func entry(key: String) -> Dictionary:
	if not Storyteller.entries.has(key):
		var d: int = SysUtil.day()
		Storyteller.entries[key] = {"level": 1.0, "points": 1.0, "last_notable": d, "last_big": -99, "last_bad_big": -99, "mercy_until": -1, "last_spend": -99}
	return Storyteller.entries[key]

## Every key that exists today, sorted (deterministic order for the dice).
static func keys() -> Array:
	var out: Array = []
	for hid in Economy.household_ids():
		out.append("h%d" % int(hid))
	var lots: Dictionary = {}
	for tid in Story.townies:
		var t: Dictionary = Story.townies[tid]
		if bool(t["alive"]) and int(t.get("lot", 0)) > 0:
			lots[int(t["lot"])] = true
	for n in lots.keys():
		out.append("l%d" % int(n))
	for z in CityState.zone_ids():
		out.append("d" + str(z))
	out.append(Storyteller.KEY_TOWN)
	out.sort()
	return out

static func size_cost(size: String) -> float:
	return float((Storyteller.cfg().get("sizes", {}) as Dictionary).get(size, {}).get("cost", 1.0))

# ------------------------------------------------------------------ household state (what the card choice looks at)
static func coins_of(key: String) -> int:
	match kind_of(key):
		"home":
			return Economy.balance(id_of(key))
		"lot":
			var sum := 0
			for m in StorytellerPlay.lot_members(id_of(key)):
				sum += int(Story.townies[m].get("coins", 0))
			return sum
	return 0

static func tier_of(key: String) -> String:
	var w: Dictionary = Storyteller.cfg().get("wealth", {})
	var c: int = coins_of(key)
	if kind_of(key) == "lot":
		c = c / maxi(StorytellerPlay.lot_members(id_of(key)).size(), 1)
	if c >= int(w.get("rich_coins", 2500)):
		return "rich"
	if c <= int(w.get("poor_coins", 450)):
		return "poor"
	return "mid"

static func mercy_on(key: String) -> bool:
	return SysUtil.day() < int(entry(key)["mercy_until"])

# ------------------------------------------------------------------ the day
static func day(key: String, today: int) -> void:
	var e: Dictionary = entry(key)
	var kind: String = kind_of(key)
	var b: Dictionary = bcfg()
	e["points"] = minf(float(e["points"]) + float(b.get("gain_" + kind, 0.3)) * float(e["level"]), float(b.get("cap", 14.0)))
	var played_now: bool = false
	if float(e["points"]) >= size_cost("small") and Storyteller.rng.randf() < float(b.get("spend_chance", 0.55)) * clampf(float(e["level"]), 0.3, 2.0):
		played_now = spend(key, today)
	if not played_now and (kind == "home" or kind == "district") and today - int(e["last_notable"]) >= int(Storyteller.param("max_quiet_days", 5)):
		guard(key, today)

## Draw a size by the personality's weights among those the points can pay and the spacing rules allow, then a card of that size (or smaller).
static func spend(key: String, today: int) -> bool:
	var e: Dictionary = entry(key)
	var sizes: Dictionary = Storyteller.param("sizes", {})
	var order: Array = []
	var weights: Array = []
	for s in Storyteller.TIERS_LOCAL:
		if size_cost(s) > float(e["points"]):
			continue
		if s == "big" and today - int(e["last_big"]) < int(Storyteller.param("big_gap_days", 7)):
			continue
		order.append(s)
		weights.append(float(sizes.get(s, 0.1)))
	if order.is_empty():
		return false
	var pick = Storyteller.pick_weighted(order, weights)
	var start: int = Storyteller.TIERS_LOCAL.find(pick)
	for i in range(start, -1, -1):          # nothing eligible of that size: try a smaller one
		var size: String = Storyteller.TIERS_LOCAL[i]
		if not order.has(size):
			continue
		var cid: String = StorytellerDeck.pick(key, size)
		if cid != "":
			e["points"] = float(e["points"]) - size_cost(size)
			e["last_spend"] = today
			StorytellerPlay.card(key, cid, {})
			return true
	return false

## The maximum-quiet guarantee: a small card even when the points cannot pay (they may go slightly negative).
static func guard(key: String, today: int) -> void:
	var e: Dictionary = entry(key)
	Storyteller.bump("guard")
	if kind_of(key) == "home" and Storyteller.rng.randf() < float(bcfg().get("guard_city_share", 0.6)):
		var dk: String = "d" + zone_of_key(key)
		var cid: String = StorytellerDeck.pick(dk, "small", {"need_near": true})
		if cid != "":
			var de: Dictionary = entry(dk)
			de["points"] = maxf(float(de["points"]) - size_cost("small"), float(bcfg().get("floor", -4.0)))
			StorytellerPlay.card(dk, cid, {"for_key": key})
			if int(e["last_notable"]) == today:
				return
	var cid2: String = StorytellerDeck.pick(key, "small")
	if cid2 == "":
		return
	e["points"] = maxf(float(e["points"]) - size_cost("small"), float(bcfg().get("floor", -4.0)))
	StorytellerPlay.card(key, cid2, {"guard": true})

# ------------------------------------------------------------------ bookkeeping after a card and for natural events
static func mark(key: String, size: String, tone: String) -> void:
	var e: Dictionary = entry(key)
	var today: int = SysUtil.day()
	e["last_notable"] = today
	if size == "big":
		e["last_big"] = today
		if tone == "bad":
			e["last_bad_big"] = today
	if tone == "bad" and size != "small":
		var mday: int = int(Storyteller.param("mercy_days", 5))
		e["mercy_until"] = maxi(int(e["mercy_until"]), today + int(round(float(mday) * (1.0 if size == "big" else 0.5))))

## A chronicle line (an incident, a death ...) touched these people or this lot: it counts as notable for their keys and spends a little budget.
static func on_chronicle(p: Dictionary) -> void:
	var b: Dictionary = bcfg()
	var sev: int = int(p.get("severity", 1))
	if sev < int(b.get("notable_severity", 2)):
		return
	var today: int = SysUtil.day()
	var touched: Dictionary = {}
	var lot: String = str(p.get("lot", ""))
	if lot.begins_with("home:"):
		touched["h" + lot.get_slice(":", 1)] = true
	elif lot.begins_with("town:") and int(lot.get_slice(":", 1)) > 0:
		touched["l" + lot.get_slice(":", 1)] = true
	for s in p.get("subjects", []):
		var f = SysUtil.folk(int(s))
		if SysUtil.is_resident(f):
			touched["h%d" % int(f.household_id)] = true
		elif Story.townies.has(int(s)) and int(Story.townies[int(s)].get("lot", 0)) > 0:
			touched["l%d" % int(Story.townies[int(s)]["lot"])] = true
	if touched.is_empty() and lot.begins_with("town:"):
		touched[Storyteller.KEY_TOWN] = true
	var cost: float = float((b.get("natural_cost", {}) as Dictionary).get(str(sev), 0.0)) if not Storyteller.playing else 0.0
	for k in touched.keys():
		if not Storyteller.entries.has(k) and not (k.begins_with("h") or k.begins_with("l") or k == Storyteller.KEY_TOWN):
			continue
		var e: Dictionary = entry(str(k))
		e["last_notable"] = today
		e["points"] = maxf(float(e["points"]) - cost, float(b.get("floor", -4.0)))
		if sev >= int(b.get("big_severity", 4)) and not Storyteller.playing:
			e["last_big"] = today
			e["last_bad_big"] = today
		if sev >= 3 and not Storyteller.playing:
			e["mercy_until"] = maxi(int(e["mercy_until"]), today + int(Storyteller.param("mercy_days", 5)))
