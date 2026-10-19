class_name PregnancyContent
extends RefCounted
## Runtime content of task 18 (idempotent): data/content_pregnancy.json merged by ContentMerge (interactions, buffs) and the cravings of
## pregnancy as WHIMS (Goals): while expecting, now and then a small want to eat something. Call from SysContent.install_all().

const WHIMS := {
	"craving_snack": {"label": "Crave a snack", "when": [{"pregnant": true}], "objective": {"type": "interaction", "ids": ["grab_snack"]}, "points": 15, "weight": 2.0, "expire_hours": 8},
	"craving_meal": {"label": "Crave a proper meal", "when": [{"pregnant": true}], "objective": {"type": "interaction", "ids": ["eat_meal"]}, "points": 15, "weight": 2.0, "expire_hours": 8},
	"craving_sweet": {"label": "Crave something sweet", "when": [{"pregnant": true}, {"stat_below": ["hunger", 70]}], "objective": {"type": "interaction", "ids": ["grab_snack", "mix_drink"]}, "points": 15, "weight": 1.0, "expire_hours": 8},
}

static func install() -> void:
	var data = SimEnv.data()
	if data.interactions().is_empty():
		return
	ContentMerge.install(data.get_table("content_pregnancy"))
	var whims: Dictionary = Goals.cfg().get("whims", {})
	for k in WHIMS:
		if not whims.has(k):
			whims[k] = (WHIMS[k] as Dictionary).duplicate(true)
