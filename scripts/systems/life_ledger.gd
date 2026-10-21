class_name LifeLedger
extends RefCounted
## Task 44: the cause links of a life. Every event with an effect on somebody (a chronicle note of severity 2 or more) and every choice the player made
## (a command, a prompt answer) is one entry: id, day, kind, text, who it touched, the entries that caused it, whether it was the player's choice.
## A new entry is linked to the latest earlier entries that touched the same people within LINK_DAYS (the real causes of 43 write chronicle notes with
## their people, so recency plus shared people finds the chain). Nothing here is shown during play: the end-of-life summary (LifeSummary) reads it.
## Compact: entries below severity 2 are dropped, capped at CAP, saved in the "ledger" block of the save.

const CAP := 700
const LINK_DAYS := 14
const MAX_CAUSES := 1
## Only these can be causes (a power cut or the weather is not why somebody was evicted): the player's choices and the kinds of event that change a life.
const CAUSE_WORDS := ["burglar", "robb", "theft", "fire", "arrest", "evict", "death", "died", "layoff", "fired", "crime", "assault", "murder", "gang", "drive", "hospital", "debt", "fine", "move", "wedding", "birth", "breakup", "divorce", "job", "attempt", "choice", "vandal", "scam", "fraud"]

static func _can_cause(e: Dictionary) -> bool:
	if bool(e["choice"]):
		return true
	var k: String = str(e["kind"]).to_lower()
	for w in CAUSE_WORDS:
		if k.contains(w):
			return true
	return false

static var entries: Array = []
static var next_id: int = 1

static func reset() -> void:
	entries = []
	next_id = 1

## From ChronicleHook.note: who = the subjects, or the residents of the household named by lot "home:<hid>".
static func from_chronicle(p: Dictionary) -> void:
	if int(p.get("severity", 1)) < 2:
		return
	var who: Array = (p.get("subjects", []) as Array).duplicate()
	var lot: String = str(p.get("lot", ""))
	if who.is_empty() and lot.begins_with("home:"):
		var hid: int = int(lot.get_slice(":", 1))
		for f in SysUtil.residents():
			if int(f.household_id) == hid:
				who.append(int(f.id))
	add(str(p.get("kind", "")), str(p.get("text", "")), who, false, int(p.get("severity", 2)))

## A choice of the player (root of a chain).
static func choice(text: String, who: Array = []) -> int:
	var w: Array = who.duplicate()
	if w.is_empty() and Pawn.of() >= 0:
		w = [Pawn.of()]
	return add("choice", text, w, true, 2)

## The player's orders that change a life are roots of chains.
static func on_command(e: Dictionary, res: Dictionary) -> void:
	if not bool(res.get("ok", false)):
		return
	var a: Dictionary = e.get("args", {})
	var f = SysUtil.folk(int(e.get("folk_id", -1)))
	var nm: String = "You" if f == null else "You"
	match str(e.get("action", "")):
		"career_accept":
			choice("You took a job.")
		"career_decline":
			choice("You turned a job offer down.")
		"solo":
			match str(a.get("action", "")):
				"move":
					choice("You moved house.")
				"give_up_home":
					choice("You gave up the flat.")
				"leave_crew":
					choice("You left the crew.")
		"life":
			if str(a.get("action", "")) == "job_apply":
				choice("You applied for work.")

static func add(kind: String, text: String, who: Array, is_choice: bool, sev: int) -> int:
	if text == "":
		return -1
	var ids: Array = []
	for x in who:
		ids.append(int(x))
	var causes: Array = _find_causes(ids)
	var e: Dictionary = {"id": next_id, "day": SysUtil.day(), "kind": kind, "text": text, "who": ids, "causes": causes, "choice": is_choice, "sev": sev}
	next_id += 1
	entries.append(e)
	while entries.size() > CAP:
		entries.pop_front()
	return int(e["id"])

static func _find_causes(who: Array) -> Array:
	var out: Array = []
	if who.is_empty():
		return out
	var from: int = SysUtil.day() - LINK_DAYS
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if int(e["day"]) < from:
			break
		if not _can_cause(e):
			continue
		for w in who:
			if (e["who"] as Array).has(int(w)):
				out.append(int(e["id"]))
				break
		if out.size() >= MAX_CAUSES:
			break
	return out

static func get_entry(id: int) -> Dictionary:
	for e in entries:
		if int(e["id"]) == id:
			return e
	return {}

## The chain of causes above an entry, nearest first, up to `depth` steps.
static func chain(id: int, depth: int = 4) -> Array:
	var out: Array = []
	var cur: Dictionary = get_entry(id)
	var seen: Dictionary = {}
	while depth > 0 and not cur.is_empty():
		var cs: Array = cur["causes"]
		if cs.is_empty() or seen.has(int(cs[0])):
			break
		seen[int(cs[0])] = true
		cur = get_entry(int(cs[0]))
		if not cur.is_empty():
			out.append(cur)
		depth -= 1
	return out

## Entries caused (directly or up to `depth` steps down) by entry `id`.
static func effects_of(id: int, depth: int = 4) -> Array:
	var out: Array = []
	var frontier: Array = [id]
	var seen: Dictionary = {id: true}
	for _d in depth:
		var next: Array = []
		for e in entries:
			if seen.has(int(e["id"])):
				continue
			for c in e["causes"]:
				if frontier.has(int(c)):
					seen[int(e["id"])] = true
					out.append(e)
					next.append(int(e["id"]))
					break
		frontier = next
		if frontier.is_empty():
			break
	return out

static func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "next": next_id, "books": LifeSummary.to_dict()}

static func from_dict(d: Dictionary) -> void:
	reset()
	entries = (d.get("entries", []) as Array).duplicate(true)
	next_id = int(d.get("next", 1))
	for e in entries:
		e["id"] = int(e["id"])
		e["day"] = int(e["day"])
		e["sev"] = int(e.get("sev", 2))
		e["who"] = (e.get("who", []) as Array).map(func(x): return int(x))
		e["causes"] = (e.get("causes", []) as Array).map(func(x): return int(x))
	LifeSummary.from_dict(d.get("books", {}))
