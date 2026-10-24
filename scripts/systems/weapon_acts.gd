class_name WeaponActs
extends RefCounted
## Task 57: a carried weapon changes what a person can do to another person (threaten, demand money, attack).
## It never adds a combat engine: it feeds SkillCheck (the weapon is the "weapon" tool from skills.json, plus its own check as a nudge),
## Health.injure (a deeper injury, capped at 3 = hospital), Notice (a gunshot is heard far; witnesses react) and justice (a case whose
## charge and evidence come from the weapon: prints, blood, casings, ballistics). A deep miss is the weapon's own `mishap`.
##   WeaponActs.entries(f, target)   WeaponActs.do_act(f, target, aid)   WeaponActs.held(pid)   WeaponActs.draw(f) / holster(f)

const MISHAP := {
	"cut_self": {"injure": 1, "cause": "cut", "line": ["The blade slips and opens your own hand.", "You cut yourself on your own knife."]},
	"hurt_hand": {"injure": 1, "cause": "bruised hand", "line": ["Your knuckles meet something harder than the face."]},
	"drop": {"injure": 0, "noise": 1.0, "line": ["It flies out of your hand and clatters on the ground."]},
	"jam": {"injure": 0, "noise": 0.6, "line": ["The gun jams. Nothing happens.", "A click. The round is stuck."]},
	"blowback": {"injure": 0, "noise": 0.4, "line": ["The spray blows back into your own face."]},
	"self_shock": {"injure": 0, "noise": 0.3, "line": ["You shock yourself with your own taser."]}
}

## weapons.json charge ids -> the real justice.json charges (the weapon file names charges justice.json does not have).
const CHARGE_MAP := {
	"assault_weapon": "aggravated_assault", "armed_assault": "aggravated_assault",
	"assault": "assault", "banned_weapon": "weapon_possession", "unlicensed_gun": "weapon_possession", "weapon_possession": "weapon_possession",
	"robbery": "robbery", "threats": "threats"
}
const CARRY_ACT := {"threaten_w": "threaten", "demand_w": "threaten", "attack_w": "fight"}

static func reset() -> void:
	pass

static func cfg() -> Dictionary:
	return SysUtil.table("weapons")

static func def(id: String) -> Dictionary:
	return (cfg().get("weapons", {}) as Dictionary).get(id, {})

static func is_weapon(id: String) -> bool:
	var d: Dictionary = def(id)
	return not d.is_empty() and d.has("skill")

## The weapon this person would use: the one held out, else the best one carried.
static func held(pid: int) -> Dictionary:
	var best: Dictionary = {}
	var best_v: float = -1.0
	for e in Inventory.items(pid):
		var id: String = str(e["id"])
		if not is_weapon(id):
			continue
		var d: Dictionary = def(id)
		if bool(e.get("shown", false)):
			return {"item": e, "id": id, "def": d}
		var v: float = float(d.get("check", 0.0)) + (10.0 if str(d.get("kind", "")) == "firearm" else 0.0)
		if v > best_v:
			best_v = v
			best = {"item": e, "id": id, "def": d}
	return best

## A firearm with no rounds on them is a club: the weapon's `empty` numbers replace check / injury.
static func _loaded(pid: int, e: Dictionary) -> bool:
	var ammo: String = str(def(str(e["id"])).get("ammo", ""))
	return ammo == "" or Inventory.count(pid, ammo) > 0

static func stats(pid: int) -> Dictionary:
	var h: Dictionary = held(pid)
	if h.is_empty():
		return {"id": "", "check": 0.0, "intimidate": 0.0, "injury_step": 0, "charge": "assault", "noise": 0.3, "skill": "fighting", "evidence": [], "legal": "free", "kind": "melee"}
	var d: Dictionary = h["def"]
	var out: Dictionary = d.duplicate()
	out["id"] = str(h["id"])
	if str(d.get("kind", "")) == "firearm" and not _loaded(pid, h["item"]):
		for k in (d.get("empty", {}) as Dictionary):
			out[k] = (d["empty"] as Dictionary)[k]
		out["empty"] = true
	return out

static func check_bonus(pid: int) -> float:
	return float(stats(pid).get("check", 0.0))

static func injury_step(pid: int) -> int:
	return int(stats(pid).get("injury_step", 0))

static func noise_of(pid: int) -> float:
	return float(stats(pid).get("noise", 0.3))

static func evidence_of(pid: int) -> Array:
	return stats(pid).get("evidence", [])

## A weapon charge id mapped onto a real justice charge.
static func charge_of(pid: int) -> String:
	return str(CHARGE_MAP.get(str(stats(pid).get("charge", "assault")), "assault"))

## Cause of the injury, for Health.injure and the obituary.
static func _cause(st: Dictionary) -> String:
	if str(st.get("kind", "")) == "firearm":
		return "gunshot"
	if (st.get("evidence", []) as Array).has("blood_trace"):
		return "cut"
	return "blunt"

# ------------------------------------------------------------------ the roll
## SkillCheck does the work; the weapon adds its check as a bounded nudge on a near miss (a firearm adds the shooting skill).
static func _attempt(fid: int, tid: int, act: String, st: Dictionary) -> Dictionary:
	var ctx: Dictionary = {"opponent": tid, "xp": 6.0}
	if float(st.get("check", 0.0)) > 0.0:
		ctx["tools"] = ["weapon"]                                  # skills.json tools.weapon
	var r: Dictionary = SkillCheck.attempt(fid, act, ctx)
	var bump: float = clampf(float(st.get("check", 0.0)) * 0.08, 0.0, 0.22)
	if str(st.get("skill", "")) == "shooting":
		bump += SkillCheck.level(fid, "shooting") / 10.0 * 0.15
	if not bool(r["ok"]) and SysUtil.rng.randf() < bump:
		r["ok"] = true
		r["grade"] = "partial"
	return r

static func _fire(pid: int, st: Dictionary) -> void:
	if str(st.get("kind", "")) == "firearm" and not bool(st.get("empty", false)):
		var ammo: String = str(st.get("ammo", ""))
		if ammo != "":
			Inventory.take(pid, ammo, 1)

static func _line(lines: Array, key: String) -> String:
	if lines.is_empty():
		return ""
	return str(lines[PlayerPrompt._pick("weapon|" + key, lines.size())])

# ------------------------------------------------------------------ the menu
static func entries(f, target) -> Array:
	if f == null or target == null or not Pawn.is_pawn(f) or not (target is Folk) or int(target.id) == int(f.id):
		return []
	if held(int(f.id)).is_empty():
		return []
	var out: Array = []
	var nm: String = str(stats(int(f.id)).get("label", "weapon")).to_lower()
	out.append({"id": "weapon_threaten", "label": "Threaten with the %s" % nm, "category": "Weapon", "enabled": true, "reason": "",
		"action": func(): _start(f, target, "threaten_w")})
	out.append({"id": "weapon_demand", "label": "Demand money with the %s" % nm, "category": "Weapon", "enabled": true, "reason": "",
		"action": func(): _start(f, target, "demand_w")})
	out.append({"id": "weapon_attack", "label": "Attack with the %s" % nm, "category": "Weapon", "enabled": true, "reason": "",
		"action": func(): _start(f, target, "attack_w")})
	if bool(held(int(f.id)).get("item", {}).get("shown", false)):
		out.append({"id": "weapon_holster", "label": "Put the %s away" % nm, "category": "Weapon", "enabled": true, "reason": "",
			"action": func(): holster(f)})
	else:
		out.append({"id": "weapon_draw", "label": "Draw the %s" % nm, "category": "Weapon", "enabled": true, "reason": "",
			"action": func():
				draw(f)
				var rt: Dictionary = Notice.react(int(target.id), int(f.id), "weapon", "victim")          # the person it is drawn on reacts first
				if str(rt["line"]) != "":
					SysUtil.notify(str(rt["line"]), "bad")})
	return out

static func _start(f, target, aid: String) -> void:
	if aid in ["demand_w", "attack_w"]:
		WalkThen.go(f, WalkThen.near(target.tile), func(): do_act(f, target, aid))
	else:
		do_act(f, target, aid)

## Hold the weapon out (people react to a weapon in the hand); or put it away.
static func draw(f) -> void:
	var h: Dictionary = held(int(f.id))
	if h.is_empty():
		return
	for e in Inventory.items(int(f.id)):
		if str(e["id"]) == str(h["id"]):
			e["shown"] = true
		elif is_weapon(str(e["id"])):
			e["shown"] = false
	_react_visible(f)

static func holster(f) -> void:
	for e in Inventory.items(int(f.id)):
		if is_weapon(str(e["id"])):
			e["shown"] = false

static func _react_visible(f) -> void:
	for w in Notice.who(int(f.id), f.tile, {"noise": 0.0, "visibility": 0.9}):
		var r: Dictionary = Notice.react(int(w["id"]), int(f.id), "weapon", "passerby")
		if str(r["line"]) != "":
			SysUtil.notify(str(r["line"]), "story")
			break

# ------------------------------------------------------------------ the acts
static func do_act(f, target, aid: String) -> void:
	var fid: int = int(f.id)
	var tid: int = int(target.id)
	var st: Dictionary = stats(fid)
	if str(st.get("id", "")) == "":
		return
	var tn: String = str(target.name).get_slice(" (", 0)
	var act: String = str(CARRY_ACT.get(aid, "fight"))
	WeaponShop.posed(fid, aid)          # task 57b: the body shows it (Threaten / Aim)
	var r: Dictionary = _attempt(fid, tid, act, st)
	var ok: bool = bool(r["ok"])
	var catastrophic: bool = str(r["grade"]) == "catastrophic"
	var coins: int = 0
	var line: String = ""
	var wn: String = str(st.get("label", "weapon")).to_lower()

	if aid == "demand_w" and ok:
		coins = mini(CrimePerson.coins(tid), SysUtil.rng.randi_range(10, 60))
		if coins > 0:
			CrimePerson.pay(tid, coins, "taken")
			CrimePerson.add_coins(fid, coins, "taken from %s" % tn)
			line = "%s hands over %d coins." % [tn, coins]
		else:
			line = "%s has nothing to hand over." % tn
	elif aid == "threaten_w":
		line = "%s backs away from the %s." % [tn, wn] if ok else "%s does not flinch." % tn
	elif aid == "attack_w":
		var shot: bool = str(st.get("kind", "")) == "firearm" and not bool(st.get("empty", false))
		line = ("You hit %s." % tn if shot else "You catch %s with the %s." % [tn, wn]) if ok else ("The shot misses %s." % tn if shot else "You swing and miss %s." % tn)

	if ok and aid == "attack_w":
		var injury: int = clampi(1 + int(st.get("injury_step", 0)), 1, 3)
		Health.injure(target, injury, _cause(st))
		if injury >= 3:
			line += " %s goes down hard." % tn
		_fire(fid, st)
	elif aid == "attack_w" and not catastrophic:
		_fire(fid, st)                            # a shot is fired even on a miss

	if catastrophic:
		line = (line + " " + _mishap(fid, st)).strip_edges()
	if line != "":
		SysUtil.notify(line, "bad" if aid != "threaten_w" else "story")
	if aid == "attack_w" and float(st.get("noise", 0.3)) >= 1.0 and not bool(st.get("empty", false)):          # only a fired shot rings out
		SysUtil.notify("The shot rings out across the street.", "story")

	RelationshipService.add_value(tid, fid, "friendship", -12.0 if aid != "attack_w" else -18.0)
	var witnesses: Array = Notice.who(fid, f.tile, {"noise": float(st.get("noise", 0.3)), "visibility": 0.9, "ignore": [tid]})
	_react(f, target, aid, st, ok, witnesses, coins)

static func _mishap(fid: int, st: Dictionary) -> String:
	var m: Dictionary = MISHAP.get(str(st.get("mishap", "")), {})
	if m.is_empty():
		return ""
	if int(m.get("injure", 0)) > 0:
		Health.injure(fid, int(m["injure"]), str(m.get("cause", "mishap")))
	return _line(m.get("line", []), str(st.get("mishap", "")))

static func _react(f, target, aid: String, st: Dictionary, ok: bool, witnesses: Array, coins: int) -> void:
	var fid: int = int(f.id)
	var tid: int = int(target.id)
	var reported: bool = false
	var wid: int = int(witnesses[0]["id"]) if not witnesses.is_empty() else -1
	var re: Dictionary = Notice.react(tid, fid, "weapon", "victim")
	if str(re["line"]) != "":
		SysUtil.notify(str(re["line"]), "bad")
	match str(re["id"]):
		"fight":
			var back: Dictionary = SkillCheck.attempt(tid, "fight", {"opponent": fid})
			if bool(back["ok"]):
				Health.injure(f, 1, "fight")
			reported = wid >= 0 and SysUtil.rng.randf() < 0.7
		"call":
			reported = true
		"confront":
			reported = wid >= 0 and SysUtil.rng.randf() < 0.35
	if wid >= 0 and not reported:
		var rw: Dictionary = Notice.react(wid, fid, "weapon", "passerby")
		if str(rw["line"]) != "":
			SysUtil.notify(str(rw["line"]), "bad")
		reported = str(rw["id"]) == "call"
	var kind: String = "robbery" if aid == "demand_w" else "assault"
	var charge: String = "threats" if aid == "threaten_w" else ("robbery" if aid == "demand_w" else charge_of(fid))
	_case(fid, tid, kind, charge, st, wid, reported, coins, ok)

static func _case(fid: int, tid: int, kind: String, charge: String, st: Dictionary, wid: int, reported: bool, coins: int, ok: bool) -> void:
	if not ok and not reported:
		return
	var ws: Array = [tid]
	if wid >= 0:
		ws.append(wid)
	var ev: Array = st.get("evidence", [])
	var c: Dictionary = CaseStore.create(kind, fid, tid, CrimePlace.where_now(tid),
		{"witnessed": true, "witnesses": ws, "witness_clarity": 0.9, "trace": clampf(0.25 + 0.2 * ev.size(), 0.0, 0.9), "stolen_coins": coins, "loot_value": coins})
	c["severity"] = clampi(1 + int(st.get("injury_step", 0)), 1, 3)
	c["act"] = "weapon"
	c["weapon"] = str(st.get("id", ""))
	c["evidence"] = ev
	c["charge_hint"] = charge
	var it: Dictionary = held(fid).get("item", {})
	if int(it.get("registered_to", -1)) >= 0:
		c["ballistics"] = int(it.get("serial", -1))
	if int(it.get("dirty_case", -1)) >= 0:
		c["dirty_case"] = int(it["dirty_case"])
	CrimePlace.place_at_scene(fid, str(c["scene"]))
	if reported:
		CaseDiscovery.report(c, wid if wid >= 0 else tid, "victim")
	if float(st.get("noise", 0.0)) >= 1.0 and kind == "assault" and charge != "threats" and not bool(st.get("empty", false)):
		Police.respond(c)                     # a gunshot (an attack that fired): neighbours and a patrol come; a threat fires nothing
