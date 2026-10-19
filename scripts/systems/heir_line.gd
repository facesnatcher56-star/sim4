class_name HeirLine
extends RefCounted
## Who plays on when the head of a player's household dies (task 15). Pure queries, nothing is changed here.
## The line (first match wins; inside a step the eldest goes first):
##   0 the heir the player picked (family panel)      1 spouse or partner living in the household
##   2 grown children (adult / elder), moved out or not   3 the other children (teens, then the little ones)
##   4 siblings      5 anyone else in the household      6 other relatives living elsewhere (parents, grandchildren, the rest of the family)
## Little ones (baby / toddler / child) are never put ahead of somebody who can run a home: they follow the grown-ups of their step list.
## Candidate = {id, name, kind, rank, in_household, stage, label}. `kind` is one of: picked spouse partner child sibling housemate relative.
## Townies who are no kin are not in the line: they are only offered when nobody is left (SuccessionNobody).

const LITTLE := ["baby", "toddler", "child"]

## `head_id` is still alive in the world while this runs (the spouse link is erased once the death is processed).
static func candidates(head_id: int, household_id: int, player_id: int) -> Array:
	var out: Array = []
	var seen: Dictionary = {head_id: true}
	var picked: int = int(Players.field(player_id, "heir", -1))
	if picked >= 0 and picked != head_id:
		_add(out, seen, picked, "picked", 0, household_id, player_id)
	var sp: int = FamilyTree.spouse_of(head_id)
	if sp >= 0:
		_add(out, seen, sp, "spouse", 1, household_id, player_id, true)
	var pr: Dictionary = FamilyTree.partner_of(head_id)
	if not pr.is_empty() and str(pr.get("status", "")) in ["partner", "spouse", "fiance"]:
		_add(out, seen, int(pr.get("id", -1)), "partner", 1, household_id, player_id, true)
	for h in SysUtil.residents():          # the partner bit alone (no family link) also counts for a housemate
		if int(h.household_id) == household_id and RelationshipBits.bit_for(int(h.id), head_id) in ["spouse", "partner"]:
			_add(out, seen, int(h.id), "partner", 1, household_id, player_id, true)
	var kids: Array = _by_age(FamilyTree.children_of(head_id))
	for c in kids:
		if not (_stage(int(c)) in LITTLE + ["teen"]):
			_add(out, seen, int(c), "child", 2, household_id, player_id)
	for c2 in kids:
		_add(out, seen, int(c2), "child", 3, household_id, player_id)
	for s in _by_age(FamilyTree.siblings_of(head_id)):
		_add(out, seen, int(s), "sibling", 4, household_id, player_id)
	var mates: Array = []
	for h2 in SysUtil.residents():
		if int(h2.household_id) == household_id:
			mates.append(int(h2.id))
	for m in _by_age(mates):
		_add(out, seen, int(m), "housemate", 5, household_id, player_id)
	var kin: Array = []
	for p in FamilyTree.parents_of(head_id):
		kin.append(int(p))
	kin.append_array(FamilyTree.descendants_of(head_id))
	for t in Story.alive_townies():
		if FamilyTree.is_kin(head_id, int(t["id"])) and not kin.has(int(t["id"])):
			kin.append(int(t["id"]))
	for r in _by_age(kin):
		_add(out, seen, int(r), "relative", 6, household_id, player_id)
	for c3 in out:
		if str(c3["stage"]) in LITTLE and str(c3["kind"]) != "picked":
			c3["rank"] = int(c3["rank"]) + 100          # little ones last, order kept
	out.sort_custom(func(a, b): return int(a["rank"]) < int(b["rank"]))
	return out

static func first(head_id: int, household_id: int, player_id: int) -> Dictionary:
	var c: Array = candidates(head_id, household_id, player_id)
	return c[0] if not c.is_empty() else {}

static func _stage(id: int) -> String:
	return str(Family.person_info(id).get("stage", "adult"))

## Eldest first.
static func _by_age(ids: Array) -> Array:
	var a: Array = ids.duplicate()
	a.sort_custom(func(x, y):
		var ax: float = Family.age_days_of(int(x))
		var ay: float = Family.age_days_of(int(y))
		return ax > ay if ax != ay else int(x) < int(y))
	return a

## A person can be handed the family home when they are alive and either live in this household, are a townie, or live in a household nobody plays.
static func eligible(id: int, household_id: int, player_id: int) -> bool:
	var f = SysUtil.folk(id)
	if f != null:
		if f.has_meta("visitor") or int(f.household_id) <= 0:
			return false
		var owner: int = Players.player_of(int(f.household_id))
		return int(f.household_id) == household_id or owner < 0 or owner == player_id
	return Story.townies.has(id) and bool(Story.townies[id]["alive"])

static func _add(out: Array, seen: Dictionary, id: int, kind: String, rank: int, household_id: int, player_id: int, household_only: bool = false) -> void:
	if id < 0 or seen.has(id) or not eligible(id, household_id, player_id):
		return
	var f = SysUtil.folk(id)
	var inside: bool = f != null and int(f.household_id) == household_id
	if household_only and not inside:
		return
	seen[id] = true
	var info: Dictionary = Family.person_info(id)
	out.append({"id": id, "name": str(info["name"]), "kind": kind, "rank": rank, "in_household": inside, "stage": str(info["stage"]),
		"label": SuccessionText.describe(kind, str(info["name"]), inside)})
