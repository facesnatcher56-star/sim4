class_name StorytellerDistrict
extends RefCounted
## Districts for the storyteller: which kind of place a zone is, its label and distances between zones.

## data.districts: which kind (downtown, suburb, industrial, waterfront) a zone is. Unknown zones (a bigger map) cycle through the kinds by their index.
static func kind_of(zone: String) -> String:
	var d: Dictionary = Storyteller.cfg().get("districts", {})
	var zones: Dictionary = d.get("zones", {})
	if zones.has(zone):
		return str(zones[zone])
	var cyc: Array = d.get("cycle", [])
	var ids: Array = CityState.zone_ids()
	if cyc.is_empty():
		return ""
	return str(cyc[maxi(ids.find(zone), 0) % cyc.size()])

static func kind_def(zone: String) -> Dictionary:
	return (Storyteller.cfg().get("districts", {}).get("kinds", {}) as Dictionary).get(kind_of(zone), {})

static func label(zone: String) -> String:
	return CityState.zone_label(zone)

## 0 = same zone; otherwise how many zones apart (ring distance over data zone order, so a bigger map keeps working).
static func distance(a: String, b: String) -> int:
	var ids: Array = CityState.zone_ids()
	var ia: int = ids.find(a)
	var ib: int = ids.find(b)
	if ia < 0 or ib < 0 or ids.is_empty():
		return 0 if a == b else 9
	var d: int = absi(ia - ib)
	return mini(d, ids.size() - d)
