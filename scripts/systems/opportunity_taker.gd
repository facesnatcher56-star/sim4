class_name OpportunityTaker
extends RefCounted
## Jobless adults sometimes take a pending job offer on their own, by how well it fits their skill and traits
## (data/story_pacing.json "opportunity"). The household sees a toast and can quit the job.

static func fit_chance(f, cid: String) -> float:
	var o: Dictionary = StoryPacing.cfg().get("opportunity", {})
	var w: float = 1.0 + float(Careers.skill_for(f, cid)) * 1.5 + Careers.trait_bonus(f, cid)
	var p: float = float(o.get("base", 0.15)) + float(o.get("per_fit", 0.12)) * w
	for t in (o.get("trait_mult", {}) as Dictionary):
		if f.has_trait(str(t)):
			p *= float(o["trait_mult"][t])
	return clampf(p, 0.0, float(o.get("max", 0.85)))

static func on_day(_day: int) -> void:
	if not StoryPacing.enabled:
		return
	for fid in Careers.offers.keys():
		var f = SysUtil.folk(int(fid))
		if f == null or not SysUtil.is_resident(f) or SysUtil.is_away(f) or Careers.jobs.has(int(fid)) or Careers.why_not_work(f, str(Careers.offers[fid]["career"]), int(Careers.offers[fid]["level"])) != "":
			continue
		if Pawn.is_pawn(f):          # the player decides on the offer card
			continue
		if not JobSeeking.may_take(f):               # waits for an answer: only somebody looking for work takes it, never daily churn
			continue
		if not (f.queue as Array).is_empty():       # the player is directing them
			continue
		var o: Dictionary = Careers.offers[fid]
		if SysUtil.chance(fit_chance(f, str(o["career"]))):
			var title: String = str(Careers.level_def(str(o["career"]), int(o["level"])).get("title", o["career"]))
			if Careers.accept_offer(int(fid)):
				SysUtil.notify("%s took the %s job." % [f.name, title], "job_offer")
				SysUtil.game_event("took_offer", {"folk_id": int(fid), "career": str(o["career"])})
