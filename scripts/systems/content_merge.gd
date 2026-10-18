class_name ContentMerge
extends RefCounted
## Merges a JSON content block into the shared Data tables and the live World object defs. Idempotent: ids that already
## exist are left alone, so install() can be called any number of times.
##
##   "interactions":        { id: interaction def }
##   "buffs":               { id: buff def }
##   "buff_patch":          { buff id: { key: value } }       overwrites keys of an existing buff
##   "objects":             { id: { "def": {...} } | { "clone": base object id, "override": {...}, } }   (override.remove = keys to drop)
##   "object_interactions": { object id: [interaction ids] }  appended to that object's `interactions`
##
## install(cfg, mark, interaction_keys): `mark` is set to true on every added interaction / object (so later patch passes can
## recognise them); `interaction_keys` are copied onto every added interaction (e.g. {"_sys_gate": true}).

static func install(cfg: Dictionary, mark: String = "", interaction_keys: Dictionary = {}) -> void:
	if cfg.is_empty():
		return
	var data = SimEnv.data()
	var inter: Dictionary = data.interactions()
	var buffs: Dictionary = data.buffs()
	if inter.is_empty():
		return
	for iid in (cfg.get("interactions", {}) as Dictionary):
		if not inter.has(iid):
			var d: Dictionary = (cfg["interactions"][iid] as Dictionary).duplicate(true)
			if mark != "":
				d[mark] = true
			for k in interaction_keys:
				d[k] = interaction_keys[k]
			inter[iid] = d
	for bid in (cfg.get("buffs", {}) as Dictionary):
		if not buffs.has(bid):
			buffs[bid] = (cfg["buffs"][bid] as Dictionary).duplicate(true)
	for bid in (cfg.get("buff_patch", {}) as Dictionary):
		if buffs.has(bid):
			for k in cfg["buff_patch"][bid]:
				buffs[bid][k] = (cfg["buff_patch"][bid][k] as Dictionary).duplicate(true)
	_into_objects(data.objects(), cfg, mark)
	var w = WorldIface.world()
	if w != null and "defs" in w and w.defs is Dictionary:
		if (w.defs as Dictionary).is_empty() and w.has_method("get_def"):
			w.get_def("fridge")        # forces World to load its defs
		_into_objects(w.defs, cfg, mark)

static func _into_objects(defs: Dictionary, cfg: Dictionary, mark: String) -> void:
	if defs.is_empty():
		return
	var spec: Dictionary = cfg.get("objects", {})
	for oid in spec:
		if defs.has(oid):
			continue
		var s: Dictionary = spec[oid]
		var d: Dictionary
		if s.has("def"):
			d = (s["def"] as Dictionary).duplicate(true)
		else:
			var base: Dictionary = defs.get(str(s.get("clone", "")), {})
			if base.is_empty():
				continue
			d = base.duplicate(true)
			var ov: Dictionary = s.get("override", {})
			for k in ov:
				if k != "remove":
					d[k] = ov[k]
			for k2 in ov.get("remove", []):
				d.erase(k2)
		if mark != "":
			d[mark] = true
		defs[oid] = d
	var extra: Dictionary = cfg.get("object_interactions", {})
	for oid in extra:
		for iid in extra[oid]:
			add_object_interaction(defs, str(oid), str(iid))

## Offer `iid` on objects of kind `obj_id` (no-op when the object kind is unknown or already offers it).
static func add_object_interaction(defs: Dictionary, obj_id: String, iid: String) -> void:
	if not defs.has(obj_id):
		return
	var od: Dictionary = defs[obj_id]
	var list: Array = od.get("interactions", [])
	if not list.has(iid):
		list.append(iid)
		od["interactions"] = list
