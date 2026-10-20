class_name Scenario
extends RefCounted
## The new-game scenario + difficulty of the running game. Data: data/scenarios.json.
##
## State (static, saved in the "scenario" block of SaveLoad):
##   active_id   ""  = no scenario (loaded old save, --autostart)
##   difficulty  relaxed | normal | hard
##   done        goal id -> day completed      progress  goal id -> event count      finished  all goals done
## Hooks other systems read: Scenario.bill_multiplier() (Economy.compute_bill), Scenario.need_drain() (Folk.decay_mult).
## Goal checking lives in ScenarioGoals; the HUD checklist in ui/scenario_tracker.gd.

static var active_id: String = ""
static var difficulty: String = "normal"
static var done: Dictionary = {}
static var progress: Dictionary = {}
static var finished: bool = false

static func reset() -> void:
	active_id = ""
	difficulty = "normal"
	done = {}
	progress = {}
	finished = false

static func cfg() -> Dictionary:
	return SysUtil.table("scenarios")

# ------------------------------------------------------------------ definitions
static func scenarios() -> Array:
	return cfg().get("scenarios", [])

static func ids() -> Array:
	var out: Array = []
	for s in scenarios():
		out.append(str(s["id"]))
	return out

static func def(scenario_id: String) -> Dictionary:
	for s in scenarios():
		if str(s["id"]) == scenario_id:
			return s
	return {}

static func default_id() -> String:
	return str(cfg().get("default_scenario", "solo"))

static func difficulty_ids() -> Array:
	return ["relaxed", "normal", "hard"]

static func difficulty_def(diff_id: String) -> Dictionary:
	return (cfg().get("difficulties", {}) as Dictionary).get(diff_id, {})

static func default_difficulty() -> String:
	return str(cfg().get("default_difficulty", "normal"))

## Starting coins for a scenario at a difficulty (rounded to 50). `base` overrides the scenario's own number (Free Play funds option).
static func funds_for(scenario_id: String, diff_id: String, base: int = -1) -> int:
	var b: int = base if base >= 0 else int(def(scenario_id).get("funds", 5000))
	var m: float = float(difficulty_def(diff_id).get("funds_mult", 1.0))
	return int(round(float(b) * m / 50.0)) * 50

## One-line plain-language explanation of a difficulty, built from the numbers.
static func difficulty_text(diff_id: String) -> String:
	return str(difficulty_def(diff_id).get("desc", ""))

# ------------------------------------------------------------------ running state
static func begin(scenario_id: String, diff_id: String) -> void:
	reset()
	active_id = scenario_id
	difficulty = diff_id if not difficulty_def(diff_id).is_empty() else default_difficulty()
	ScenarioGoals.install()

static func active() -> bool:
	return active_id != ""

static func goals() -> Array:
	return def(active_id).get("goals", []) if active() else []

## Shown text of a checklist goal: goals with `label_no_fridge` / `hint_no_fridge` switch while the home has no fridge yet (empty starts).
static func goal_text(g: Dictionary) -> Dictionary:
	var label: String = str(g.get("label", ""))
	var hint: String = str(g.get("hint", ""))
	if g.has("label_no_fridge") and not _home_has_fridge():
		label = str(g["label_no_fridge"])
		hint = str(g.get("hint_no_fridge", hint))
	if g.has("hint_no_computer") and not home_has("computer"):
		hint = str(g["hint_no_computer"])
	return {"label": label, "hint": hint}

static func _home_has_fridge() -> bool:
	return home_has("fridge")

## Does the player's household own an object of this def? (empty starts have no computer / fridge until they are bought)
static func home_has(def_id: String) -> bool:
	for o in Economy.objects_of(Economy.primary_household()):
		if str(o.def_id) == def_id:
			return true
	return false

## Welcome tips of a scenario: entries listed in `tips_no_computer` ({index: text}) change while the home has no computer.
static func tips_text(sdef: Dictionary) -> Array:
	var tips: Array = (sdef.get("tips", []) as Array).duplicate()
	if home_has("computer"):
		return tips
	var alt: Dictionary = sdef.get("tips_no_computer", {})
	for k in alt:
		if int(k) < tips.size():
			tips[int(k)] = str(alt[k])
	return tips

static func has_goals() -> bool:
	return not goals().is_empty()

static func is_done(goal_id: String) -> bool:
	return done.has(goal_id)

static func done_count() -> int:
	var n := 0
	for g in goals():
		if is_done(str(g["id"])):
			n += 1
	return n

static func bill_multiplier() -> float:
	return float(difficulty_def(difficulty).get("bill_mult", 1.0))

static func need_drain() -> float:
	return float(difficulty_def(difficulty).get("need_mult", 1.0))

# ------------------------------------------------------------------ save
static func to_dict() -> Dictionary:
	return {"id": active_id, "difficulty": difficulty, "done": done.duplicate(), "progress": progress.duplicate(), "finished": finished}

static func from_dict(d: Dictionary) -> void:
	reset()
	if d.is_empty():
		return
	active_id = str(d.get("id", ""))
	difficulty = str(d.get("difficulty", "normal"))
	for k in (d.get("done", {}) as Dictionary):
		done[str(k)] = int(d["done"][k])
	for k2 in (d.get("progress", {}) as Dictionary):
		progress[str(k2)] = int(d["progress"][k2])
	finished = bool(d.get("finished", false))
	if active():
		ScenarioGoals.install()
