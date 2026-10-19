class_name PregnancyLoss
extends RefCounted
## Pregnancy loss and termination (task 18 part 4). Filled in by the next commit; this keeps the hooks in Pregnancy valid.

static func reset() -> void:
	pass

static func on_day(_id: int, _r: Dictionary) -> void:
	pass

## Statistical loss for a pregnant townie (filled in with the loss rates). Returns true when the pregnancy ended.
static func townie_day(_t: Dictionary, _pr: Dictionary) -> bool:
	return false

static func to_dict() -> Dictionary:
	return {}

static func from_dict(_d: Dictionary) -> void:
	pass
