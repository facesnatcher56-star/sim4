class_name LifeLedger
extends RefCounted
## Task 44: the cause links of a life. Every event with an effect on somebody (a chronicle note of severity 2 or more) and every choice the player made
## (a command, a prompt answer) is one entry: id, day, kind, text, who it touched, the entries that caused it, whether it was the player's choice.
## A new entry is linked only to an earlier entry that really caused it: CAUSES names, for each kind of effect, the kinds of event that can cause it (a
## break-in leads to an arrest, a layoff to a new job, an engagement to a wedding). Kinds with no rule take no cause: a power cut, the weather or a wedding
## never borrow an unrelated event as their "because". Nothing here is shown during play: the end-of-life summary (LifeSummary) reads it.
## Milestones that are game events (jobs, romance, a death in the family) come from LifeLedgerEvents. Compact: severity 2 or more, capped at CAP.

const CAP := 700
const LINK_DAYS := 30
## effect kind -> kinds that can cause it (prefixes; "choice" = a choice of the player). Chronicle kinds and the LifeLedgerEvents kinds.
const CAUSES := {
	"jailed": ["crime", "attempt", "heist", "fight", "gang", "choice", "drama"], "released": ["jailed"], "civil_": ["crime", "fight", "fraud", "drama"],
	"eviction": ["layoff", "fired", "debt", "foreclosure"], "foreclosure": ["layoff", "fired", "debt"], "move": ["eviction", "fire", "foreclosure", "choice"],
	"moved": ["eviction", "fire", "foreclosure", "choice"], "hospital": ["fight", "car_crash", "fire", "collapse", "crime", "attempt", "gas_leak", "addiction"],
	"death": ["hospital", "fire", "collapse", "fight", "car_crash", "crime", "addiction", "gas_leak"], "fire": ["gas_leak", "fire"],
	"revenge": ["secret_out", "crime", "fight", "drama"], "forgiveness": ["secret_out", "crime", "fight", "revenge", "drama"], "separation": ["secret_out", "drama"],
	"recovery": ["addiction", "hospital"], "redemption": ["jailed", "released"], "child_placed": ["child_services"], "child_returned": ["child_placed"]}

## A kind matches a rule word when it is that word, or the word ends in "_" and names a family ("civil_" = civil_suit, civil_won...): "fired" is not "fire".
static func kind_is(kind: String, word: String) -> bool:
	return kind == word or (word.ends_with("_") and kind.begins_with(word))

static func _can_cause(effect: String, e: Dictionary) -> bool:
	var rule: Array = CAUSES.get(effect, [])
	for k in CAUSES:
		if rule.is_empty() and kind_is(effect, str(k)):
			rule = CAUSES[k]
	var ck: String = "choice" if bool(e["choice"]) else str(e["kind"])
	for w in rule:
		if kind_is(ck, str(w)):
			return true
	return false

static var entries: Array = []
static var next_id: int = 1

static func reset() -> void:
	entries = []
	next_id = 1

## From ChronicleHook.note: who = the subjects, or the residents of the household named by lot "home:<hid>".
static func from_chronicle(p: Dictionary) -> void:
	PhoneOwn.on_chronicle(p)          # a robbery takes the phone, a fall breaks it
	if int(p.get("severity", 1)) < 2 or str(p.get("kind", "")) in ["wedding", "moved_in"]:          # these two come from LifeLedgerEvents, with the people and the cause
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
	return _put(kind, text, ids, is_choice, sev, _find_causes(kind, ids, []), "")

## A milestone with its own list of possible cause kinds (LifeLedgerEvents). Skipped when the same thing about the same people is already there today.
static func add_linked(kind: String, text: String, who: Array, sev: int, cause_kinds: Array, tag: String) -> int:
	var ids: Array = []
	for x in who:
		ids.append(int(x))
	for i in range(entries.size() - 1, maxi(entries.size() - 12, 0) - 1, -1):
		var o: Dictionary = entries[i]
		if int(o["day"]) == SysUtil.day() and str(o["text"]) == text:
			return int(o["id"])
	return _put(kind, text, ids, false, sev, _find_causes(kind, ids, cause_kinds), tag)

static func _put(kind: String, text: String, ids: Array, is_choice: bool, sev: int, causes: Array, tag: String) -> int:
	var e: Dictionary = {"id": next_id, "day": SysUtil.day(), "kind": kind, "text": text, "who": ids, "causes": causes, "choice": is_choice, "sev": sev}
	if tag != "":
		e["tag"] = tag
	next_id += 1
	entries.append(e)
	while entries.size() > CAP:
		entries.pop_front()
	return int(e["id"])

## The latest earlier entry, within LINK_DAYS, about the same people, that can cause this kind (CAUSES, or the given kinds). At most one.
static func _find_causes(kind: String, who: Array, kinds: Array) -> Array:
	if who.is_empty():
		return []
	var from: int = SysUtil.day() - LINK_DAYS
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if int(e["day"]) < from:
			break
		var ok: bool = _can_cause(kind, e) if kinds.is_empty() else kinds.any(func(k): return kind_is("choice" if bool(e["choice"]) else str(e["kind"]), str(k)))
		if not ok:
			continue
		for w in who:
			if (e["who"] as Array).has(int(w)):
				return [int(e["id"])]
	return []

## Has a tagged milestone (LifeLedgerEvents) already been written for these two people?
static func has_tag(a: int, b: int, tag: String) -> bool:
	for e in entries:
		if str(e.get("tag", "")) == tag and (e["who"] as Array).has(a) and (e["who"] as Array).has(b):
			return true
	return false

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
	return {"entries": entries.duplicate(true), "next": next_id, "books": LifeSummary.to_dict(), "prompts": PlayerPrompt.to_dict()}

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
	PlayerPrompt.from_dict(d.get("prompts", {}))
