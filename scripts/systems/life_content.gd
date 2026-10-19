class_name LifeContent
extends RefCounted
## Runtime content of task 14 (idempotent): data/content_life.json merged by ContentMerge. SysContent.install_all() calls it.

static func install() -> void:
	ContentMerge.install(SimEnv.data().get_table("content_life"))
