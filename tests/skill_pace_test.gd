extends RefCounted
## Skills level up fast at first, then slower: the old 5500 xp no longer masters a skill, and each level past 3 costs more than the last.

func run() -> Array:
	var f: Array = []
	var a := Folk.create("Pace", [])
	for i in 55:
		a.add_skill_xp("logic", 100.0)
	if a.skill_level("logic") >= 10:
		f.append("5500 xp must not master a skill (level %d)" % a.skill_level("logic"))
	if a.skill_level("logic") < 6:
		f.append("5500 xp still gives a solid level (%d)" % a.skill_level("logic"))
	var b := Folk.create("Early", [])
	b.add_skill_xp("cooking", Folk.xp_for_level(3))
	if b.skill_level("cooking") != 3:
		f.append("the first levels are unchanged (%d)" % b.skill_level("cooking"))
	var c := Folk.create("Grind", [])
	for i in 130:
		c.add_skill_xp("fitness", 100.0)
	if c.skill_level("fitness") >= 10:
		f.append("13000 xp is not yet mastery (level %d)" % c.skill_level("fitness"))
	return f
