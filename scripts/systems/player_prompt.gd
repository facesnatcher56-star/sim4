class_name PlayerPrompt
extends RefCounted
## Task 48: the player decides everything that involves their character. Whatever used to happen to the pawn on its own (a romance step, a proposal, a
## wedding, a baby, a party invitation, a request for money) is put to the player as a question through JusticePlayer.ask (the CasePrompt window).
## The question says WHO asks, WHAT they want and WHY (a real reason), and each answer says what it DOES. It never states how the two know each other
## (no relationship words, durations or scores); that only shapes the VOICE (warm, formal, shy, bold). The same line is never used twice in a row for the
## same pair, and not again until most others have been used (the rule of the thought lines). Text and variants: data/prompts.json.
##   PlayerPrompt.ask("loan", pawn_id, other_id, {"amount": 30, "why": "..."}, on_choice(choice_id), default_id)
## Without a UI (headless) the default answer is used at once (JusticePlayer.ask does that).

static var used: Dictionary = {}         # "type|pair|part" -> [indices used in the present round]
static var last: Dictionary = {}         # same key -> index used last
static var asked: Dictionary = {}        # "type|pair" -> day last asked (cooldown)

static func reset() -> void:
	used = {}
	last = {}
	asked = {}

static func cfg() -> Dictionary:
	return (SysUtil.table("prompts").get("types", {}) as Dictionary)

## May this question be asked again today? (cooldown days since the last time for this pair)
static func ready(type: String, a: int, b: int, cooldown: int) -> bool:
	return SysUtil.day() - int(asked.get("%s|%s" % [type, SysUtil.pair_key(a, b)], -999)) >= cooldown

## Index into `n` choices for a memory key: not the last one, not one already used this round; a new round starts when most are used.
static func _pick(key: String, n: int) -> int:
	if n <= 1:
		return 0
	var u: Array = used.get(key, [])
	if u.size() >= n - 1:
		u = []
	var pool: Array = []
	for i in n:
		if not u.has(i) and i != int(last.get(key, -1)):
			pool.append(i)
	if pool.is_empty():
		pool = range(n)
	var i2: int = int(pool[SysUtil.rng.randi_range(0, pool.size() - 1)])
	u.append(i2)
	used[key] = u
	last[key] = i2
	return i2

## The voice of the asker towards this person: partners speak warmly, strangers formally; shy and bold natures colour it. Never shown.
static func voice(asker: int, to: int) -> String:
	var tr: Array = RelationshipBits.traits_of(asker)
	if tr.has("shy"):
		return "shy"
	if tr.has("hot_headed") or tr.has("showoff"):
		return "bold"
	var close: bool = RelationshipService.value(asker, to, "friendship") >= 35.0 or RelationshipBits.has_flag(asker, to, "sweetheart") or RelationshipBits.has_flag(asker, to, "partner") or RelationshipBits.has_flag(asker, to, "spouse")
	return "warm" if close else "formal"

static func _fill(t: String, ctx: Dictionary, other: int) -> String:
	var out: String = t
	for k in ctx:
		out = out.replace("{%s}" % str(k), str(ctx[k]))
	out = out.replace("{name}", CrimePerson.name_of(other))
	return Sexes.fill(out, other)

## Put the question to the pawn. `other` asks (a townie or a Folk). ctx slots: why (index text from the data if absent), amount, place. Returns false when
## the type is unknown or the pawn cannot be asked right now (not a resident, or already waiting on this pair).
static func ask(type: String, pawn: int, other: int, ctx: Dictionary, on_choice: Callable, default_id: String = "no") -> bool:
	var def: Dictionary = cfg().get(type, {})
	if def.is_empty() or not CrimePerson.is_player(pawn):
		return false
	var pk: String = "%s|%s" % [type, SysUtil.pair_key(pawn, other)]
	asked[pk] = SysUtil.day()
	var c: Dictionary = ctx.duplicate()
	if not c.has("place"):
		c["place"] = "home"
	if not c.has("why"):
		var whys: Array = def.get("why", [""])
		c["why"] = str(whys[_pick(pk + "|why", whys.size())])
	var v: String = voice(other, pawn)
	var lines: Array = (def.get("lines", {}) as Dictionary).get(v, [])
	if lines.is_empty():
		lines = (def.get("lines", {}) as Dictionary).values()[0]
	var text: String = str(lines[_pick(pk + "|line|" + v, lines.size())])
	text = text.replace("{why}", str(c["why"]))
	var titles: Array = def.get("titles", [type])
	var title: String = str(titles[_pick(pk + "|title", titles.size())])
	var opts: Array = []
	for o in def.get("options", []):
		var labels: Array = o.get("labels", [str(o["id"])])
		var hints: Array = o.get("hints", [""])
		var label: String = str(labels[_pick("%s|opt|%s" % [pk, str(o["id"])], labels.size())])
		var hint: String = str(hints[_pick("%s|hint|%s" % [pk, str(o["id"])], hints.size())])
		opts.append({"id": str(o["id"]), "label": _fill("%s (%s)" % [label, hint] if hint != "" else label, c, other)})
	LifeLedger.add("prompt", "%s asked you (%s)." % [CrimePerson.name_of(other), type], [pawn, other], false, 1)
	JusticePlayer.ask(pawn, _fill(title, c, other), _fill(text, c, other), opts, on_choice, default_id)
	return true

static func to_dict() -> Dictionary:
	return {"used": used.duplicate(true), "last": last.duplicate(), "asked": asked.duplicate()}

static func from_dict(d: Dictionary) -> void:
	reset()
	used = (d.get("used", {}) as Dictionary).duplicate(true)
	last = (d.get("last", {}) as Dictionary).duplicate()
	asked = (d.get("asked", {}) as Dictionary).duplicate()
