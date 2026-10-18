class_name ShareMail
extends RefCounted
## Object gifts: put the gift on a free tile next to the home mailbox (when the world can place it).

static func object_label(def_id: String) -> String:
	return str(SimEnv.data().object_def(def_id).get("label", def_id.replace("_", " ")))

static func place_object(def_id: String) -> bool:
	var w = WorldIface.world()
	if w == null or not w.has_method("place_object") or not w.has_method("can_place"):
		return false
	var box = null
	for o in SysUtil.all_world_objects():
		if str(o.def_id) == "mailbox" and Neighborhood.lot_at(o.tile) == Neighborhood.HOME:
			box = o
			break
	if box == null:
		return false
	for r in range(1, 5):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var t: Vector2i = box.tile + Vector2i(dx, dy)
				if w.can_place(def_id, t, 0, int(box.level)):
					return int(w.place_object(def_id, t, 0, int(box.level))) >= 0
	return false
