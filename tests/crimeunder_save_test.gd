extends RefCounted
## Task 23: save / load and determinism. Every underworld table (contracts, addicts, dealers, corners, gangs, rackets, cops, reputations, redemption,
## undercover, informants, protection, taint, fronts) survives a JSON round trip inside the justice life block, and the same saved state plays out
## the same days twice (own seeded rng; nothing reads the clock or an unseeded dice).

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	_roundtrip(f)
	_replay(f)
	_reset(f)
	return f

func _populate() -> void:
	var ids: Array = C.adults()
	for i in 6:
		CrimeLifePath.join(int(ids[i]), "chose")
		CrimeLifePath.member(int(ids[i]))["cred"] = 40.0
		CrimeLifePath.member(int(ids[i]))["rank"] = "crew_boss" if i < 2 else "burglar"
	CrimeUnderState.lines[int(ids[0])] = {"hit": {"standing": 14.0, "since": 1, "acts": 2, "via": "contact"}, "deal": {"standing": 3.0, "since": 1, "acts": 0, "via": "record"}}
	CrimeUnderState.lines[int(ids[1])] = {"racket": {"standing": 20.0, "since": 1, "acts": 0, "via": "contact"}}
	Story.townies[int(ids[5])]["coins"] = 3000
	CrimeUnderHit.post(int(ids[5]), int(ids[4]), "grudge", {"fee": 450})
	CrimeUnderState.contracts[1]["hitman"] = int(ids[0])
	CrimeUnderState.contracts[1]["state"] = "taken"
	CrimeUnderState.contracts[1]["research"] = 0.4
	CrimeUnderAddict.try_onset(int(ids[3]), "slumber", int(ids[0]), true)
	CrimeUnderDeal.ensure(int(ids[0]))["stock"] = {"glow": 5}
	CrimeUnderDeal.rec(int(ids[0]))["customers"] = [int(ids[3])]
	CrimeUnderState.corners["c1"] = {"owner": int(ids[0]), "hold": 0.5, "day": 3}
	var g: int = CrimeUnderGang.found(int(ids[1]), "the Save Crew")
	CrimeUnderGang.add_member(g, int(ids[2]))
	CrimeUnderGang.add_member(g, int(ids[0]))
	CrimeUnderState.informant[int(ids[2])] = {"gang": g, "day": 2, "exposed": false}
	CrimeUnderState.protected[int(ids[3])] = 99
	CrimeUnderState.cops[int(ids[4])] = {"taken": 2, "corruption": 2.0, "protecting": [int(ids[0])], "refused": 1}
	CrimeUnderState.rep[int(ids[0])] = {"hero": 3.0, "honour": 1.0, "guilt": 2.0, "deeds": 4}
	CrimeUnderState.redeem[int(ids[3])] = {"start": 1, "progress": 33.0, "mentor": int(ids[2]), "resisted": 1, "falls": 0, "last_tempt": 4}
	CrimeUnderState.undercover[int(ids[4])] = {"gang": g, "trust": 0.3, "evidence": 0.2, "day": 3}
	CrimeUnderState.taint[int(ids[1])] = 5.5
	CrimeUnderState.front[int(ids[1])] = 2
	WorldIface.coins[1] = 1000
	CrimeUnderRacket.lend(int(ids[1]), int(ids[5]), 100)
	CrimeLifeState.queue({"kind": "hit_exec", "pid": 1, "contract": 1, "scene": "street", "due_min": 5000})

func _first_diff(a: String, b: String) -> String:
	var n: int = mini(a.length(), b.length())
	for i in n:
		if a[i] != b[i]:
			return "@%d: %s <> %s" % [i, a.substr(maxi(i - 40, 0), 90), b.substr(maxi(i - 40, 0), 90)]
	return "length %d vs %d" % [a.length(), b.length()]

## Normalised: a loaded save holds floats where the game holds ints, so compare the JSON text after one more trip.
func _dump() -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(CrimeLifeState.to_dict())), "", true)

func _roundtrip(f: Array) -> void:
	var w := C.town(14)
	_populate()
	var before: String = _dump()
	var parsed = JSON.parse_string(JSON.stringify(CrimeLifeState.to_dict()))
	CrimeLifeState.from_dict(parsed)
	var after: String = _dump()
	K.expect(f, before == after, "the underworld state is identical after a JSON round trip (%d bytes) %s" % [before.length(), _first_diff(before, after)])
	var ids: Array = C.adults()
	K.expect(f, CrimeUnderState.contracts.has(1) and typeof(CrimeUnderState.contracts[1]["hitman"]) == TYPE_INT, "ids come back as integers")
	K.expect(f, CrimeUnderGang.of(int(ids[2])) >= 0 and typeof(CrimeUnderGang.member(1, int(ids[2]))["pid"]) == TYPE_INT, "gang members are found by integer id")
	K.expect(f, (CrimeUnderState.dealers[int(ids[0])]["customers"] as Array).has(int(ids[3])), "customer lists keep their ids")
	K.expect(f, int(CrimeLifeState.pending[0]["contract"]) == 1, "pending timed work keeps its contract id")
	K.teardown()

func _play(days: int) -> String:
	for d in days:
		K.set_time(10 + d, 12)
		CrimeUnderFlow.on_day(false)
	return _dump()

func _scenario() -> String:
	var w := C.town(16)
	_populate()
	for k in ["client_daily", "boss_daily"]:
		CrimeUnderState.sect("hit")[k] = 0.5
	var start: String = _dump()
	var end: String = _play(20)
	K.teardown()
	return start + "
" + end

func _replay(f: Array) -> void:
	var a: String = _scenario()
	var b: String = _scenario()
	K.expect(f, a == b, "the same start plays out the same 20 days twice %s" % _first_diff(a, b))
	var parts: PackedStringArray = a.split("
")
	K.expect(f, parts[0] != parts[1], "and something did happen in those days")

func _reset(f: Array) -> void:
	var w := C.town(12)
	_populate()
	CrimeFlow.reset()
	K.expect(f, CrimeUnderState.contracts.is_empty() and CrimeUnderState.gangs.is_empty() and CrimeUnderState.addicts.is_empty() and CrimeUnderState.lines.is_empty(), "a new game starts with no underworld")
	K.expect(f, CrimeUnderState.next_contract == 1 and CrimeUnderState.counters.is_empty(), "counters and ids restart")
	K.teardown()
