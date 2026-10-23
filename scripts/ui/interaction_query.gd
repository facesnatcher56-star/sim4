class_name InteractionQuery
extends RefCounted
## Lists the interactions a folk can pick on a target, with disabled reasons.
## Uses Interaction.available_for(folk, target) when sim-core provides it, else Interaction.can_run.

## Pure function (testable): ids + table -> sorted entries [{id,label,category,enabled,reason}]
static func build_entries(folk, ids: Array, table: Dictionary, checker: Callable = Callable()) -> Array:
	var out: Array = []
	for id in ids:
		var def: Dictionary = table.get(id, {})
		if def.is_empty() and not table.has(id):
			continue
		if def.get("hidden", false) or def.get("autonomous_only", false):
			continue
		var reason := ""
		if checker.is_valid():
			reason = str(checker.call(id))
		out.append({
			"id": id,
			"label": str(def.get("label", UIU.sentence(str(id)))),
			"category": UIU.sentence(str(def.get("category", def.get("kind", "general")))),
			"enabled": reason == "",
			"reason": reason,
		})
	out.sort_custom(func(a, b):
		if a["category"] != b["category"]:
			return a["category"] < b["category"]
		return a["label"] < b["label"])
	return out

## Player-facing group: explicit category (social actions) or the first matching tag group.
const TAG_GROUPS := [["Food", ["food", "drink", "cook", "snack", "coffee", "tea", "meal"]], ["Rest", ["sleep", "rest", "relax", "toilet"]],
	["Hygiene", ["hygiene", "vanity"]], ["Fun", ["fun", "game", "tv", "music", "creative", "art", "dance", "perform", "party"]],
	["Skills", ["skill", "read", "study", "write", "science", "practice", "work", "career", "exercise", "fitness", "fish"]],
	["Chores", ["chore", "clean", "repair", "plant", "garden", "junk"]]]

static func category_for(def: Dictionary) -> String:
	if def.has("category"):
		return UIU.sentence(str(def["category"]))
	var tags: Array = def.get("tags", [])
	for g in TAG_GROUPS:
		for t in tags:
			if t in g[1]:
				return str(g[0])
	return "Other" if str(def.get("kind", "")) == "super" else UIU.sentence(str(def.get("kind", "general")))

static func describe_tests(def: Dictionary, folk = null, target = null) -> String:
	var parts: Array = []
	var ctx := {}
	if folk != null:
		ctx = {"folk": folk, "object": target if not (target is Folk) else null, "target": target if target is Folk else null}
		if target != null and not (target is Folk) and bool(WorldIface.state_get(target, "broken", false)) and not bool(def.get("works_when_broken", false)):
			return "Broken. Repair it first"
		var only: Array = def.get("objects", [])
		if target != null and not (target is Folk) and not only.is_empty() and not only.has(str(UIU.prop(target, "def_id", ""))):
			return "Nothing to do here"
	for t in def.get("tests", []):
		if not (t is Dictionary):
			continue
		if folk != null and Cond.check_one(t, ctx):
			continue
		for k in t:
			var v = t[k]
			match k:
				"stat_below": parts.append(str(PieEntries.NOT_NEEDED.get(str(v[0]), "Not needed right now")))
				"stat_above": parts.append(str(PieEntries.TOO_LOW.get(str(v[0]), "Not right now")))
				"has_trait": parts.append("needs the %s trait" % PieEntries.label_of_trait(str(v)))
				"lacks_trait": parts.append("not for %s Folk" % PieEntries.label_of_trait(str(v)))
				"coins_at_least": parts.append("costs %s Coins" % v)
				"pays_ingredients": parts.append("No money for ingredients (%s Coins)" % v)
				"is_pawn": parts.append("not for you")
				"owns_car": parts.append("You have no car" if bool(v) else "You already have a car")
				"car_impounded": parts.append("No car of yours is at the pound")
				"bills_due": parts.append("Nothing to pay")
				"has_licence": parts.append("needs a driving licence (the test is at City Hall)")
				"election_open": parts.append("No election on right now")
				"has_guests": parts.append("You don't know anyone to invite yet")
				"not": parts.append("Not at your own home" if (v is Dictionary and (v as Dictionary).has("at_home_lot")) else "not possible right now")
				"circadian": parts.append("Not time to sleep yet")
				"no_free_bed": parts.append("You have a bed to use")
				"time_between": parts.append("Only between %d:00 and %d:00" % [int(v[0]), int(v[1])])
				"at_lot": parts.append("not here")
				"on_street": parts.append("only outdoors, on a street or in a park")
				"homeless": parts.append("only if you have no home")
				"shelter_night": parts.append("no shelter nights left this week")
				"skill_at_least": parts.append("needs %s skill level %s" % [UIU.sentence(str(v[0])), v[1]])
				"object_state_above": parts.append("Out of stock" if str(v[0]) == "stock" else "Nothing to do here")
				"object_state_below", "object_state_eq": parts.append("Nothing to do here")
				_: parts.append("not possible right now")
	if parts.size() == 0:
		if folk != null and target != null and not (target is Folk) and not WorldIface.has_free_slot(target, int(folk.id)):
			return "In use right now"
		return "Unavailable right now"
	var txt: String = ", ".join(parts)
	return txt.substr(0, 1).to_upper() + txt.substr(1)

static func make_checker(folk, target) -> Callable:
	var ic = UIU.cls("Interaction")
	var table := UIU.tbl("interactions")
	if ic == null:
		return Callable()
	var avail := {}
	var have_avail := false
	for m in ic.get_script_method_list():
		if m.get("name") == "available_for":
			have_avail = true
	if have_avail:
		var res = ic.call("available_for", folk, target)
		if res is Array:
			for r in res:
				if r is Dictionary:
					avail[str(r.get("id", r.get("def_id", "")))] = r
				else:
					avail[str(r)] = {"enabled": true}
		return func(id):
			if not avail.has(id):
				return InteractionQuery.describe_tests(table.get(id, {}), folk, target)
			var r: Dictionary = avail[id]
			if r.get("enabled", true):
				return ""
			return str(r.get("reason", InteractionQuery.describe_tests(table.get(id, {}), folk, target)))
	return func(id):
		var it = ic.call("create", id, folk, int(UIU.prop(target, "id", -1)), true)
		if it == null:
			return "Unavailable"
		var ok = it.call("can_run", folk, target)
		return "" if ok else InteractionQuery.describe_tests(table.get(id, {}), folk, target)

## The things a folk can do to itself (sleep on the floor, ...): target "self" defs that are not hidden, not idle fillers and not emergencies.
## One-character play: autonomy never starts these for the pawn, so the player orders them from the Myself menu.
static func self_entries(folk) -> Array:
	var table := UIU.tbl("interactions")
	var ids: Array = []
	for id in table:
		var d: Dictionary = table[id]
		if str(d.get("target", "")) != "self" or bool(d.get("hidden", false)) or bool(d.get("idle_gate", false)) or d.has("emergency"):
			continue
		if (not bool(d.get("autonomous", true)) and not bool(d.get("player_menu", false))) or str(d.get("kind", "")) != "super":
			continue
		if d.has("_solo") and (d.get("tests", []) as Array).has({"is_pawn": false}):
			continue          # not for the pawn at all (the welcome basket)
		ids.append(id)
	return build_entries(folk, ids, table, make_checker(folk, null)) + Habits.self_entries(folk)          # task 55: the smoker's cigarette

## target_kind: "object" | "folk"
static func entries_for(folk, target_kind: String, target_id: int) -> Array:
	var table := UIU.tbl("interactions")
	var ids: Array = []
	var target = null
	if target_kind == "object":
		target = World.call("get_object", target_id) if World.has_method("get_object") else null
		if target == null:
			return []
		var odef: Dictionary = UIU.tbl("objects").get(str(UIU.prop(target, "def_id", "")), {})
		ids = (odef.get("interactions", []) as Array).duplicate()
		for gone in ShopActs.hides(folk, target):          # task 53: in a shop the pawn takes goods and pays at the till (ShopActs)
			ids.erase(gone)
		var shop: Array = ShopActs.entries(folk, target)
		for e in shop:          # a greyed order says why, in the same words as any other entry
			if not bool(e["enabled"]) and str(e["reason"]) == "" and e.has("iid"):
				e["reason"] = describe_tests(table.get(str(e["iid"]), {}), folk, target)
		return build_entries(folk, ids, table, make_checker(folk, target)) + shop + TillActs.entries(folk, target) + BankBranch.entries(folk, target)
	else:
		target = UIU.get_folk(target_id)
		for id in table:
			var d: Dictionary = table[id]
			if d.get("target", "") == "folk":
				ids.append(id)
	var acts: Array = PersonActs.entries(folk, target) + Licences.person_entries(folk, target) + JobLeads.person_entries(folk, target) + WeaponShop.permit_entries(folk, target) + WeaponActs.entries(folk, target)
	var have: Dictionary = {}
	for e in acts:
		have[str(e["label"]).to_lower()] = true
	# an older social action with the same name as a newer act (Pick Their Pocket / Pick their pocket) is shown once: the act
	return build_entries(folk, ids, table, make_checker(folk, target)).filter(func(e): return not have.has(str(e["label"]).to_lower())) + acts          # task 53: physical acts; 55: the driving test; 51: ask if they're hiring; 57: a carried weapon (owner's weapon_acts.gd)
