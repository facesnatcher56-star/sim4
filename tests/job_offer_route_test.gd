extends RefCounted
## Task 33c: the job-offer toast names the route the household really has. No computer: Town -> Jobs tab (which can hire, and now also answers a pending offer);
## a computer: its 'Look for Jobs'. A jobless adult with no computer to search from counts as looking for work, so autonomy (OpportunityTaker) takes a fitting
## offer for them (the "no job for 37 days" finding); with a computer and money in the bank they wait for a search as before.

const K = preload("res://tests/systems_kit.gd")


func run() -> Array:
	var f: Array = []
	# toast text
	var w := K.setup()
	var a := K.make_folk(w, "Pia", [], 1)
	K.mgr.new_game([1])
	Careers.confirm_offers = true
	WorldIface.coins[1] = 5000
	Careers.make_offer(a, "coder", 1)
	K.expect(f, K.has_note("Town, open the Jobs tab"), "no computer: the offer toast names Town -> Jobs")
	K.expect(f, not K.has_note("Use a computer"), "no computer: the toast does not send them to a computer")
	K.expect(f, not Careers.pending_offer(int(a.id)).is_empty(), "the offer waits for an answer")
	# the Jobs tab route can answer it: the same command the offer card sends
	var r: Dictionary = Commands.run({"folk_id": int(a.id), "action": "career_accept"})
	K.expect(f, bool(r.get("ok", false)) and Careers.jobs.has(int(a.id)), "accepting from the Jobs tab card hires")
	Careers.quit_job(a)
	K.notes.clear()
	var comp = w.add_object("computer", Vector2i(14, 12))
	Economy.owner[int(comp.id)] = 1
	K.expect(f, JobSeeking.has_computer(1), "the household now has a computer")
	Careers.offers.erase(int(a.id))
	Careers.make_offer(a, "coder", 1)
	K.expect(f, K.has_note("Use a computer's 'Look for Jobs'"), "with a computer the toast names Look for Jobs")
	K.expect(f, not K.has_note("Jobs tab"), "with a computer the toast does not mention the Jobs tab")
	# the Jobs tab itself hires (EduJobs.apply)
	Careers.confirm_offers = false
	K.teardown()
	# autonomy: a jobless adult without a computer takes a fitting offer; with a computer and money they wait
	for has_comp in [false, true]:
		var w2 := K.setup()
		var p := K.make_folk(w2, "Quill", [], 1)
		K.mgr.new_game([1])
		WorldIface.coins[1] = 5000
		if has_comp:
			var c2 = w2.add_object("computer", Vector2i(14, 12))
			Economy.owner[int(c2.id)] = 1
		Careers.confirm_offers = true
		Careers.make_offer(p, "coder", 1)
		K.expect(f, JobSeeking.is_seeking(p) == (not has_comp), "is_seeking with computer=%s" % str(has_comp))
		for i in 40:
			Careers.offers[int(p.id)] = Careers.offers.get(int(p.id), {"career": "coder", "level": 1, "expires_day": 999})
			OpportunityTaker.on_day(10 + i)
			if Careers.jobs.has(int(p.id)):
				break
		K.expect(f, Careers.jobs.has(int(p.id)) == (not has_comp), "has_comp=%s: took the job on their own = %s" % [str(has_comp), str(Careers.jobs.has(int(p.id)))])
		Careers.confirm_offers = false
		K.teardown()
	return f
