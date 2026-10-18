class_name Loot
extends RefCounted
## Applies reward/effect dictionaries. Each entry may include "chance": 0..1 (default 1).
## ctx keys: "folk" (actor), "object", "target" (Folk or null).

static var rng: RandomNumberGenerator = null

static func get_rng() -> RandomNumberGenerator:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng

static func apply(list: Array, ctx: Dictionary) -> void:
	for entry in list:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		if d.has("chance") and get_rng().randf() > float(d["chance"]):
			continue
		_apply_one(d, ctx)

static func _apply_one(d: Dictionary, ctx: Dictionary) -> void:
	var folk = ctx.get("folk", null)
	var obj = ctx.get("object", null)
	var target = ctx.get("target", null)
	for key in d:
		var v: Variant = d[key]
		match str(key):
			"chance":
				pass
			"add_buff":
				if folk != null:
					folk.add_buff(str(v), true)
			"remove_buff":
				if folk != null:
					folk.remove_buff(str(v))
			"target_add_buff":
				if target != null:
					target.add_buff(str(v), false)
			"target_remove_buff":
				if target != null:
					target.remove_buff(str(v))
			"stat_add":
				if folk != null:
					folk.add_to_stat(str(v[0]), float(v[1]))
			"target_stat_add":
				if target != null:
					target.add_to_stat(str(v[0]), float(v[1]))
			"skill_xp":
				if folk != null:
					folk.add_skill_xp(str(v[0]), float(v[1]))
			"object_state_add":
				if obj != null:
					WorldIface.state_add(obj, str(v[0]), float(v[1]))
			"object_state_set":
				if obj != null:
					WorldIface.state_set(obj, str(v[0]), v[1])
			"object_state_toggle":
				if obj != null:
					WorldIface.state_set(obj, str(v), not bool(WorldIface.state_get(obj, str(v), false)))
			"coins_add":
				if folk != null:
					WorldIface.add_coins(int(folk.household_id), int(v))
			"relationship_add":
				if folk != null and target != null:
					folk.add_rel(int(target.id), str(v[0]), float(v[1]))
					target.add_rel(int(folk.id), str(v[0]), float(v[1]))
			"fire_event":
				var payload := {"folk_id": -1, "object_id": -1, "target_id": -1}
				if folk != null:
					payload["folk_id"] = folk.id
				if obj != null:
					payload["object_id"] = obj.id
				if target != null:
					payload["target_id"] = target.id
				SimEnv.emit("game_event", str(v), payload)
			"notify":
				if v is Array:
					SimEnv.emit("notification", str(v[0]), str(v[1]) if v.size() > 1 else "info")
				else:
					SimEnv.emit("notification", str(v), "info")
			"consume_item":
				if obj != null and WorldIface.state_get(obj, "stock", null) != null:
					WorldIface.state_add(obj, "stock", -1.0)
				var payload2 := {"item": str(v), "folk_id": folk.id if folk != null else -1}
				SimEnv.emit("game_event", "consume_item", payload2)
			_:
				push_warning("Loot: unknown key '%s'" % str(key))
