class_name WeatherContent
extends RefCounted
## Runtime content injected into the shared Data tables by the weather / holiday layer (idempotent, like SysContent):
##  * buffs (data/weather.json "buffs" + data/holidays.json "buffs"): cold, hot, soaked, sunburn, fresh_air, the hidden
##    wx_* weather markers, holiday_today, festive_* ...
##  * interactions (data/weather.json "interactions"): sunbathe, rain_dance, build_snowfolk, give_holiday_gift
##    (also listed on garden_plot / fishing_spot / grill so the pie menu and autonomy find them)
##  * Goals whims: weather whims (weather.json "whims") + one whim per holiday
##  * patch: every interaction tagged `outdoor` gets a `lacks_buff wx_severe` test (nobody gardens in a thunderstorm).
## Cond has no weather keys, so the weather is exposed through marker buffs (see Weather).

static func install() -> void:
	var data = SimEnv.data()
	var inter: Dictionary = data.interactions()
	var buffs: Dictionary = data.buffs()
	if inter.is_empty() or buffs.is_empty():
		return
	if buffs.has("wx_clear") and inter.has("sunbathe"):
		_ensure_world_defs()
		return
	SysContent.install()
	var wc: Dictionary = SysUtil.table("weather")
	var hc: Dictionary = SysUtil.table("holidays")
	for src in [wc.get("buffs", {}), hc.get("buffs", {})]:
		for id in (src as Dictionary):
			if not buffs.has(id):
				buffs[id] = (src[id] as Dictionary).duplicate(true)
	_add_interactions(inter, wc.get("interactions", {}))
	_patch_outdoor(inter, wc.get("effects", {}).get("outdoor_patch", {}))
	_add_whims(wc, hc)
	_ensure_world_defs()

static func _add_interactions(inter: Dictionary, defs: Dictionary) -> void:
	for id in defs:
		if inter.has(id):
			continue
		var d: Dictionary = (defs[id] as Dictionary).duplicate(true)
		if str(d.get("target", "object")) == "folk":
			var tt: Array = d.get("target_tests", [])
			tt.append({"lacks_buff": "away"})
			d["target_tests"] = tt
		inter[id] = d
	SysContent._patch_stage_gates(inter)    # idempotent: only touches interactions that have no gate mark yet

static func _patch_outdoor(inter: Dictionary, p: Dictionary) -> void:
	var tag: String = str(p.get("tag", "outdoor"))
	var marker: String = str(p.get("block_marker", "wx_severe"))
	var mark: String = str(p.get("mark", "_wx_patch"))
	for iid in inter:
		var d: Dictionary = inter[iid]
		if bool(d.get(mark, false)):
			continue
		d[mark] = true
		if (d.get("tags", []) as Array).has(tag):
			var tests: Array = d.get("tests", [])
			tests.append({"lacks_buff": marker})
			for extra in p.get("also_block", []):      # e.g. "cold": nobody starts a garden chore or a fishing trip while already chilled through
				tests.append({"lacks_buff": str(extra)})
			d["tests"] = tests

static func _add_whims(wc: Dictionary, hc: Dictionary) -> void:
	var goals: Dictionary = SysUtil.table("goals")
	if goals.is_empty():
		return
	if not goals.has("whims"):
		goals["whims"] = {}
	var whims: Dictionary = goals["whims"]
	var ww: Dictionary = wc.get("whims", {})
	for id in ww:
		if not whims.has(id):
			whims[id] = (ww[id] as Dictionary).duplicate(true)
	var hs: Dictionary = hc.get("holidays", {})
	for hid in hs:
		var h: Dictionary = hs[hid]
		var wid: String = "hol_" + str(hid)
		if whims.has(wid) or not h.has("whim"):
			continue
		var w: Dictionary = (h["whim"] as Dictionary).duplicate(true)
		w["when"] = [{"has_buff": str(h.get("buff", "holiday_today"))}]
		w["points"] = int(w.get("points", 35))
		w["weight"] = float(w.get("weight", 4.0))
		w["expire_hours"] = float(w.get("expire_hours", 14))
		whims[wid] = w

## Make the outdoor objects list the new interactions (also in the World's def copy).
static func _ensure_world_defs() -> void:
	var odefs: Dictionary = SimEnv.data().objects()
	_add_obj(odefs)
	var w = WorldIface.world()
	if w != null and "defs" in w and w.defs is Dictionary:
		_add_obj(w.defs)

static func _add_obj(defs: Dictionary) -> void:
	var idefs: Dictionary = SimEnv.data().interactions()
	for iid in ["sunbathe", "rain_dance", "build_snowfolk"]:
		var objs: Array = (idefs.get(iid, {}) as Dictionary).get("objects", [])
		for oid in objs:
			if not defs.has(oid):
				continue
			var od: Dictionary = defs[oid]
			var list: Array = od.get("interactions", [])
			if not list.has(iid):
				list.append(iid)
				od["interactions"] = list
