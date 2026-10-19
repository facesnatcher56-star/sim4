class_name RomanceRules
extends RefCounted
## THE central guard for anything romantic or intimate (flirting, dating, proposals, marriage, affairs, flings, trying for a baby,
## conception). A pair is allowed only when BOTH are adult or elder AND they are not family (parent / child incl. adoptive and step,
## grandparent / grandchild, siblings incl. half, aunt or uncle / niece or nephew, cousins, or flagged `family` in the household).
## Everything that raises the romance track or sets a romantic bit asks `allowed(a, b)` first (see RelationshipService.set_value,
## Folk.add_rel, RelationshipBits.set_flag, Interaction.def_runnable, Autonomy.gather, FamilyMarriage, Aging.try_for_baby).

const ADULT_STAGES := ["adult", "elder"]
const TAGS := ["flirt", "romance", "kiss", "dating", "wedding", "proposal", "conception"]
const EVENTS := ["try_for_baby", "propose", "wedding"]
const ROMANTIC_FLAGS := ["dating", "sweetheart", "partner", "spouse", "ex"]

## Life stage of any person (on the lot, townie, or only in the family book). Strangers with no record count as adults.
static func stage_of(id: int) -> String:
	var f = SysUtil.folk(id)
	if f != null:
		return str(f.age_stage)
	if Story.townies.has(id):
		return Story.stage_of(Story.townies[id])
	if Family.people.has(id) or Aging.records.has(id):
		return Aging.stage_for_days(Family.age_days_of(id))
	return "adult"

static func is_adult(id: int) -> bool:
	return stage_of(id) in ADULT_STAGES

## Family of any kind (blood, adoptive, step, flagged `family`). Ignores marriage so a stale married relative still counts.
static func related(a: int, b: int) -> bool:
	if RelationshipBits.has_flag(a, b, "family") and not _co_parents(a, b):
		return true
	var la: Array = _lineage(a)
	var lb: Array = _lineage(b)
	if la.has(b) or lb.has(a) or FamilyTree.siblings_of(a).has(b):
		return true
	for x in la:           # aunts / uncles (and great-aunts), and step-parents
		if FamilyTree.siblings_of(int(x)).has(b):
			return true
	for y in lb:
		if FamilyTree.siblings_of(int(y)).has(a):
			return true
	var pa: Array = FamilyTree.parents_of(a)
	var pb: Array = FamilyTree.parents_of(b)
	for p in pa:
		if _step(int(p), b):
			return true
		for q in pb:
			if FamilyTree.siblings_of(int(p)).has(int(q)):    # first cousins
				return true
	for q2 in pb:
		if _step(int(q2), a):
			return true
	return false

## Parents, grandparents, great-grandparents ... (four generations) of `id`.
static func _lineage(id: int) -> Array:
	var out: Array = []
	var level: Array = [id]
	for _g in 4:
		var nxt: Array = []
		for x in level:
			for p in FamilyTree.parents_of(int(x)):
				if not out.has(int(p)):
					out.append(int(p))
					nxt.append(int(p))
		level = nxt
		if level.is_empty():
			break
	return out

## Two people who share a child are flagged `family` too (Aging._birth), but that does not make them kin.
static func _co_parents(a: int, b: int) -> bool:
	var kb: Array = FamilyTree.children_of(b)
	for c in FamilyTree.children_of(a):
		if kb.has(c):
			return true
	return false

## Is `x` the (ex-)spouse, fiance or live-in partner of `parent`? Then x is a step relative of the parent's children.
static func _step(parent: int, x: int) -> bool:
	if FamilyTree.spouse_of(parent) == x or FamilyTree.fiance_of(parent) == x:
		return true
	return int(FamilyTree.partner_of(parent).get("id", -1)) == x

## May a and b be romantic or intimate with each other?
static func allowed(a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0:
		return false
	return is_adult(a) and is_adult(b) and not related(a, b)

static func why_not(a: int, b: int) -> String:
	if not is_adult(a) or not is_adult(b):
		return "Too young for that."
	if related(a, b):
		return "They are family."
	return ""

## Is this interaction definition a romantic / intimate one (category, tags, or the events it fires)?
static func is_romantic_def(d: Dictionary) -> bool:
	if str(d.get("category", "")) == "romantic":
		return true
	if bool((d.get("social", {}) as Dictionary).get("intimate", false)):
		return true
	for t in d.get("tags", []):
		if TAGS.has(str(t)):
			return true
	for e in d.get("on_finish", []):
		if e is Dictionary and EVENTS.has(str((e as Dictionary).get("fire_event", ""))):
			return true
	return false
