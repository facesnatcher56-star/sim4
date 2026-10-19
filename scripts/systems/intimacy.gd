class_name Intimacy
extends RefCounted
## Quiet evenings together (task 18 part 2), non-graphic: the actions "Get Intimate (careful)" and "(no protection)" show a short scene and a
## warm mood, and may lead to an UNPLANNED pregnancy (Conception.intimate): small chance without protection, very small with it. The same dice
## run once a day for the couples of the controlled households (StoryMilestones), where the couple's traits pick whether they are careful.
## RomanceRules.allowed guards both doors; a same-sex couple has the evening but cannot conceive. Nothing here ever names a body part.

static func on_game_event(ev: String, payload: Dictionary) -> void:
	if ev != "intimate_careful" and ev != "intimate_open":
		return
	var a: int = int(payload.get("folk_id", -1))
	var b: int = int(payload.get("target_id", -1))
	if not RomanceRules.allowed(a, b):
		return
	Conception.intimate(a, b, "protected" if ev == "intimate_careful" else "none")

## One day of a committed couple: maybe an evening together. Returns true when it happened.
static func daily_couple(a: int, b: int) -> bool:
	var cc: Dictionary = Pregnancy.cfg("conception")
	if not RomanceRules.allowed(a, b):
		return false
	var ro: float = minf(RelationshipService.value(a, b, "romance"), RelationshipService.value(b, a, "romance"))
	if ro < float(cc.get("min_romance", 40)) or Pregnancy.rng.randf() >= float(cc.get("intimacy_per_day", 0.25)):
		return false
	RelationshipService.add_both(a, b, "romance", 1.5)
	var fa = SysUtil.folk(a)
	var fb = SysUtil.folk(b)
	if fa != null:
		fa.add_buff("bonded_glow")
	if fb != null:
		fb.add_buff("bonded_glow")
	Conception.intimate(a, b, Conception.pick_protection(a, b))
	return true
