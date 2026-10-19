extends RefCounted
## Stage gates for ALL interactions (task 19j): after every content layer is installed, each interaction must say what a baby, toddler and child
## may do with it. "Says" = a test in its def that blocks the stage (`lacks_buff stage_x`, `has_buff stage_x`, `age_stage_is`, nested in `any`), which
## SysContent adds from the tags in data/aging.json (forbid_tags / allow_tags) or the def brings itself. Anything left over must be listed here with a reason,
## so a new repair / paperwork / crime interaction can never reach a baby by accident.

const K = preload("res://tests/systems_kit.gd")
const LITTLE := ["baby", "toddler", "child"]

## Tags that are harmless for little ones (care, play, family life, sleep, food, hygiene...): an interaction whose tags are ALL in this list passes.
const SAFE_TAGS := {
	"social": "talking and playing with others is fine at every stage", "fun": "play", "outdoor": "play outside", "kids": "made for children",
	"rest": "resting", "sleep": "sleeping", "relax": "relaxing", "food": "eating", "meal": "eating", "snack": "eating", "drink": "drinking",
	"hygiene": "washing", "clean": "tidying is a normal chore for a child (toddlers are blocked by the chore tag)", "creative": "drawing and building",
	"memory": "remembering the dead", "grave": "visiting a grave with the family", "health": "taking care of oneself", "medicine": "a parent or the child takes it",
	"clothes": "putting on a coat", "care": "helping someone who is hurt", "help": "helping someone who is hurt", "baby_care": "holding and teaching a little one (the target tests limit who)",
	"family": "family life", "holiday": "gifts and festivities", "gift": "giving a present", "away": "marker interaction", "emergency": "an emergency (collapse, lift stuck) happens to anyone",
	"collapsed": "an emergency (collapse) happens to anyone", "shelter": "taking cover is what a child should do", "visit": "going out with the family", "town": "going out with the family",
	"fire": "fleeing a fire, watching it or calling for help is what anyone does", "water": "paddling and swimming on holiday", "sun": "sunbathing on holiday",
	"snow": "play in the snow", "rain": "play in the rain", "nature": "a walk", "culture": "a visit with the family", "performance": "a show on holiday", "science": "wonder at a meteorite",
	"vacation": "a family holiday", "fitness": "swimming and hiking on holiday", "night": "only a tag", "cafe": "a family meal out",
	"kitchen": "a child may boil water for tea", "safety": "taking care", "conflict": "children argue (toddlers are blocked by the conflict tag)", "chore": "a child's chore (toddlers are blocked by the chore tag)",
	"skill": "learning something", "shop": "a child may buy a snack (toddlers are blocked by the shop tag)", "purchase": "a child may buy a snack (toddlers are blocked by the purchase tag)",
	"romance": "children's crushes are blocked by their own stage tests", "wedding": "the wedding def tests for the engagement",
}

## Interactions listed by id whose tags are not all in SAFE_TAGS but which are harmless or gated some other way, with the reason.
const ALLOWED := {
	"sys_staff": "the staff marker is only given to folk on a shift (workplaces check the career)",
	"apologize": "saying sorry is fine at every stage (target tests keep it to a real quarrel)",
	"seek_counselling": "needs a counselling booking; children are taken by their parents",
	"paternity_test": "needs a doubted birth; only the household's grown-ups ever have one",
	"place_visit": "children go out with the family",
	"anger_course": "needs a justice record",
	"read_town_law": "reading the notice board is harmless",
	"toss_coin": "play",
	"play_on_playground": "made for children",
	"order_groceries": "a child may ask for the shopping",
	"plan_vacation": "children can help plan the family holiday",
	"admire_slots": "watching the lights on a holiday",
	"bridge_tour": "a tour with the family",
	"browse_shop": "window shopping on holiday",
	"buy_souvenir": "a child may spend pocket money on a souvenir",
	"get_massage": "a spa day on a holiday",
	"hospital_stay": "any stage can be admitted to the ward",
	"confront_intruder": "anybody can shout at an intruder (the crime rules decide the rest)",
	"pay_blackmailer": "blackmail targets are grown-ups; the case rules check the victim",
	"refuse_blackmailer": "as above", "report_blackmail": "as above", "confront_blackmailer": "as above",
	"douse_fireplace": "a child may put out the hearth", "use_extinguisher": "the fire rules decide who can act", "call_firefighters": "anybody can ring the fire brigade",
	"watch_fire": "watching", "flee_fire": "running away",
	"boil_water": "a child may make tea",
	"bed_rest": "only offered to a pregnant folk (a baby can never be)",
}

func run() -> Array:
	var f: Array = []
	K.setup()
	SysContent.install_all()
	NeighborhoodContent.install()
	Workplace.install()
	var inter: Dictionary = SimEnv.data().interactions()
	K.expect(f, inter.size() > 250, "the full interaction set is loaded (%d)" % inter.size())
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interactions.json").trim_prefix("﻿"))
	var bad: Array = []
	for iid in inter:
		if base.has(iid):
			continue                                 # the original household interactions were stage-tuned by hand and are covered by the aging tests
		var d: Dictionary = inter[iid]
		var open_for: Array = []
		for st in LITTLE:
			if not blocks(d, st):
				open_for.append(st)
		if open_for.is_empty():
			continue
		var tags: Array = d.get("tags", [])
		var all_safe: bool = tags.size() > 0
		for t in tags:
			if not SAFE_TAGS.has(t):
				all_safe = false
		if all_safe or ALLOWED.has(iid):
			continue
		bad.append("%s (%s; tags %s)" % [iid, ",".join(open_for), ",".join(tags)])
	bad.sort()
	K.expect(f, bad.is_empty(), "interactions with no stage gate for little ones and no entry in this test: %s" % "; ".join(bad))
	# the chaos counterplay never reaches a baby, a toddler or a child
	for iid in ["fix_leak", "shut_off_gas", "report_identity_theft", "check_pipes", "call_plumber", "call_handyperson", "call_exterminator", "set_roach_traps", "call_gas_company"]:
		for st in LITTLE:
			K.expect(f, blocks(inter[iid], st), "%s is not offered to a %s" % [iid, st])
	for iid in ["fix_leak", "shut_off_gas"]:
		K.expect(f, blocks(inter[iid], "teen") and not blocks(inter[iid], "adult") and not blocks(inter[iid], "elder"), "%s is for adults and elders only" % iid)
	for iid in ALLOWED:
		K.expect(f, inter.has(iid), "ALLOWED names a real interaction: %s" % iid)
	K.teardown()
	return f

## True when the def's tests (or target tests) make `stage` unable to use it. Only stage keys count; every other test is treated as "can pass".
static func blocks(d: Dictionary, stage: String) -> bool:
	return _all_block(d.get("tests", []), stage) or _all_block(d.get("target_tests", []), stage)

static func _all_block(tests: Array, stage: String) -> bool:
	for t in tests:
		if _one_blocks(t, stage):
			return true
	return false

static func _one_blocks(t: Dictionary, stage: String) -> bool:
	for k in t:
		var v = t[k]
		match k:
			"lacks_buff":
				if str(v) == "stage_" + stage:
					return true
			"has_buff":
				if str(v).begins_with("stage_") and str(v) != "stage_" + stage:
					return true
			"age_stage_is":
				var ok: Array = v if v is Array else [v]
				if not ok.has(stage):
					return true
			"any":
				var all: bool = (v as Array).size() > 0
				for sub in v:
					if not _one_blocks(sub, stage):
						all = false
				if all:
					return true
	return false
