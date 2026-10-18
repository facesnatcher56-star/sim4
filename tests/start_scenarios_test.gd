extends RefCounted
## Every scenario builds a playable world (house loaded, member counts / ages / relations, funds, goals registered), Solo Start is
## the default selection of the new-game screen, and Free Play accepts any custom household.

const Kit := preload("res://tests/start_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	_defaults()
	_solo()
	_couple()
	_family()
	_roommates()
	_sandbox()
	Kit.teardown()
	return fails

func _defaults() -> void:
	_check(Scenario.default_id() == "solo", "default scenario is Solo Start")
	_check(Scenario.ids() == ["solo", "couple", "family", "roommates", "sandbox"], "five scenarios in order: %s" % str(Scenario.ids()))
	var sp := StartPicker.new()
	Kit.root().add_child(sp)
	_check(sp.selected_id == "solo", "picker pre-selects solo (%s)" % sp.selected_id)
	_check(sp.difficulty == "normal", "picker defaults to Normal")
	_check(sp.start_btn.text == "Start: Solo Start", "big Start button names the default (%s)" % sp.start_btn.text)
	var got: Array = []
	sp.chosen.connect(func(cfg): got.append(cfg))
	sp.start_btn.pressed.emit()
	_check(got.size() == 1, "one click on Start chooses the default")
	if got.size() == 1:
		var cfg: Dictionary = got[0]
		_check(str(cfg["scenario"]) == "solo" and (cfg["household"]["folk"] as Array).size() == 1, "default start is one Folk")
		_check(int(cfg["funds"]) == 4000 and str(cfg["start_id"]) == "small", "default start: 4000 coins in the studio")
		_check(HouseholdSetup.validate(cfg["household"]) == "", "default household is valid")
		_check(str(cfg["home_template"]).begins_with("small_"), "the card shows a studio from the small pool (%s)" % str(cfg["home_template"]))
		_check((sp.cards["solo"] as ScenarioCard).thumb.template_id == cfg["home_template"], "the thumbnail shows the chosen home")
	var first: String = str(sp.homes["solo"])
	for i in 6:      # Reroll home: always another layout of the pool, and it is what Start sends
		sp.reroll_home("solo")
		_check(str(sp.homes["solo"]) != first and str(sp.homes["solo"]).begins_with("small_"), "reroll gives another small home (%s)" % sp.homes["solo"])
		first = str(sp.homes["solo"])
	got.clear()
	sp.start_btn.pressed.emit()
	_check(got.size() == 1 and got[0]["home_template"] == first, "Start sends the rerolled home")
	sp.select("sandbox")
	_check(sp.start_btn.text == "Create Household" and not sp.custom_btn.visible, "Free Play creates a household instead of starting")
	sp.queue_free()

func _built(folk: Array, id: String, want: int) -> void:
	var W: Node = Kit.world()
	_check(folk.size() == want and SysUtil.residents().size() == want, "%s: %d residents (%d)" % [id, want, SysUtil.residents().size()])
	_check(W.objects.size() >= 14, "%s: home is furnished (%d objects)" % [id, W.objects.size()])
	for f in folk:
		_check(W.is_walkable(f.tile), "%s: %s stands on a walkable tile" % [id, f.name])
		_check(f.household_id == 1, "%s: %s lives in household 1" % [id, f.name])
		_check(Aging.records.has(f.id) and Goals.profiles.has(f.id), "%s: %s registered in Aging and Goals" % [id, f.name])
	var def: Dictionary = Scenario.def(id)
	_check(Economy.balance(1) == Scenario.funds_for(id, "normal"), "%s: funds %d" % [id, Economy.balance(1)])
	_check(Kit.clock().hour() == int(def["start_hour"]) and Kit.clock().day() == 1, "%s: starts day 1 at %d:00" % [id, int(def["start_hour"])])
	_check(Scenario.active_id == id and Scenario.goals().size() == (def["goals"] as Array).size(), "%s: goals registered" % id)
	_check(Scenario.done_count() == 0 and not Scenario.finished, "%s: nothing done yet" % id)

func _solo() -> void:
	var folk: Array = Kit.new_game("solo")
	_built(folk, "solo", 1)
	_check(Scenario.goals().size() == 4, "solo has 4 goals")
	_check(str(folk[0].age_stage) == "adult" and folk[0].traits.size() == 3, "solo: one adult with 3 traits")
	_check(Neighborhood.home_template.begins_with("small_"), "solo lives in the studio (%s)" % Neighborhood.home_template)
	_check(Kit.world().starter_spawn_tiles.has(folk[0].tile), "solo spawns at the door")

func _couple() -> void:
	var folk: Array = Kit.new_game("couple")
	_built(folk, "couple", 2)
	var a: int = folk[0].id
	var b: int = folk[1].id
	_check(RelationshipBits.bit_for(a, b) == "partner" and RelationshipBits.bit_for(b, a) == "partner", "couple: partners both ways (%s)" % RelationshipBits.bit_for(a, b))
	_check(RelationshipService.value(a, b, "romance") >= 45.0, "couple: romance high enough to try for a baby")
	_check(Neighborhood.home_template.begins_with("medium_"), "couple: medium home (%s)" % Neighborhood.home_template)

func _family() -> void:
	var folk: Array = Kit.new_game("family")
	_built(folk, "family", 3)
	var a: int = folk[0].id
	var b: int = folk[1].id
	var c: int = folk[2].id
	_check(FamilyTree.spouse_of(a) == b and FamilyTree.spouse_of(b) == a, "family: spouses")
	_check(str(folk[2].age_stage) == "child" and folk[2].traits.size() == 2, "family: child with 2 trait slots")
	_check(FamilyTree.parents_of(c).has(a) and FamilyTree.parents_of(c).has(b), "family: both adults are the child's parents")
	_check(FamilyTree.relation_id(a, c) == "child", "family: parent->child relation id (%s)" % FamilyTree.relation_id(a, c))
	_check(Genetics.is_valid(folk[2].appearance), "family: child look is a full appearance")
	_check(Careers.school.has(c), "family: child is enrolled in school")
	_check(Economy.balance(1) == 4500, "family: tight 4500 coins")

func _roommates() -> void:
	var folk: Array = Kit.new_game("roommates")
	_built(folk, "roommates", 3)
	for i in 3:
		for j in range(i + 1, 3):
			_check(not FamilyTree.is_kin(folk[i].id, folk[j].id) and FamilyTree.spouse_of(folk[i].id) < 0, "roommates: unrelated")
	_check(Neighborhood.home_template.begins_with("large_"), "roommates: large home (%s)" % Neighborhood.home_template)

func _member(nm: String, stage: String, rel: String, asp: String = "") -> Dictionary:
	return {"name": nm, "stage": stage, "rel": rel, "traits": HouseholdSetup.random_traits(HouseholdSetup.trait_count(stage)), "aspiration": asp,
		"appearance": Genetics.random_appearance()}

func _sandbox() -> void:
	var h := {"name": "Test", "folk": [_member("Ada", "elder", "none", "iron_will"), _member("Bo", "adult", "child"), _member("Cy", "teen", "sibling"),
		_member("Di", "child", "none"), _member("Ed", "adult", "none"), _member("Flo", "adult", "none")]}
	_check(HouseholdSetup.validate(h) == "", "sandbox: six mixed-age Folk validate (%s)" % HouseholdSetup.validate(h))
	Kit.new_game("sandbox", "normal", h.duplicate(true), 50000)
	for start in ["small", "medium", "large", "classic"]:
		var folk: Array = NewGame.start(Kit.mgr, h.duplicate(true), start, {"scenario": "sandbox", "funds": 50000})
		_check(SysUtil.residents().size() == 6, "sandbox on %s: 6 residents (%d)" % [start, SysUtil.residents().size()])
		var seen := {}
		for f in folk:
			_check(Kit.world().is_walkable(f.tile), "sandbox on %s: %s on a walkable tile" % [start, f.name])
			seen[f.tile] = true
		_check(seen.size() >= 4, "sandbox on %s: Folk are spread out (%d distinct tiles)" % [start, seen.size()])
		_check(Economy.balance(1) == 50000, "sandbox on %s: rich funds option (%d)" % [start, Economy.balance(1)])
		_check(Scenario.goals().is_empty() and not Scenario.has_goals(), "sandbox: no scenario goals")
		_check(Goals.profiles[folk[0].id]["aspiration"] == "iron_will", "sandbox: chosen aspiration applied")
		_check(str(folk[0].age_stage) == "elder" and str(folk[2].age_stage) == "teen" and str(folk[3].age_stage) == "child", "sandbox: age groups kept")
		_check(FamilyTree.parents_of(folk[1].id).has(folk[0].id), "sandbox: Bo is a child of Ada")
		_check(FamilyTree.siblings_of(folk[0].id).has(folk[2].id), "sandbox: Cy is a sibling of Ada")
