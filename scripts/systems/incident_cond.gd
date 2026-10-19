class_name IncidentCond
extends RefCounted
## Condition lists for incidents, evaluated on an IncidentSubject (Folk, townie record or lot) so the same data drives the
## FULL and the STATISTICAL resolution. Folk subjects delegate to SysCond (so every Cond / SysCond key works);
## townie subjects understand the keys in TOWNIE_KEYS (anything else is false for them).
## Extra keys: has_object / lacks_object (def id or list; objects of the subject's household, townie lots use `town_objects` of
## the record), weather_is [ids], season_is [ids], any_member [conds] / all_members [conds] (lot subjects), hour_between [h1,h2].

const OWN_KEYS := ["has_object", "lacks_object", "weather_is", "season_is", "any_member", "all_members", "hour_between", "not", "any", "disaster", "chaos"]
const TOWNIE_KEYS := ["age_stage_is", "has_trait", "lacks_trait", "has_buff", "lacks_buff", "skill_at_least", "skill_below", "coins_at_least",
	"stat_below", "stat_above", "has_job", "time_between"]
## Every key a data file may use (validation).
const VALID_KEYS := ["stat_below", "stat_above", "has_trait", "lacks_trait", "has_buff", "lacks_buff", "mood_is", "skill_at_least", "skill_below",
	"time_between", "coins_at_least", "has_job", "posture_is", "posture_not", "friends_at_least", "bit_count", "career_is", "career_level_at_least",
	"age_stage_is", "in_school", "pregnant", "has_object", "lacks_object", "weather_is", "season_is", "any_member", "all_members", "hour_between", "not", "any", "disaster", "chaos"]

static func check(conds: Array, subj) -> bool:
	for c in conds:
		if not check_one(c, subj):
			return false
	return true

static func check_one(c: Variant, subj) -> bool:
	if c is Array:
		return check(c, subj)
	if not (c is Dictionary):
		return false
	if subj.folk != null:                  # a real Folk: when no key is one of ours, SysCond takes the whole dictionary (no one-key dictionary per key)
		var own := false
		for key0 in c:
			if OWN_KEYS.has(str(key0)):
				own = true
				break
		if not own:
			return SysCond.check_one(c, subj.folk)
	for key in c:
		if not _key(str(key), c[key], subj):
			return false
	return true

static func _key(key: String, v: Variant, subj) -> bool:
	match key:
		"not":
			return not check_one(v, subj)
		"any":
			for sub in v:
				if check_one(sub, subj):
					return true
			return false
		"weather_is":
			return (v as Array).has(Weather.current()) if v is Array else Weather.current() == str(v)
		"season_is":
			return (v as Array).has(Seasons.current()) if v is Array else Seasons.current() == str(v)
		"hour_between":
			return Cond._time_between(float(v[0]), float(v[1]))
		"disaster":
			return DisasterConds.check(v, subj)
		"chaos":
			return ChaosConds.check(v, subj)
		"has_object":
			return _has_object(subj, v)
		"lacks_object":
			return not _has_object(subj, v)
		"any_member":
			for m in subj.members():
				if check(v, m):
					return true
			return false
		"all_members":
			var ms: Array = subj.members()
			for m in ms:
				if not check(v, m):
					return false
			return not ms.is_empty()
	if subj.kind == "lot":
		var h = subj.head()
		return h != null and _key(key, v, h)
	if subj.folk != null:
		return SysCond.check_one({key: v}, subj.folk)
	return _townie_key(key, v, subj)

static func _townie_key(key: String, v: Variant, s) -> bool:
	match key:
		"age_stage_is":
			return (v as Array).has(s.age_stage()) if v is Array else s.age_stage() == str(v)
		"has_trait":
			return s.has_trait(str(v))
		"lacks_trait":
			return not s.has_trait(str(v))
		"has_buff":
			return s.has_buff(str(v))
		"lacks_buff":
			return not s.has_buff(str(v))
		"skill_at_least":
			return s.skill_level(str(v[0])) >= int(v[1])
		"skill_below":
			return s.skill_level(str(v[0])) < int(v[1])
		"coins_at_least":
			return s.coins() >= int(v)
		"stat_below":
			return s.stat(str(v[0])) < float(v[1])
		"stat_above":
			return s.stat(str(v[0])) > float(v[1])
		"has_job":
			return (str(s.t().get("career", "")) != "") == bool(v)
		"time_between":
			return Cond._time_between(float(v[0]), float(v[1]))
	return false

static func _has_object(subj, v: Variant) -> bool:
	var want: Array = v if v is Array else [v]
	var have: Array = []
	if subj.lot_key.begins_with("town:") or subj.kind == "townie":
		have = _town_objects(subj)
	else:
		var hid: int = subj.household_id
		if hid <= 0 and subj.folk != null:
			hid = int(subj.folk.household_id)
		if IncidentSubject.caching:
			have = IncidentSubject.household_defs(hid)
		else:
			for o in Economy.objects_of(hid):
				have.append(str(o.def_id))
	for w in want:
		if have.has(str(w)):
			return true
	return false

## Far lots have no real objects: their Story records may list `town_objects` (def ids), else a plain default set.
static func _town_objects(subj) -> Array:
	var key: String = subj.lot_key
	var n: int = int(key.get_slice(":", 1)) if key.begins_with("town:") else 0
	var out: Array = []
	for tid in Story.townies:
		var rec: Dictionary = Story.townies[tid]
		if int(rec.get("lot", -1)) == n:
			for o in rec.get("town_objects", []):
				out.append(str(o))
	return out
