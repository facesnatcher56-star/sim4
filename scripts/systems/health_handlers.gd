class_name HealthHandlers
extends RefCounted
## Incident handlers for data/incidents/02_needs_health.json (signature: func(ctx, args) -> Dictionary).

## args {kind, severity}: the person falls ill with that illness.
static func catch_illness(ctx: Dictionary, args: Dictionary) -> Dictionary:
	var f = ctx.get("folk", null)
	if f != null:
		Health.fall_ill(f, str(args.get("kind", "generic")), int(args.get("severity", 1)), str(args.get("reason", "")))
	return {}
