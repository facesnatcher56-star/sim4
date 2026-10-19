class_name SuccessionNobody
extends RefCounted
## "Nobody left" (task 15): the head died and the house is empty (or only far relatives remain). The player is told in plain words (a toast and a banner
##   at the top of the screen that does not block) and can choose who to play: a relative (moves into the family home) | someone from town (a townie
##   moves in) | a new family (the town and its history stay). Meanwhile the town runs on autopilot and the household is marked `pending` in the Players table.
## Every morning the player is reminded; with the setting "Pick for me after 2 days" on (default) the choice is made automatically after AUTO_DAYS days
##   WITH OR WITHOUT a UI, so no empty household is simulated for long. With it off the reminders and the banner stay until the player chooses.
## Choices: "relative:<id>", "townie:<id>", "town" (shows the town list), "new", "later". Who autopilot picks: SuccessionPick.
const AUTO_DAYS := 2
const MAX_RELATIVES := 4
const MAX_TOWNIES := 6

static var auto_pick: bool = true         # setting "Pick for me after 2 days" (SettingsApply); off = keep reminding, never decide
static var _asking: Dictionary = {}       # player id -> true while a prompt is on screen

static func reset() -> void:
	_asking.clear()

static func begin(pid: int, hid: int, late_name: String, line: Array) -> void:
	Succession._ensure_entry(pid)
	Players.set_field(pid, "pending", true)
	Players.set_field(pid, "late", late_name)
	Players.set_field(pid, "since", SysUtil.day())
	SysUtil.notify(SuccessionText.nobody_title(late_name), "death")
	SysUtil.game_event("household_empty", {"player_id": pid, "household_id": hid, "days_left": days_left(pid, SysUtil.day())})

## Days until someone is picked for the player (0 = tomorrow morning at the latest), or -1 when "pick for me" is off.
static func days_left(pid: int, day: int) -> int:
	if not auto_pick:
		return -1
	return maxi(0, AUTO_DAYS - (day - int(Players.field(pid, "since", day))))

# ------------------------------------------------------------------ prompts
static func relatives(pid: int) -> Array:
	var hid: int = Players.household_of(pid)
	return HeirLine.candidates(int(Players.field(pid, "gone", -1)), hid, pid)

static func options(pid: int) -> Array:
	var out: Array = []
	var rel: Array = relatives(pid)
	for i in mini(rel.size(), MAX_RELATIVES):
		out.append({"id": "relative:%d" % int(rel[i]["id"]), "label": "Play " + str(rel[i]["label"])})
	out.append({"id": "town", "label": "Pick someone from town"})
	out.append({"id": "new", "label": "Start a new family"})
	out.append({"id": "later", "label": "Decide later"})
	return out

static func town_options() -> Array:
	var out: Array = []
	for t in townies():
		if out.size() >= MAX_TOWNIES:
			break
		var job: String = "works as a %s" % str(t["career"]).replace("_", " ") if str(t["career"]) != "" else "looking for work"
		out.append({"id": "townie:%d" % int(t["id"]), "label": "Play %s (%s, %s)" % [t["name"], Story.stage_of(t), job]})
	out.append({"id": "back", "label": "Back"})
	return out

## Grown townies who could take over the home: adults first (youngest first), elders last, steady order.
static func townies() -> Array:
	var out: Array = []
	for t in Story.alive_townies():
		if Story.stage_of(t) in ["adult", "elder"]:
			out.append(t)
	var order: Array = HeirLine.grown_first(out.map(func(t): return int(t["id"])))
	return order.map(func(id): return Story.townies[id])

static func prompt(pid: int, town_list: bool = false) -> void:
	if not JusticePlayer.ask_fn.is_valid() or bool(_asking.get(pid, false)) or not Succession.is_pending(pid):
		return
	_asking[pid] = true
	var late: String = str(Players.field(pid, "late", ""))
	var opts: Array = town_options() if town_list else options(pid)
	var title: String = "Who do you play now?" if town_list else SuccessionText.nobody_title(late)
	var text: String = "Pick one of the grown-ups in town to move into the family home." if town_list else SuccessionText.nobody_body(not relatives(pid).is_empty())
	JusticePlayer.ask_fn.call(-1, title, text, opts, func(choice):
		_asking.erase(pid)
		choose(pid, str(choice)), "later")

# ------------------------------------------------------------------ choosing
## Returns {ok, msg}. "town" / "back" / "later" re-open or close the prompt and change nothing.
static func choose(pid: int, choice: String, household: Dictionary = {}) -> Dictionary:
	if not Succession.is_pending(pid):
		return {"ok": false, "msg": "Your household has someone to play already."}
	var hid: int = Players.household_of(pid)
	var late: String = str(Players.field(pid, "late", ""))
	match choice.get_slice(":", 0):
		"later":
			return {"ok": true, "msg": "The town carries on. You can decide tomorrow."}
		"town", "back":
			prompt(pid, choice == "town")
			return {"ok": true, "msg": ""}
		"relative", "townie":
			var id: int = int(choice.get_slice(":", 1))
			if not HeirLine.eligible(id, hid, pid) or SysUtil.folk(id) != null and int(SysUtil.folk(id).household_id) == hid:
				return {"ok": false, "msg": "They cannot move in."}
			if choice.begins_with("townie") and not Story.stage_of(Story.townies.get(id, {"age_days": 0.0})) in ["adult", "elder"]:
				return {"ok": false, "msg": "Only grown-ups can head a household."}
			var ok: bool = SuccessionTake.take(pid, hid, {"id": id, "kind": choice.get_slice(":", 0), "in_household": false}, late)
			return {"ok": ok, "msg": "" if ok else "They could not move in."}
		"new":
			return new_family(pid, household)
	return {"ok": false, "msg": "That choice is not available."}

## A new family moves into the old home (the town, its people and its history stay). `household` = a HouseholdSetup dict, or {} for a random single adult.
static func new_family(pid: int, household: Dictionary = {}) -> Dictionary:
	var hid: int = Players.household_of(pid)
	var h: Dictionary = household
	if h.is_empty() or HouseholdSetup.validate(h) != "":
		h = HouseholdSetup.make_household(Scenario.default_id(), SysUtil.rng)
	var folk: Array = HouseholdSetup.create_folk(h)
	var tiles: Array = HouseholdSetup.spawn_tiles(folk.size(), [StoryVisits.entrance()])
	for i in folk.size():
		folk[i].household_id = hid
		SysUtil.world_add_folk(folk[i], tiles[i])
	Aging.ensure_all()
	Genetics.ensure_all()
	Goals.ensure_all()
	HouseholdSetup.apply(h, folk)
	Succession.set_head(pid, int(folk[0].id))
	Players.set_field(pid, "pending", false)
	SuccessionTake._announce(pid, int(folk[0].id), SuccessionText.new_family(str(folk[0].name)))
	return {"ok": true, "msg": "", "folk_id": int(folk[0].id)}

# ------------------------------------------------------------------ the day row
## Every morning while pending: pick for the player once AUTO_DAYS passed (setting on), else a toast + the banner event. Never depends on a UI.
static func on_day(pid: int, day: int) -> void:
	var left: int = days_left(pid, day)
	if auto_pick and left <= 0:
		autopilot(pid)
		return
	SysUtil.notify(SuccessionText.nobody_reminder(left), "death")
	SysUtil.game_event("household_empty", {"player_id": pid, "household_id": Players.household_of(pid), "days_left": left})

## Nobody chose: the first person SuccessionPick lists who can move in, else a new family (which always works).
static func autopilot(pid: int) -> Dictionary:
	for c in SuccessionPick.order(pid):
		var r: Dictionary = choose(pid, "%s:%d" % [str(c["pick"]), int(c["id"])])
		if bool(r["ok"]) and not Succession.is_pending(pid):
			return r
	return choose(pid, "new")
