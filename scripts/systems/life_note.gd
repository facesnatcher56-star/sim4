class_name LifeNote
extends RefCounted
## One way for the life areas (task 14) to tell the player things, following the notify policy of the incident framework: a TOAST only when the news
## is about somebody in a player's household (or the player asked for it), everything else goes to the town chronicle only. Places add their own
## news items this way ("The cinema now shows ...").
##   LifeNote.say(kind, text, subjects, severity, toast)   chronicle always (public) + a toast when a resident is involved and `toast` is true
##   LifeNote.news(place_id, text)                        a chronicle line with the place's lot, no toast

static func say(kind: String, text: String, subjects: Array = [], severity: int = 1, toast: bool = true, toast_kind: String = "info") -> void:
	var lot := ""
	var mine := false
	for s in subjects:
		var f = SysUtil.folk(int(s))
		if f != null and SysUtil.is_resident(f):
			mine = true
			lot = "home:%d" % int(f.household_id)
	ChronicleHook.note(kind, text, subjects, lot, severity, true)
	if toast and mine:
		SysUtil.notify(text, toast_kind)

static func news(place_id: String, text: String, severity: int = 1) -> void:
	ChronicleHook.note("place_news", text, [], "place:%s" % place_id, severity, true)

## A resident's pronoun-safe name for sentences.
static func nm(id: int) -> String:
	return SysUtil.folk_name(id)
