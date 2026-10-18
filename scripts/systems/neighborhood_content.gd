class_name NeighborhoodContent
extends RefCounted
## Runtime content injected into the shared Data tables (idempotent, like SysContent / FamilyContent). Everything comes from
## data/venues.json "content": cloned object defs (park_bench, cafe_counter, grocery_cooler), venue interactions
## (order_coffee, order_meal, order_round, buy_groceries, buy_fresh_snack, sys_staff) and venue buffs.
## Also patches the live World.defs so lots built by LotLoader can use the new objects.

const MARK := "_hood_content"

static func install() -> void:
	var data = SimEnv.data()
	var cfg: Dictionary = (data.get_table("venues") as Dictionary).get("content", {})
	if cfg.is_empty():
		return
	var inter: Dictionary = data.interactions()
	var buffs: Dictionary = data.buffs()
	var odefs: Dictionary = data.objects()
	if inter.is_empty():
		return
	for iid in (cfg.get("interactions", {}) as Dictionary):
		if not inter.has(iid):
			var d: Dictionary = (cfg["interactions"][iid] as Dictionary).duplicate(true)
			d[MARK] = true
			d["_sys_gate"] = true      # keep SysContent from re-gating these
			inter[iid] = d
	for bid in (cfg.get("buffs", {}) as Dictionary):
		if not buffs.has(bid):
			buffs[bid] = (cfg["buffs"][bid] as Dictionary).duplicate(true)
	_install_objects(odefs, cfg.get("objects", {}))
	var w = WorldIface.world()
	if w != null and "defs" in w and w.defs is Dictionary:
		if (w.defs as Dictionary).is_empty() and w.has_method("get_def"):
			w.get_def("fridge")        # forces World to load its defs
		_install_objects(w.defs, cfg.get("objects", {}))

static func _install_objects(defs: Dictionary, spec: Dictionary) -> void:
	for oid in spec:
		if defs.has(oid):
			continue
		var s: Dictionary = spec[oid]
		var base: Dictionary = defs.get(str(s.get("clone", "")), {})
		if base.is_empty():
			continue
		var d: Dictionary = base.duplicate(true)
		var ov: Dictionary = s.get("override", {})
		for k in ov:
			if k == "remove":
				continue
			d[k] = ov[k]
		for k2 in ov.get("remove", []):
			d.erase(k2)
		d[MARK] = true
		defs[oid] = d

## Ids of every venue buff the crowd/ambient code may apply.
static func buff_ids() -> Array:
	var cfg: Dictionary = (SimEnv.data().get_table("venues") as Dictionary).get("content", {})
	return (cfg.get("buffs", {}) as Dictionary).keys()
