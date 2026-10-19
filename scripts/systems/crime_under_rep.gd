class_name CrimeUnderRep
extends RefCounted
## Task 23, part 3: TWO REPUTATIONS, MORAL MEMORIES and how the family and the world react.
##  - public reputation = RelationshipKnowledge (the town's view; falls on a conviction); underworld reputation = street cred (CrimeLifePath) + the
##    standing in each line; hero standing (CrimeUnderState.rep.hero) rises with good deeds. `summary` / `known_to` say who would know what.
##  - `deed(pid, kind)`: guilt or pride as a mood, by TRAIT (the shrugging kind feel nothing, the empathic suffer); kinds: kill, mercy, betray, heroic.
##  - `family_reaction`: relatives who find out (CrimeLifeMoral.find_out) may DISOWN, COVER UP or JOIN; the legacy keeps notoriety and honour sides.
##  - `refused_service`: shops turn away a known thief.
## Tier: instant calls from events; no daily loop over people beyond the small `rep` table (hero decay).

static func cfg() -> Dictionary:
	return CrimeUnderState.sect("rep")

static func rec(pid: int) -> Dictionary:
	return CrimeUnderState.rep.get(pid, {"hero": 0.0, "honour": 0.0, "guilt": 0.0, "deeds": 0})

static func _put(pid: int, r: Dictionary) -> void:
	CrimeUnderState.rep[pid] = r

static func hero(pid: int) -> float:
	return float(rec(pid).get("hero", 0.0))

static func underworld(pid: int) -> float:
	var v: float = CrimeLifePath.cred(pid)
	for line in CrimeUnderLines.ids():
		v = maxf(v, CrimeLifePath.cred(pid) * 0.5 + CrimeUnderLines.standing(pid, line) * 0.5) if CrimeUnderLines.has(pid, line) else v
	return v

## {public, underworld, hero, heat, notoriety, honour}: both reputations side by side.
static func summary(pid: int) -> Dictionary:
	var m: Dictionary = CrimeLifePath.member(pid)
	var r: Dictionary = rec(pid)
	return {"public": int(CrimePerson.reputation(pid)), "underworld": int(underworld(pid)), "hero": int(hero(pid)), "heat": int(float(m.get("heat", 0.0))), "notoriety": CrimeLifeMoral.notoriety(pid),
		"honour": int(float(r.get("honour", 0.0))), "rank": CrimeLifePath.rank_label(pid)}

## Who would know. The town reads the public side (and a record); the underworld reads cred; the police read heat. A hero is known by everyone.
static func known_to(observer: int, subject: int) -> Dictionary:
	var out: Dictionary = {"public": true, "underworld": false, "heat": false}
	if CrimeLifePath.is_member(observer) or CrimeLifeContacts.has(observer, subject) or CrimeLifeContacts.has(subject, observer):
		out["underworld"] = CrimeLifePath.cred(subject) >= float(cfg().get("known_underworld_cred", 12.0)) or CrimeLifeContacts.has(subject, observer)
	var cr: String = CrimePerson.career(observer)
	out["heat"] = cr in ["police_officer", "detective"]
	return out

# ------------------------------------------------------------------ moral memories
static func _shrugs(pid: int) -> bool:
	for t in cfg().get("shrug", []):
		if CrimePerson.has_trait(pid, str(t)):
			return true
	return false

static func _suffers(pid: int) -> bool:
	for t in cfg().get("suffer", []):
		if CrimePerson.has_trait(pid, str(t)):
			return true
	return false

## Guilt and pride from a deed. Returns the feeling ("guilt", "pride" or "").
static func deed(pid: int, kind: String) -> String:
	var r: Dictionary = rec(pid)
	r["deeds"] = int(r.get("deeds", 0)) + 1
	var feeling: String = ""
	match kind:
		"kill", "betray":
			feeling = "guilt" if (_suffers(pid) or not _shrugs(pid)) else ""
			if feeling == "guilt":
				r["guilt"] = float(r.get("guilt", 0.0)) + (2.0 if _suffers(pid) else 1.0)
				CrimePerson.add_buff_safe(pid, str(cfg().get("guilt_buff", "troubled_conscience")))
			else:
				r["honour"] = float(r.get("honour", 0.0)) - 0.5
		"mercy":
			r["honour"] = float(r.get("honour", 0.0)) + 1.0
			if not _shrugs(pid):
				feeling = "pride"
				CrimePerson.add_buff_safe(pid, str(cfg().get("pride_buff", "proud")))
		"heroic":
			r["honour"] = float(r.get("honour", 0.0)) + 2.0
			feeling = "pride"
			CrimePerson.add_buff_safe(pid, "hero_of_the_day")
	_put(pid, r)
	return feeling

## Good deeds: hero standing, public reputation, a Chronicle line for big ones.
static func add_hero(pid: int, amount: float, text: String = "") -> void:
	var r: Dictionary = rec(pid)
	r["hero"] = clampf(float(r.get("hero", 0.0)) + amount, 0.0, 100.0)
	_put(pid, r)
	var f = CrimePerson.folk(pid)
	if f != null and amount > 0.0:
		RelationshipKnowledge.add_reputation(pid, amount * float(cfg().get("public_per_hero", 0.5)))
	if text != "" and amount >= 2.0:
		ChronicleHook.note("hero", text, [pid], "", 2, true)
		if CrimePerson.is_player(pid):
			SysUtil.notify(text, "good")

# ------------------------------------------------------------------ family
## A relative found out (CrimeLifeMoral.find_out has already cost friendship and started gossip). They may disown, cover up or join.
static func family_reaction(culprit: int, kin: int) -> String:
	var k: Dictionary = cfg().get("family", {})
	if not CrimePerson.alive(kin):
		return ""
	var fr: float = RelationshipService.value(kin, culprit, "friendship")
	var traits_good: bool = CrimePerson.has_trait(kin, "honest") or CrimePerson.has_trait(kin, "empath")
	var dishonest: bool = CrimePerson.has_trait(kin, "dishonest") or CrimePerson.has_trait(kin, "vengeful")
	var disown: float = float(k.get("disown", 0.25)) * (2.0 if traits_good else 1.0) * (0.3 if fr > 70.0 else 1.0)
	var cover: float = float(k.get("cover", 0.3)) * (1.6 if fr >= float(k.get("min_friendship", 40.0)) else 0.4) * (0.5 if traits_good else 1.0)
	var join: float = float(k.get("join", 0.08)) * (2.5 if dishonest else 0.2) * (1.0 + CrimePressure.risk(kin))
	var i: int = CrimeUnderState.pick_index([disown, cover, join, 0.35])
	var out: String = ["disown", "cover", "join", ""][maxi(i, 0)]
	match out:
		"disown":
			RelationshipService.add_both(kin, culprit, "friendship", float(k.get("friendship", -30.0)))
			var r: Dictionary = rec(culprit)
			r["disowned"] = int(r.get("disowned", 0)) + 1
			r["honour"] = float(r.get("honour", 0.0)) - 2.0
			_put(culprit, r)
			if CrimePerson.is_player(culprit) or CrimePerson.is_player(kin):
				SysUtil.notify("%s has turned their back on %s. \"I can't know you any more.\"" % [CrimePerson.name_of(kin), CrimePerson.name_of(culprit)], "bad")
		"cover":
			for c in CaseStore.cases_of_culprit(culprit):
				if str(c["state"]) in ["hidden", "open"]:
					c["trace"] = maxf(float(c.get("trace", 0.2)) * (1.0 - float(k.get("cover_trace", 0.35))), 0.0)
					CaseStore.note(c, "A relative of the culprit has been less than helpful to the police.")
			if CrimePerson.is_player(culprit):
				SysUtil.notify("%s knows, and is keeping quiet for %s." % [CrimePerson.name_of(kin), CrimePerson.name_of(culprit)], "info")
		"join":
			if not CrimePerson.is_player(kin) and CrimePerson.is_adult(kin) and not CrimeLifePath.is_member(kin):
				CrimeLifePath.join(kin, "chose")
				CrimeLifeContacts.add(culprit, kin, "", 0.6)
				if CrimePerson.is_player(culprit):
					SysUtil.notify("%s wants in. %s doesn't tell them no." % [CrimePerson.name_of(kin), CrimePerson.name_of(culprit)], "warn")
	if out != "":
		CrimeUnderState.count("family_" + out)
		SysUtil.game_event("family_reacted", {"folk_id": culprit, "target_id": kin, "reaction": out})
	return out

## Legacy lines of both sides: notoriety (from the criminal life) and honour (from the good and the merciful).
static func legacy_lines(pid: int) -> Array:
	var out: Array = []
	var r: Dictionary = rec(pid)
	if float(r.get("hero", 0.0)) >= 10.0:
		out.append("Remembered by the town as someone who stepped in when it counted.")
	elif float(r.get("honour", 0.0)) >= 4.0:
		out.append("Known for mercy where mercy was not expected.")
	if int(r.get("disowned", 0)) > 0:
		out.append("Turned away by family for the life led.")
	return out

# ------------------------------------------------------------------ the world reacts
## A shop turns away someone with a recent theft conviction and a poor name.
static func refused_service(pid: int) -> bool:
	var k: Dictionary = cfg().get("refuse_theft", {})
	if hero(pid) >= 10.0 or CrimePerson.reputation(pid) >= float(k.get("rep_below", 20.0)):
		return false
	for r in JusticeRecords.convictions(pid):
		if (k.get("charges", []) as Array).has(str(r.get("charge", ""))) and SysUtil.day() - int(r.get("day", 0)) <= int(k.get("window_days", 56)):
			return true
	return false

static func on_day() -> void:
	for pid in CrimeUnderState.rep.keys():
		var r: Dictionary = CrimeUnderState.rep[pid]
		if float(r.get("hero", 0.0)) > 0.0:
			r["hero"] = maxf(float(r["hero"]) - float(cfg().get("hero_decay_day", 0.005)), 0.0)
		if not CrimePerson.alive(int(pid)):
			CrimeUnderState.rep.erase(pid)
