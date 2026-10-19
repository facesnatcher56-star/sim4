class_name UtilityContent
extends RefCounted
## Runtime patch (idempotent) of task 12.1: the interactions that need running water, a phone line or the internet get a `lacks_buff` test, so a dry tap or a
## dead line really stops them. The id lists are data (data/city.json utilities.needs_water / needs_signal / needs_online).

static func ensure() -> void:
	var inter: Dictionary = SimEnv.data().interactions()
	if inter.is_empty():
		return
	var u: Dictionary = Utilities.cfg()
	_gate(inter, u.get("needs_water", []), "no_water")
	_gate(inter, u.get("needs_signal", []), "no_signal")
	_gate(inter, u.get("needs_online", []), "offline")

static func _gate(inter: Dictionary, ids: Array, buff: String) -> void:
	for iid in ids:
		if not inter.has(iid):
			continue
		var d: Dictionary = inter[iid]
		var tests: Array = d.get("tests", [])
		var t := {"lacks_buff": buff}
		if not tests.has(t):
			tests.append(t)
		d["tests"] = tests
