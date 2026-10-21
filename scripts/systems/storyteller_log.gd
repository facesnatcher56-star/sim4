class_name StorytellerLog
extends RefCounted
## The Storyteller log ("what happened and why", for the Town panel): plain words, newest last, no spoilers (an event is written only when it has happened;
## signs and rumours say what people noticed, never what is coming). Also foreshadowing: before a medium or big BAD card the storyteller may post a sign
## ("strange cars on the street at night") and play the card 1-3 days later, so the chaos feels fair. How often is the personality's `foreshadow` chance.
## Capped (data log_cap). Toasts for ripples are capped per household per day (data toast_cap_per_day).

static var entries: Array = []       # [{day, kind, text, why, key, hids, scope, card}]
static var _toasts: Dictionary = {}  # hid -> [day, count]  (not saved)
static var total: int = 0            # lines ever added (not saved): tests read the new ones after each day

static func reset() -> void:
	entries.clear()
	_toasts.clear()
	total = 0

static func cap() -> int:
	return int(Storyteller.cfg().get("log_cap", 120))

static func add(kind: String, text: String, why: String, key: String, hids: Array, scope: String, card: String, size: String = "", tone: String = "") -> void:
	if text == "":
		return
	entries.append({"day": SysUtil.day(), "kind": kind, "text": text, "why": why, "key": key, "hids": hids.duplicate(), "scope": scope, "card": card, "size": size, "tone": tone})
	total += 1
	while entries.size() > cap():
		entries.pop_front()

static func recent(n: int) -> Array:
	return entries.slice(maxi(entries.size() - n, 0))

## "Day 12: A break-in on the east side. (Money was tight.)"
static func lines(n: int, hid: int = 0) -> Array:
	var out: Array = []
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if hid > 0 and not (e["hids"] as Array).has(hid) and str(e["scope"]) != "town":
			continue
		out.push_front("Day %d: %s%s" % [int(e["day"]), str(e["text"]), (" (%s)" % str(e["why"])) if str(e["why"]) != "" else ""])
		if out.size() >= n:
			break
	return out

# ------------------------------------------------------------------ events
static func _why(key: String, c: Dictionary, extra: Dictionary) -> String:
	var t: Dictionary = Storyteller.cfg().get("text", {})
	if bool(extra.get("chain", false)):
		return str(t.get("why_chain", ""))
	if bool(extra.get("guard", false)) or extra.has("for_key"):
		return str(t.get("why_quiet", ""))
	if c.has("cycle"):
		return str(t.get("why_cycle", ""))
	var tier: String = StorytellerBudget.tier_of(key)
	var tone: String = str(c.get("tone", "mixed"))
	var cat: String = str(c.get("cat", ""))
	if tier == "poor" and cat == "money" and tone == "bad":
		return str(t.get("why_money_low", ""))
	if tier == "rich" and cat in ["money", "crime"] and tone == "bad":
		return str(t.get("why_money_high", ""))
	if tone == "good" and StorytellerBudget.mercy_on(key):
		return str(t.get("why_mercy", ""))
	if StorytellerChaos.level_of(key) > 1.6:
		return str(t.get("why_streak", ""))
	return str(t.get("why_default", ""))

static func event(cid: String, c: Dictionary, ctx: Dictionary, res: Dictionary, scope: String, extra: Dictionary) -> void:
	var text: String = str(res.get("text", ""))
	if text == "":
		text = StorytellerFx.fill(str(c.get("title", cid)), ctx)
	var hids: Array = [int(ctx["hid"])] if int(ctx.get("hid", 0)) > 0 else []
	add("event", text, _why(str(ctx.get("key", "")), c, extra), str(ctx.get("key", "")), hids, scope, cid, str(c.get("size", "small")), str(c.get("tone", "mixed")))

# ------------------------------------------------------------------ toasts (capped per household per day)
static func toast(hid: int, text: String, kind: String = "info") -> void:
	if text == "" or Players.player_of(hid) < 0:
		return
	var e: Array = _toasts.get(hid, [-1, 0])
	if int(e[0]) != SysUtil.day():
		e = [SysUtil.day(), 0]
	if int(e[1]) >= int(Storyteller.cfg().get("toast_cap_per_day", 3)):
		return
	e[1] = int(e[1]) + 1
	_toasts[hid] = e
	SysUtil.notify(text, kind)

# ------------------------------------------------------------------ foreshadowing
## Returns true when the card was postponed behind a sign.
static func foreshadow(key: String, cid: String, c: Dictionary, ctx: Dictionary, extra: Dictionary) -> bool:
	if not bool(Storyteller.cfg().get("foreshadow_signs", false)):
		return false          # owner: no signs, no warnings: things just happen from their own causes
	if str(c.get("size", "small")) == "small" or str(c.get("tone", "")) != "bad" or (c.get("signs", []) as Array).is_empty():
		return false
	if extra.has("from_sign") or extra.has("chain") or extra.has("followup") or extra.has("guard") or extra.has("for_key"):
		return false
	if Storyteller.rng.randf() >= float(Storyteller.param("foreshadow", 0.8)):
		return false
	var signs: Array = c["signs"]
	var sign_text: String = StorytellerFx.fill(str(signs[Storyteller.rng.randi_range(0, signs.size() - 1)]), ctx)
	var stored: Dictionary = ctx.duplicate(true)
	stored.erase("target")
	StorytellerQueue.add({"kind": "play", "card": cid, "key": key, "ctx": stored, "due": SysUtil.day() + Storyteller.rng.randi_range(1, 3)})
	var hids: Array = []
	if int(ctx.get("hid", 0)) > 0:
		hids = [int(ctx["hid"])]
		toast(int(ctx["hid"]), sign_text)
	else:
		for hid in CityState.full_households():
			if StorytellerDistrict.distance(CityState.zone_of_household(int(hid)), str(ctx.get("zone", ""))) <= int(StorytellerRipple.rcfg().get("near_zones", 0)):
				hids.append(int(hid))
				toast(int(hid), sign_text)
	add("sign", sign_text, "", key, hids, "home" if not hids.is_empty() else "city", cid)
	Storyteller.bump("signs")
	return true

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true)}

static func from_dict(d: Dictionary) -> void:
	entries.clear()
	for e in d.get("entries", []):
		var r: Dictionary = (e as Dictionary).duplicate(true)
		SysUtil.ints_in(r, ["day"])
		r["hids"] = SysUtil.to_ints(r.get("hids", []))
		entries.append(r)
