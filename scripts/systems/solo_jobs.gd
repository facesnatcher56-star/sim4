class_name SoloJobs
extends RefCounted
## The first board of jobs of a solo game always has openings a player with no skills and no computer can take (R2.4): the Jobs tab at the Town
## window. The wanted number depends on the difficulty. Data: data/solo.json "jobs".

static func seed_board() -> void:
	var jc: Dictionary = SoloCfg.sect("jobs")
	var want: int = int(SoloCfg.by_diff("jobs", "min_openings"))
	EduJobs.refresh(SysUtil.day())
	var have: int = 0
	var board: Dictionary = EduState.board
	var open: Dictionary = board.get("openings", {})
	for cid in jc.get("first_board", []):
		if have >= want:
			break
		if int(open.get(str(cid), 0)) <= 0:
			open[str(cid)] = 1
		have += 1
	board["openings"] = open
