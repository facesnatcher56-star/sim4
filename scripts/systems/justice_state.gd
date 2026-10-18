class_name JusticeState
extends RefCounted
## All state of the crime and justice track (tasks 04 / 09 / 09b) in one place, plus the data accessor and the save round trip.
## Data: data/justice.json (table "justice"). The CASE RECORD lives in `cases` (see CaseStore for the fields); everything else is
## small bookkeeping: criminal records, inmates, grudges, queued events, the whereabouts log, serial-killer state, civil cases.
## Own seeded rng (saved) so the crime story is reproducible and independent of every other system's dice.

const DEFAULT_SEED := 40404
const INT_FIELDS := ["id", "day", "minute", "culprit", "victim", "hid", "disc_day", "reporter", "accused", "serial", "reopened", "last_work_day",
	"vhid", "arrest_day", "trial_day", "closed_day", "lawyer", "bail", "stolen_coins", "loot_value"]
const INT_ARRAYS := ["witnesses", "suspect_ids"]

static var rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var cases: Dictionary = {}         # case id -> case record (JSON safe)
static var next_case: int = 1
static var records: Dictionary = {}       # person id -> [{day, charge, case, result}]
static var inmates: Dictionary = {}       # person id -> {case, kind: jail|prison, since, until, behaviour, parole_day}
static var grudges: Dictionary = {}       # "a>b" -> {rage, since, warned, vow}
static var pending: Array = []            # queued events [{kind, due_min, ...}]
static var whereabouts: Dictionary = {}   # person id -> Array of 72 location strings (ring by absolute hour)
static var counters: Dictionary = {}      # crime kind -> count, "exposure_hh" household-years, ...
static var serial: Dictionary = {}        # {pid, victims:[], active, caught, start_day, ...}
static var civil: Array = []              # civil cases
static var probation: Dictionary = {}     # person id -> day it ends
static var service: Dictionary = {}       # person id -> {days_left, last_day}
static var uneasy_until: int = -1         # the town is jumpy until this day
static var fresh_start: Dictionary = {}   # person id -> day the release goal began
static var lawyers: Dictionary = {}       # person id -> {skill, fee}
static var year_log: Array = []           # [{day, kind, solved}] for crime rate
static var blackmail: Array = []          # blackmail demands [{id, blackmailer, victim, secret, amount, every, state, paid, next_day}]
static var revenge: Array = []            # revenge chains [{id, avenger, target, case, level, since}]
static var relief: Dictionary = {}        # person id -> {amount, until}: a loan, charity or family help that lowers the pressure for a while
static var watch_until: int = -1          # neighbourhood watch active until this day
static var rate_now: float = 0.0          # town crime rate 0..100
static var rate_hist: Array = []          # [{day, rate}] one entry per season check
static var enabled: bool = true

static func cfg() -> Dictionary:
	return SysUtil.table("justice")

static func sect(name: String) -> Dictionary:
	return cfg().get(name, {})

static func reset() -> void:
	cases.clear()
	next_case = 1
	records.clear()
	inmates.clear()
	grudges.clear()
	pending.clear()
	whereabouts.clear()
	counters.clear()
	serial = {}
	civil.clear()
	probation.clear()
	service.clear()
	uneasy_until = -1
	fresh_start.clear()
	lawyers.clear()
	year_log.clear()
	blackmail.clear()
	revenge.clear()
	relief.clear()
	watch_until = -1
	rate_now = 0.0
	rate_hist.clear()
	enabled = true
	seed_rng(DEFAULT_SEED)

static func seed_rng(s: int) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = s

static func chance(p: float) -> bool:
	return rng.randf() < p

static func count(kind: String, n: int = 1) -> void:
	counters[kind] = int(counters.get(kind, 0)) + n

static func counter(kind: String) -> int:
	return int(counters.get(kind, 0))

static func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[rng.randi_range(0, arr.size() - 1)]

## Weighted pick of an index; weights below 0 count as 0. Returns -1 when all are 0.
static func pick_index(weights: Array) -> int:
	var total: float = 0.0
	for w in weights:
		total += maxf(float(w), 0.0)
	if total <= 0.0:
		return -1
	var roll: float = rng.randf() * total
	for i in weights.size():
		roll -= maxf(float(weights[i]), 0.0)
		if roll <= 0.0:
			return i
	return weights.size() - 1

static func queue(ev: Dictionary) -> void:
	pending.append(ev)

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"rng_seed": rng.seed, "rng_state": str(rng.state), "cases": SysUtil.str_keys(cases).duplicate(true), "next_case": next_case,
		"records": SysUtil.str_keys(records).duplicate(true), "inmates": SysUtil.str_keys(inmates).duplicate(true), "grudges": grudges.duplicate(true),
		"pending": pending.duplicate(true), "whereabouts": SysUtil.str_keys(whereabouts).duplicate(true), "counters": counters.duplicate(true),
		"serial": serial.duplicate(true), "civil": civil.duplicate(true), "probation": SysUtil.str_keys(probation), "service": SysUtil.str_keys(service).duplicate(true),
		"uneasy_until": uneasy_until, "fresh_start": SysUtil.str_keys(fresh_start), "lawyers": SysUtil.str_keys(lawyers).duplicate(true),
		"year_log": year_log.duplicate(true), "blackmail": blackmail.duplicate(true), "revenge": revenge.duplicate(true),
		"relief": SysUtil.str_keys(relief).duplicate(true), "watch_until": watch_until, "rate_now": rate_now, "rate_hist": rate_hist.duplicate(true)}

static func fix_case(c: Dictionary) -> void:
	SysUtil.ints_in(c, INT_FIELDS)
	for k in INT_ARRAYS:
		if c.has(k):
			c[k] = SysUtil.to_ints(c[k])

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	rng.seed = int(d.get("rng_seed", DEFAULT_SEED))
	rng.state = int(str(d.get("rng_state", rng.state)))
	next_case = int(d.get("next_case", 1))
	for k in (d.get("cases", {}) as Dictionary):
		var c: Dictionary = (d["cases"][k] as Dictionary).duplicate(true)
		fix_case(c)
		cases[int(str(k))] = c
	records = SysUtil.int_keys((d.get("records", {}) as Dictionary).duplicate(true))
	inmates = SysUtil.int_keys((d.get("inmates", {}) as Dictionary).duplicate(true))
	for k2 in inmates:
		SysUtil.ints_in(inmates[k2], ["case", "since", "until", "parole_day"])
	grudges = (d.get("grudges", {}) as Dictionary).duplicate(true)
	pending = (d.get("pending", []) as Array).duplicate(true)
	for p in pending:
		SysUtil.ints_in(p, ["due_min", "case", "culprit", "victim", "pid"])
	whereabouts = SysUtil.int_keys((d.get("whereabouts", {}) as Dictionary).duplicate(true))
	counters = (d.get("counters", {}) as Dictionary).duplicate(true)
	for k3 in counters:
		if str(k3).begins_with("exposure"):
			counters[k3] = float(counters[k3])
		else:
			counters[k3] = int(counters[k3])
	serial = (d.get("serial", {}) as Dictionary).duplicate(true)
	if serial.has("pid"):
		serial["pid"] = int(serial["pid"])
		serial["victims"] = SysUtil.to_ints(serial.get("victims", []))
		serial["cases"] = SysUtil.to_ints(serial.get("cases", []))
	civil = (d.get("civil", []) as Array).duplicate(true)
	probation = SysUtil.int_keys(d.get("probation", {}))
	service = SysUtil.int_keys((d.get("service", {}) as Dictionary).duplicate(true))
	uneasy_until = int(d.get("uneasy_until", -1))
	fresh_start = SysUtil.int_keys(d.get("fresh_start", {}))
	lawyers = SysUtil.int_keys((d.get("lawyers", {}) as Dictionary).duplicate(true))
	year_log = (d.get("year_log", []) as Array).duplicate(true)
	blackmail = (d.get("blackmail", []) as Array).duplicate(true)
	for b in blackmail:
		SysUtil.ints_in(b, ["id", "blackmailer", "victim", "secret", "amount", "every", "paid", "next_day"])
	revenge = (d.get("revenge", []) as Array).duplicate(true)
	for r in revenge:
		SysUtil.ints_in(r, ["id", "avenger", "target", "case", "since"])
	relief = SysUtil.int_keys((d.get("relief", {}) as Dictionary).duplicate(true))
	watch_until = int(d.get("watch_until", -1))
	rate_now = float(d.get("rate_now", 0.0))
	rate_hist = (d.get("rate_hist", []) as Array).duplicate(true)
