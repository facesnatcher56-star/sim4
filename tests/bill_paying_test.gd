extends RefCounted
## 19i: the world runs without the player - the bills get paid. Households nobody plays pay by themselves on the due date; the player's own household
## has an autopay setting (default off) and, off or not, an adult at home pays at the mailbox on their own once a bill is waiting and the coins are
## there (sooner when it is overdue, and the neat first). Nobody pays a bill they cannot afford.

const K = preload("res://tests/systems_kit.gd")
const Kit = preload("res://tests/sim_testkit.gd")

func run() -> Array:
	var f: Array = []
	_autopay(f)
	_by_hand(f)
	return f

func _world() -> Dictionary:
	var w := K.setup(7, true)
	SysContent.install()
	var ada := K.make_folk(w, "Ada Voss", [], 1, Vector2i(12, 12))
	var kid := K.make_folk(w, "Kit Voss", [], 1, Vector2i(13, 12), "child")
	var bo := K.make_folk(w, "Bo Rook", [], 2, Vector2i(40, 40))
	w.add_object("mailbox", Vector2i(14, 12))
	K.mgr.new_game([1])
	Economy.reset()
	WorldIface.coins[1] = 3000
	WorldIface.coins[2] = 3000
	return {"w": w, "ada": ada, "kid": kid, "bo": bo}

func _autopay(f: Array) -> void:
	var h := _world()
	K.expect(f, Economy.auto_pay == false, "autopay for the player's own household is off by default")
	K.expect(f, Economy.autopay_for(2) and not Economy.autopay_for(1), "a household nobody plays always pays by itself; the player's does not by default")
	var b1: Dictionary = Economy.issue_bill(1)
	var b2: Dictionary = Economy.issue_bill(2)
	var due: int = int(Economy.outstanding(1)[0]["due"])
	K.set_time(due, 8)
	Economy.on_day(due)
	K.expect(f, bool(b2["paid"]), "the townie household's bill is paid on the due date")
	K.expect(f, not bool(b1["paid"]), "the player's household bill waits when autopay is off")
	Economy.auto_pay = true
	Economy.on_day(due + 1)
	K.expect(f, bool(b1["paid"]), "and is paid by autopay when the player turns it on")
	K.teardown()

func _by_hand(f: Array) -> void:
	var h := _world()
	var ada: Folk = h["ada"]
	var kid: Folk = h["kid"]
	K.set_time(8, 10)
	Economy.issue_bill(1)
	BillPaying.refresh()
	K.expect(f, ada.has_buff("bills_waiting") and not ada.has_buff("bills_late"), "an unpaid bill the household can afford is on the adult's mind")
	K.expect(f, not kid.has_buff("bills_waiting"), "a child never is")
	var found := false
	for c in Autonomy.gather(ada):
		if str(c["id"]) == "pay_bills":
			found = true
	K.expect(f, found, "Pay Bills is offered at the mailbox")
	var due: int = int(Economy.outstanding(1)[0]["due"])
	K.set_time(due, 10)
	BillPaying.refresh()
	K.expect(f, ada.has_buff("bills_late") and not ada.has_buff("bills_waiting"), "past the due date it is urgent")
	var paid_by_choice := false
	for i in 40:
		var pick: Dictionary = Autonomy.choose(ada)
		if str(pick.get("interaction_id", "")) == "pay_bills":
			paid_by_choice = true
			break
	K.expect(f, paid_by_choice, "an adult with an overdue bill and the coins goes to pay it on their own")
	SysUtil.game_event("pay_bills", {"folk_id": ada.id, "target_id": -1})
	K.expect(f, Economy.outstanding(1).is_empty() and not ada.has_buff("bills_late"), "paying clears the bills and the worry")
	K.expect(f, int(Economy.missed.get(1, 0)) == 0, "no missed bill on record")
	# no money, no errand
	Economy.issue_bill(1)
	WorldIface.coins[1] = 0
	BillPaying.refresh()
	K.expect(f, not ada.has_buff("bills_waiting") and not ada.has_buff("bills_late"), "nobody goes to pay a bill the house cannot afford")
	K.teardown()
