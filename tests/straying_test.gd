extends RefCounted
## Committed people rarely go romantic with somebody else (Straying): a happily married couple tempted only a couple of times
## per marriage-year (28 days), a flirty or unhappy one more often, a single person never limited, the storyteller's "tempted"
## buff opens the door, RomanceRules.allowed is still asked. Plus a short run of a happy couple among neighbours: jealous scenes stay rare.

const S = preload("res://tests/social_kit.gd")

## Tempted pair-windows per person per 28 days, over seeds (different people ids) and 12 years.
func _rate(traits: Array, romance: float) -> float:
	var total: float = 0.0
	var persons: int = 0
	for seed_v in [11, 12, 13, 14, 15, 16]:
		var w := S.setup(seed_v)
		var a: Folk = S.K.make_folk(w, "ann", traits, 1, Vector2i(12, 12))
		var b: Folk = S.K.make_folk(w, "bo", [], 1, Vector2i(13, 12))
		RelationshipBits.set_flag(a.id, b.id, "spouse", true, false)
		RelationshipService.set_value(a.id, b.id, "romance", romance)
		var others: Array = []
		for i in 6:
			others.append(S.K.make_folk(w, "n%d" % i, [], 2, Vector2i(14 + i, 12)))
		var partners: Array = RelationshipRomance.exclusive_partners(a.id)
		var windows: int = 0
		for day in range(0, 336, 3):
			for o in others:
				if Straying.roll(a.id, o.id, day) < Straying.chance(a.id, o.id, partners):
					windows += 1
		total += float(windows) / 12.0
		persons += 1
		S.teardown()
	return total / float(persons)

func run() -> Array:
	var f: Array = []
	var happy: float = _rate([], 85.0)
	var cool: float = _rate([], 20.0)
	var flirty: float = _rate(["romantic", "charmer"], 55.0)
	var flirty_unhappy: float = _rate(["romantic", "charmer"], 20.0)
	print("  tempted stretches per person-year: happy %.2f, cooling %.2f, flirty %.2f, flirty+unhappy %.2f" % [happy, cool, flirty, flirty_unhappy])
	S.expect(f, happy <= 1.0, "a happily married person is tempted at most about once a year (%.2f)" % happy)
	S.expect(f, cool > happy * 3.0 and flirty > happy * 3.0 and flirty_unhappy > cool, "cooling / flirty / unhappy people stray more (%.2f %.2f %.2f vs %.2f)" % [cool, flirty, flirty_unhappy, happy])
	# gate behaviour
	var w := S.setup(21)
	var a: Folk = S.K.make_folk(w, "ann", [], 1, Vector2i(12, 12))
	var b: Folk = S.K.make_folk(w, "bo", [], 1, Vector2i(13, 12))
	var c: Folk = S.K.make_folk(w, "cy", [], 2, Vector2i(14, 12))
	S.expect(f, Straying.may_flirt(a.id, c.id, []), "a single person is never limited")
	RelationshipBits.set_flag(a.id, b.id, "spouse", true, false)
	RelationshipService.set_value(a.id, b.id, "romance", 90.0)
	var partners: Array = RelationshipRomance.exclusive_partners(a.id)
	S.expect(f, Straying.may_flirt(a.id, b.id, partners), "always free with the partner")
	var open_days: int = 0
	for d in range(0, 300, 3):
		S.set_time(d + 1, 12)
		if Straying.may_flirt(a.id, c.id, partners):
			open_days += 1
	S.expect(f, open_days <= 8, "a happy spouse is rarely open to a stranger (%d of 100 windows)" % open_days)
	var found: bool = false
	for d in range(0, 3000, 3):
		S.set_time(d + 1, 12)
		if not Straying.may_flirt(a.id, c.id, partners):
			found = true
			break
	S.expect(f, found, "there are closed days")
	Straying.tempt(a.id)
	S.expect(f, a.has_buff("tempted") and Straying.may_flirt(a.id, c.id, partners), "the tempted buff opens the door")
	Straying.tempt(c.id)
	S.expect(f, not c.has_buff("tempted"), "the storyteller hook does nothing for a single person")
	# the autonomy list: a minor is never offered, and a closed day offers nothing romantic to the spouse's neighbour
	var kid: Folk = S.K.make_folk(w, "kid", [], 2, Vector2i(15, 12), "child")
	for row in Autonomy.gather(a):
		if str(row["kind"]) == "folk":
			S.expect(f, int(row["target_id"]) != kid.id or not RomanceRules.is_romantic_def(SimEnv.data().interactions()[str(row["id"])]), "no romance towards a child")
	S.teardown()
	return f
