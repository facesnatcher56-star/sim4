class_name CrimeForce
extends RefCounted
## Handlers behind the F9 / Incidents.force buttons for assault and murder (their natural rates come from motive, not dice).
## The selected person becomes the culprit; the target is whoever they are angriest at (else anyone they know, else anyone).

static func _target_for(pid: int) -> int:
	var best: int = -1
	var best_a: float = -1.0
	var pool: Array = RelationshipBits.all_known(pid)
	if pool.is_empty():
		pool = CrimePerson.everyone()
	for o in pool:
		var other: int = int(o)
		if other == pid or not CrimePerson.alive(other):
			continue
		var a: float = CrimeMurder.anger(pid, other)
		if a > best_a:
			best_a = a
			best = other
	return best

static func assault(ctx: Dictionary, _args: Dictionary) -> Dictionary:
	var pid: int = int(ctx["subject"].id)
	var t: int = _target_for(pid)
	if t >= 0:
		CrimeAssault.fight(pid, t)
	return {"text": ""}

static func murder(ctx: Dictionary, _args: Dictionary) -> Dictionary:
	var pid: int = int(ctx["subject"].id)
	var t: int = _target_for(pid)
	if t >= 0 and CrimePerson.alive(pid):
		CrimeMurder.execute(pid, t)
	return {"text": ""}
