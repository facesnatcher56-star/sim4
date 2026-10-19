extends RefCounted
## Task 18 part 1: every folk is female or male (creator, townies, births 50/50, saved), name pools and looks by sex,
## pronouns and family labels by sex, trait sex limit by data.

const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_creator_and_save(f)
	_townies_and_names(f)
	_looks(f)
	_words(f)
	_births(f)
	return f

func _creator_and_save(f: Array) -> void:
	var w := K.setup(77)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var nf := 0
	var nm := 0
	for i in 40:
		var fd := HouseholdSetup.random_folk("adult", "none", [], rng)
		K.expect(f, Sexes.valid(fd["sex"]), "creator folk has a sex")
		var first: String = Names.first_of(str(fd["name"]))
		K.expect(f, (Names.female_set() if fd["sex"] == "female" else Names.male_set()).has(first), "creator name %s fits %s" % [first, fd["sex"]])
		if fd["sex"] == "female":
			nf += 1
			K.expect(f, int(fd["appearance"]["facial_hair"]) == 0, "no facial hair on a woman")
		else:
			nm += 1
	K.expect(f, nf > 8 and nm > 8, "both sexes appear in the creator (%d/%d)" % [nf, nm])
	var a := K.make_folk(w, "Zed Fox", [])
	a.sex = "male"
	var back := Folk.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	K.expect(f, back.sex == "male", "sex survives save and load")
	var old: Dictionary = a.to_dict()
	old.erase("sex")
	K.expect(f, Sexes.valid(Folk.from_dict(old).sex), "an old save without sex gets one")
	K.teardown()

func _townies_and_names(f: Array) -> void:
	var w := K.setup(78)
	var fem := 0
	for i in 60:
		var t: Dictionary = Story.add_townie()
		K.expect(f, Sexes.valid(t["sex"]), "townie has a sex")
		var first: String = Names.first_of(str(t["name"]))
		K.expect(f, (Names.female_set() if t["sex"] == "female" else Names.male_set()).has(first), "townie name fits sex")
		if t["sex"] == "female":
			fem += 1
			K.expect(f, int(t["appearance"]["facial_hair"]) == 0, "townie woman without facial hair")
	K.expect(f, fem > 15 and fem < 45, "townies split roughly 50/50 (%d female of 60)" % fem)
	K.teardown()
	w = null

func _looks(f: Array) -> void:
	K.setup(79)
	var g := RandomNumberGenerator.new()
	g.seed = 9
	var hf := 0.0
	var hm := 0.0
	var beards := 0
	for i in 150:
		var af := Genetics.random_appearance(g, "female")
		var am := Genetics.random_appearance(g, "male")
		hf += float(af["height"])
		hm += float(am["height"])
		beards += 1 if int(am["facial_hair"]) > 0 else 0
		K.expect(f, int(af["facial_hair"]) == 0, "female look has no facial hair")
	K.expect(f, hm > hf, "men are taller on average (%.3f vs %.3f)" % [hm / 150.0, hf / 150.0])
	K.expect(f, beards > 5, "some men have facial hair (%d)" % beards)
	K.teardown()

func _words(f: Array) -> void:
	var w := K.setup(80)
	var m := Folk.create("Gus Fern", [], -1, "male")
	var s := Folk.create("Cora Fern", [], -1, "female")
	w.add_folk(m, Vector2i(5, 5))
	w.add_folk(s, Vector2i(6, 5))
	K.expect(f, Sexes.fill("{They} lost {their} keys; call {them}.", m.id) == "He lost his keys; call him.", "male pronouns: %s" % Sexes.fill("{They} lost {their} keys; call {them}.", m.id))
	K.expect(f, Sexes.fill("{They} lost {their} keys; call {them}.", s.id) == "She lost her keys; call her.", "female pronouns")
	K.expect(f, Sexes.fill("{they} {themself}", s.id) == "she herself", "reflexive")
	Family.link_parent(m.id, s.id)
	K.expect(f, Family.relation_label(m.id, s.id) == "Mother", "label Mother: %s" % Family.relation_label(m.id, s.id))
	K.expect(f, Family.relation_label(s.id, m.id) == "Son", "label Son: %s" % Family.relation_label(s.id, m.id))
	K.expect(f, Sexes.label("aunt_uncle", "male") == "Uncle" and Sexes.label("niece_nephew", "female") == "Niece", "aunt/uncle and niece/nephew")
	K.expect(f, Sexes.label("sibling", "female") == "Sister" and Sexes.label("grandparent", "male") == "Grandfather", "sister / grandfather")
	K.expect(f, Sexes.label("spouse", "female") == "Wife" and Sexes.label("parent_in_law", "male") == "Father-in-law", "wife / in-laws")
	# a death text uses the right pronoun
	var res := Aging.kill(m.id, "starvation")
	var txt := str(res.get("summary", ""))
	K.expect(f, txt.find("{") < 0 and txt.find("They ") < 0, "no raw tokens or 'They' in death summary: %s" % txt)
	# trait sex limit by data
	SimEnv.data().traits()["__t"] = {"label": "T", "sex": "female"}
	K.expect(f, Sexes.allowed_trait("__t", "female") and not Sexes.allowed_trait("__t", "male"), "a trait can be limited to one sex by data")
	var limited := 0
	for t in SimEnv.data().traits():
		if t != "__t" and str(SimEnv.data().trait_def(str(t)).get("sex", "")) != "":
			limited += 1
	K.expect(f, limited == 0, "no shipped trait is limited to a sex")
	SimEnv.data().traits().erase("__t")
	K.teardown()

func _births(f: Array) -> void:
	var w := K.setup(81)
	var mom := K.make_folk(w, "Ann Rowe", [])
	mom.sex = "female"
	var dad := K.make_folk(w, "Bo Rowe", [], 1, Vector2i(13, 12))
	dad.sex = "male"
	Aging.set_age_days(mom, 92.0)
	Aging.set_age_days(dad, 92.0)
	var girls := 0
	for i in 40:
		Aging.pregnancies[mom.id] = {"father": dad.id, "due_day": 1, "started": 1, "kids": 1, "kid_sexes": [Sexes.roll()]}
		PregnancyBirth.deliver(mom.id, dad.id)
		Aging.pregnancies.erase(mom.id)
	for b in w.all_folk():
		if b.age_stage == "baby":
			K.expect(f, Sexes.valid(b.sex), "baby has a sex")
			if b.sex == "female":
				girls += 1
	K.expect(f, girls > 8 and girls < 32, "babies are born about 50/50 (%d girls of 40)" % girls)
	K.teardown()
