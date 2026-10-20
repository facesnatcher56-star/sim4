class_name Heritage
extends RefCounted
## Heritage communities (R13, data/heritage.json). A Folk or townie has a `heritage` id ("" = none yet, "mixed" for a child of two). Inherited like a look but
## independent of it. It NEVER feeds rent, wages, hiring, justice, crime or district roughness: the only reader is the soft PULL of where people choose to
## live (townie tenants, the player's listings) and the festival day. Source guard: tools/heritage_guard.ps1.

static var rng: RandomNumberGenerator = RandomNumberGenerator.new()          # its own stream: a heritage never depends on a home, a job or money

static func reset(seed_value: int = 7) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 31

static func cfg() -> Dictionary:
	return SysUtil.table("heritage")

static func ids() -> Array:
	var out: Array = (cfg().get("heritages", {}) as Dictionary).keys()
	out.sort()
	return out

static func label_of(id: String) -> String:
	if id == "mixed":
		return "Mixed heritage"
	return str(((cfg().get("heritages", {}) as Dictionary).get(id, {}) as Dictionary).get("label", ""))

static func random_id() -> String:
	var all: Array = ids()
	return "" if all.is_empty() else str(all[rng.randi_range(0, all.size() - 1)])

## Heritage of a Folk, a townie record or a person-info dictionary.
static func of(x) -> String:
	if x == null:
		return ""
	if x is Dictionary:
		return str((x as Dictionary).get("heritage", ""))
	return str(x.heritage) if "heritage" in x else ""

## A child's heritage: one parent's, or "mixed" when the parents differ (mixed_chance of the time even then).
static func inherit(a, b) -> String:
	var ha: String = of(a)
	var hb: String = of(b)
	if ha == "":
		return hb
	if hb == "" or ha == hb:
		return ha
	if rng.randf() < float(cfg().get("mixed_chance", 0.2)):
		return "mixed"
	return ha if rng.randf() < 0.5 else hb

# ------------------------------------------------------------------ the soft pull
## Weight of living in a district for a person: 1 + 0.15 relatives there (cap 3) + 0.10 friends there (cap 3) + 0.10 x the share of the district
## with the person's own heritage, capped at 1.4. Never an input to rent, wages, hiring or crime.
static func pull(person_id: int, own: String, district_id: String) -> float:
	if district_id == "":
		return 1.0
	var p: Dictionary = cfg().get("pull", {})
	var rel := 0
	var known := 0
	var same := 0
	var n := 0
	for t in Story.alive_townies():
		if SoloDistricts.district_of(SoloDistricts.townie_lot_id(int(t.get("lot", 1)))) != district_id:
			continue
		n += 1
		if own != "" and str(t.get("heritage", "")) == own:
			same += 1
		var tid: int = int(t["id"])
		if tid == person_id:
			continue
		if FamilyTree.is_kin(person_id, tid):
			rel += 1
		elif RelationshipService.value(person_id, tid, "friendship") >= 40.0:
			known += 1
	var share: float = float(same) / float(maxi(n, 1))
	return minf(1.0 + float(p.get("relative", 0.15)) * minf(float(rel), float(p.get("relative_cap", 3))) + float(p.get("known", 0.1)) * minf(float(known), float(p.get("known_cap", 3))) + float(p.get("share", 0.1)) * share, float(p.get("cap", 1.4)))

## Listing tags for a lot as the player sees it ("near family", "friends nearby", "community shops here"): never a price.
static func tags_for_lot(lot_orig: String, f) -> Array:
	var out: Array = []
	var did: String = SoloDistricts.district_of(lot_orig)
	if did == "" or f == null:
		return out
	var own: String = of(f)
	var rel := 0
	var known := 0
	var same := 0
	for t in Story.alive_townies():
		if SoloDistricts.district_of(SoloDistricts.townie_lot_id(int(t.get("lot", 1)))) != did:
			continue
		if own != "" and str(t.get("heritage", "")) == own:
			same += 1
		if FamilyTree.is_kin(int(f.id), int(t["id"])):
			rel += 1
		elif RelationshipService.value(int(f.id), int(t["id"]), "friendship") >= 40.0:
			known += 1
	if rel > 0:
		out.append("near family")
	if known > 0:
		out.append("friends nearby")
	if same > 0:
		out.append("%s community here" % label_of(own))
	return out

# ------------------------------------------------------------------ festival
## Daily: a festival day of the pawn's heritage is a small pleasure (a toast and a cheerful buff), a calendar fact.
static func on_day(day: int) -> void:
	if not SoloHome.active:
		return
	var f = SysUtil.folk(Pawn.of())
	var h: String = of(f)
	if h == "" or h == "mixed":
		return
	var fest: Dictionary = ((cfg().get("heritages", {}) as Dictionary).get(h, {}) as Dictionary).get("festival", {})
	if fest.is_empty():
		return
	var doy: int = (day - 1) % 112 + 1          # four seasons of 28 days
	if doy == int(fest.get("day_of_year", -1)):
		f.add_buff("cheered_up")
		SysUtil.notify("%s today: the %s community is out. %s." % [str(fest.get("label", "A festival")), label_of(h), str(((cfg().get("heritages", {}) as Dictionary).get(h, {}) as Dictionary).get("cuisine", "")).capitalize()], "good")
