class_name TimedAttempt
extends RefCounted
## Task 53/54: an attempt takes the minutes its SkillCheck rolled (an expert in one, a novice in ten), shown as a timed action with its own label.
## The roll is made at the start; `done` is called with the result when the action finishes. Cancelling the action means giving up: nothing happens.
## Used by the doors and the cars.   TimedAttempt.start(f, act, label, ctx, done: Callable(result))

static var working: Dictionary = {}          # fid -> {r, done}

static func reset() -> void:
	working = {}

static func start(f, act: String, label: String, ctx: Dictionary, done: Callable) -> void:
	var r: Dictionary = SkillCheck.attempt(int(f.id), act, ctx)
	var ir: Interaction = Interaction.create("wait_here", f, -1, true)
	if ir == null:
		done.call(r)
		return
	ir.def = ir.def.duplicate(true)
	ir.def["duration_min"] = maxf(float(r["minutes"]), 1.0)
	ir.def["label"] = label
	ir.def.erase("thought")
	working[int(f.id)] = {"r": r, "done": done}
	f.cancel_current("attempt")
	f.clear_queue()
	f.enqueue(ir)

static func busy(fid: int) -> bool:
	return working.has(fid)

static func on_interaction_finished(folk_id: int, iid: String, success: bool) -> void:
	if iid != "wait_here" or not working.has(folk_id):
		return
	var w: Dictionary = working[folk_id]
	working.erase(folk_id)
	if success:
		(w["done"] as Callable).call(w["r"])
