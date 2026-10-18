class_name VacationContent
extends RefCounted
## Installs the "content" block of data/vacation.json (holiday objects, interactions, buffs) into the shared tables with ContentMerge.
## Idempotent. SysContent.install_all() calls it, so every game and test that installs the systems content gets the holiday things.

static func install() -> void:
	var cfg: Dictionary = SysUtil.table("vacation").get("content", {})
	if cfg.is_empty():
		return
	ContentMerge.install(cfg)
