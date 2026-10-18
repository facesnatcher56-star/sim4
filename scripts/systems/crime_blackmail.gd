class_name CrimeBlackmail
extends RefCounted
## Task 09c section 3: blackmail with the secrets system (RelationshipKnowledge). Someone who learns a damaging secret (an affair, a crime, a
## hidden debt) demands coins on a schedule. The victim has FOUR answers (a prompt for a player folk, traits and coins decide for townies):
##   pay      the demand is met; it will come again on schedule until the victim chooses otherwise or runs dry
##   refuse   the secret is exposed: gossip, reputation and relationship damage
##   police   blackmail is a crime (a case, arrest, charge); the secret may still come out during the investigation
##   confront a charisma contest: the blackmailer backs off, or exposes them out of spite
## The same four are social actions (interactions pay_blackmailer / refuse_blackmailer / report_blackmail / confront_blackmailer, buff `blackmailed`).
## Dishonest and mean (grudge-holding, competitive) folk are likelier to blackmail; pressure for money pushes it too.

static func cfg() -> Dictionary:
	return JusticeState.sect("blackmail")

static func find(id: int) -> Dictionary:
	for b in JusticeState.blackmail:
		if int(b["id"]) == id:
			return b
	return {}

static func active_on(victim: int) -> Array:
	return JusticeState.blackmail.filter(func(b): return int(b["victim"]) == victim and str(b["state"]) in ["demand", "paying"])

## Likelihood weight that `pid` would blackmail.
static func inclination(pid: int) -> float:
	var w: float = 0.3 + CrimePressure.risk(pid) * 2.0
	if CrimePerson.has_trait(pid, "dishonest"):
		w *= 3.0
	for t in ["grudgeholder", "competitive", "vengeful"]:
		if CrimePerson.has_trait(pid, t):
			w *= 1.5
	for t2 in ["honest", "generous", "empath", "forgiving"]:
		if CrimePerson.has_trait(pid, t2):
			w *= 0.1
	return w

# ------------------------------------------------------------------ start
static func on_day() -> void:
	if not JusticeState.enabled:
		return
	var k: Dictionary = cfg()
	for pid in CrimePerson.everyone():
		var p: int = int(pid)
		if CrimePerson.is_player(p) or not CrimePerson.is_adult(p) or CrimePerson.in_custody(p):
			continue
		var known: Array = RelationshipKnowledge.secrets_known_by(p)
		if known.is_empty():
			continue
		if JusticeState.chance(float(k.get("daily", 0.01)) * inclination(p) * Incidents.surprise_mult()):
			var sec: Dictionary = known[JusticeState.rng.randi_range(0, known.size() - 1)]
			if int(sec["owner"]) != p and CrimePerson.alive(int(sec["owner"])) and active_on(int(sec["owner"])).is_empty():
				demand(p, int(sec["owner"]), int(sec["id"]))
	_collect()

## The blackmailer asks for money. Returns the record.
static func demand(blackmailer: int, victim: int, secret: int, amount: int = -1) -> Dictionary:
	var k: Dictionary = cfg()
	if amount < 0:
		amount = JusticeState.rng.randi_range(int(k.get("amount", [40, 160])[0]), int(k.get("amount", [40, 160])[1]))
	var id: int = 1
	for o in JusticeState.blackmail:
		id = maxi(id, int(o["id"]) + 1)
	var b: Dictionary = {"id": id, "blackmailer": blackmailer, "victim": victim, "secret": secret, "amount": amount, "every": int(k.get("every_days", 7)),
		"state": "demand", "paid": 0, "next_day": SysUtil.day() + int(k.get("every_days", 7))}
	JusticeState.blackmail.append(b)
	JusticeState.count("blackmail")
	var fv = CrimePerson.folk(victim)
	if fv != null:
		fv.add_buff("blackmailed")
	var sec_text: String = _secret_text(victim, secret)
	if CrimePerson.is_player(victim):
		JusticePlayer.ask(victim, "A threat", "%s knows that %s %s and wants %d coins to keep quiet, again every %d days. What does %s do?" % [CrimePerson.name_of(blackmailer), CrimePerson.name_of(victim), sec_text, amount, int(b["every"]), CrimePerson.name_of(victim)],
			[{"id": "pay", "label": "Pay (%d coins)" % amount}, {"id": "refuse", "label": "Refuse (the secret comes out)"}, {"id": "police", "label": "Go to the police"}, {"id": "confront", "label": "Confront them"}],
			_choice.bind(int(b["id"])), "pay" if CrimePerson.coins(victim) >= amount else "police")
	else:
		_choice(npc_choice(b), int(b["id"]))
	return b

static func _secret_text(victim: int, sid: int) -> String:
	for s in RelationshipKnowledge.ensure_secrets(victim):
		if int(s["id"]) == sid:
			return str(s["text"])
	return "has something to hide"

## What a townie victim does: rich enough and meek -> pay; honest or proud -> police; hot-headed -> confront; broke -> refuse.
static func npc_choice(b: Dictionary) -> String:
	var v: int = int(b["victim"])
	var weights: Array = [1.0 if CrimePerson.coins(v) >= int(b["amount"]) * 2 else 0.1, 0.4 + (0.6 if CrimePerson.coins(v) < int(b["amount"]) else 0.0),
		0.8 + (1.0 if CrimePerson.has_trait(v, "honest") else 0.0), 0.3 + (1.2 if CrimePerson.has_trait(v, "hot_headed") else 0.0) + CrimePerson.charisma(v)]
	if int(b["paid"]) >= 2:
		weights[0] = float(weights[0]) * 0.3                      # fed up with paying
	return ["pay", "refuse", "police", "confront"][JusticeState.pick_index(weights)]

static func _choice(choice, id: int) -> void:
	resolve(id, str(choice))

# ------------------------------------------------------------------ the four answers
static func resolve(id: int, choice: String) -> String:
	var b: Dictionary = find(id)
	if b.is_empty() or str(b["state"]) in ["ended", "exposed", "police"]:
		return ""
	var bm: int = int(b["blackmailer"])
	var v: int = int(b["victim"])
	var fv = CrimePerson.folk(v)
	match choice:
		"pay":
			var paid: int = CrimePerson.pay(v, int(b["amount"]), "blackmail")
			if paid < int(b["amount"]):
				return resolve(id, "refuse")          # cannot afford it: the secret comes out
			CrimePerson.add_coins(bm, paid, "blackmail")
			b["paid"] = int(b["paid"]) + 1
			b["state"] = "paying"
			b["next_day"] = SysUtil.day() + int(b["every"])
			return "paid"
		"refuse":
			expose(b)
			return "exposed"
		"police":
			b["state"] = "police"
			_remove_buff(fv)
			var c: Dictionary = CaseStore.create("blackmail", bm, v, CrimePerson.home_key(v), {"witnessed": true, "witness_clarity": 0.85, "witnesses": [v], "trace": 0.4,
				"stolen_coins": int(b["amount"]) * int(b["paid"]), "loot_value": int(b["amount"])})
			c["blackmail"] = id
			CaseDiscovery.report(c, v, "victim")
			c["progress"] = 0.5
			if JusticeState.chance(float(cfg().get("police_leak", 0.35))):
				expose(b, true)                       # the secret comes out during the investigation
			return "police"
		"confront":
			var win: float = clampf(float(cfg().get("confront_base", 0.4)) + (CrimePerson.charisma(v) - CrimePerson.charisma(bm)) * 0.4 + (0.1 if CrimePerson.has_trait(v, "hot_headed") else 0.0), 0.1, 0.85)
			if JusticeState.chance(win):
				b["state"] = "ended"
				_remove_buff(fv)
				RelationshipService.add_both(v, bm, "friendship", -15.0)
				RelationshipKnowledge.add_reputation(bm, -2.0)
				if CrimePerson.is_player(v):
					SysUtil.notify("%s stared %s down. The blackmail is over." % [CrimePerson.name_of(v), CrimePerson.name_of(bm)], "good")
				return "backed_off"
			expose(b)
			return "exposed"
	return ""

static func _remove_buff(f) -> void:
	if f != null:
		f.remove_buff("blackmailed")

## The secret gets out: gossip through the blackmailer's friends, reputation and relationship damage.
static func expose(b: Dictionary, quiet: bool = false) -> void:
	b["state"] = "exposed"
	var v: int = int(b["victim"])
	var bm: int = int(b["blackmailer"])
	_remove_buff(CrimePerson.folk(v))
	var sec: Dictionary = {}
	for s in RelationshipKnowledge.ensure_secrets(v):
		if int(s["id"]) == int(b["secret"]):
			sec = s
	var told: Array = CrimePerson.friends(bm).slice(0, 3)
	for h in told:
		RelationshipKnowledge.learn_secret(int(h), v, int(b["secret"]))
	RelationshipKnowledge.add_reputation(v, -float(cfg().get("expose_reputation", 8)) * float(sec.get("severity", 0.5)) * 2.0)
	for o in CrimePerson.close_alive(v).slice(0, 2):
		RelationshipService.add_both(v, int(o), "trust", -10.0)
	RelationshipService.add_both(v, bm, "friendship", -30.0)
	var text: String = "The secret of %s is out." % CrimePerson.name_of(v)
	ChronicleHook.note("secret_out", text, [v], CrimePerson.home_key(v), 2, false)
	if CrimePerson.is_player(v) and not quiet:
		SysUtil.notify(text + " The gossip is spreading.", "bad")

## Scheduled demands: paying victims are asked again.
static func _collect() -> void:
	for b in JusticeState.blackmail:
		if str(b["state"]) == "paying" and SysUtil.day() >= int(b["next_day"]):
			if not (CrimePerson.alive(int(b["victim"])) and CrimePerson.alive(int(b["blackmailer"]))) or CrimePerson.in_custody(int(b["blackmailer"])):
				b["state"] = "ended"
				continue
			b["state"] = "demand"
			var v: int = int(b["victim"])
			if CrimePerson.is_player(v):
				JusticePlayer.ask(v, "The demand again", "%s wants another %d coins." % [CrimePerson.name_of(int(b["blackmailer"])), int(b["amount"])],
					[{"id": "pay", "label": "Pay (%d coins)" % int(b["amount"])}, {"id": "refuse", "label": "Refuse (the secret comes out)"}, {"id": "police", "label": "Go to the police"}, {"id": "confront", "label": "Confront them"}],
					_choice.bind(int(b["id"])), "pay")
			else:
				resolve(int(b["id"]), npc_choice(b))

## Social actions fire these events (payload folk_id = victim, target_id = blackmailer).
static func on_event(ev: String, p: Dictionary) -> void:
	var v: int = int(p.get("folk_id", -1))
	var bm: int = int(p.get("target_id", -1))
	if ev == "blackmail_demand":
		for s in RelationshipKnowledge.secrets_known_by(v):
			if int(s["owner"]) == bm:
				demand(v, bm, int(s["id"]))
				return
		return
	var choice: String = {"blackmail_pay": "pay", "blackmail_refuse": "refuse", "blackmail_report": "police", "blackmail_confront": "confront"}.get(ev, "")
	if choice == "":
		return
	for b in JusticeState.blackmail:
		if int(b["victim"]) == v and int(b["blackmailer"]) == bm and str(b["state"]) in ["demand", "paying"]:
			resolve(int(b["id"]), choice)
			return
