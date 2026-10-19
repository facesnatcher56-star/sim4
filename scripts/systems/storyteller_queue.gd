class_name StorytellerQueue
extends RefCounted
## Things that happen a few days from now, saved with the storyteller: a foreshadowed card waiting for its day ("play"), a chain event ("chain": one thing
## led to another, data chains), a follow-up card for a household ("home_card": a friend asks for a bed), a thank-you visit ("thanks").
## Capped at 40; the oldest are dropped.

const CAP := 40

static func add(row: Dictionary) -> void:
	Storyteller.queue.append(row)
	while Storyteller.queue.size() > CAP:
		Storyteller.queue.pop_front()

## The data chains: after card `cid` played in a zone, related events may follow nearby after a few days.
static func chain_from(cid: String, ctx: Dictionary) -> void:
	for ch in Storyteller.cfg().get("chains", []):
		if str(ch["from"]) != cid:
			continue
		if Storyteller.rng.randf() >= float(ch["chance"]):
			continue
		var zone: String = str(ctx.get("zone", ""))
		if zone == "":
			continue
		var d: Array = ch["delay"]
		add({"kind": "chain", "card": str(ch["to"]), "due": SysUtil.day() + Storyteller.rng.randi_range(int(d[0]), int(d[1])), "key": "d" + zone, "zone": zone,
			"lot": int(ctx.get("lot", 0)), "who": int(ctx.get("who", -1))})

static func on_day(day: int) -> void:
	StorytellerChoice.expire(day)
	var keep: Array = []
	var due: Array = []
	for r in Storyteller.queue:
		if int(r["due"]) <= day:
			due.append(r)
		else:
			keep.append(r)
	Storyteller.queue = keep
	for r in due:
		_run(r as Dictionary)

static func _run(r: Dictionary) -> void:
	match str(r.get("kind", "")):
		"play":
			var c: Dictionary = StorytellerDeck.card(str(r["card"]))
			var key: String = str(r["key"])
			if not c.is_empty() and Storyteller.cat_on(str(c.get("cat", ""))) and StorytellerPlay.can_play(str(r["card"]), c, key):
				StorytellerPlay.execute(key, str(r["card"]), c, _ctx_in(r["ctx"]), {"from_sign": true})
		"chain":
			var c2: Dictionary = StorytellerDeck.card(str(r["card"]))
			var key2: String = str(r["key"])
			if c2.is_empty() or not Storyteller.cat_on(str(c2.get("cat", ""))) or not StorytellerPlay.can_play(str(r["card"]), c2, key2):
				return
			var e: Dictionary = StorytellerBudget.entry(key2)
			e["points"] = maxf(float(e["points"]) - StorytellerBudget.size_cost(str(c2.get("size", "small"))), float(StorytellerBudget.bcfg().get("floor", -4.0)))
			Storyteller.bump("chains")
			StorytellerPlay.card(key2, str(r["card"]), {"chain": true, "ctx": {"lot": int(r.get("lot", 0)), "who": int(r.get("who", -1))}})
		"home_card":
			var hid: int = int(r["hid"])
			var c3: Dictionary = StorytellerDeck.card(str(r["card"]))
			if c3.is_empty() or StorytellerPlay.residents_of(hid).is_empty() or not Storyteller.cat_on(str(c3.get("cat", ""))):
				return
			var key3: String = "h%d" % hid
			var ctx: Dictionary = StorytellerPlay.make_ctx(key3, c3, {"ctx": {"other": int(r["other"])}})
			ctx["folk_id"] = int(r["folk_id"])
			Storyteller.bump("followups")
			StorytellerPlay.execute(key3, str(r["card"]), c3, ctx, {"followup": true})
		"thanks":
			if Story.townies.has(int(r["other"])) and SysUtil.folk(int(r["folk_id"])) != null:
				StoryThreads._visit({"text": "{other} dropped by to say thanks for the kindness."}, int(r["folk_id"]), int(r["other"]))

static func _ctx_in(src: Dictionary) -> Dictionary:
	var c: Dictionary = src.duplicate(true)
	SysUtil.ints_in(c, ["hid", "folk_id", "other", "lot", "who"])
	return c
