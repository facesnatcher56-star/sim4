class_name PhoneJobs
extends RefCounted
## Task 51: where the job board can be reached. With a working phone it is the Jobs app. Without one (no phone, stolen, broken, cut off) a person can still
## stand at the job centre counter at city hall in its opening hours (the same board), or buy the paper: today's ads are a few openings of the board, and
## those can be asked about in person that day. Numbers: data/solo.json "phone".
##   PhoneJobs.how(fid)            "phone" | "centre" | "paper" | "" (how the board is reachable right now)
##   PhoneJobs.why_not(fid, cid)   "" when this person can apply for that line of work now, else why not
##   PhoneJobs.read_paper(fid)     buy the paper: {ok, reason, careers}

static var ads: Dictionary = {}          # folk id -> {day, careers: [...]}

static func reset() -> void:
	ads = {}

static func cfg() -> Dictionary:
	return (SoloCfg.sect("phone") as Dictionary)

static func centre_open() -> bool:
	var h: Array = (cfg().get("job_centre", {}) as Dictionary).get("hours", [9, 17])
	return SysUtil.hour_f() >= float(h[0]) and SysUtil.hour_f() < float(h[1])

static func at_centre(fid: int) -> bool:
	var f = SysUtil.folk(fid)
	return f != null and PhoneOwn.at_lot(f, str((cfg().get("job_centre", {}) as Dictionary).get("lot", "city_hall"))) and centre_open()

static func paper_careers(fid: int) -> Array:
	var e: Dictionary = ads.get(fid, {})
	return e.get("careers", []) if int(e.get("day", -1)) == SysUtil.day() else []

static func how(fid: int) -> String:
	if PhoneOwn.block(fid) == "":
		return "phone"
	if at_centre(fid):
		return "centre"
	return "paper" if not paper_careers(fid).is_empty() else ""

static func why_not(fid: int, cid: String) -> String:
	var h: String = how(fid)
	if h in ["phone", "centre"]:
		return ""
	if (h == "paper" and paper_careers(fid).has(cid)) or JobLeads.has(fid, cid):
		return ""
	return "%s Find the board at the job centre in city hall or read the paper." % PhoneOwn.block(fid)

static func read_paper(fid: int) -> Dictionary:
	var f = SysUtil.folk(fid)
	if f == null:
		return {"ok": false, "reason": "Nobody is reading."}
	var price: int = int((cfg().get("paper", {}) as Dictionary).get("price", 2))
	if not paper_careers(fid).is_empty():
		return {"ok": true, "reason": "", "careers": paper_careers(fid)}
	if not Economy.spend(int(f.household_id), price, "newspaper"):
		return {"ok": false, "reason": "Not enough coins.", "careers": []}
	var rows: Array = EduJobs.board_for(f).filter(func(r): return bool(r["qualified"]) and int(r["openings"]) > 0)
	var pool: Array = rows.map(func(r): return str(r["career"]))
	var picked: Array = []
	var n: int = int((cfg().get("paper", {}) as Dictionary).get("ads", 3))
	while picked.size() < n and not pool.is_empty():
		var i: int = SysUtil.rng.randi_range(0, pool.size() - 1)
		picked.append(pool[i])
		pool.remove_at(i)
	ads[fid] = {"day": SysUtil.day(), "careers": picked}
	return {"ok": true, "reason": "", "careers": picked}
