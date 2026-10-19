extends RefCounted
## Autonomy.choose caches (task 17.4): the per-decision memos of the story-pacing and skill-interest multipliers and the exempt memo of AutonomyVariety
## must give exactly the numbers of the plain calls, and the cached "iid|object kind" keys must be the ones the candidates carry.

const Kit = preload("res://tests/hood_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func _exempt_plain(iid: String, d: Dictionary) -> bool:
	var c: Dictionary = AutonomyVariety.cfg()
	if (c.get("exempt_ids", []) as Array).has(iid):
		return true
	for t in d.get("tags", []):
		if (c.get("exempt_tags", []) as Array).has(t):
			return true
	return false

func run() -> Array:
	fails = []
	var folk: Array = Kit.new_game("classic", 777)
	Kit.set_time(2, 12)
	var defs: Dictionary = SimEnv.data().interactions()
	var n := 0
	for iid in defs:
		var d: Dictionary = defs[iid]
		_check(AutonomyVariety.exempt(str(iid), d) == _exempt_plain(str(iid), d), "exempt memo agrees for %s" % str(iid))
		_check(AutonomyVariety.exempt(str(iid), d) == _exempt_plain(str(iid), d), "and on the second (memoised) call for %s" % str(iid))
		n += 1
	_check(n > 50, "many interactions were compared")
	# the pacing and skill multipliers: with a shared per-decision memo, in any order, equal to the plain ones
	for f in folk:
		StoryPacing.add_beat(int(f.household_id), 6.0)
		var memo: Dictionary = {}
		for pass_no in 2:
			for iid2 in defs:
				var d2: Dictionary = defs[iid2]
				_check(absf(StoryPacing.interaction_mult(f, d2, memo) - StoryPacing.interaction_mult(f, d2)) < 1e-9, "pacing memo agrees for %s" % str(iid2))
				_check(absf(SkillInterest.mult(f, str(iid2), d2, memo) - SkillInterest.mult(f, str(iid2), d2)) < 1e-9, "skill memo agrees for %s" % str(iid2))
	# candidates carry the same profile key as the old string build
	var f0 = folk[0]
	var cands: Array = Autonomy.gather(f0)
	_check(not cands.is_empty(), "there are candidates")
	for c in cands:
		if c["obj"] != null:
			_check(str(c["pk"]) == str(c["id"]) + "|" + str(c["obj"].def_id), "profile key is iid|object kind")
	Kit.teardown()
	return fails
