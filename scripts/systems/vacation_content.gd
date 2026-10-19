class_name VacationContent
extends RefCounted
## Installs the "content" block of data/vacation.json (holiday objects, interactions, buffs) into the shared tables with ContentMerge, and the
## "norovirus" illness kind into the Health config (data files cannot add one: incident config merges are shallow). Idempotent.
## SysContent.install() calls it before its tag patches (stage gates, severe-weather tests); SysContent.install_all() calls it again (no-op).

const NORO := {"buff": "norovirus", "hours": 30, "contagious": false, "exposed_buff": "exposed_noro", "immune_buff": "immune_noro", "immune_hours": 48}

static func install() -> void:
	var cfg: Dictionary = SysUtil.table("vacation").get("content", {})
	if not cfg.is_empty():
		ContentMerge.install(cfg)
	var kinds: Dictionary = HealthIllness.kinds()
	if not kinds.is_empty() and not kinds.has("norovirus"):
		kinds["norovirus"] = NORO.duplicate()