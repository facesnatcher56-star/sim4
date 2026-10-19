extends RefCounted
## Murder wording: a trial that cannot go ahead because the accused is secretly dead says nothing about the death (it is closed the day the
## body is found), and the finding of a body gives one death toast, not two.

const C = preload("res://tests/crime_kit.gd")
const K = preload("res://tests/systems_kit.gd")

func run() -> Array:
	var f: Array = []
	var w := C.town(10)
	var ids: Array = C.adults()
	var res: int = int(ids[0])
	var tid: int = int(Story.alive_townies()[2]["id"])
	var tname: String = Story.name_of(tid)
	K.set_time(10, 9)
	RelationshipService.add_both(res, tid, "friendship", 60.0)
	var c: Dictionary = CaseStore.create("assault", tid, res, "town:2", {})
	c["accused"] = tid
	c["charge"] = "assault"
	c["state"] = "charged"
	CrimePerson.hide_death(tid, "murder")
	K.expect(f, CrimePerson.death_hidden(tid), "the townie's death is hidden")
	var n0: int = K.notes.size()
	Courthouse.verdict_day(c)
	var said: bool = false
	for n in c["notes"]:
		if str(n["text"]).find("died before the trial") >= 0:
			said = true
	for i in range(n0, K.notes.size()):
		if str(K.notes[i][0]).find(tname) >= 0:
			said = true
	K.expect(f, not said and str(c["state"]) != "closed", "no 'died before the trial' line while the death is hidden")
	# the body is found: ONE death toast, then the case closes
	var m0: int = K.notes.size()
	c["found"] = false
	var murder: Dictionary = CaseStore.create("murder", res, tid, "town:2", {})
	murder["found"] = false
	CaseDiscovery._found(murder, "body")
	CaseStore.on_death(tid)
	var deaths: int = 0
	for i in range(m0, K.notes.size()):
		var t: String = str(K.notes[i][0])
		if t.find(tname) >= 0 and (t.find("is dead") >= 0 or t.find("found dead") >= 0):
			deaths += 1
	K.expect(f, deaths <= 1, "one death toast for the finding, not two (%d)" % deaths)
	# the same body cannot be found again: another search day, a serial-pattern sweep or the daily case pass say nothing more
	var m1: int = K.notes.size()
	CaseDiscovery._found(murder, "search")
	CaseDiscovery.on_day()
	var again: int = 0
	for i2 in range(m1, K.notes.size()):
		var t2: String = str(K.notes[i2][0])
		if t2.find(tname) >= 0 and (t2.find("is dead") >= 0 or t2.find("found dead") >= 0 or t2.find("was found") >= 0):
			again += 1
	K.expect(f, again == 0, "a second finding of the same body is silent (%d more toasts)" % again)
	var closed_note: bool = false
	for n2 in c["notes"]:
		if str(n2["text"]).find("died before the trial") >= 0:
			closed_note = true
	K.expect(f, closed_note and str(c["state"]) == "closed", "once the death is known the case is closed with the plain line")
	# an incident whose effect kills (a heart attack) gives one toast too: the death line, not the outcome summary as well
	var tid2: int = int(Story.alive_townies()[3]["id"])
	RelationshipService.add_both(res, tid2, "friendship", 60.0)
	var k0: int = K.notes.size()
	Incidents.force("heart_attack", {"folk_id": tid2, "outcome": 0})
	var died: int = 0
	for i3 in range(k0, K.notes.size()):
		if str(K.notes[i3][0]).find(Story.name_of(tid2)) >= 0:
			died += 1
	K.expect(f, died <= 1, "a fatal incident toasts the death once (%d)" % died)
	K.teardown()
	return f
