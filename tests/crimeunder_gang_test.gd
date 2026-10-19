extends RefCounted
## Task 23: crime families and gangs. Townie crews form around a crew boss, a player's folk is recruited and can rise (or challenge the boss), members
## betray when loyalty is gone, informants and undercover evidence bring busts, and a WAR between two gangs raises the town crime rate and decays
## afterwards (and ends by itself). Leaving is betrayal.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_found(f)
	_player(f)
	_war(f)
	_betray_and_bust(f)
	_informant(f)
	_challenge(f)
	return f

func _member(pid: int, rank: String, cred: float = 50.0) -> void:
	CrimeLifePath.join(pid, "chose")
	CrimeLifePath.member(pid)["rank"] = rank
	CrimeLifePath.member(pid)["cred"] = cred

func _two_gangs() -> Array:
	var ids: Array = C.adults()
	for i in 6:
		_member(int(ids[i]), "crew_boss" if i % 3 == 0 else "burglar")
	var a: int = CrimeUnderGang.found(int(ids[0]), "the Test Crew")
	var b: int = CrimeUnderGang.found(int(ids[3]), "the Other Crew")
	CrimeUnderGang.add_member(a, int(ids[1]))
	CrimeUnderGang.add_member(a, int(ids[2]))
	CrimeUnderGang.add_member(b, int(ids[4]))
	CrimeUnderGang.add_member(b, int(ids[5]))
	return [a, b]

func _found(f: Array) -> void:
	var w := C.town(20)
	var ids: Array = C.adults()
	for i in 5:
		_member(int(ids[i]), "crew_boss" if i == 0 else "burglar")
	CrimeUnderState.sect("gang")["found_daily"] = 1.0
	CrimeUnderGang._found_dice(CrimeUnderGang.cfg())
	K.expect(f, CrimeUnderState.gangs.size() == 1, "a crew boss with enough burglars around founds a gang")
	var g: Dictionary = CrimeUnderState.gangs[1]
	K.expect(f, int(g["boss"]) == int(ids[0]) and CrimeUnderGang.size(1) >= 3, "with a boss and members (%d)" % CrimeUnderGang.size(1))
	K.expect(f, str(CrimeUnderGang.rank_of(1, int(ids[0])).get("id", "")) == "boss", "the boss holds the top rank")
	K.teardown()

func _player(f: Array) -> void:
	var w := C.town(20)
	var g: Array = _two_gangs()
	CrimeLifePath.join(1)
	var low: Dictionary = CrimeUnderGang.join(1, int(g[0]))
	K.expect(f, not bool(low["ok"]), "a nobody is not let in")
	CrimeLifePath.member(1)["cred"] = 40.0
	var r: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimeunder", "args": {"action": "gang_join", "gang": int(g[0])}})
	K.expect(f, bool(r["ok"]) and CrimeUnderGang.of(1) == int(g[0]), "recruited through the command layer")
	K.expect(f, CrimeUnderGang.rank_label(1) == "Associate", "starting as an associate")
	CrimeUnderGang.member(int(g[0]), 1)["standing"] = 10.0
	K.expect(f, CrimeUnderGang.rank_label(1) == "Soldier", "standing earns rank")
	var boss: int = int(CrimeUnderState.gangs[int(g[0])]["boss"])
	var coins_boss: int = CrimePerson.coins(boss)
	CrimeUnderGang.dues(1, 200)
	K.expect(f, CrimePerson.coins(boss) > coins_boss, "dues go up to the boss")
	var left: Dictionary = CrimeUnderGang.leave(1)
	K.expect(f, bool(left["ok"]) and CrimeUnderGang.of(1) < 0, "the player can walk away")
	K.teardown()

func _war(f: Array) -> void:
	var w := C.town(24)
	var g: Array = _two_gangs()
	var base: float = CrimeRate.compute()
	var pts0: float = CrimeRate.recent_points()
	CrimeUnderState.sect("gang")["war"]["incidents_day"] = [3, 3]
	K.expect(f, CrimeUnderGang.start_war(int(g[0]), int(g[1])), "two gangs go to war")
	K.expect(f, not CrimeUnderGang.start_war(int(g[0]), int(g[1])), "but not twice")
	CrimeUnderState.sect("gang")["war"]["casualty"] = 0.0
	CrimeUnderState.sect("gang")["war"]["jail"] = 0.0
	CrimeUnderState.sect("gang")["war"]["truce_chance"] = 0.0
	CrimeUnderState.sect("gang")["war"]["police_end"] = 0.0
	var start: int = SysUtil.day()
	for d in 8:
		K.set_time(start + d, 12)
		CrimeUnderGang._war_day(CrimeUnderGang.cfg())
	var during: float = CrimeRate.compute()
	K.expect(f, CrimeRate.recent_points() > pts0 + 30.0, "war days write violence into the crime record (+%.0f points)" % (CrimeRate.recent_points() - pts0))
	K.expect(f, during > base + 8.0, "a gang war raises the town crime rate (%.1f -> %.1f)" % [base, during])
	# ends by itself, and the rate decays afterwards
	CrimeUnderState.sect("gang")["war"]["incidents_day"] = [0, 0]
	K.set_time(start + 25, 12)
	CrimeUnderGang._war_day(CrimeUnderGang.cfg())
	K.expect(f, CrimeUnderGang.at_war().is_empty(), "the war burns out when its time is up")
	K.set_time(start + 60, 12)
	var after: float = CrimeRate.compute()
	K.expect(f, after < during - 5.0 and after <= base + 3.0, "and the rate decays afterwards (%.1f -> %.1f)" % [during, after])
	K.teardown()

func _betray_and_bust(f: Array) -> void:
	var w := C.town(24)
	var g: Array = _two_gangs()
	var gid: int = int(g[0])
	var gang: Dictionary = CrimeUnderState.gangs[gid]
	var victim: Dictionary = (gang["members"] as Array)[1]
	var vp: int = int(victim["pid"])
	victim["loyal"] = 0.0
	CrimeUnderState.sect("gang")["loyalty"]["betray_daily"] = 1.0
	CrimeUnderGang._loyalty(gang, CrimeUnderGang.cfg())
	K.expect(f, CrimeUnderGang.of(vp) < 0 and bool(CrimeLifePath.member(vp).get("snitch", false)), "a member with no loyalty left talks and is out")
	K.expect(f, float(gang["tips"]) > 0.3, "and the police have a tip")
	var arrests: int = CrimeUnderGang.bust(gid)
	K.expect(f, arrests >= 1 and CrimeUnderState.counter("gang_bust") == 1, "the police bust the gang (%d arrested)" % arrests)
	K.expect(f, CrimePerson.in_custody(int(gang["boss"])) or not CaseStore.cases_of_culprit(int(gang["boss"])).is_empty(), "the boss is charged")
	K.teardown()

func _informant(f: Array) -> void:
	var w := C.town(24)
	var g: Array = _two_gangs()
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["cred"] = 40.0
	CrimeUnderGang.join(1, int(g[0]))
	var coins: int = CrimePerson.coins(1)
	var r: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimeunder", "args": {"action": "gang_inform"}})
	K.expect(f, bool(r["ok"]) and CrimePerson.coins(1) > coins and CrimeUnderState.informant.has(1), "the player turns informant for a fee")
	K.expect(f, float(CrimeUnderState.gangs[int(g[0])]["tips"]) >= 1.0, "the gang's trouble grows")
	K.expect(f, CrimeUnderGood.protection(1) >= 0.5, "and the police go easy on them for a while")
	var p: Dictionary = Commands.run({"player_id": 1, "folk_id": 1, "action": "crimeunder", "args": {"action": "gang_protect"}})
	K.expect(f, bool(p["ok"]) and CrimeUnderGang.of(1) < 0 and not CrimeLifePath.is_member(1) and CrimeUnderState.protected.has(1), "witness protection takes them out of the underworld")
	K.expect(f, not bool(CrimeUnderLines.join(1, "deal")["ok"]), "and the door stays shut for a while")
	K.teardown()

func _challenge(f: Array) -> void:
	var w := C.town(24)
	var g: Array = _two_gangs()
	CrimeLifePath.join(1)
	CrimeLifePath.member(1)["cred"] = 99.0
	CrimeUnderGang.join(1, int(g[0]))
	CrimeUnderGang.member(int(g[0]), 1)["standing"] = 40.0
	CrimeUnderGang.member(int(g[0]), 1)["loyal"] = 1.0
	var won: int = 0
	var boss0: int = int(CrimeUnderState.gangs[int(g[0])]["boss"])
	for i in 30:
		CrimeUnderState.gangs[int(g[0])]["boss"] = boss0
		if CrimeUnderGang.of(1) < 0:
			CrimeUnderGang.add_member(int(g[0]), 1, 40.0)
			CrimeUnderGang.member(int(g[0]), 1)["loyal"] = 1.0
		var r: Dictionary = CrimeUnderGang.challenge(1)
		if bool(r.get("won", false)):
			won += 1
	K.expect(f, won >= 5 and won <= 29, "a strong lieutenant can take the top place, but not always (%d of 30)" % won)
	K.teardown()
