class_name PocketActs
extends RefCounted
## Task 63: what the pawn has on them, from the Myself menu: "On you" lists the carried things (Inventory) in one line, and a carried weapon
## can be drawn or put away (WeaponActs.draw / holster) without picking a person first.
##   PocketActs.self_entries(f)   PocketActs.label_of(id)

static func label_of(id: String) -> String:
	if WeaponActs.is_weapon(id):
		return str(WeaponActs.def(id).get("label", id))
	var sid: String = ShopBuy._shop_of(id)
	if sid != "":
		return str(ShopStock.item(sid, id).get("label", id))
	return id.capitalize()

static func _entry(id: String, label: String, fn: Callable) -> Dictionary:
	return {"id": id, "label": label, "category": "Myself", "enabled": true, "reason": "", "action": fn}

static func self_entries(f) -> Array:
	if f == null or not Pawn.is_pawn(f) or Inventory.items(int(f.id)).is_empty():
		return []
	var out: Array = [_entry("pocket_list", "On you", func(): SysUtil.notify(text(int(f.id)), "info"))]
	var h: Dictionary = WeaponActs.held(int(f.id))
	if not h.is_empty():
		var nm: String = label_of(str(h["id"])).to_lower()
		if bool((h["item"] as Dictionary).get("shown", false)):
			out.append(_entry("pocket_holster", "Put the %s away" % nm, func(): WeaponActs.holster(f)))
		else:
			out.append(_entry("pocket_draw", "Draw the %s" % nm, func(): WeaponActs.draw(f)))
	return out

## "On you: a baseball bat, glasses, 8 cigarettes." (a held-out weapon says so)
static func text(pid: int) -> String:
	var parts: Array = []
	for e in Inventory.items(pid):
		var nm: String = label_of(str(e["id"])).to_lower()
		var n: int = int(e.get("n", 1))
		parts.append(("%d x %s" % [n, nm] if n > 1 else nm) + (" (in your hand)" if bool(e.get("shown", false)) else ""))
	return "On you: %s." % ", ".join(parts) if not parts.is_empty() else "Your pockets are empty."
