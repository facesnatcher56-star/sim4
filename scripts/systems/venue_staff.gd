class_name VenueStaff
extends RefCounted
## Task 53: the people who work at a place react to what the player's person does there. The game never walks the pawn out by itself: at closing time somebody who is
## actually at the place (its staff) says so, asks again 15 minutes later, and after 30 minutes walks the pawn out (the pawn is told to go; if it was not theirs to stay in,
## that is trespassing). No staff on the floor = nobody says anything. Lines vary and never repeat twice in a row.
##   VenueStaff.closing(f, lot_id)   (called each minute for the pawn inside a lot that is closed)

static var first_asked: Dictionary = {}          # "fid|lot" -> game minute of the first request

const FIRST := ["We are closing now. Time to head out.", "Sorry, we are closed. Please make your way out.", "That is closing time, I am afraid."]
const SECOND := ["I will have to ask you to leave now.", "We really are closed. Please go.", "Please, we need to lock up."]
const THIRD := ["That is enough. Out you go.", "I am walking you out. Come on."]

static func _staff(lot_id: String) -> Array:
	var out: Array = Crowd.staff_folk(lot_id)
	return out

static func _speak(f, who, text: String) -> void:
	if who != null:
		SimEnv.emit("thought", int(who.id), text)
	SysUtil.notify("%s: %s" % [str(who.name) if who != null else "Staff", text], "story")

static func closing(f, lot_id: String) -> void:
	if f == null:
		return
	var staff: Array = _staff(lot_id)
	if staff.is_empty():
		return          # nobody on the floor to say it
	var key: String = "%d|%s" % [int(f.id), lot_id]
	var now: int = SysUtil.now()
	var who = staff[0]
	if not first_asked.has(key):
		first_asked[key] = now
		_speak(f, who, str(FIRST[PlayerPrompt._pick("staff|first", FIRST.size())]))
		return
	var since: int = now - int(first_asked[key])
	if since == 15:
		_speak(f, who, str(SECOND[PlayerPrompt._pick("staff|second", SECOND.size())]))
	elif since >= 30:
		first_asked.erase(key)
		_speak(f, who, str(THIRD[PlayerPrompt._pick("staff|third", THIRD.size())]))
		var out: Interaction = Interaction.create_goto(f, NeighborhoodLots.street_tile(lot_id) + Vector2i(0, 3), true, 0)
		f.clear_queue()
		if out != null:
			f.enqueue(out)
		CrimePetty.commit("trespassing", int(f.id), "venue:" + lot_id, {"seen": true})
