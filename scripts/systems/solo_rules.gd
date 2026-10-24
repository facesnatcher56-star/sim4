class_name SoloRules
extends RefCounted
## Small hooks of one-character play that other systems call (kept here so those files stay one-liners). Numbers: data/solo.json.

## Wages and the day labour pay for the pawn, by difficulty.
static func wage_mult(f) -> float:
	return float(SoloCfg.by_diff("start", "wage_mult")) if Pawn.is_pawn(f) else 1.0

## Missed rents before the eviction notice: the pawn's tenancy follows the difficulty, everybody else the housing table.
static func evict_after(p: Dictionary) -> int:
	if str(p.get("tenant_kind", "")) == "player" and SoloHome.active:
		return SoloRent.evict_after()
	return int(HousingRent.rc().get("evict_after_missed", 2))

## The landlord pays some of the fixed charges of a let place (data/solo.json start.landlord_pays: part -> share).
static func landlord_pays(hid: int, parts: Dictionary) -> void:
	if not SoloHome.active or SoloHome.homeless or Players.player_of(hid) <= 0:
		return
	var shares: Dictionary = (SoloCfg.sect("start") as Dictionary).get("landlord_pays", {})
	for k in shares:
		if parts.has(k):
			parts[k] = float(parts[k]) * (1.0 - float(shares[k]))
	# task 63: no home internet without a device that needs it (the mobile plan is the phone), and a studio's electricity sized to the studio
	var defs: Dictionary = UtilityHomes.defs_of(hid)
	if not (SoloCfg.sect("start").get("internet_devices", []) as Array).any(func(d): return not (defs.get(d, []) as Array).is_empty()):
		parts["internet"] = 0.0
	if SoloHome.rung == "starter" and parts.has("power"):
		parts["power"] = minf(float(parts["power"]), float(SoloCfg.by_diff("start", "studio_power_cap")))

## Named consequences fired from interaction data ({"solo_hook": name}).
static func hook(name: String, folk) -> void:
	match name:
		"rough_night":
			SoloShelter.rough_night(folk)
		"shelter_night":
			SoloShelter.shelter_night(folk)
		"day_labour":
			SoloShelter.day_labour_done(folk)
