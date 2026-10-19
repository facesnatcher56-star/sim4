class_name HobbyServices
extends RefCounted
## The handler "hobby" (PlaceHandlers) of the hobby places; `args.act` picks the hobby:
##   fish         a catch by skill (common, good, rare for anglers of level 4+): fish go to the market stall crafts, a rare one is news and a town record
##   tend/harvest the community garden plot (rent it first: a pass; three tendings and it can be harvested for produce and the pantry)
##   paint/photo  a painting (a craft for the market or the gallery) or photographs (sold at the gallery)
##   hunt/stamps  collecting: a rock, a bug or a stamp by rarity; eight make a set
##   donate       a complete set goes to the museum (coins, fame, news); collecting then starts again
##   handicraft   the workshop: made things sold at the craft stall (pay by handiness)
##   sell_photos  the gallery buys the photographs

static func hc() -> Dictionary:
	return HobbyState.cfg()

static func check(_handler: String, f, _pid: String, _sid: String, svc: Dictionary) -> String:
	var a: Dictionary = svc.get("args", {})
	var id: int = int(f.id)
	match str(a.get("act", "")):
		"tend":
			if not PlaceMember.has_pass(id, "community_garden"):
				return "Rent a plot first."
		"harvest":
			if not PlaceMember.has_pass(id, "community_garden"):
				return "Rent a plot first."
			if int((HobbyState.plots.get(id, {}) as Dictionary).get("tends", 0)) < int(hc().get("garden", {}).get("tends_to_harvest", 3)):
				return "The plot needs more tending before it can be harvested."
		"sell_photos":
			if int(HobbyState.photos.get(id, 0)) <= 0:
				return "%s has no photographs to sell." % f.name
		"donate":
			var kind: String = str(a.get("kind", ""))
			if not HobbyState.complete(id, kind):
				return "The set is not complete yet (%d of %d)." % [HobbyState.found_count(id, kind), HobbyState.items(kind).size()]
	return ""

static func finish(_handler: String, f, pid: String, _sid: String, svc: Dictionary) -> Dictionary:
	var a: Dictionary = svc.get("args", {})
	var id: int = int(f.id)
	var hid: int = int(f.household_id)
	match str(a.get("act", "")):
		"fish":
			return _fish(f, pid)
		"tend":
			var pl: Dictionary = HobbyState.plots.get(id, {"tends": 0, "day": SysUtil.day()})
			pl["tends"] = int(pl["tends"]) + 1
			pl["day"] = SysUtil.day()
			HobbyState.plots[id] = pl
			return {"text": "%s weeded and watered the plot (%d tending%s so far)." % [f.name, int(pl["tends"]), "" if int(pl["tends"]) == 1 else "s"]}
		"harvest":
			var g: Dictionary = hc().get("garden", {})
			var n: int = int(g.get("yield_base", 2)) + f.skill_level("gardening") / 3 * int(g.get("yield_per_3_levels", 1))
			MarketWork.add_craft(hid, "produce", n)
			Neighborhood.add_pantry(int(g.get("pantry", 2)))
			HobbyState.plots[id] = {"tends": 0, "day": SysUtil.day()}
			f.add_buff("fresh_produce")
			return {"text": "%s harvested %d vegetables from the plot." % [f.name, n]}
		"paint":
			MarketWork.add_craft(hid, "painting", 1)
			if HobbyState.rng.randf() < 0.3:
				f.add_buff("inspired")
			return {"text": "%s painted the view from the bench. The canvas is drying." % f.name}
		"photo":
			var shots: int = 1 + (1 if f.skill_level("photography") >= 3 else 0)
			HobbyState.photos[id] = int(HobbyState.photos.get(id, 0)) + shots
			return {"text": "%s took %d good photograph%s." % [f.name, shots, "" if shots == 1 else "s"]}
		"sell_photos":
			var ph: Dictionary = hc().get("photo", {})
			var n2: int = mini(int(HobbyState.photos.get(id, 0)), int(ph.get("sell_cap", 5)))
			var pay: int = n2 * (int(ph.get("sell_base", 5)) + int(ph.get("sell_per_level", 2)) * f.skill_level("photography"))
			HobbyState.photos[id] = int(HobbyState.photos.get(id, 0)) - n2
			Economy.deposit(hid, pay, "photographs sold")
			LifeFame.add(id, 0.2 * float(n2))
			return {"text": "The gallery bought %d of %s's photographs for %d coins." % [n2, f.name, pay]}
		"hunt", "stamps":
			return _find(f, str(a.get("kind", "")), 2 if str(a.get("act", "")) == "stamps" else 1)
		"donate":
			var kind: String = str(a.get("kind", ""))
			var cc: Dictionary = hc().get("collect", {})
			Economy.deposit(hid, int(cc.get("donate_pay", 120)), "museum donation reward")
			LifeFame.add(id, float(cc.get("donate_fame", 3.0)))
			HobbyState.collections[id][kind] = {}
			var dn: Dictionary = HobbyState.donated.get(id, {})
			dn[kind] = int(dn.get(kind, 0)) + 1
			HobbyState.donated[id] = dn
			var label: String = str((HobbyState.coll_defs().get(kind, {}) as Dictionary).get("label", kind))
			LifeNote.say("donation", "%s gave the museum a complete collection: %s." % [f.name, label.to_lower()], [id], 1, true, "good")
			return {"text": "%s donated the whole collection to the museum and was paid %d coins." % [f.name, int(cc.get("donate_pay", 120))]}
		"handicraft":
			var hcg: Dictionary = hc().get("handicraft", {})
			var pay2: int = int(hcg.get("base", 12)) + int(hcg.get("per_level", 5)) * f.skill_level("handiness")
			Economy.deposit(hid, pay2, "handicrafts sold")
			return {"text": "%s made handicrafts that sold at the craft stall for %d coins." % [f.name, pay2]}
	return {}

static func _fish(f, pid: String) -> Dictionary:
	var fc: Dictionary = hc().get("fish", {})
	var lvl: int = f.skill_level("fishing")
	var p: float = minf(float(fc.get("base", 0.35)) + float(fc.get("per_level", 0.06)) * float(lvl), float(fc.get("cap", 0.9)))
	if HobbyState.rng.randf() >= p:
		return {"text": "%s fished all afternoon and caught nothing but a good mood." % f.name}
	var kind := "common"
	var roll: float = HobbyState.rng.randf()
	if lvl >= int(fc.get("rare_level", 4)) and roll < float(fc.get("rare_chance", 0.06)):
		kind = "rare"
	elif roll < float(fc.get("good_chance", 0.25)) + float(fc.get("rare_chance", 0.06)):
		kind = "good"
	var value: int = int((fc.get("values", {}) as Dictionary).get(kind, 5))
	if MarketEconomy.enabled:
		MarketWork.add_craft(int(f.household_id), "fish", 1)
	else:
		Economy.deposit(int(f.household_id), value, "fish sold")
	if kind == "rare":
		var r: Dictionary = LifeFame.note_score(int(f.id), "rare_fish", value, str(f.name))
		LifeNote.say("fishing", "%s landed a rare fish at the pier." % f.name, [int(f.id)], 1, true, "good")
		LifeFame.add(int(f.id), 0.5)
		return {"text": "%s landed a rare fish! It will fetch a good price." % f.name}
	return {"text": "%s caught a %s fish." % [f.name, "fine" if kind == "good" else "small"]}

static func _find(f, kind: String, n: int) -> Dictionary:
	var id: int = int(f.id)
	var lines: Array = []
	for _i in n:
		var r: Dictionary = HobbyState.find(id, kind, float(f.skill_level("logic")) * 0.05)
		if r.is_empty():
			continue
		lines.append("%s%s" % [r["label"], " (new!)" if bool(r["new"]) else " (already have)"])
	f.add_skill_xp("logic", 6.0)
	var have: int = HobbyState.found_count(id, kind)
	var total: int = HobbyState.items(kind).size()
	var text := "%s found: %s. The set has %d of %d." % [f.name, ", ".join(lines), have, total]
	if have >= total:
		text += " The set is complete: the museum would love it."
	return {"text": text}
