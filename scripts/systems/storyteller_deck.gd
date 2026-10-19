class_name StorytellerDeck
extends RefCounted
## The event deck (data/storyteller_cards.json). pick(key, size) draws one eligible card of that size for a key, weighted by
##   the card's own weight x wealth (rich households get burglaries and audits, poor ones windfalls and eviction scares) x the district kind's mix for the card's tags
##   x heat (related events nearby) x tone (the personality's good share, mercy after a rough patch) x a cooldown for cards just played.
## Eligibility: the category and "Mature life events" switches, the scope (household / lot / district / town), the card's `when` conditions, the incident's own
## conditions, the pile-on cap for bad big cards, and the one-arc-per-household / one-town-arc / one-cycle rules.

static func cards() -> Dictionary:
	return SysUtil.table("storyteller_cards").get("cards", {})

static func card(cid: String) -> Dictionary:
	if cid.begins_with("arc:"):
		return StorytellerArcs.stage_card(cid)      # a climax choice of an arc
	return cards().get(cid, {})

static func scope_ok(c: Dictionary, key: String) -> bool:
	var scope: String = str(c.get("scope", "home"))
	match StorytellerBudget.kind_of(key):
		"home":
			return scope == "home"
		"lot":
			return scope == "home" and (bool(c.get("lot", false)) or c.has("lot_text"))
		"district":
			return scope == "district"
	return scope == "town"

static func weight_of(cid: String, c: Dictionary, key: String) -> float:
	var w: float = float(c.get("weight", 0.0))
	if w <= 0.0:
		return 0.0
	var e: Dictionary = StorytellerBudget.entry(key)
	var tier: String = StorytellerBudget.tier_of(key)
	w *= float((c.get("wealth", {}) as Dictionary).get(tier, 1.0))
	var zone: String = StorytellerBudget.zone_of_key(key)
	var mix: Dictionary = StorytellerDistrict.kind_def(zone).get("mix", {})
	var best: float = 1.0
	for t in c.get("tags", []):
		best = maxf(best, float(mix.get(str(t), 1.0)))
	w *= best
	w *= StorytellerChaos.heat_mult(zone, c.get("tags", []))
	var good: float = float(Storyteller.param("good_share", 0.5))
	var mercy: float = float(Storyteller.param("mercy", 0.5)) if StorytellerBudget.mercy_on(key) else 0.0
	match str(c.get("tone", "mixed")):
		"good":
			w *= 2.0 * good * (1.0 + mercy)
		"bad":
			w *= 2.0 * (1.0 - good) * (1.0 - mercy)
	var last: int = int(Storyteller.played.get("%s|%s" % [key, cid], -99))
	var cd: int = int(c.get("cooldown", 3 if str(c.get("scope", "")) == "district" else 9))
	if SysUtil.day() - last < cd:
		w *= 0.05
	if c.has("cycle") or c.has("arc"):
		w *= float(e.get("level", 1.0))
	return w

## True when the card may be played for this key right now (used by pick and by tests).
static func eligible(cid: String, c: Dictionary, key: String, size: String = "") -> bool:
	if size != "" and str(c.get("size", "small")) != size:
		return false
	if not scope_ok(c, key) or not Storyteller.cat_on(str(c.get("cat", ""))):
		return false
	if bool(c.get("mature", false)) and not PregnancyLoss.mature_enabled():
		return false
	if c.has("arc") and not Storyteller.cat_on("arcs"):
		return false
	if str(c.get("size", "")) == "big" and str(c.get("tone", "")) == "bad":
		var e: Dictionary = StorytellerBudget.entry(key)
		if SysUtil.day() - int(e["last_bad_big"]) < int(Storyteller.param("bad_big_gap_days", 7)):
			return false
	return StorytellerPlay.can_play(cid, c, key)

static func pick(key: String, size: String, opts: Dictionary = {}) -> String:
	var tp := PerfProf.start()
	StorytellerScan.begin()
	var ids: Array = []
	var ws: Array = []
	var all: Dictionary = cards()
	var names: Array = all.keys()
	names.sort()
	for cid in names:
		var c: Dictionary = all[cid]
		if not eligible(str(cid), c, key, size):
			continue
		if bool(opts.get("need_near", false)) and not (c.get("ripple", {}) as Dictionary).has("near"):
			continue
		var w: float = weight_of(str(cid), c, key)
		if w > 0.0:
			ids.append(str(cid))
			ws.append(w)
	StorytellerScan.end()
	var pick = Storyteller.pick_weighted(ids, ws)
	PerfProf.stop("story/pick", tp)
	return str(pick) if pick != null else ""
