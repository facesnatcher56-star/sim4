extends RefCounted
## Task 15: control passes when the head dies. Spouse in the house; a moved-out child who is not controlled until then and moves back into the
## family home (with partner and young child, funds and furniture staying); the player's pick; a non-head death changes nothing; plain words.

const K := preload("res://tests/succession_kit.gd")
var fails: Array = []
var changed: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)

func run() -> Array:
	fails = []
	changed.clear()
	SimEnv.events().game_event.connect(func(n, p): if n == "head_changed": changed.append(p))
	_spouse()
	_moved_out_child()
	_pick_and_commands()
	_non_head()
	return fails

func _watch() -> void:
	changed.clear()

func _spouse() -> void:
	var folk: Array = K.new_game()
	_watch()
	var head = folk[0]
	K.marry(int(head.id), int(folk[1].id))
	_check(Succession.head_of(1) == int(head.id), "the first folk of the household is its head")
	Aging.kill(int(head.id), "old age")
	_check(Succession.head_of(1) == int(folk[1].id), "the spouse is head now")
	_check(changed.size() == 1 and int(changed[0]["folk_id"]) == int(folk[1].id) and int(changed[0]["player_id"]) == 1, "head_changed names the new head and the player")
	_check(not Succession.is_pending(1) and K.household_count() == 2, "the household goes on with two members")
	_check(K.world().get_folk(int(folk[1].id)) != null and Players.owns(1, int(folk[1].household_id)), "the new head is controlled by player 1")
	var said := false
	for n in K.HoodKit.notes:
		if str(n[0]).find("You now play Tobin") >= 0 and str(n[0]).find("has died") >= 0 and str(n[0]).find("their spouse") >= 0:
			said = true
	_check(said, "plain words say who died and who you play now: %s" % str(K.HoodKit.notes.map(func(n): return n[0])))
	K.teardown()

func _moved_out_child() -> void:
	var folk: Array = K.new_game()
	_watch()
	var head = folk[0]
	var ada = K.housemate("Ada", "adult", 20.0)
	K.child_of(int(ada.id), int(head.id))
	var kit: Dictionary = K.townie("Kit", "child", 2.0)         # Ada's own child and partner live out of the family home
	var pal: Dictionary = K.townie("Pal", "adult", 4.0)
	K.child_of(int(kit["id"]), int(ada.id))
	K.marry(int(ada.id), int(pal["id"]))
	FamilyHousehold.move_out(int(ada.id), 0.0)
	_check(K.world().get_folk(int(ada.id)) == null and not Players.owns(1, 2), "a child who moved out is a townie: the player does not control them")
	_check(Succession.head_of(1) == int(head.id), "moving out does not change the head")
	Economy.deposit(1, 1000, "test")
	var coins: int = WorldIface.get_coins(1)
	var objs: int = Economy.objects_of(1).size()
	Aging.kill(int(head.id), "old age")
	var a = K.world().get_folk(int(ada.id))
	_check(a != null and int(a.household_id) == 1, "after the head dies the moved-out child moves back into the family home")
	_check(Succession.head_of(1) == int(ada.id) and Players.owns(1, int(a.household_id)), "control passes to the moved-out child")
	_check(changed.size() == 1 and int(changed[0]["folk_id"]) == int(ada.id), "head_changed names the heir")
	var p = K.world().get_folk(int(pal["id"]))
	var k = K.world().get_folk(int(kit["id"]))
	_check(p != null and int(p.household_id) == 1 and k != null and int(k.household_id) == 1, "their partner and young child come along")
	_check(WorldIface.get_coins(1) == coins and Economy.objects_of(1).size() >= objs, "the family home keeps its funds and furniture (coins %d->%d, objects %d->%d; the grave is new)" % [coins, WorldIface.get_coins(1), objs, Economy.objects_of(1).size()])
	_check(K.household_count() == 2 + 3, "the housemates stay too (Tobin, Wren, Ada, Pal, Kit)")
	var said := false
	for n in K.HoodKit.notes:
		if str(n[0]).find("Ada, their child, moves into the family home. You now play Ada") >= 0:
			said = true
	_check(said, "plain words: %s" % str(K.HoodKit.notes.map(func(n): return n[0])))
	K.teardown()

func _pick_and_commands() -> void:
	var folk: Array = K.new_game()
	var head = folk[0]
	K.marry(int(head.id), int(folk[1].id))
	var r: Dictionary = Commands.run({"player_id": 1, "folk_id": int(head.id), "action": "set_heir", "args": {"heir_id": int(folk[2].id)}})
	_check(bool(r["ok"]) and Succession.heir_of(1) == int(folk[2].id), "set_heir command picks the heir: %s" % str(r))
	var bad: Dictionary = Commands.run({"player_id": 1, "folk_id": int(head.id), "action": "set_heir", "args": {"heir_id": 99999}})
	_check(not bool(bad["ok"]) and str(bad["msg"]) != "", "an unknown heir is refused with a message")
	var other: Dictionary = Commands.run({"player_id": 7, "folk_id": int(head.id), "action": "set_heir", "args": {"heir_id": int(folk[2].id)}})
	_check(not bool(other["ok"]), "a player who plays no household cannot pick an heir")
	Aging.kill(int(head.id), "old age")
	_check(Succession.head_of(1) == int(folk[2].id), "the picked heir plays on, even with a spouse in the house")
	_check(Succession.heir_of(1) == -1, "the pick is used up")
	K.teardown()

func _non_head() -> void:
	var folk: Array = K.new_game()
	var head = folk[0]
	Succession.pick_heir(1, int(folk[2].id))
	Aging.kill(int(folk[1].id), "old age")
	_check(Succession.head_of(1) == int(head.id) and Succession.heir_of(1) == int(folk[2].id), "another death changes neither head nor pick")
	Aging.kill(int(folk[2].id), "old age")
	_check(Succession.heir_of(1) == -1, "when the picked heir dies the pick is cleared")
	_check(Succession.head_of(1) == int(head.id), "the head is still the head")
	K.teardown()
