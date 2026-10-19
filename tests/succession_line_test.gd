extends RefCounted
## Task 15: the heir line. Spouse / partner in the household, then grown children (moved out or not, eldest first), then the other children,
## siblings, housemates, other relatives; little ones last; the player's pick first; strangers never.

const K := preload("res://tests/succession_kit.gd")
var fails: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	var folk: Array = K.new_game()
	var head = folk[0]
	var tobin = folk[1]
	var wren = folk[2]
	var hid := 1
	# 1. the spouse first, whatever else there is
	K.marry(int(head.id), int(tobin.id))
	var ada = K.housemate("Ada", "adult", 30.0)
	K.child_of(int(ada.id), int(head.id))
	var line: Array = HeirLine.candidates(int(head.id), hid, 1)
	_check(not line.is_empty() and int(line[0]["id"]) == int(tobin.id) and str(line[0]["kind"]) == "spouse", "the spouse in the household is first: %s" % str(K.ids_of(line)))
	# a partner bit alone counts for a housemate
	Family.spouses.erase(int(head.id))
	Family.spouses.erase(int(tobin.id))
	RelationshipBits.set_flag(int(head.id), int(wren.id), "partner", true, false)
	line = HeirLine.candidates(int(head.id), hid, 1)
	_check(not line.is_empty() and int(line[0]["id"]) == int(wren.id) and str(line[0]["kind"]) == "partner", "a partner who lives in the house is first: %s" % str(K.ids_of(line)))
	RelationshipBits.set_flag(int(head.id), int(wren.id), "partner", false, false)
	# a spouse living elsewhere is not in the line
	var far_spouse: Dictionary = K.townie("Sol", "adult")
	K.marry(int(head.id), int(far_spouse["id"]))
	line = HeirLine.candidates(int(head.id), hid, 1)
	_check(not K.ids_of(line).has(int(far_spouse["id"])) or str(line[K.ids_of(line).find(int(far_spouse["id"]))]["kind"]) != "spouse", "a spouse who lives elsewhere does not jump the line")
	Family.spouses.erase(int(head.id))
	Family.spouses.erase(int(far_spouse["id"]))
	# 2. grown children: the moved-out eldest ranks before the younger one at home; teens after grown kids; little ones last
	var bo = K.housemate("Bo", "adult", 5.0)
	var cy = K.housemate("Cy", "teen", 3.0)
	var di = K.housemate("Di", "child", 3.0)
	for k in [bo, cy, di]:
		K.child_of(int(k.id), int(head.id))
	_check(FamilyHousehold.move_out(int(ada.id), 0.0), "Ada moves out")
	var eli: Dictionary = K.townie("Eli", "adult")
	var par: int = int(eli["id"])
	K.child_of(int(head.id), par)                    # Eli is the head's PARENT
	var sib: Dictionary = K.townie("Sib", "adult")
	K.child_of(int(sib["id"]), par)                  # a sibling shares that parent
	var stranger: Dictionary = K.townie("Zed", "adult")
	line = HeirLine.candidates(int(head.id), hid, 1)
	var ids: Array = K.ids_of(line)
	var want: Array = [int(ada.id), int(bo.id), int(cy.id), int(sib["id"])]
	_check(ids.slice(0, 4) == want, "line = moved-out eldest child, grown child at home, teen, sibling; got %s want %s" % [str(ids), str(want)])
	var mates: Array = ids.slice(4, 6)
	_check(mates.has(int(tobin.id)) and mates.has(int(wren.id)) and ids.slice(6) == [par, int(di.id)], "then the housemates, the relative elsewhere, and the little child last; got %s" % str(ids))
	_check(not ids.has(int(stranger["id"])), "a townie who is no kin is not in the line")
	_check(not bool(line[0]["in_household"]) and str(line[0]["kind"]) == "child", "the moved-out child is flagged as living elsewhere")
	# 3. the player's pick goes first, only family / housemates can be picked
	var res: Dictionary = Succession.pick_heir(1, int(wren.id))
	_check(bool(res["ok"]), "pick a housemate as heir")
	line = HeirLine.candidates(int(head.id), hid, 1)
	_check(int(line[0]["id"]) == int(wren.id) and str(line[0]["kind"]) == "picked", "the picked heir is first")
	_check(not bool(Succession.pick_heir(1, int(stranger["id"]))["ok"]), "a stranger cannot be the heir")
	_check(not bool(Succession.pick_heir(1, int(head.id))["ok"]), "the head cannot be their own heir")
	_check(int(Players.field(1, "heir")) == int(wren.id), "a refused pick keeps the earlier one")
	_check(bool(Succession.pick_heir(1, -1)["ok"]) and Succession.heir_of(1) == -1, "the pick can be cleared")
	# 4. the little one picked on purpose stays first
	Succession.pick_heir(1, int(di.id))
	_check(int(HeirLine.candidates(int(head.id), hid, 1)[0]["id"]) == int(di.id), "a picked little one still goes first")
	K.teardown()
	return fails
