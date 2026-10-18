class_name DisasterContent
extends RefCounted
## Runtime patches for task 06 (idempotent, called from the disaster hooks): interactions that need electricity get a
## `lacks_buff power_out` test so nothing electric works during an outage, and the insurance function is installed.

const POWERED := ["stove", "microwave_cart", "coffee_maker", "washing_machine", "tea_kettle", "ceiling_fan", "hot_tub", "stereo", "treadmill"]
const EXEMPT_TAGS := ["repair", "clean", "chore", "paperwork"]

static var _seen_size: int = -1

static func ensure() -> void:
	DisasterInsurance.ensure()
	var data = SimEnv.data()
	var inter: Dictionary = data.interactions()
	var objs: Dictionary = data.objects()
	if inter.is_empty() or objs.is_empty() or (inter.size() == _seen_size and bool((inter.get("watch_tv", {}) as Dictionary).get("_dis_patch", false))):
		return
	_seen_size = inter.size()
	var powered: Dictionary = {}
	for oid in objs:
		var od: Dictionary = objs[oid]
		if (od.get("tags", []) as Array).has("electronics") or POWERED.has(str(oid)):
			powered[str(oid)] = true
	var offered: Dictionary = {}                      # interaction id -> object ids that offer it
	for oid2 in objs:
		for iid in (objs[oid2] as Dictionary).get("interactions", []):
			if not offered.has(iid):
				offered[iid] = []
			(offered[iid] as Array).append(str(oid2))
	for iid2 in inter:
		var d: Dictionary = inter[iid2]
		if bool(d.get("_dis_patch", false)):
			continue
		d["_dis_patch"] = true
		var tags: Array = d.get("tags", [])
		var skip: bool = false
		for t in EXEMPT_TAGS:
			if tags.has(t):
				skip = true
		if skip:
			continue
		var who: Array = (d.get("objects", []) as Array).duplicate()      # the interaction's own list is authoritative
		if who.is_empty():
			who = (offered.get(iid2, []) as Array).duplicate()
		if who.is_empty():
			continue
		var all_powered: bool = true
		for o4 in who:
			if not powered.has(str(o4)):
				all_powered = false
		if all_powered:
			var tests: Array = d.get("tests", [])
			tests.append({"lacks_buff": "power_out"})
			d["tests"] = tests
