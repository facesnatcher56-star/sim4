class_name ChronicleHook
extends RefCounted
## The hook the Town Chronicle (a later task) listens to. Every incident outcome, death, birth and wedding calls note():
##   Events.game_event("chronicle", {kind, text, day, subjects:[ids], lot, severity, public})
## kind: incident id | "death" | "birth" | "wedding" ...; lot: "home:<hid>" / "town:<n>" / "" ; severity 1 (trivia) .. 5 (tragedy);
## public: may the newspaper print it. We keep a tiny recent list (not saved) so tests and the debug panel can look.

static var recent: Array = []

static func reset() -> void:
	recent.clear()

static func note(kind: String, text: String, subjects: Array = [], lot: String = "", severity: int = 1, is_public: bool = true) -> Dictionary:
	var ids: Array = []
	for s in subjects:
		ids.append(int(s))
	var p: Dictionary = {"kind": kind, "text": text, "day": SysUtil.day(), "subjects": ids, "lot": lot, "severity": severity, "public": is_public}
	recent.append(p)
	while recent.size() > 40:
		recent.pop_front()
	SysUtil.game_event("chronicle", p)
	return p

## Births and weddings of the player's household come in as game events; Story reports townie ones itself.
static func on_game_event(ev: String, payload: Dictionary) -> void:
	match ev:
		"baby_born":
			var b = SysUtil.folk(int(payload.get("baby_id", -1)))
			var m = SysUtil.folk(int(payload.get("folk_id", -1)))
			if b != null and m != null:
				note("birth", "%s was born to %s." % [b.name, m.name], [b.id, m.id], "home:%d" % int(m.household_id), 2)
		"married":
			var a = SysUtil.folk(int(payload.get("folk_id", -1)))
			var c = SysUtil.folk(int(payload.get("target_id", -1)))
			if a != null and c != null:
				note("wedding", "%s and %s got married." % [a.name, c.name], [a.id, c.id], "home:%d" % int(a.household_id), 2)
