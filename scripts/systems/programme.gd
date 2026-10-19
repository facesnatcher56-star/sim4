class_name Programme
extends RefCounted
## What is on this week (task 14): a place with a `programme` {slots: [...], titles: {slot: [title, ...]}} (cinema, theatre, concert hall, museum, gallery)
## shows one title per slot, the next one every game week; the weeks are counted from day 1 so every client agrees without any dice.
## A service with `programme_slot` shows the title in its label ("Family Film: {title}") and in its text.

static func week(day: int = -1) -> int:
	return ((day if day > 0 else SysUtil.day()) - 1) / 7

static func titles(pid: String, slot: String) -> Array:
	return ((Places.def(pid).get("programme", {}) as Dictionary).get("titles", {}) as Dictionary).get(slot, [])

static func title(pid: String, slot: String, day: int = -1) -> String:
	var t: Array = titles(pid, slot)
	if t.is_empty():
		return ""
	return str(t[week(day) % t.size()])
