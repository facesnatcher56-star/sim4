class_name SocialContent
extends RefCounted
## Runtime content + wiring for the social/emotion layer (idempotent, like SysContent):
##  * hidden mood-effect buffs (Emotions.install_buffs)
##  * data/social.json "story_scores" merged into data/story.json visits.score so group socials count for Story parties
##  * the `karaoke` interaction is offered by the stereo (objects.json is not edited)
##  * signal binding: SimScheduler rows (sim_registry.gd) -> SocialDynamics.on_minute / on_hour, Events.game_event -> SocialDynamics.on_game_event.
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
	ContentMerge.add_object_interaction(data.objects(), "stereo", "karaoke")
	var w = WorldIface.world()
	if w != null and "defs" in w and w.defs is Dictionary:
		ContentMerge.add_object_interaction(w.defs, "stereo", "karaoke")

static func _bind() -> void:
	var ev = SimEnv.events()
	if ev != _events:
		_events = ev
		if not ev.game_event.is_connected(SocialDynamics.on_game_event):
			ev.game_event.connect(SocialDynamics.on_game_event)
	var ck = SimEnv.clock()
	if ck != _clock:
		_clock = ck
		var sch := SimScheduler.of(ck)            # the minute / hour jobs are rows in sim_registry.gd (social_rows)
		if not sch.has_group(SimRegistry.GROUP_SOCIAL):
			SimRegistry.install_social(sch)

## Detach (tests that replace Events/Clock call this implicitly through the rebinding in ensure()).
static func unbind() -> void:
	if _events != null and is_instance_valid(_events) and _events.game_event.is_connected(SocialDynamics.on_game_event):
		_events.game_event.disconnect(SocialDynamics.on_game_event)
	if _clock != null and is_instance_valid(_clock):
		SimScheduler.of(_clock).remove_group(SimRegistry.GROUP_SOCIAL)
	_events = null
	_clock = null
