class_name BankWill
extends RefCounted
## Wills (task 13). "Write a will" (desk / computer) names an heir: a family member, a friend or a townie. When a household ENDS
## (nobody left in it), Aging._inherit calls apply(): coins, bank savings, belongings and rented-out properties go to the heir (debts are
## paid out of the estate first). Without a will the old rule (closest family) still decides. Also pays life-insurance claims.
## Tier: event driven. State: wills (folk id -> heir id). Heir id: a Folk id or a Story townie id.

static var wills: Dictionary = {}       # folk id -> heir person id

static func reset() -> void:
	wills.clear()

static func has_will(folk_id: int) -> bool:
	return wills.has(folk_id)

static func heir_of(folk_id: int) -> int:
	return int(wills.get(folk_id, -1))

static func write(folk_id: int, heir_id: int) -> bool:
	if folk_id == heir_id or heir_id < 0:
		return false
	if SysUtil.folk(heir_id) == null and not Story.is_townie(heir_id):
		return false
	wills[folk_id] = heir_id
	SysUtil.game_event("will_written", {"folk_id": folk_id, "heir_id": heir_id})
	return true

static func clear(folk_id: int) -> void:
	wills.erase(folk_id)

## Who the person could name: housemates, relatives and friends first, then the living townies.
static func candidates(folk_id: int) -> Array:
	var out: Array = []
	for f in SysUtil.residents():
		if int(f.id) != folk_id:
			out.append({"id": int(f.id), "name": str(f.name)})
	for t in Story.alive_townies():
		out.append({"id": int(t["id"]), "name": str(t["name"])})
	return out

## The "Write a will" interaction: if nobody is named yet, the partner / closest family / first housemate is.
static func default_heir(folk_id: int) -> int:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return -1
	for rank in ["spouse", "partner", "family"]:
		for c in candidates(folk_id):
			if RelationshipBits.bit_for(int(c["id"]), folk_id) == rank:
				return int(c["id"])
	for c2 in candidates(folk_id):
		if SysUtil.folk(int(c2["id"])) != null and int(SysUtil.folk(int(c2["id"])).household_id) == int(f.household_id):
			return int(c2["id"])
	return -1

static func on_write_event(folk_id: int) -> void:
	var f = SysUtil.folk(folk_id)
	if f == null:
		return
	var h: int = heir_of(folk_id) if has_will(folk_id) else default_heir(folk_id)
	if h < 0:
		SysUtil.notify("%s has nobody to leave things to yet." % f.name, "info")
		return
	write(folk_id, h)
	SysUtil.notify("%s wrote a will naming %s." % [f.name, SysUtil.folk_name(h)], "info")

# ------------------------------------------------------------------ Aging._inherit hook
## {} = no will (the old rules decide). Otherwise the estate is moved and the Aging result dictionary is returned.
static func apply(f, _mourners: Array) -> Dictionary:
	var fid: int = int(f.id)
	if not wills.has(fid) or not SysUtil.is_resident(f):
		wills.erase(fid)
		return {}
	var heir_id: int = heir_of(fid)
	wills.erase(fid)
	var hid: int = int(f.household_id)
	var hf = SysUtil.folk(heir_id)
	var coins: int = WorldIface.get_coins(hid)
	var saved: int = BankAccounts.balance(hid)
	var debts: int = 0
	for l in BankAccounts.loans_of(hid, "loan"):
		debts += int(ceil(float(l["balance"])))
		BankAccounts.loans.erase(l)
	var estate: int = maxi(coins + saved - debts, 0)
	BankAccounts.savings.erase(hid)
	if coins > 0:
		Economy.deposit(hid, -coins, "inheritance paid out")
	var props: int = 0
	if hf != null:
		if estate > 0:
			Economy.deposit(int(hf.household_id), estate, "inheritance from %s" % f.name)
		var moved: int = 0
		for o in Economy.objects_of(hid):
			Economy.owner[int(o.id)] = int(hf.household_id)
			moved += 1
		props = HousingProps.transfer(hid, int(hf.household_id), "player")
		SysUtil.notify("%s inherited %d coins and %d objects from %s's will." % [hf.name, estate, moved, f.name], "death")
		return {"to": int(hf.household_id), "heir": heir_id, "coins": estate, "objects": moved, "properties": props, "will": true}
	# a townie heir: the money and houses go to them (their things stay in town)
	if Story.is_townie(heir_id):
		(Story.townies[heir_id] as Dictionary)["coins"] = int(Story.townies[heir_id]["coins"]) + estate
		props = HousingProps.transfer(hid, heir_id, "townie")
		SysUtil.notify(Sexes.fill("%s left {their} estate to %s." % [f.name, Story.name_of(heir_id)], int(f.id)), "death")
		return {"to": -1, "heir": heir_id, "coins": estate, "objects": 0, "properties": props, "will": true}
	return {}

## Life insurance: to the household if somebody lives on in it, otherwise to whoever inherited.
static func queue_life_payout(hid: int, _who: int, amount: int) -> void:
	var to: int = hid
	if Aging.dead.size() > 0:
		var inh: Dictionary = (Aging.dead.back() as Dictionary).get("inheritance", {})
		if int(inh.get("to", -1)) > 0:
			to = int(inh["to"])
		elif int(inh.get("to", 0)) == -1 and int(inh.get("heir", -1)) >= 0 and Story.is_townie(int(inh["heir"])):
			(Story.townies[int(inh["heir"])] as Dictionary)["coins"] = int(Story.townies[int(inh["heir"])]["coins"]) + amount
			return
	BankInsurance._pay(to, "life", amount, "life insurance claim")

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"wills": SysUtil.str_keys(wills)}

static func from_dict(d: Dictionary) -> void:
	reset()
	wills = SysUtil.int_keys(d.get("wills", {}))
	for k in wills:
		wills[k] = int(wills[k])
