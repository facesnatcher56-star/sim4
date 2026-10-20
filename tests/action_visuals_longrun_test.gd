extends RefCounted
## Task 33 (slow, view data only): plays 3 game days of the real game (the hash-baseline setup, classic start, seed 4242) counting every interaction that
## starts, and checks that none of the 30 most frequent ones shows a generic clip (Use_Stand, Idle, Talk, Sit_Idle) except the allow-listed walk / marker /
## plain sitting ids, and that the run exercised a real spread of interactions.

const AK = preload("res://tests/action_visual_kit.gd")
const TOP := 30


func run() -> Array:
	var fails: Array = []
	var rows: Dictionary = AK.rows()
	AK.Kit.teardown()
	var freq: Dictionary = AK.freq(3)
	var ids: Array = freq.keys()
	ids.sort_custom(func(a, b): return int(freq[a]) > int(freq[b]) or (int(freq[a]) == int(freq[b]) and str(a) < str(b)))
	if ids.size() < 40:
		fails.append("the 3-day run started only %d distinct interactions" % ids.size())
	var line: Array = []
	for i in mini(TOP, ids.size()):
		var id := str(ids[i])
		var r: Variant = rows.get(id, null)
		line.append("%s x%d" % [id, int(freq[id])])
		if r == null:
			fails.append("top-%d interaction %s is not in the audit tables" % [TOP, id])
		elif bool(r["generic"]):
			fails.append("#%d most frequent, %s (x%d), shows the generic clip %s" % [i + 1, id, int(freq[id]), str(r["clips"])])
	print("top %d of a 3-day run: %s" % [TOP, ", ".join(line)])
	return fails
