class_name SocialContent
extends RefCounted
## Runtime content + wiring for the social/emotion layer (idempotent, like SysContent):
##  * hidden mood-effect buffs (Emotions.install_buffs)
##  * data/social.json "story_scores" merged into data/story.json visits.score so group socials count for Story parties
##  * the `karaoke` interaction is offered by the stereo (objects.json is not edited)
##  * signal binding: Clock.minute_passed / hour_passed -> SocialDynamics, Events.game_event -> SocialDynamics.on_game_event.
##    Rebinds automatically when SimEnv swaps in new standalone Events / Clock instances (tests).
## ensure() is called from RelationshipService hooks, so it works whether or not SystemsManager is installed.

static var _events = null
static var _clock = null

static func ensure() -> void:
	install()
	_bind()

static func install() -> void:
	var data = SimEnv.data()
	var buffs: Dictionary = data.buffs()
	if buffs.is_empty():
		return
	if not buffs.has("mfx_happy_1"):
		Emotions.install_buffs(buffs)
	var st: Dictionary = data.get_table("story")
	var scores: Dictionary = data.get_table("social").get("story_scores", {})
	if not st.is_empty() and not scores.is_empty():
		var visits: Dictionary = st.get("visits", {})
		var table: Dictionary = visits.get("score", {})
		for iid in scores:
			if not table.has(iid):
				table[iid] = scores[iid]
		visits["score"] = table
		st["visits"] = visits
	_add_obj_interaction(data.objects(), "stereo", "karaoke")
	var w = WorldIface.world()
	if w != null and "defs" in w and w.defs is Dictionary:
		_add_obj_interaction(w.defs, "stereo", "karaoke")

static func _add_obj_interaction(defs: Dictionary, obj_id: String, iid: String) -> void:
	if not defs.has(obj_id):
		return
	var od: Dictionary = defs[obj_id]
	var list: Array = od.get("interactions", [])
	if not list.has(iid):
		list.append(iid)
		od["interactions"] = list

static func _bind() -> void:
	var ev = SimEnv.events()
	if ev != _events:
		_events = ev
		if not ev.game_event.is_connected(SocialDynamics.on_game_event):
			ev.game_event.connect(SocialDynamics.on_game_event)
	var ck = SimEnv.clock()
	if ck != _clock:
		_clock = ck
		if not ck.minute_passed.is_connected(SocialDynamics.on_minute):
			ck.minute_passed.connect(SocialDynamics.on_minute)
		if not ck.hour_passed.is_connected(SocialDynamics.on_hour):
			ck.hour_passed.connect(SocialDynamics.on_hour)

## Detach (tests that replace Events/Clock call this implicitly through the rebinding in ensure()).
static func unbind() -> void:
	if _events != null and is_instance_valid(_events) and _events.game_event.is_connected(SocialDynamics.on_game_event):
		_events.game_event.disconnect(SocialDynamics.on_game_event)
	if _clock != null and is_instance_valid(_clock):
		if _clock.minute_passed.is_connected(SocialDynamics.on_minute):
			_clock.minute_passed.disconnect(SocialDynamics.on_minute)
		if _clock.hour_passed.is_connected(SocialDynamics.on_hour):
			_clock.hour_passed.disconnect(SocialDynamics.on_hour)
	_events = null
	_clock = null
