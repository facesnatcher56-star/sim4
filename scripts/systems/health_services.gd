class_name HealthServices
extends RefCounted
## The handlers (PlaceHandlers) of the health places: the clinic (checkup, treat, vaccinate), the dentist (dental_clean, dental_fix), the counselling
## centre (counsel) and the pharmacy counter (prescription). check() refuses before money is taken, finish() runs when the visit ends.

static func check(handler: String, f, _pid: String, _sid: String, svc: Dictionary) -> String:
	var id: int = int(f.id)
	var r: Dictionary = HealthLife.rec(id)
	match handler:
		"checkup":
			return "%s had a check-up only a few days ago." % f.name if SysUtil.day() - int(r["checkup_day"]) < 3 and int(r["checkup_day"]) >= 0 else ""
		"treat":
			return "" if (Health.is_ill(f) or Health.is_injured(f) or Health.is_collapsed(f)) else "Nothing needs treating."
		"vaccinate":
			return "%s is already protected for %d more days." % [f.name, int(r["shot_until"]) - SysUtil.day() + 1] if int(r["shot_until"]) >= SysUtil.day() else ""
		"dental_clean":
			return "%s's teeth are spotless." % f.name if float(r["dental"]) >= float(HealthLife.cfg().get("dental", {}).get("clean_to", 95)) - 1.0 else ""
		"dental_fix":
			var tb: String = str(HealthLife.cfg().get("dental", {}).get("toothache_buff", "toothache"))
			return "" if (f.has_buff(tb) or float(r["dental"]) < float(HealthLife.cfg().get("dental", {}).get("toothache_below", 35))) else "No sore tooth to fix."
		"prescription":
			var cid: String = str(svc.get("args", {}).get("condition", ""))
			return "" if HealthCond.diagnosed(id, cid) else "%s has no prescription for that." % f.name
	return ""

static func finish(handler: String, f, pid: String, _sid: String, svc: Dictionary) -> Dictionary:
	var id: int = int(f.id)
	var r: Dictionary = HealthLife.rec(id)
	var dn: Dictionary = HealthLife.cfg().get("dental", {})
	match handler:
		"checkup":
			r["checkup_day"] = SysUtil.day()
			f.add_buff("checked_up")
			var found: Array = []
			for cid in (r["conds"] as Dictionary).keys():
				if HealthCond.diagnose(id, str(cid), false):
					found.append(str(HealthCond.def(str(cid)).get("label", cid)).to_lower())
			var who: String = PlaceStaff.who(pid, "doctor")
			var text: String = "%s had a check-up%s. %s, %s, %s." % [f.name, "" if who == "" else " with " + who, HealthLife.label("fitness", float(r["fitness"])),
				HealthLife.label("diet", float(r["diet"])).to_lower(), HealthLife.label("dental", float(r["dental"])).to_lower()]
			if not found.is_empty():
				text += " Found: %s. Medicine from the pharmacy counter keeps it under control." % ", ".join(found)
			elif float(r["fitness"]) < 40.0 or float(r["diet"]) < 40.0:
				text += " The doctor suggests more exercise and better food."
			HealthLife.count("checkup")
			return {"text": text}
		"treat":
			var treated: Array = Health.on_doctor(f)
			return {"text": "The doctor treated %s (%s)." % [f.name, ", ".join(treated)] if not treated.is_empty() else ""}
		"vaccinate":
			r["shot_until"] = SysUtil.day() + int(HealthLife.cfg().get("flu_shot", {}).get("days", 28)) - 1
			return {"text": "%s had a flu shot and is protected for a good while." % f.name}
		"dental_clean":
			r["dental"] = maxf(float(r["dental"]), float(dn.get("clean_to", 95)))
			f.remove_buff(str(dn.get("toothache_buff", "toothache")))
			return {"text": "%s's teeth are clean and bright." % f.name}
		"dental_fix":
			r["dental"] = maxf(float(r["dental"]), float(dn.get("fix_to", 80)))
			f.remove_buff(str(dn.get("toothache_buff", "toothache")))
			return {"text": "The dentist fixed %s's sore tooth." % f.name}
		"counsel":
			Counselling.session(f)
			return {}
		"prescription":
			var cid2: String = str(svc.get("args", {}).get("condition", ""))
			HealthCond.prescribe(id, cid2)
			return {"text": "%s picked up %s for %d days." % [f.name, str(HealthCond.def(cid2).get("medicine", "medicine")), HealthCond.doses(id, cid2)]}
	return {}
