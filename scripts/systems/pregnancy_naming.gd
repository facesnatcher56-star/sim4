class_name PregnancyNaming
extends RefCounted
## Naming the baby (task 18 part 5). A new baby always gets a name by its sex at once (townies and every folk the player does not steer keep
## it). For the PLAYER's households a prompt follows with random suggestions of the baby's sex; the command `pregnancy name_baby {baby_id,
## name}` (PregnancyCmd) lets the UI offer free typing too. The surname is the mother's.

const MAX_LEN := 14

## Letters, spaces and hyphens only; 2..14 long; "" when not usable.
static func clean(raw: String) -> String:
	var s: String = raw.strip_edges()
	var out := ""
	for i in s.length():
		var ch: String = s[i]
		if ch.to_upper() != ch.to_lower() or ch == " " or ch == "-":
			out += ch
	out = out.strip_edges()
	if out.length() < 2 or out.length() > MAX_LEN:
		return ""
	return out.substr(0, 1).to_upper() + out.substr(1)

static func rename(baby_id: int, first: String) -> bool:
	var b = SysUtil.folk(baby_id)
	var nm: String = clean(first)
	if b == null or nm == "" or str(b.age_stage) != "baby":
		return false
	var surname: String = Aging._surname(str(b.name))
	b.name = nm + " " + surname if surname != str(b.name) else nm
	Family.note_person(baby_id, str(b.name))
	SysUtil.game_event("baby_named", {"folk_id": baby_id, "name": str(b.name)})
	return true

## Ask the player who controls the mother. Each baby gets its own prompt with suggestions of its sex.
static func offer(mother_id: int, babies: Array) -> void:
	if not CrimePerson.is_player(mother_id):
		return
	var n: int = int(Pregnancy.cfg("birth").get("name_suggestions", 3))
	for b in babies:
		var opts: Array = [{"id": "keep", "label": "Keep %s" % Names.first_of(str(b.name))}]
		for nm in Names.suggestions(str(b.sex), n):
			opts.append({"id": "name:" + str(nm), "label": str(nm)})
		var bid: int = int(b.id)
		JusticePlayer.ask(mother_id, "Name your baby", "A new %s! What should %s be called?" % [Sexes.word_for(str(b.sex), "child"), Sexes.word_for(str(b.sex), "they")],
			opts, func(choice): _picked(bid, str(choice)), "keep")

static func _picked(baby_id: int, choice: String) -> void:
	if choice.begins_with("name:"):
		rename(baby_id, choice.substr(5))
