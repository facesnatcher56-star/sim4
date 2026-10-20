class_name AgingStart
extends RefCounted
## Starting ages for Folk created without an explicit age: spread inside their life stage, with birthdays on different days of the
## 4-day year (so a household does not all turn a year older at the same midnight), and partners within a few years of each other.

static func phase(age_days: float) -> int:
	return posmod(int(floor(age_days)), maxi(int(Aging.days_per_year()), 1))

static func _used_phases() -> Array:
	var out: Array = []
	for rec in Aging.records.values():
		out.append(phase(float((rec as Dictionary).get("age_days", 0.0))))
	return out

static func default_age(f) -> float:
	var sd: Dictionary = Aging.stage_def(str(f.age_stage))
	var start: float = float(sd.get("from_day", 44))
	var idx: int = Aging.stage_index(str(f.age_stage))
	var nxt: float = start + 8.0
	if idx >= 0 and idx + 1 < Aging.stage_table().size():
		nxt = float(Aging.stage_table()[idx + 1]["from_day"])
	var span: float = minf(nxt - start, 96.0)          # a long stage (adult: 19 to 62 years) still starts people young inside it
	if span < 12.0:
		return start + span * 0.35
	var h: int = absi(hash("%d:%s" % [int(f.id), str(f.name)]))
	var u: float = 0.12 + 0.38 * float(h % 1000) / 1000.0
	var base: int = int(floor(start + span * u))
	var used: Array = _used_phases()
	for shift in 4:
		if not used.has(phase(float(base + shift))) and float(base + shift) < nxt - 1.0:
			return float(base + shift)
	return float(base)

## Put `mate` within three years of `first`, keeping its own birthday phase (so the two still differ).
static func settle_partner(first, mate) -> void:
	if not (Aging.records.has(int(first.id)) and Aging.records.has(int(mate.id))):
		return
	if str(first.age_stage) != "adult" or str(mate.age_stage) != "adult":
		return
	var fa: float = Aging.age_days(int(first.id))
	var r: int = posmod(phase(Aging.age_days(int(mate.id))) - phase(fa), 4)
	var opts: Array = []
	for d in range(-12, 13):
		if posmod(d, 4) == r:
			opts.append(d)
	var h: int = absi(hash("%d>%d" % [int(first.id), int(mate.id)]))
	var na: float = fa + float(opts[h % opts.size()])
	var lo: float = float(Aging.stage_def("adult").get("from_day", 44)) + 1.0
	var hi: float = float(Aging.stage_def("elder").get("from_day", 140)) - 2.0
	if na >= lo and na <= hi:
		Aging.set_age_days(mate, na)
