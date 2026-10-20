class_name DynSocial
extends RefCounted
## Task 32c: household initiative. Once an hour, per household with people at home: a family dinner, a game night, playtime for the kids (and a parent
## who joins in), and a resident who invites a friend over. Everything is a buff whose autonomy_mult pulls the people toward the shared thing (they
## still sort their own needs first) or a real visit through StoryVisits. Data: data/dynamic_life.json `social`. Kids never get adult content: the
## interactions are stage-gated by their tags and the guests an invitation may bring are limited by stage (RomanceRules and Straying are untouched).

const KIDS := ["toddler", "child"]

static func on_hour(ppl: Array, abs_hour: int) -> void:
	var sc: Dictionary = DynLife.cfg().get("social", {})
	if not bool(sc.get("enabled", true)):
		return
	var homes: Dictionary = {}                    # household id -> awake people at home (ACTIVE / NEAR)
	for f in ppl:
		if DynLife.awake(f) and DynLife.at_home(f) and Tiers.of(f) <= Tiers.NEAR:
			var l: Array = homes.get(int(f.household_id), [])
			l.append(f)
			homes[int(f.household_id)] = l
	var h: float = SysUtil.hour_f()
	var weekend := DynLife.is_weekend()
	for hid in homes:
		var members: Array = homes[hid]
		_together(members, hid, abs_hour, h, weekend, sc.get("family_dinner", {}), "family_dinner", 101, ["child", "teen", "adult", "elder"])
		_together(members, hid, abs_hour, h, weekend, sc.get("game_night", {}), "game_night", 102, ["child", "teen", "adult", "elder"])
		_playtime(members, hid, abs_hour, h, weekend, sc.get("playtime", {}))
	_invites(ppl, abs_hour, h, weekend, sc.get("friends_over", {}))

static func _mean_factor(members: Array, traits: Dictionary) -> float:
	var s := 0.0
	for f in members:
		s += DynLife.trait_factor(f, traits)
	return s / maxf(float(members.size()), 1.0)

static func _toast(hid: int, text: String) -> void:
	if text != "" and Players.player_of(hid) > 0:
		SysUtil.notify(text, "good")

## Dinner or game night: everyone at home who may join gets the buff, so the household drifts toward the same thing at the same time.
static func _together(members: Array, hid: int, abs_hour: int, h: float, weekend: bool, p: Dictionary, buff: String, salt: int, stages: Array) -> void:
	if p.is_empty() or h < float((p["hours"] as Array)[0]) or h >= float((p["hours"] as Array)[1]):
		return
	var who: Array = members.filter(func(f): return stages.has(str(f.age_stage)) and not f.has_buff(buff))
	if who.size() < int(p.get("min_people", 2)):
		return
	var prob: float = float(p.get("chance", 0.0)) * _mean_factor(who, p.get("traits", {})) * (float(p.get("weekend_mult", 1.0)) if weekend else 1.0)
	if DynLife.dice(hid, abs_hour, salt) >= prob:
		return
	for f in who:
		f.add_buff(buff)
	_toast(hid, str(p.get("toast", "")))
	SysUtil.game_event("dyn_household", {"household": hid, "what": buff, "folk_id": int(who[0].id)})

## Kids play: the little ones, and a teen or adult who joins in, get the playful buff (interaction play_together / tickle).
static func _playtime(members: Array, hid: int, abs_hour: int, h: float, weekend: bool, p: Dictionary) -> void:
	if p.is_empty() or not DynLife.in_hours(p.get("hours", []), h):
		return
	var kids: Array = members.filter(func(f): return KIDS.has(str(f.age_stage)))
	if kids.is_empty() or members.size() < 2:
		return
	var prob: float = float(p.get("chance", 0.0)) * (float(p.get("weekend_mult", 1.0)) if weekend else 1.0)
	if DynLife.dice(hid, abs_hour, 103) >= prob:
		return
	var buff := str(p.get("buff", "plan_play_kids"))
	var joined := 0
	for f in members:
		var kid: bool = KIDS.has(str(f.age_stage))
		if (kid or (str(f.age_stage) in ["teen", "adult"] and DynLife.dice(int(f.id), abs_hour, 104) < 0.5 * DynLife.trait_factor(f, {"social": 1.4, "loner": 0.4, "lazy": 0.6, "workaholic": 0.5}))) and not f.has_buff(buff):
			f.add_buff(buff)
			joined += 1
	if joined > 1:
		SysUtil.game_event("dyn_household", {"household": hid, "what": "playtime", "folk_id": int(kids[0].id)})

## A resident asks a friend over (a real visit: the guest walks to the door and comes in).
static func _invites(ppl: Array, abs_hour: int, h: float, weekend: bool, p: Dictionary) -> void:
	if p.is_empty() or not DynLife.in_hours(p.get("hours", []), h):
		return
	var day_len := 1440
	var now := SimEnv.now_min()
	for f in ppl:
		if not (p.get("stages", []) as Array).has(str(f.age_stage)) or not DynLife.awake(f) or not DynLife.at_home(f) or Tiers.of(f) > Tiers.NEAR:
			continue
		if now < int(f.cooldowns.get("dyn:invite", -1)):
			continue
		var prob: float = float(p.get("chance", 0.0)) * HomeBare.boost(f, "invite_gain") * DynLife.trait_factor(f, p.get("traits", {})) * (float(p.get("weekend_mult", 1.0)) if weekend else 1.0)
		if DynLife.dice(int(f.id), abs_hour, 105) >= prob:
			continue
		var guest = _pick_friend(f, float(p.get("min_friendship", 25)))
		if guest == null:
			continue
		var dur: Array = p.get("duration", [150, 240])
		var minutes: int = int(dur[0]) + int(DynLife.dice(int(f.id), abs_hour, 106) * float(int(dur[1]) - int(dur[0])))
		var sit: Dictionary = StoryVisits.invite_over(int(guest["id"]), int(f.id), minutes)
		if sit.is_empty():
			continue
		f.cooldowns["dyn:invite"] = now + day_len
		_toast(int(f.household_id), str(p.get("toast", "")).replace("{name}", str(f.name)).replace("{guest}", SysUtil.folk_name(int(guest["id"]))))
		SysUtil.game_event("dyn_household", {"household": int(f.household_id), "what": "friends_over", "folk_id": int(f.id)})

## The best-liked free townie who may visit this person (same life stage group, not barred, not here lately).
static func _pick_friend(f, min_friendship: float):
	var best = null
	var best_v := min_friendship
	var day: int = SysUtil.day()
	var host_stage := str(f.age_stage)
	for t in Story.free_townies():
		var st: String = Story.stage_of(t)
		if st in ["baby", "toddler", "child"] or (host_stage == "teen" and st == "elder") or day - int(t["last_visit_day"]) < 3:
			continue
		var v: float = RelationshipService.value(int(f.id), int(t["id"]), "friendship")
		if v >= best_v and not JusticeOrders.bars(int(t["id"]), int(f.id)):
			best_v = v
			best = t
	return best
