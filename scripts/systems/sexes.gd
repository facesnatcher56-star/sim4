class_name Sexes
extends RefCounted
## Every folk is female or male (task 18). One place answers "what sex is person X" for a Folk on the lot, a townie record or a
## person who only exists in the family book, and builds the words that depend on it: pronouns (he / she), family labels
## (mother, son, aunt ...) and a noun (woman / man). Personality traits stay open to both sexes unless a trait def says
## `"sex": "female"` / `"male"` (none do today; see allowed_trait()).
## Pronoun tokens for text templates: {they} {They} {them} {their} {Their} {theirs} {themself}. Verbs are written singular next to them
## ("{They} is expecting"), so a template reads right for both sexes. Use Sexes.fill(text, id).
## Determinism: a random sex is drawn from its own seeded stream (Sexes.rng, seeded by SimSeed.apply); an unknown person gets a stable sex from the id.

const FEMALE := "female"
const MALE := "male"
const BOTH := [FEMALE, MALE]

static func valid(s) -> bool:
	return str(s) == FEMALE or str(s) == MALE

static func other(s: String) -> String:
	return MALE if s == FEMALE else FEMALE

## Own stream for the sex of newcomers and babies, seeded by SimSeed.apply, so the draw never shifts the gameplay stream.
static var rng: RandomNumberGenerator = _make_rng()

static func _make_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 0x5e75
	return r

static func seed_rng(s: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = s

## 50 / 50 at birth (or for a random newcomer).
static func roll(r: RandomNumberGenerator = null) -> String:
	var g: RandomNumberGenerator = r if r != null else rng
	return FEMALE if g.randf() < 0.5 else MALE

## A stable sex for somebody who has none yet: the name pools first (a first name in the female or male list), else the id.
static func guess(full_name: String, id: int) -> String:
	var first: String = Names.first_of(full_name)
	if first != "":
		if Names.female_set().has(first):
			return FEMALE
		if Names.male_set().has(first):
			return MALE
	return FEMALE if absi(id) % 2 == 1 else MALE

## Sex of any person id (Folk, townie, family-book person). Unknown ids get the stable guess.
static func of(id: int) -> String:
	var f = SysUtil.folk(id)
	if f != null:
		if not valid(f.sex):
			f.sex = guess(str(f.name), id)
		return str(f.sex)
	var t = Story.townies.get(id, null)
	if t != null:
		return of_townie(t)
	var p: Dictionary = Family.people.get(id, {})
	if valid(p.get("sex", "")):
		return str(p["sex"])
	return guess(str(p.get("name", "")), id)

static func of_townie(t: Dictionary) -> String:
	if not valid(t.get("sex", "")):
		t["sex"] = guess(str(t.get("name", "")), int(t.get("id", 0)))
	return str(t["sex"])

static func is_female(id: int) -> bool:
	return of(id) == FEMALE

static func is_male(id: int) -> bool:
	return of(id) == MALE

## The data-driven sex limit of a trait (`"sex": "female"`); "" = open to both. Nothing is limited today.
static func allowed_trait(trait_id: String, sex: String) -> bool:
	var lim: String = str(SimEnv.data().trait_def(trait_id).get("sex", ""))
	return lim == "" or lim == sex or not valid(sex)

# ------------------------------------------------------------------ words
const _PRON := {
	FEMALE: {"they": "she", "them": "her", "their": "her", "theirs": "hers", "themself": "herself", "person": "woman", "child": "girl"},
	MALE: {"they": "he", "them": "him", "their": "his", "theirs": "his", "themself": "himself", "person": "man", "child": "boy"},
}

## One pronoun form ("they" | "them" | "their" | "theirs" | "themself" | "person" | "child") of person `id`.
static func word(id: int, form: String) -> String:
	return str((_PRON[of(id)] as Dictionary).get(form, form))

static func word_for(sex: String, form: String) -> String:
	return str((_PRON.get(sex, _PRON[FEMALE]) as Dictionary).get(form, form))

static func they(id: int) -> String:
	return word(id, "they")

static func them(id: int) -> String:
	return word(id, "them")

static func their(id: int) -> String:
	return word(id, "their")

## Replace the pronoun tokens of `text` with the forms of person `id`.
static func fill(text: String, id: int) -> String:
	if text.find("{") < 0:
		return text
	return fill_sex(text, of(id))

static func fill_sex(text: String, sex: String) -> String:
	var out: String = text
	for form in ["themself", "theirs", "their", "them", "they"]:
		var w: String = word_for(sex, form)
		out = out.replace("{%s}" % form, w).replace("{%s}" % form.capitalize(), w.capitalize())
	return out

## "Mother", "Son", "Aunt" ... for relation id `rid` when the other person is `sex`. Falls back to the neutral label.
static func label(rid: String, sex: String) -> String:
	var tbl: Dictionary = Family.cfg().get("labels_" + sex, {})
	if tbl.has(rid):
		return str(tbl[rid])
	return str(Family.cfg().get("labels", {}).get(rid, rid.capitalize()))
