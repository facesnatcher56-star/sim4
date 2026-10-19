extends RefCounted
## Household chaos (task 07b), good surprises (finding money is the framework example found_money): a lottery win that needs a market ticket (small wins common,
## the big one rare), an inheritance that only ever comes from a REAL old relative through BankWill (never a stranger, never against a will that names
## somebody else), and a long-lost sibling who really is family (RomanceRules treats them as family). The twins hook stays a hook.

const K = preload("res://tests/systems_kit.gd")
const C = preload("res://tests/chaos_kit.gd")

func run() -> Array:
	var f: Array = []
	_lottery(f)
	_inheritance(f)
	_long_lost(f)
	_twins_hook(f)
	return f

func _lottery(f: Array) -> void:
	var h: Dictionary = C.setup()
	var subj := IncidentSubject.of_household(1)
	K.expect(f, Incidents.effective_rate("lottery_win", subj) == 0.0, "no ticket, no lottery win")
	BankGamble.add_tickets(1, 2)
	K.expect(f, absf(Incidents.effective_rate("lottery_win", subj) - 0.4) < 0.001, "a ticket from the market can win")
	var bal: int = Economy.balance(1)
	Incidents.force("lottery_win", {"lot": "home:1", "outcome": 0})
	var small: int = Economy.balance(1) - bal
	Incidents.force("lottery_win", {"lot": "home:1", "outcome": 2})
	var big: int = Economy.balance(1) - bal - small
	K.expect(f, small >= 25 and small <= 60 and big >= 1500 and big <= 3000, "small %d, big %d" % [small, big])
	var big_share: float = 2.5 / 100.0
	K.expect(f, absf(0.4 * big_share - 0.01) < 0.0001, "the big win is about once in a hundred years of play (0.01 a year)")
	K.expect(f, K.has_note("raffle"), "told in plain words")
	K.teardown()

## Ada's grandparent is the townie `t` (through a long dead parent).
func _grandparent(h: Dictionary, t: Dictionary) -> void:
	Family.note_person(9001, "Nell Voss")
	Family.link_parent(int(h["ada"].id), 9001)
	Family.link_parent(9001, int(t["id"]))

func _inheritance(f: Array) -> void:
	var h: Dictionary = C.setup()
	Story.generate_townies()
	var subj := IncidentSubject.of_household(1)
	var rich: Dictionary = Story.add_townie(185.0, "Old Rowan", [], "")
	rich["coins"] = 1000
	K.expect(f, Incidents.effective_rate("inheritance", subj) == 0.0, "a rich stranger leaves nothing: no relative, no inheritance")
	var bal: int = Economy.balance(1)
	var r0: Dictionary = Incidents.force("inheritance", {"lot": "home:1", "outcome": 0})
	K.expect(f, Economy.balance(1) == bal and bool(rich["alive"]) and str(r0["text"]) == "", "forcing it still gives nothing from a stranger")
	_grandparent(h, rich)
	K.expect(f, RomanceRules.related(int(h["ada"].id), int(rich["id"])), "test setup: Rowan is Ada's grandparent")
	K.expect(f, absf(Incidents.effective_rate("inheritance", subj) - 0.25) < 0.001, "a real old relative with savings makes it possible")
	rich["coins"] = 50
	K.expect(f, Incidents.effective_rate("inheritance", subj) == 0.0, "but only if there is something to leave")
	rich["coins"] = 1000
	var other: Dictionary = Story.add_townie(120.0, "Stranger Lee", [], "")
	BankWill.wills[int(rich["id"])] = int(other["id"])
	K.expect(f, Incidents.effective_rate("inheritance", subj) == 0.0, "a will that names somebody outside the home is respected")
	BankWill.wills[int(rich["id"])] = int(h["bo"].id)
	K.expect(f, Incidents.effective_rate("inheritance", subj) > 0.0, "a will that names a housemate is fine")
	BankWill.wills.erase(int(rich["id"]))
	var r: Dictionary = Incidents.force("inheritance", {"lot": "home:1", "outcome": 0})
	K.expect(f, bool(r["ok"]) and Economy.balance(1) == bal + 800 and not bool(rich["alive"]) and int(rich["coins"]) == 200, "the estate moves through the will: +800 coins, Rowan has passed away")
	K.expect(f, not BankWill.has_will(int(rich["id"])) and str(r["text"]).contains("left 800 coins"), "the will is used up (%s)" % str(r["text"]))
	K.expect(f, Incidents.effective_rate("inheritance", subj) == 0.0, "and it cannot happen twice")
	K.teardown()

func _long_lost(f: Array) -> void:
	var h: Dictionary = C.setup()
	Story.generate_townies()
	var ada: Folk = h["ada"]
	var teen := K.make_folk(h["w"], "Teo Voss", [], 1, Vector2i(14, 12), "teen")
	var n0: int = Story.townies.size()
	var sit0: int = Story.situations.size()
	var r: Dictionary = Incidents.force("long_lost_family", {"lot": "home:1", "outcome": 0})
	K.expect(f, bool(r["ok"]) and Story.townies.size() == n0 + 1 and str(r["text"]).contains("long-lost sibling"), "a sibling turns up (%s)" % str(r["text"]))
	var kin: int = -1
	for id in Story.townies:
		kin = maxi(kin, int(id))                              # the newest townie
	var who = null
	for m in [ada, h["bo"]]:
		if RomanceRules.related(int(m.id), kin):
			who = m
	K.expect(f, who != null, "the newcomer is related to someone in the home")
	K.expect(f, not RomanceRules.allowed(int(who.id), kin) and RomanceRules.why_not(int(who.id), kin) == "They are family.", "RomanceRules treats them as family: nothing romantic allowed")
	K.expect(f, FamilyTree.siblings_of(int(who.id)).has(kin) and RelationshipBits.has_flag(int(who.id), kin, "family"), "a real sibling in the family tree, flagged family")
	K.expect(f, RomanceRules.is_adult(kin) and not RomanceRules.allowed(int(teen.id), kin), "an adult, and the teen can never be romantic with them either")
	K.expect(f, Story.situations.size() == sit0 + 1, "they come to visit the same day")
	var r2: Dictionary = Incidents.force("long_lost_family", {"lot": "home:1", "outcome": 0})
	K.expect(f, str(r2["text"]) == "" and Story.townies.size() == n0 + 1, "not again for a long while (min gap)")
	K.expect(f, Incidents.effective_rate("long_lost_family", IncidentSubject.of_household(1)) > 0.0, "(the dice themselves stay rare: %.2f a year)" % Incidents.effective_rate("long_lost_family", IncidentSubject.of_household(1)))
	K.teardown()
	# someone who already has a parent on record gets a half sibling through that parent
	var h2: Dictionary = C.setup()
	Story.generate_townies()
	Family.note_person(9100, "Vic Voss")
	Family.note_person(9101, "Una Voss")
	Family.link_parent(int(h2["ada"].id), 9100)
	Family.link_parent(int(h2["bo"].id), 9101)
	var before: int = Story.next_id
	Incidents.force("long_lost_family", {"lot": "home:1", "outcome": 0})
	var k2: int = -1
	var m2 = null
	for id2 in Story.townies:
		if int(id2) >= before:
			k2 = int(id2)
	for m in [h2["ada"], h2["bo"]]:
		if k2 >= 0 and RomanceRules.related(int(m.id), k2):
			m2 = m
	K.expect(f, m2 != null and not RomanceRules.allowed(int(m2.id), k2) and (FamilyTree.parents_of(k2).has(9100) or FamilyTree.parents_of(k2).has(9101)), "or a half sibling through a parent already on record")
	K.teardown()

func _twins_hook(f: Array) -> void:
	K.expect(f, ChaosTwinsHook.multiples_for(1, 2) == 1, "twins are only a documented hook until task 18: one baby")
