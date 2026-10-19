class_name RomanceCleanup
extends RefCounted
## After a load: wipe romance, romantic bits, marriages/engagements and hidden affairs of pairs RomanceRules forbids (old saves).

static func run() -> int:
	var fixed: int = 0
	for key in RelationshipService.pairs.keys():
		var p: Dictionary = RelationshipService.pairs[key]
		var a: int = int(p["lo"])
		var b: int = int(p["hi"])
		if RomanceRules.allowed(a, b) or not _has_romance(p, a, b):
			continue
		_clear(p, a, b)
		fixed += 1
		print("[romance] cleared a forbidden romantic pair on load: %d and %d (%s)" % [a, b, RomanceRules.why_not(a, b)])
	var keep: Array = []
	for af in RelationshipService.affairs:
		if RomanceRules.allowed(int(af["cheater"]), int(af["other"])) and RomanceRules.allowed(int(af["cheater"]), int(af["victim"])):
			keep.append(af)
		else:
			fixed += 1
	RelationshipService.affairs = keep
	return fixed

static func _has_romance(p: Dictionary, a: int, b: int) -> bool:
	for f in (p["flags"] as Dictionary):
		if RomanceRules.ROMANTIC_FLAGS.has(str(f)):
			return true
	return RelationshipService.value(a, b, "romance") > 0.0 or RelationshipService.value(b, a, "romance") > 0.0 \
		or Family.spouses.get(a, -1) == b or Family.engaged.has(SysUtil.pair_key(a, b))

static func _clear(p: Dictionary, a: int, b: int) -> void:
	for f in RomanceRules.ROMANTIC_FLAGS:
		(p["flags"] as Dictionary).erase(f)
		(p["since"] as Dictionary).erase(f)
	for k in ["dates", "confessed", "first_kiss"]:
		p.erase(k)
	for dir in [[a, b], [b, a]]:
		var vk: String = "%d>%d" % [dir[0], dir[1]]
		for rec in [(p["vals"] as Dictionary).get(vk, {}), (SysUtil.folk(dir[0]).relationships.get(dir[1], {}) if SysUtil.folk(dir[0]) != null else {})]:
			for t in ["romance", "bond", "ex"]:
				if (rec as Dictionary).has(t):
					rec[t] = 0.0
	if Family.spouses.get(a, -1) == b:
		Family.spouses.erase(a)
		Family.spouses.erase(b)
	Family.engaged.erase(SysUtil.pair_key(a, b))
	for x in [a, b]:
		var fx = SysUtil.folk(x)
		if fx != null:
			for bid in ["engaged", "married", "newlywed", "holiday_fling"]:
				fx.remove_buff(bid)
	RelationshipService._bit_cache.clear()
