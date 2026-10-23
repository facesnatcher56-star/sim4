class_name SoloTeach
extends RefCounted
## Task 61A: teach by doing. One short line the first time each thing matters, in the toast style, said once (SoloOpening.said):
## the first hunger, the first night with no bed, the first bill. (The first time the phone opens, the Jobs app is lit: LifeHubPhone.)
## Lines: data/solo.json "opening.teach".

static func cfg() -> Dictionary:
	return (SoloOpening.cfg().get("teach", {}) as Dictionary)

static func on_hour(h: int) -> void:
	if not SoloHome.active:
		return
	var f = SysUtil.folk(Pawn.of())
	if f == null or SysUtil.is_away(f):
		return
	var hid: int = int(f.household_id)
	var c: Dictionary = cfg()
	var hu: Dictionary = c.get("hunger", {})
	if f.get_stat_value("hunger") < float(hu.get("below", -10)) and SoloOpening.once("t_hunger"):
		var food: bool = Economy.objects_of(hid).any(func(o): return str(o.def_id) == "fridge" and float(WorldIface.state_get(o, "stock", 0.0)) > 0.0)
		SysUtil.notify(str(hu.get("line_food" if food else "line", "")).replace("{coins}", str(Economy.balance(hid))), "story")
	var nb: Dictionary = c.get("no_bed", {})
	if h >= int(nb.get("hour", 21)) and not SoloHome.homeless and not _has_bed(hid) and SoloOpening.once("t_no_bed"):
		SysUtil.notify(str(nb.get("line", "")), "story")
	if Economy.bills.any(func(b): return int(b["hid"]) == hid) and SoloOpening.once("t_bill"):
		SysUtil.notify(str((c.get("first_bill", {}) as Dictionary).get("line", "")), "story")

static func _has_bed(hid: int) -> bool:
	var beds: Array = ["bed", "single_bed", "bunk_bed", "sofa_bed", "cot"]
	return Economy.objects_of(hid).any(func(o): return beds.has(str(o.def_id)))
