extends RefCounted
## Test helper (no run()): a handler declared by script path in a test incident ("handlers" spec) and one registered as a Callable.

static var calls: Array = []

static func on_incident(ctx: Dictionary, args: Dictionary) -> Dictionary:
	calls.append({"incident": ctx.get("incident", ""), "statistical": bool(ctx.get("statistical", false)), "args": args.duplicate(true), "name": ctx["subject"].display_name()})
	return {"text": "%s was touched by the handler (%s)." % [ctx["subject"].display_name(), str(args.get("tag", ""))], "kind": "info"}
