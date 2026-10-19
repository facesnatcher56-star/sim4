extends RefCounted
## Rare / negative traits (dishonest, kleptomaniac, vengeful, reckless) never appear by chance in children: only a parent passes them down.
## Also the growing-up toast says "an adult" / "an elder".

const K = preload("res://tests/systems_kit.gd")
const RARE := ["dishonest", "kleptomaniac", "vengeful", "reckless"]

func run() -> Array:
	var f: Array = []
	var w := K.setup(41)
	SysContent.install_all()
	for r0 in RARE:
		if not SimEnv.data().traits().has(r0):
			SimEnv.data().traits()[r0] = {"label": r0, "need_decay_mult": {}, "autonomy_mult": {}, "likes": [], "dislikes": [], "refuses": [], "buffs_on": {}, "conflicts": ["honest"]}
	var pool: Array = Genetics.random_pool([])
	for r in RARE:
		K.expect(f, not pool.has(r), "%s is never a random pick" % r)
	K.expect(f, pool.size() >= 30, "the ordinary traits stay in the pool (%d)" % pool.size())
	K.expect(f, not Genetics.random_pool(["honest"]).has("dishonest") and not Genetics.random_pool(["lazy"]).has("lazy"), "no repeats")
	var rare_kids: int = 0
	var g := RandomNumberGenerator.new()
	g.seed = 5
	for i in 600:
		var t: Array = Genetics.inherit_traits({"traits": ["lazy", "social"]}, {"traits": ["neat"]}, g, {"cap": 2})
		for r2 in RARE:
			if t.has(r2):
				rare_kids += 1
	K.expect(f, rare_kids == 0, "600 children of ordinary parents: no rare trait (%d)" % rare_kids)
	var from_parent: int = 0
	for i2 in 600:
		if Genetics.inherit_traits({"traits": ["kleptomaniac"]}, {"traits": []}, g, {"cap": 2, "extra": 0}).has("kleptomaniac"):
			from_parent += 1
	K.expect(f, from_parent > 120 and from_parent < 300, "a kleptomaniac parent still passes it on about a third of the time (%d / 600)" % from_parent)
	# growing up: the new trait is never a rare one, and the text has the right article
	var kid := K.make_folk(w, "Kiddo", [], 1, Vector2i(12, 12), "teen")
	kid.traits.clear()
	for i3 in 60:
		kid.traits.clear()
		Aging._grow_trait(kid)
		K.expect(f, kid.traits.size() == 1 and not RARE.has(str(kid.traits[0])), "a grown-up trait is an ordinary one (%s)" % str(kid.traits))
	Aging._age_up(kid, "adult")
	K.expect(f, K.has_note("grew up into an adult!"), "toast says 'an adult'")
	Aging._age_up(kid, "elder")
	K.expect(f, K.has_note("grew up into an elder!"), "toast says 'an elder'")
	K.teardown()
	return f
