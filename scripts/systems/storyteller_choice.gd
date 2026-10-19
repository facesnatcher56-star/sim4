class_name StorytellerChoice
extends RefCounted
## Player choices inside twists ("keep the wallet or return it?"). A card with `options` asks the player of the household (JusticePlayer.ask, the same prompt
## the case board uses) and the answer goes through the command layer (action "storyteller", args {action: "choose", id, option}) so it replays and syncs.
## Without a UI (tests, headless) or for a household nobody plays, the card's `default` is taken at once; townies and far lots take `auto`.
## An open choice is saved; after data choice_days the default is taken. Consequences are plain fx lists (money, reputation, conscience, friendship ...).

static func ccfg() -> int:
	return int(Storyteller.cfg().get("choice_days", 3))

static func open(key: String, cid: String, c: Dictionary, ctx: Dictionary) -> Dictionary:
	var hid: int = int(ctx["hid"])
	var pid: int = Players.player_of(hid)
	var text: String = StorytellerFx.fill(str(c.get("text", "")), ctx)
	if pid < 0:
		return resolve_option(c, str(c.get("auto", c.get("default", ""))), ctx)
	var id: int = int(Storyteller.stats.get("choice_seq", 0)) + 1
	Storyteller.stats["choice_seq"] = id
	var opts: Array = []
	var ids: Array = []
	for o in c.get("options", []):
		opts.append({"id": str(o["id"]), "label": StorytellerFx.fill(str(o["label"]), ctx)})
		ids.append(str(o["id"]))
	Storyteller.choices.append({"id": id, "card": cid, "ctx": ctx.duplicate(), "day": SysUtil.day(), "pid": pid, "title": str(c.get("title", "")), "text": text})
	while Storyteller.choices.size() > 6:
		Storyteller.choices.pop_front()
	var folk_id: int = int(ctx["folk_id"])
	JusticePlayer.ask(folk_id, str(c.get("title", "")), text, opts, func(choice):
		Commands.run({"player_id": pid, "folk_id": folk_id, "action": "storyteller", "args": {"action": "choose", "id": id, "option": str(choice)}}),
		str(c.get("default", ids[0] if not ids.is_empty() else "")))
	return {"text": text, "ok": true, "asked": id}

## Apply one option of a card: its fx, and the result text. Used for answered choices and for autonomous resolution.
static func resolve_option(c: Dictionary, option: String, ctx: Dictionary) -> Dictionary:
	var chosen: Dictionary = {}
	for o in c.get("options", []):
		if str(o["id"]) == option:
			chosen = o
	if chosen.is_empty():
		var opts: Array = c.get("options", [])
		if opts.is_empty():
			return {"text": "", "ok": false}
		chosen = opts[0]
	var was: bool = Storyteller.playing
	Storyteller.playing = true
	StorytellerFx.apply(chosen.get("fx", []), ctx)
	Storyteller.playing = was
	var intro: String = StorytellerFx.fill(str(c.get("lot_text", c.get("text", ""))) if bool(ctx["stat"]) else "", ctx)
	var outcome: String = StorytellerFx.fill(str(chosen.get("text", "")), ctx)
	Storyteller.bump("choice_" + str(chosen["id"]))
	return {"text": outcome if intro == "" else intro, "ok": true, "option": str(chosen["id"]), "outcome": outcome}

## Called by the command (and by expiry): resolve choice `id` with `option`. Returns {ok, msg}.
static func answer(id: int, option: String, player_id: int = -1) -> Dictionary:
	for i in Storyteller.choices.size():
		var row: Dictionary = Storyteller.choices[i]
		if int(row["id"]) != id:
			continue
		if player_id >= 0 and not Players.owns(player_id, int(row["ctx"]["hid"])):
			return {"ok": false, "msg": "That is not your decision."}
		Storyteller.choices.remove_at(i)
		var c: Dictionary = StorytellerDeck.card(str(row["card"]))
		var res: Dictionary = resolve_option(c, option, row["ctx"])
		var msg: String = str(res.get("outcome", ""))
		if msg != "":
			SysUtil.notify(msg, "info")
			StorytellerLog.add("answer", msg, "", str(row["ctx"]["key"]), [int(row["ctx"]["hid"])], "home", str(row["card"]))
		return {"ok": true, "msg": msg}
	return {"ok": false, "msg": "That choice is no longer open."}

## Daily: choices nobody answered take their default.
static func expire(day: int) -> void:
	for row in Storyteller.choices.duplicate():
		if day - int(row["day"]) >= ccfg():
			var c: Dictionary = StorytellerDeck.card(str(row["card"]))
			answer(int(row["id"]), str(c.get("default", "")))
