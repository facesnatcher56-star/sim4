class_name Circadian
extends RefCounted
## Every Folk has a preferred bedtime and wake time (data/circadian.json): by life stage, shifted by early bird / night owl and a
## per-person hash; a job pulls the wake time earlier. Sleep follows the clock: phases tell Cond ("circadian": phase) and Routine
## ("circadian": phase) whether it is bed time, the night, or day time for THIS Folk.
##   bed      the hour they like to go to bed        wake    the hour they get up
##   wind_down  [bed - 1h, bed)        bedtime  [bed - 1h, bed + 1.5h)       night  [bed + 1.5h, wake)
##   day      [wake, bed - 1h)         sleep_ok  the sleep_bed test: bedtime/night and not full of energy, or utterly worn out
##   alarm    a job's wake-up call: [job wake, job start + 1h)

static func cfg() -> Dictionary:
	return SysUtil.table("circadian")

static func _h(f, salt: String) -> float:
	return float(absi(hash("%d:%s:%s" % [int(f.id), str(f.name), salt])) % 1000) / 1000.0

## [bed, wake] in hours (bed may be >= 24 meaning after midnight; use fposmod).
static func schedule(f) -> Array:
	var c: Dictionary = cfg()
	var st: Dictionary = (c.get("stages", {}) as Dictionary).get(str(f.age_stage), (c.get("stages", {}) as Dictionary).get("adult", {}))
	if st.is_empty():
		return [22.5, 7.0]
	var bed_r: Array = st.get("bed", [22.0, 23.5])
	var len_r: Array = st.get("sleep_h", [7.0, 8.5])
	var bed: float = lerpf(float(bed_r[0]), float(bed_r[1]), _h(f, "bed"))
	var slen: float = lerpf(float(len_r[0]), float(len_r[1]), _h(f, "len"))
	for t in (c.get("trait_shift_h", {}) as Dictionary):
		if f.has_trait(str(t)):
			bed += float(c["trait_shift_h"][t])
	var wake: float = bed + slen
	if f.has_job():
		var ws: float = float(f.work_start)
		var night_shift: bool = ws >= 19.0 or ws < 5.0
		if night_shift:
			# sleeps through the day after the shift
			bed = fposmod(float(f.work_end) + 1.0, 24.0) if f.work_end >= 0.0 else fposmod(ws + 9.0, 24.0)
			wake = bed + slen
		else:
			var latest: float = ws - float(c.get("work_wake_before_h", 1.75))
			var w24: float = fposmod(wake, 24.0)
			if w24 > latest and w24 < ws + 6.0:
				wake = bed + (fposmod(latest - bed, 24.0))
	elif Careers.school.has(int(f.id)):        # school pulls the wake time earlier too
		var ss: float = float(Careers.cfg().get("school", {}).get("start", 9.0))
		var latest_s: float = ss - float(c.get("work_wake_before_h", 1.75))
		var w24s: float = fposmod(wake, 24.0)
		if w24s > latest_s and w24s < ss + 6.0:
			wake = bed + fposmod(latest_s - bed, 24.0)
	return [fposmod(bed, 24.0), fposmod(wake, 24.0)]

static func _in(h: float, lo: float, hi: float) -> bool:
	lo = fposmod(lo, 24.0)
	hi = fposmod(hi, 24.0)
	if is_equal_approx(lo, hi):
		return false
	if lo < hi:
		return h >= lo and h < hi
	return h >= lo or h < hi

## When a party (an invite away from home) should be over for this person, in hours (24.5 = 00:30): children and elders earlier, night
## owls and social butterflies a little later (data/circadian.json "party_end").
static func party_end_hour(f) -> float:
	var pe: Dictionary = cfg().get("party_end", {})
	var e: float = float(pe.get(str(f.age_stage), pe.get("default", 24.5)))
	for t in (pe.get("late_traits", {}) as Dictionary):
		if f.has_trait(str(t)):
			e += float(pe["late_traits"][t])
	return e

## Minutes from now until the party should be over for this person (daytime: no limit; 0 when it is already too late to go).
static func party_minutes_left(f) -> int:
	var h: float = SimEnv.hour_f()
	if h >= 6.0 and h < 9.0:
		return 0                  # too early to go anywhere
	if h >= 9.0 and h < 18.0:
		return 24 * 60
	var late: float = h + 24.0 if h < 6.0 else h
	return maxi(int((party_end_hour(f) - late) * 60.0), 0)

## Guests leave (parties end) between 00:30 and 06:00.
static func guests_curfew() -> bool:
	var h: float = SimEnv.hour_f()
	return h >= float(cfg().get("curfew_from", 1.5)) and h < float(cfg().get("curfew_until", 6.0))

static func in_phase(f, phase: String) -> bool:
	if str(f.age_stage) in ["baby", "toddler"]:
		return phase == "sleep_ok"
	var sc: Array = schedule(f)
	var bed: float = sc[0]
	var wake: float = sc[1]
	var c: Dictionary = cfg()
	var h: float = SimEnv.hour_f()
	var wd: float = float(c.get("wind_down_before_h", 1.0))
	var after: float = float(c.get("bed_window_after_h", 1.5))
	match phase:
		"wind_down":
			return _in(h, bed - wd, bed)
		"bedtime":
			return _in(h, bed - wd, bed + after)
		"night":
			return _in(h, bed + after, wake)
		"day":
			return _in(h, wake, bed - wd)
		"sleep_ok":
			var e: float = f.get_stat_value("energy")
			if e < float(c.get("sleepy_anywhere_energy", 12)):
				return true
			return e < float(c.get("bed_ok_energy", 92)) and _in(h, bed - wd, wake)
		"alarm":
			var ws: float = float(f.work_start)
			if not f.has_job():
				if not Careers.school.has(int(f.id)):
					return false
				ws = float(Careers.cfg().get("school", {}).get("start", 9.0))
			return _in(h, wake, ws + 1.0) and _in(h, ws - 4.0, ws + 1.0)
	return false
