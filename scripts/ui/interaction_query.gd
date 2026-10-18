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
			"label": str(def.get("label", str(id).capitalize())),
			"category": str(def.get("category", def.get("kind", "general"))).capitalize(),
			"enabled": reason == "",
			"reason": reason,
		})
	out.sort_custom(func(a, b):
		if a["category"] != b["category"]:
			return a["category"] < b["category"]
		return a["label"] < b["label"])
	return out

static func describe_tests(def: Dictionary) -> String:
	var parts: Array = []
	for t in def.get("tests", []):
		if not (t is Dictionary):
			continue
		for k in t:
			var v = t[k]
			match k:
				"stat_below": parts.append("needs %s below %s" % [v[0], v[1]])
				"stat_above": parts.append("needs %s above %s" % [v[0], v[1]])
				"has_trait": parts.append("requires trait %s" % v)
				"lacks_trait": parts.append("not for %s folk" % v)
				"coins_at_least": parts.append("costs %s Coins" % v)
				"skill_at_least": parts.append("needs %s skill %s" % [v[0], v[1]])
				_: parts.append("%s %s" % [k, v])
	return "Unavailable: " + ", ".join(parts) if parts.size() > 0 else "Unavailable right now"

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
				return InteractionQuery.describe_tests(table.get(id, {}))
			var r: Dictionary = avail[id]
			if r.get("enabled", true):
				return ""
			return str(r.get("reason", InteractionQuery.describe_tests(table.get(id, {}))))
	return func(id):
		var it = ic.call("create", id, folk, int(UIU.prop(target, "id", -1)), true)
		if it == null:
			return "Unavailable"
		var ok = it.call("can_run", folk, target)
		return "" if ok else InteractionQuery.describe_tests(table.get(id, {}))

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
		ids = odef.get("interactions", [])
	else:
		target = UIU.get_folk(target_id)
		for id in table:
			var d: Dictionary = table[id]
			if d.get("target", "") == "folk":
				ids.append(id)
	return build_entries(folk, ids, table, make_checker(folk, target))
