class_name SoloCrews
extends RefCounted
## The crews of the rough district (R14.3) and its drive-by shootings. The crews themselves are the town's gangs (CrimeUnderGang: boss, ranks, wars,
## crackdowns); the district only changes their rates (data/crimeunder.json gang.*: founding x4, wars x5, recruiting x1.5). This class adds the
## DRIVE-BY: a car passes a crew-held block at night; only people outdoors on that block can be hit; no child is ever exposed; deaths only when
## "Mature life events" is on and "Gang violence" is above Low. Rates, hit chances, severities: data/solo.json "crime.drive_by". Not graphic: a toast
## and a chronicle line. State: the night a drive-by is due (saved with SoloHome).

static var due_abs: int = -1          # absolute game hour of the planned drive-by ((day - 1) * 24 + hour; hours past 24 are the next morning), -1 none
static var district_id: String = ""   # where

static func reset() -> void:
	due_abs = -1
	district_id = ""

static func cfg() -> Dictionary:
	return (SoloCfg.sect("crime") as Dictionary).get("drive_by", {})

static func at_war() -> bool:
	return not CrimeUnderGang.at_war().is_empty()

## Daily: roll whether a drive-by happens in a rough district tonight.
static func on_day(day: int) -> void:
	if not SoloHome.active or due_abs >= 0:
		return
	var vf: float = SoloDistricts.setting_factor()
	if vf <= 0.0:
		return
	var c: Dictionary = cfg()
	for d in SoloDistricts.districts():
		if SoloDistricts.roughness_of(str(d)) < float(SoloCfg.sect("pressure").get("min_roughness", 0.6)):
			continue
		var p: float = float(c.get("war_daily" if at_war() else "peace_daily", 0.006)) * vf * clampf(SoloDistricts.roughness_of(str(d)) / 0.85, 0.2, 1.5)
		if SysUtil.chance(p):
			var hrs: Array = c.get("hours", [20, 3])
			var span: int = (int(hrs[1]) + 24) - int(hrs[0])
			due_abs = (day - 1) * 24 + int(hrs[0]) + SysUtil.rng.randi_range(0, maxi(span - 1, 0))
			district_id = str(d)
			return

## Hourly: the planned hour has come.
static func on_hour(hour: int) -> void:
	if due_abs < 0 or not SoloHome.active:
		return
	if (SysUtil.day() - 1) * 24 + hour < due_abs:
		return
	var did: String = district_id
	due_abs = -1
	_drive_by(did)

static func _drive_by(did: String) -> void:
	var c: Dictionary = cfg()
	var label: String = SoloDistricts.label_of(did)
	var exposed: Array = []
	for f in SysUtil.residents():
		if str(f.age_stage) in ["baby", "toddler", "child"] or SysUtil.is_away(f) or Hospital.is_in(int(f.id)):
			continue
		if NeighborhoodLots.lot_at(f.tile) == "" and SoloDistricts.district_at_tile(f.tile) == did:
			exposed.append(f)
	var hit_names: Array = []
	var sev_w: Array = c.get("severity", [0.6, 0.28, 0.12])
	for f2 in exposed:
		if not SysUtil.chance(float(c.get("hit_chance", 0.08))):
			continue
		var roll: float = SysUtil.rng.randf()
		var sev: int = 1 if roll < float(sev_w[0]) else (2 if roll < float(sev_w[0]) + float(sev_w[1]) else 3)
		var deadly: bool = GameSettings.get_bool("mature_events") and SoloDistricts.setting_factor() > float((SoloCfg.sect("crime").get("violence_setting", {}) as Dictionary).get("low", 0.35)) \
			and SysUtil.chance(float(c.get("death_of_hit", 0.12)))
		hit_names.append(str(f2.name))
		if deadly:
			Aging.kill(int(f2.id), "gang_violence")
		else:
			Hospital.emergency(int(f2.id), sev, "gunshot wound")
	JusticeState.year_log.append({"day": SysUtil.day(), "kind": "gang_violence", "solved": false, "case": -1})
	var text: String = "Shots were fired from a passing car on a block of the %s. The police are on their way." % label
	if not hit_names.is_empty():
		text += " %s was hit." % ", ".join(hit_names)
	SysUtil.notify(text, "bad" if not hit_names.is_empty() else "warn")
	ChronicleHook.note("crime", "A drive-by shooting in the %s." % label, [], "town:0", 3, true)
	SysUtil.game_event("drive_by", {"district": did, "hit": hit_names.size()})
