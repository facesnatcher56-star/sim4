class_name SuccessionText
extends RefCounted
## Every word the player reads about succession (task 15): plain, short, no ids. Who died, what happens, who you play now.

static func describe(kind: String, name: String, in_household: bool) -> String:
	var rel: String = {"picked": "the heir you chose", "spouse": "their spouse", "partner": "their partner", "child": "their child", "sibling": "their sibling",
		"housemate": "lives in the house", "relative": "a relative"}.get(kind, "")
	var where: String = "" if in_household else ", lives elsewhere"
	return "%s (%s%s)" % [name, rel, where]

## What the toast / chronicle says when control passes to someone.
static func took_over(head_name: String, heir_name: String, kind: String, moved_in: bool) -> String:
	var who: String = {"picked": "the heir you chose", "spouse": "their spouse", "partner": "their partner", "child": "their child", "sibling": "their sibling",
		"housemate": "a housemate", "relative": "a relative", "townie": "a neighbour", "new": "someone new"}.get(kind, "next in line")
	var base: String = "%s has died. %s, %s, " % [head_name, heir_name, who]
	if moved_in:
		return base + "moves into the family home. You now play %s." % heir_name
	return base + "takes over as head of the household. You now play %s." % heir_name

static func nobody_title(head_name: String) -> String:
	return "%s has died. Nobody is left in the house." % head_name

static func nobody_body(has_kin: bool) -> String:
	var s: String = "The town carries on, but you need somebody to play. "
	if has_kin:
		s += "A relative can move into the family home, or you can pick someone from town, or start a new family. "
	else:
		s += "Pick someone from town to move into the family home, or start a new family. "
	return s + "The town and its history stay as they are."

static func new_family(first_name: String) -> String:
	return "A new family has moved into the old home. You now play %s. The town and its history carry on." % first_name

## Morning reminder while nobody plays the household. `days_left` < 0 means "pick for me" is off.
static func nobody_reminder(days_left: int) -> String:
	if days_left < 0:
		return "Nobody is playing your household. Open the banner at the top and choose who to play."
	if days_left <= 1:
		return "Nobody is playing your household. If you do not choose today, someone will be picked for you tomorrow."
	return "Nobody is playing your household. Choose who to play, or someone will be picked for you in %d days." % days_left

## The line on the banner.
static func nobody_banner(days_left: int) -> String:
	if days_left < 0:
		return "Nobody is playing your household. The town is running by itself until you choose."
	return "Nobody is playing your household. Someone is picked for you in %d day%s unless you choose." % [days_left, "" if days_left == 1 else "s"]
