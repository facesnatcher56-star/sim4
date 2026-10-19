class_name Works
extends RefCounted
## Industrial careers (task 31): factory worker -> plant manager, warehouse and logistics, construction, mechanic, power and utility tech.
## Data: data/careers_works.json (careers, merged into the careers table by scripts/core/data.gd; `works` = numbers and texts; `content` = the
## station objects and work interactions of the lot). The lot is "works" (Ironbridge Works, data/lot_templates.json).
## Files: Works (this: lookups, content install, injury tier, layoff weight), WorksEvents (strikes, closures, state, save), WorksUnion,
## WorksPay (days off, overtime, dues, townie shifts), WorksUtility (repair crews), WorksCmd (player commands). Documented in docs/WORKS.md.

const MARK := "_works_content"

static func table() -> Dictionary:
	return SysUtil.table("careers_works")

static func cfg() -> Dictionary:
	return table().get("works", {})

static func texts() -> Dictionary:
	return cfg().get("texts", {})

## Station objects and work interactions (idempotent); called from NeighborhoodContent.install so lots built by LotLoader can use them.
static func install() -> void:
	ContentMerge.install(table().get("content", {}), MARK, {"_sys_gate": true})

static func career_ids() -> Array:
	return (table().get("careers", {}) as Dictionary).keys()

static func is_works(cid: String) -> bool:
	return (table().get("careers", {}) as Dictionary).has(cid)

## "plant", "depot", "site", "garage", "grid" ("" for other careers).
static func sector_of(cid: String) -> String:
	return str(Careers.career_def(cid).get("sector", "")) if is_works(cid) else ""

static func sector_label(cid: String) -> String:
	return str((texts().get("sectors", {}) as Dictionary).get(sector_of(cid), "industrial"))

static func fill(key: String, vars: Dictionary) -> String:
	var s: String = str(texts().get(key, ""))
	for k in vars:
		s = s.replace("{%s}" % k, str(vars[k]))
	return s

## How dangerous the work is: the higher of the accident table (data/incidents/05_accidents.json physical_careers) and the career's own `injury_tier`.
## 1 = physical, 2 = dangerous (doubles the hourly dice), 3 = dangerous and hazardous (construction).
static func injury_tier(cid: String) -> int:
	var base: int = int(((IncidentDefs.cfg("accidents", {}) as Dictionary).get("physical_careers", {}) as Dictionary).get(cid, 0))
	return maxi(base, int(Careers.career_def(cid).get("injury_tier", 0)))

## Weight of the layoff dice for a career (1.0 = average): heavy industry feels a slump first, the grid and the garage are steadier.
static func layoff_mult(cid: String) -> float:
	return float(Careers.career_def(cid).get("layoff_mult", 1.0))

## Residents and townies who hold the career right now.
static func headcount(cid: String) -> int:
	var n: int = 0
	for fid in Careers.jobs:
		if str(Careers.jobs[fid]["career"]) == cid:
			n += 1
	for t in Story.alive_townies():
		if str(t.get("career", "")) == cid:
			n += 1
	return n
