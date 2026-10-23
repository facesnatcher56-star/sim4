class_name OrderRefusal
extends RefCounted
## An order the player gave that could not start says why, as a toast ("Toggle Lamp: Orrin can't get there."), instead of only the
## character's "I can't do that right now." (SimDirector emits game_event "order_refused" with the reason start() found, or none when
## the order's own tests failed: then the same words the pie menu greys an entry with).

static func hook() -> void:
	UIU.connect_ev("game_event", Callable(OrderRefusal, "_on_event"))


static func _on_event(name: String, p: Dictionary) -> void:
	if name != "order_refused":
		return
	var f = UIU.get_folk(int(p.get("folk_id", -1)))
	if f == null or not Pawn.is_pawn(f):
		return
	UIU.notify(text(f, str(p.get("interaction", "")), int(p.get("target_id", -1)), str(p.get("why", ""))), "warn")


static func text(f, iid: String, target_id: int, why: String) -> String:
	var def: Dictionary = UIU.tbl("interactions").get(iid, {})
	var label := str(def.get("label", UIU.sentence(iid)))
	var who := str(f.name)
	match why:
		"gone":
			return "%s: it isn't there any more." % label
		"busy":
			return "%s: someone else is using it." % label
		"no_way":
			return "%s: %s can't get there from here." % [label, who]
	var target = UIU.get_folk(target_id) if str(def.get("target", "")) == "folk" else WorldIface.get_object(target_id)
	var reason := PieEntries.polish_reason(InteractionQuery.describe_tests(def, f, target))
	return "%s: %s" % [label, reason if reason != "" else "%s can't do that right now." % who]
